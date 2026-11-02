import Foundation

/// 16bit PCM の WAV を逐次書き込みする。
public final class WAVWriter {
    private let handle: FileHandle
    private let sampleRate: UInt32
    private let channels: UInt16
    public private(set) var sampleCount = 0

    public init(url: URL, sampleRate: UInt32 = 16_000, channels: UInt16 = 1) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        self.sampleRate = sampleRate
        self.channels = channels
        try handle.write(contentsOf: header(dataBytes: 0))
    }

    public func append(_ samples: [Int16]) throws {
        var data = Data(capacity: samples.count * 2)
        for s in samples { withUnsafeBytes(of: s.littleEndian) { data.append(contentsOf: $0) } }
        try handle.write(contentsOf: data)
        sampleCount += samples.count
    }

    public func close() throws {
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header(dataBytes: UInt32(sampleCount * 2)))
        try handle.close()
    }

    private func header(dataBytes: UInt32) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(channels)
        u32(sampleRate); u32(sampleRate * UInt32(channels) * 2); u16(channels * 2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        return d
    }
}

/// 生 Report の記録形式: {timestamp_ns: u64 LE}{length: u16 LE}{Report ID + payload}
/// fire-remote-client の .bin と同じ形式。
public enum CaptureFile {
    public static func encode(timestampNs: UInt64, reportID: UInt8, payload: [UInt8]) -> Data {
        var d = Data()
        withUnsafeBytes(of: timestampNs.littleEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(payload.count + 1).littleEndian) { d.append(contentsOf: $0) }
        d.append(reportID)
        d.append(contentsOf: payload)
        return d
    }

    public static func decode(_ data: Data) -> [(timestampNs: UInt64, reportID: UInt8, payload: [UInt8])] {
        let b = [UInt8](data)
        var out: [(UInt64, UInt8, [UInt8])] = []
        var i = 0
        while i + 10 <= b.count {
            var ns: UInt64 = 0
            for n in 0..<8 { ns |= UInt64(b[i + n]) << UInt64(8 * n) }
            let len = Int(b[i + 8]) | Int(b[i + 9]) << 8
            i += 10
            guard len >= 1, i + len <= b.count else { break }
            out.append((ns, b[i], Array(b[(i + 1)..<(i + len)])))
            i += len
        }
        return out
    }
}

/// 音声パケットの到着統計。ペイロードにシーケンス番号があるかは未確定のため、時刻から推定する。
public struct AudioStats {
    public private(set) var packets = 0
    public private(set) var decodeErrors = 0
    public private(set) var tocBytes = Set<UInt8>()
    public private(set) var payloadSizes = Set<Int>()
    public private(set) var maxGapNs: UInt64 = 0
    private var firstNs: UInt64?
    private var lastNs: UInt64?

    public init() {}

    public mutating func record(timestampNs: UInt64, payload: [UInt8], decodeFailed: Bool) {
        packets += 1
        if decodeFailed { decodeErrors += 1 }
        if let toc = payload.first { tocBytes.insert(toc) }
        payloadSizes.insert(payload.count)
        if let lastNs, timestampNs > lastNs { maxGapNs = max(maxGapNs, timestampNs - lastNs) }
        if firstNs == nil { firstNs = timestampNs }
        lastNs = timestampNs
    }

    public var spanSeconds: Double {
        guard let firstNs, let lastNs, lastNs > firstNs else { return 0 }
        return Double(lastNs - firstNs) / 1e9
    }

    /// 20ms 間隔を前提とした欠落推定。
    public var estimatedLostPackets: Int {
        guard packets > 0 else { return 0 }
        return max(0, Int((spanSeconds / 0.02).rounded()) + 1 - packets)
    }

    public var summary: String {
        let tocs = tocBytes.sorted().map { String(format: "0x%02X", $0) }.joined(separator: ",")
        let sizes = payloadSizes.sorted().map(String.init).joined(separator: ",")
        return String(format: "packets=%d decodeErrors=%d span=%.2fs estLost=%d maxGap=%.1fms toc=[%@] payload=[%@]B",
                      packets, decodeErrors, spanSeconds, estimatedLostPackets,
                      Double(maxGapNs) / 1e6, tocs, sizes)
    }
}
