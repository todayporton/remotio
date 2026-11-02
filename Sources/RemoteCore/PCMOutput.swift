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

    /// - Parameter prebufferPackets: BLE の到着ゆらぎ(実測で最大約43ms)を吸収する待機量。1個 20ms。
    public init(device: AudioDeviceInfo, prebufferPackets: Int = 3) throws {
        guard device.outputChannels > 0 else { throw AudioDeviceError.noOutput(device.name) }
        self.prebufferPackets = prebufferPackets
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

        var id = device.id
        let status = AudioUnitSetProperty(engine.outputNode.audioUnit!, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw PCMOutputError.setDevice(status) }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    public func start() throws {
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        player.stop()
        engine.stop()
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
        waiting.forEach { player.scheduleBuffer($0, completionHandler: nil) }
        waiting.removeAll()
        player.play()
        playing = true
    }
}
