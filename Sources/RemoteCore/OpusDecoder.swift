import COpus

public enum OpusError: Error, CustomStringConvertible {
    case create(Int32), decode(Int32)
    public var description: String {
        switch self {
        case .create(let c): return "opus_decoder_create 失敗: \(String(cString: opus_strerror(c)))"
        case .decode(let c): return "opus_decode 失敗: \(String(cString: opus_strerror(c)))"
        }
    }
}

public final class OpusDecoder {
    private let decoder: OpaquePointer
    private let maxFrameSamples: Int32

    public init(sampleRate: Int32 = 16_000, channels: Int32 = 1) throws {
        var err: Int32 = 0
        guard let d = opus_decoder_create(sampleRate, channels, &err), err == OPUS_OK else {
            throw OpusError.create(err)
        }
        decoder = d
        maxFrameSamples = sampleRate * 120 / 1000 // Opus の最大パケット長
    }

    deinit { opus_decoder_destroy(decoder) }

    public func decode(_ packet: [UInt8]) throws -> [Int16] {
        var pcm = [Int16](repeating: 0, count: Int(maxFrameSamples))
        let n = opus_decode(decoder, packet, Int32(packet.count), &pcm, maxFrameSamples, 0)
        guard n >= 0 else { throw OpusError.decode(n) }
        return Array(pcm.prefix(Int(n)))
    }
}
