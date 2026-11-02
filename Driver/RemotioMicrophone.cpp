// Remotio Microphone: 出力へ書かれた音声を、そのまま入力として他のアプリへ渡す仮想デバイス。
// Remotio は出力側へ書き込み、音声入力を使うアプリは入力側から読み取る。
#include <aspl/Driver.hpp>

#include <CoreAudio/AudioServerPlugIn.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstring>
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

// サンプル時刻で位置を決めるリングバッファ。HAL の I/O スレッドだけが読み書きする。
class LoopbackHandler : public aspl::IORequestHandler
{
public:
    LoopbackHandler()
        : ring_(RingFrames * BytesPerFrame, 0)
    {
    }

    void OnWriteMixedOutput(const std::shared_ptr<aspl::Stream>&,
        Float64,
        Float64 timestamp,
        const void* bytes,
        UInt32 bytesCount) override
    {
        const auto start = static_cast<uint64_t>(timestamp);
        const uint64_t frames = bytesCount / BytesPerFrame;
        Copy(start, frames, static_cast<const uint8_t*>(bytes));
        writtenUntil_.store(start + frames, std::memory_order_release);
    }

    void OnReadClientInput(const std::shared_ptr<aspl::Client>&,
        const std::shared_ptr<aspl::Stream>&,
        Float64,
        Float64 timestamp,
        void* bytes,
        UInt32 bytesCount) override
    {
        const auto start = static_cast<uint64_t>(timestamp);
        const uint64_t frames = bytesCount / BytesPerFrame;
        const uint64_t writtenUntil = writtenUntil_.load(std::memory_order_acquire);
        auto* out = static_cast<uint8_t*>(bytes);

        // 書き込まれていない範囲は無音にする(古い音声を繰り返さないため)
        for (uint64_t i = 0; i < frames; i++) {
            const uint64_t t = start + i;
            const bool valid = t < writtenUntil && writtenUntil - t <= RingFrames;
            auto* dest = out + i * BytesPerFrame;
            if (valid) {
                std::memcpy(dest, ring_.data() + (t % RingFrames) * BytesPerFrame, BytesPerFrame);
            } else {
                std::memset(dest, 0, BytesPerFrame);
            }
        }
    }

private:
    void Copy(uint64_t start, uint64_t frames, const uint8_t* source)
    {
        frames = std::min(frames, RingFrames);
        for (uint64_t i = 0; i < frames; i++) {
            std::memcpy(ring_.data() + ((start + i) % RingFrames) * BytesPerFrame,
                source + i * BytesPerFrame,
                BytesPerFrame);
        }
    }

    std::vector<uint8_t> ring_;
    std::atomic<uint64_t> writtenUntil_ {0};
};

std::shared_ptr<aspl::Driver> CreateDriver()
{
    auto context = std::make_shared<aspl::Context>();

    aspl::DeviceParameters params;
    params.Name = "Remotio Microphone";
    params.Manufacturer = "Remotio";
    params.DeviceUID = "online.todayporton.remotio.microphone";
    params.ModelUID = "online.todayporton.remotio.microphone.model";
    params.SampleRate = SampleRate;
    params.ChannelCount = ChannelCount;
    params.EnableMixing = true;
    // 通知音などが流れ込まないようにする
    params.CanBeDefaultForSystemSounds = false;

    auto device = std::make_shared<aspl::Device>(context, params);

    aspl::StreamParameters input;
    input.Direction = aspl::Direction::Input;
    input.Format = StreamFormat();
    device->AddStreamAsync(input);

    aspl::StreamParameters output;
    output.Direction = aspl::Direction::Output;
    output.Format = StreamFormat();
    device->AddStreamAsync(output);

    device->SetIOHandler(std::make_shared<LoopbackHandler>());

    auto plugin = std::make_shared<aspl::Plugin>(context);
    plugin->AddDevice(device);

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
