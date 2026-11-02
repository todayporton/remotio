import CoreAudio
import Foundation

public struct AudioDeviceInfo: Equatable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let inputChannels: Int
    public let outputChannels: Int
}

public enum AudioDeviceError: Error, CustomStringConvertible {
    case notFound(String), ambiguous(String, [String]), noOutput(String), noInput(String)
    public var description: String {
        switch self {
        case .notFound(let q): return "オーディオデバイスが見つかりません: \(q)"
        case .ambiguous(let q, let c): return "\(q) に複数一致します: \(c.joined(separator: ", "))"
        case .noOutput(let n): return "\(n) には出力チャンネルがありません"
        case .noInput(let n): return "\(n) には入力チャンネルがありません"
        }
    }
}

public enum AudioDevices {
    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }

    private static func channels(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    public static func all() -> [AudioDeviceInfo] {
        var addr = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map {
            AudioDeviceInfo(id: $0,
                            uid: string($0, kAudioDevicePropertyDeviceUID),
                            name: string($0, kAudioObjectPropertyName),
                            inputChannels: channels($0, scope: kAudioObjectPropertyScopeInput),
                            outputChannels: channels($0, scope: kAudioObjectPropertyScopeOutput))
        }
    }

    /// UID の完全一致を優先し、なければ名前の部分一致で 1 件に絞る。
    public static func resolve(_ query: String, in devices: [AudioDeviceInfo]) throws -> AudioDeviceInfo {
        if let exact = devices.first(where: { $0.uid == query }) { return exact }
        let hits = devices.filter { $0.name.range(of: query, options: .caseInsensitive) != nil }
        guard let first = hits.first else { throw AudioDeviceError.notFound(query) }
        guard hits.count == 1 else { throw AudioDeviceError.ambiguous(query, hits.map(\.name)) }
        return first
    }

    public static func defaultDevice(input: Bool) -> AudioDeviceID {
        var addr = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    public static func nominalSampleRate(_ id: AudioDeviceID) -> Double {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &rate)
        return rate
    }
}

/// デバイスの入力第 1 チャンネルを WAV に保存する検証用レコーダ。
public final class DeviceInputRecorder {
    private let device: AudioDeviceInfo
    private let writer: WAVWriter
    private let queue = DispatchQueue(label: "fireremote.capture-input")
    private var procID: AudioDeviceIOProcID?

    public init(device: AudioDeviceInfo, url: URL) throws {
        guard device.inputChannels > 0 else { throw AudioDeviceError.noInput(device.name) }
        self.device = device
        writer = try WAVWriter(url: url, sampleRate: UInt32(AudioDevices.nominalSampleRate(device.id)))
    }

    public func start() -> OSStatus {
        let writer = self.writer
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, device.id, queue) { _, input, _, _, _ in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let buffer = list.first, let data = buffer.mData else { return }
            let stride = max(Int(buffer.mNumberChannels), 1)
            let floats = data.assumingMemoryBound(to: Float32.self)
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size / stride
            let samples = (0..<frames).map { Int16(max(-1, min(1, floats[$0 * stride])) * 32767) }
            try? writer.append(samples)
        }
        guard status == noErr, let procID else { return status }
        return AudioDeviceStart(device.id, procID)
    }

    public func stop() throws {
        if let procID {
            AudioDeviceStop(device.id, procID)
            AudioDeviceDestroyIOProcID(device.id, procID)
        }
        try queue.sync { try writer.close() }
    }
}
