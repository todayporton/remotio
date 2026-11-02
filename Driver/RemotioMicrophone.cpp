// Remotio Microphone: 他のアプリから入力として見える仮想マイク。
// Remotio は一覧に出ない隠しデバイスへ書き込み、音声入力を使うアプリは入力デバイスから読み取る。
#include <aspl/Driver.hpp>

#include <CoreAudio/AudioServerPlugIn.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <memory>
#include <utility>
#include <vector>

namespace {

constexpr UInt32 SampleRate = 48000;
constexpr UInt32 ChannelCount = 2;
constexpr UInt32 BytesPerFrame = ChannelCount * sizeof(Float32);
constexpr uint64_t RingFrames = SampleRate * 2;

AudioStreamBasicDescription StreamFormat()
{
    AudioStreamBasicDescription format = {};
    format.mSampleRate = SampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    format.mBitsPerChannel = 32;
    format.mChannelsPerFrame = ChannelCount;
    format.mBytesPerFrame = BytesPerFrame;
    format.mFramesPerPacket = 1;
    format.mBytesPerPacket = BytesPerFrame;
    return format;
}

// 隠しデバイス(書き込み側)と入力デバイス(読み取り側)が共有するリングバッファ。
// 2 つのデバイスはそれぞれの I/O スレッドで動き、サンプル時刻の起点も別なので、
// 書き込み側の時刻を基準にして、読み取り側の時刻との差(offset)を保持する。
class SharedRing
{
public:
    SharedRing()
        : ring_(RingFrames * BytesPerFrame, 0)
    {
    }

    void Write(uint64_t start, uint64_t frames, const uint8_t* source)
    {
        // 書き込み側の I/O が再開すると時刻が飛ぶので、読み取り側に合わせ直しを伝える
        if (start != nextWrite_) {
            generation_.fetch_add(1, std::memory_order_acq_rel);
        }
        const uint64_t count = std::min(frames, RingFrames);
        for (uint64_t i = 0; i < count; i++) {
            std::memcpy(ring_.data() + ((start + i) % RingFrames) * BytesPerFrame,
                source + i * BytesPerFrame,
                BytesPerFrame);
        }
        nextWrite_ = start + frames;
        lastWriteFrames_.store(frames, std::memory_order_release);
        writtenUntil_.store(start + frames, std::memory_order_release);
    }

    void Read(uint64_t start, uint64_t frames, uint8_t* out)
    {
        const uint64_t writtenUntil = writtenUntil_.load(std::memory_order_acquire);
        const uint32_t generation = generation_.load(std::memory_order_acquire);

        if (writtenUntil == 0) {
            std::memset(out, 0, frames * BytesPerFrame);
            return;
        }

        // 複数のアプリが読むときは同じ時刻で呼ばれるので、合わせ直しの判定は時刻が飛んだときだけ行う
        const bool sameCycle = hasRead_ && start == lastReadStart_;
        const bool continuous = hasRead_ && start == lastReadStart_ + lastReadFrames_;
        if (!hasRead_ || generation != readGeneration_ || (!sameCycle && !continuous)) {
            Resync(start, frames, writtenUntil, generation);
        }
        lastReadStart_ = start;
        lastReadFrames_ = frames;
        hasRead_ = true;

        // 時計は同じなので通常はずれないが、遅れすぎたら合わせ直す。
        // 追い越した場合は書き込みが止まっている可能性があるので、古い音声を読まないよう無音のままにする
        const int64_t mappedEnd = static_cast<int64_t>(start + frames) + offset_;
        if (static_cast<int64_t>(writtenUntil) - mappedEnd > static_cast<int64_t>(MaxLagFrames)) {
            Resync(start, frames, writtenUntil, generation);
        }

        for (uint64_t i = 0; i < frames; i++) {
            const int64_t t = static_cast<int64_t>(start + i) + offset_;
            auto* dest = out + i * BytesPerFrame;
            // 書き込まれていない範囲は無音にする(古い音声を繰り返さないため)
            const bool valid = t >= 0 && static_cast<uint64_t>(t) < writtenUntil
                && writtenUntil - static_cast<uint64_t>(t) <= RingFrames;
            if (valid) {
                std::memcpy(dest, ring_.data() + (static_cast<uint64_t>(t) % RingFrames) * BytesPerFrame, BytesPerFrame);
            } else {
                std::memset(dest, 0, BytesPerFrame);
            }
        }
    }

private:
    static constexpr uint64_t MarginFrames = 480;       // 10ms
    static constexpr uint64_t MaxLagFrames = SampleRate / 5; // 200ms

