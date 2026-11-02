import AudioToolbox
import AVFoundation
import CoreAudio

public enum PCMOutputError: Error, CustomStringConvertible {
    case setDevice(OSStatus)
    public var description: String {
        switch self {
        case .setDevice(let s): return "出力デバイスの設定に失敗: OSStatus \(s)"
        }
    }
}

/// 16kHz mono PCM を指定デバイスへ出力する。システムの既定デバイスは変更しない。
/// BlackHole のようなループバックデバイスを指定すると、他アプリがその入力から音声を受け取れる。
public final class PCMOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let prebufferPackets: Int
    private var waiting: [AVAudioPCMBuffer] = []
    private var playing = false
    private var deviceID: AudioDeviceID
    private var configObserver: NSObjectProtocol?
    private var wantsRunning = false

    /// 状態の変化をログへ伝える
    public var onLog: ((String) -> Void)?

    /// - Parameter prebufferPackets: BLE の到着ゆらぎ(実測で最大約43ms)を吸収する待機量。1個 20ms。
    public init(device: AudioDeviceInfo, prebufferPackets: Int = 3) throws {
        guard device.outputChannels > 0 else { throw AudioDeviceError.noOutput(device.name) }
        self.prebufferPackets = prebufferPackets
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

        deviceID = device.id
        try applyDevice()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // サンプルレートの変更などで AVAudioEngine は停止するため、再開する
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.restart(attemptsLeft: 5) }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    private func applyDevice() throws {
        var id = deviceID
        let status = AudioUnitSetProperty(engine.outputNode.audioUnit!, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw PCMOutputError.setDevice(status) }
    }

    public func start() throws {
        wantsRunning = true
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        wantsRunning = false
        player.stop()
        engine.stop()
    }

    private func restart(attemptsLeft: Int) {
        guard wantsRunning else { return }
        player.stop()
        playing = false
        waiting.removeAll()
        do {
            engine.stop()
            try applyDevice()
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.connect(engine.mainMixerNode, to: engine.outputNode,
                           format: engine.outputNode.inputFormat(forBus: 0))
            engine.prepare()
            try engine.start()
            onLog?("音声出力を再開しました(デバイスの設定変更)")
        } catch {
            guard attemptsLeft > 1 else {
                onLog?("音声出力を再開できません: \(error)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.restart(attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    /// 発話の開始時に呼ぶ。前回の残りを破棄し、再びプリバッファから始める。
    public func beginSession() {
        player.stop()
        waiting.removeAll()
        playing = false
    }

    /// 発話の終了時に呼ぶ。プリバッファに満たない短い発話も出力する。
    public func endSession() {
        guard !playing else { return }
        flushWaiting()
    }

    public func enqueue(_ samples: [Int16]) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let out = buffer.floatChannelData![0]
        for (i, s) in samples.enumerated() { out[i] = Float(s) / 32768 }

        if playing {
            player.scheduleBuffer(buffer, completionHandler: nil)
        } else {
            waiting.append(buffer)
            if waiting.count >= prebufferPackets { flushWaiting() }
        }
    }

    private func flushWaiting() {
        guard !waiting.isEmpty else { return }
        guard engine.isRunning else {
            // 再開処理の完了前は再生できないため、待機分を捨てる
            waiting.removeAll()
            return
        }
        waiting.forEach { player.scheduleBuffer($0, completionHandler: nil) }
        waiting.removeAll()
        player.play()
        playing = true
    }
}
