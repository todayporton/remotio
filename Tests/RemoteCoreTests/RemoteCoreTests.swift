import COpus
import XCTest
@testable import RemoteCore

final class RemoteCoreTests: XCTestCase {
    /// 実機(FW 53305501)の IORegistry から取得した Descriptor
    static let descriptorHex = "05010906a1010507850195037508150025ff190029ff8100c0050c0901a1018502950275101500269c0219002a9c028100c006ff000900a10185f095507508150025ff810085f1950375080900810285f2950175080900910285f3950a75080900910285ef95037508150025ff190029ff09018100c0050c0901a101850305010906a102050609201500266400750895018102c0c0"

    var reports: [HIDReportInfo] {
        let h = Array(Self.descriptorHex)
        let bytes = stride(from: 0, to: h.count, by: 2).map { UInt8(String(h[$0...$0 + 1]), radix: 16)! }
        return HIDReportDescriptor.parse(bytes)
    }

    func testDescriptorSizes() {
        let byID = Dictionary(uniqueKeysWithValues: reports.map { ($0.id, $0) })
        XCTAssertEqual(byID[0x01]?.inputBytes, 3)
        XCTAssertEqual(byID[0x02]?.inputBytes, 4)
        XCTAssertEqual(byID[0xF0]?.inputBytes, 80)
        XCTAssertEqual(byID[0xF2]?.outputBytes, 1)
        XCTAssertEqual(byID[0xF3]?.outputBytes, 10)
    }

    func testVoiceReportDetection() {
        let v = FireTVRemoteProfile().voiceReports(in: reports)
        XCTAssertEqual(v, VoiceReports(audioReportID: 0xF0, micEnableReportID: 0xF2, audioPayloadBytes: 80))
    }

    func testButtonEventsAndVoiceControl() {
        let profile = FireTVRemoteProfile()
        var tracker = ButtonTracker(profile: profile)
        var voice = VoiceController(voiceButton: profile.voiceButtonName)

        let down = tracker.process(reportID: 0x02, payload: [0x21, 0x02, 0, 0])
        XCTAssertEqual(down, [ButtonEvent(name: "voice", isDown: true)])
        XCTAssertEqual(voice.process(down[0]), true)
        XCTAssertEqual(tracker.process(reportID: 0x02, payload: [0x21, 0x02, 0, 0]), [])

        let up = tracker.process(reportID: 0x02, payload: [0, 0, 0, 0])
        XCTAssertEqual(up, [ButtonEvent(name: "voice", isDown: false)])
        XCTAssertEqual(voice.process(up[0]), false)

        XCTAssertEqual(tracker.process(reportID: 0x01, payload: [0x52, 0, 0]),
                       [ButtonEvent(name: "dpad_up", isDown: true)])
        XCTAssertEqual(tracker.process(reportID: 0xF0, payload: [0xB8]), [])
    }

    func testStripReportID() {
        XCTAssertEqual(stripReportID(0xF0, from: [0xF0, 0xB8], expectedPayload: 1), [0xB8])
        XCTAssertEqual(stripReportID(0xF0, from: [0xB8, 0x00], expectedPayload: 2), [0xB8, 0x00])
        XCTAssertEqual(stripReportID(0x01, from: [0x01, 0x00], expectedPayload: 2), [0x01, 0x00])
    }

    func testOpusRoundTrip() throws {
        var err: Int32 = 0
        let encoder = try XCTUnwrap(opus_encoder_create(16_000, 1, OPUS_APPLICATION_RESTRICTED_LOWDELAY, &err))
        defer { opus_encoder_destroy(encoder) }
        let decoder = try OpusDecoder()

        var energy = 0.0
        for frame in 0..<25 {
            let input = (0..<320).map { n in
                Int16(8000 * sin(2 * .pi * 440 * Double(frame * 320 + n) / 16_000))
            }
            var packet = [UInt8](repeating: 0, count: 200)
            let n = opus_encode(encoder, input, 320, &packet, 200)
            XCTAssertGreaterThan(n, 0)
            let pcm = try decoder.decode(Array(packet.prefix(Int(n))))
            XCTAssertEqual(pcm.count, 320)
            if frame > 5 { energy += pcm.reduce(0) { $0 + Double($1) * Double($1) } }
        }
        XCTAssertGreaterThan(energy, 1e6)
    }

    func testOpusRejectsCorruptPacket() throws {
        XCTAssertThrowsError(try OpusDecoder().decode([0xFF, 0xFF]))
    }

    func testWAVHeader() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let w = try WAVWriter(url: url)
        try w.append([1, -1, 300])
        try w.close()
        let d = [UInt8](try Data(contentsOf: url))
        XCTAssertEqual(d.count, 50)
        XCTAssertEqual(String(decoding: d[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(UInt32(d[4]) | UInt32(d[5]) << 8, 42)
        XCTAssertEqual(UInt32(d[40]) | UInt32(d[41]) << 8, 6)
        XCTAssertEqual(Array(d[44...45]), [1, 0])
    }

    func testCaptureRoundTripAndStats() {
        var data = CaptureFile.encode(timestampNs: 1_000, reportID: 0xF0, payload: [0xB8, 1])
        data += CaptureFile.encode(timestampNs: 2_000, reportID: 0x02, payload: [])
        let r = CaptureFile.decode(data)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].timestampNs, 1_000)
        XCTAssertEqual(r[0].payload, [0xB8, 1])
        XCTAssertEqual(r[1].reportID, 0x02)

        var stats = AudioStats()
        for ms: UInt64 in [0, 20, 40, 100] {
            stats.record(timestampNs: ms * 1_000_000, payload: [0xB8], decodeFailed: false)
        }
        XCTAssertEqual(stats.estimatedLostPackets, 2)
    }
}