    void Resync(uint64_t start, uint64_t frames, uint64_t writtenUntil, uint32_t generation)
    {
        const uint64_t writerFrames = lastWriteFrames_.load(std::memory_order_acquire);
        // 読み取りの終端が、書き込み済みの位置より少し手前に来るようにする
        const int64_t targetEnd = static_cast<int64_t>(writtenUntil) - static_cast<int64_t>(writerFrames + MarginFrames);
        offset_ = targetEnd - static_cast<int64_t>(start + frames);
        readGeneration_ = generation;
    }

    std::vector<uint8_t> ring_;
    std::atomic<uint64_t> writtenUntil_ {0};
    std::atomic<uint64_t> lastWriteFrames_ {0};
    std::atomic<uint32_t> generation_ {0};

    // 書き込みスレッド専用
    uint64_t nextWrite_ = 0;

    // 読み取りスレッド専用
    int64_t offset_ = 0;
    uint32_t readGeneration_ = 0;
    uint64_t lastReadStart_ = 0;
    uint64_t lastReadFrames_ = 0;
    bool hasRead_ = false;
};

class OutputHandler : public aspl::IORequestHandler
{
public:
    explicit OutputHandler(std::shared_ptr<SharedRing> ring)
        : ring_(std::move(ring))
    {
    }

    void OnWriteMixedOutput(const std::shared_ptr<aspl::Stream>&,
        Float64,
        Float64 timestamp,
        const void* bytes,
        UInt32 bytesCount) override
    {
        ring_->Write(static_cast<uint64_t>(timestamp), bytesCount / BytesPerFrame, static_cast<const uint8_t*>(bytes));
    }

private:
    std::shared_ptr<SharedRing> ring_;
};

class InputHandler : public aspl::IORequestHandler
{
public:
    explicit InputHandler(std::shared_ptr<SharedRing> ring)
        : ring_(std::move(ring))
    {
    }

    void OnReadClientInput(const std::shared_ptr<aspl::Client>&,
        const std::shared_ptr<aspl::Stream>&,
        Float64,
        Float64 timestamp,
        void* bytes,
        UInt32 bytesCount) override
    {
        ring_->Read(static_cast<uint64_t>(timestamp), bytesCount / BytesPerFrame, static_cast<uint8_t*>(bytes));
    }

private:
    std::shared_ptr<SharedRing> ring_;
};

// Remotio だけが UID を指定して書き込む、一覧に出ない出力デバイス
class HiddenDevice : public aspl::Device
{
public:
    using aspl::Device::Device;
    bool GetIsHidden() const override { return true; }
};

std::shared_ptr<aspl::Driver> CreateDriver()
{
    auto context = std::make_shared<aspl::Context>();
    auto ring = std::make_shared<SharedRing>();

    aspl::DeviceParameters inputParams;
    inputParams.Name = "Remotio Microphone";
    inputParams.Manufacturer = "Remotio";
    inputParams.DeviceUID = "online.todayporton.remotio.microphone";
    inputParams.ModelUID = "online.todayporton.remotio.microphone.model";
    inputParams.SampleRate = SampleRate;
    inputParams.ChannelCount = ChannelCount;
    inputParams.CanBeDefaultForSystemSounds = false;

    auto inputDevice = std::make_shared<aspl::Device>(context, inputParams);
    aspl::StreamParameters input;
    input.Direction = aspl::Direction::Input;
    input.Format = StreamFormat();
    inputDevice->AddStreamAsync(input);
    inputDevice->SetIOHandler(std::make_shared<InputHandler>(ring));

    aspl::DeviceParameters outputParams;
    outputParams.Name = "Remotio Microphone Output";
    outputParams.Manufacturer = "Remotio";
    outputParams.DeviceUID = "online.todayporton.remotio.microphone.output";
    outputParams.ModelUID = "online.todayporton.remotio.microphone.output.model";
    outputParams.SampleRate = SampleRate;
    outputParams.ChannelCount = ChannelCount;
    outputParams.EnableMixing = true;
    outputParams.CanBeDefault = false;
    outputParams.CanBeDefaultForSystemSounds = false;

    auto outputDevice = std::make_shared<HiddenDevice>(context, outputParams);
    aspl::StreamParameters output;
    output.Direction = aspl::Direction::Output;
    output.Format = StreamFormat();
    outputDevice->AddStreamAsync(output);
    outputDevice->SetIOHandler(std::make_shared<OutputHandler>(ring));

    auto plugin = std::make_shared<aspl::Plugin>(context);
    plugin->AddDevice(inputDevice);
    plugin->AddDevice(outputDevice);

    return std::make_shared<aspl::Driver>(context, plugin);
}

} // namespace

extern "C" void* RemotioMicrophoneEntryPoint(CFAllocatorRef, CFUUIDRef typeUUID)
{
    if (!CFEqual(typeUUID, kAudioServerPlugInTypeUUID)) {
        return nullptr;
    }
    static std::shared_ptr<aspl::Driver> driver = CreateDriver();
    return driver->GetReference();
}
