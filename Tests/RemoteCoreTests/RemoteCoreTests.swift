import COpus
import CoreGraphics
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

    func testKeyComboParsing() throws {
        let combo = try KeyCombo("cmd+shift+a")
        XCTAssertEqual(combo.keyCode, 0)
        XCTAssertEqual(combo.flags, CGEventFlags([.maskCommand, .maskShift]).rawValue)
        XCTAssertEqual(try KeyCombo("Return").keyCode, 36)
        XCTAssertThrowsError(try KeyCombo("cmd+nosuchkey"))
        XCTAssertThrowsError(try KeyCombo("hyper+a"))
        XCTAssertThrowsError(try KeyCombo(""))
    }

    func testModifierOnlyAndRecordedText() throws {
        XCTAssertEqual(try KeyCombo("fn").keyCode, 63)
        XCTAssertEqual(try KeyCombo("fn").modifierOnlyFlag, CGEventFlags.maskSecondaryFn.rawValue)
        XCTAssertEqual(try KeyCombo("ropt").keyCode, 61)
        XCTAssertNil(try KeyCombo("cmd+a").modifierOnlyFlag)
        XCTAssertEqual(KeyCombo.recordedText(keyCode: 36, flags: []), "return")
        XCTAssertEqual(KeyCombo.recordedText(keyCode: 35, flags: [.maskCommand, .maskShift]), "shift+cmd+p")
        XCTAssertEqual(KeyCombo.recordedModifierText(keyCode: 63), "fn")
        XCTAssertEqual(KeyCombo.displayText("cmd+shift+p"), "⌘⇧P")
        // 記録した文字列はそのまま読み込める
        XCTAssertEqual(try KeyCombo("shift+cmd+p").keyCode, 35)
    }

    func testActionsAndDisabledButtons() throws {
        let map = try KeyMap(["mute": "none", "tv": "media:play_pause", "home": "system:mission_control"])
        XCTAssertEqual(map.disabledButtons, ["mute"])
        XCTAssertNil(map.bindings["mute"])
        XCTAssertEqual(Set(map.suppressedButtons), ["mute", "tv", "home"])

        let media = try XCTUnwrap(map.bindings["tv"])
        XCTAssertEqual(media.mediaKey, 16)
        XCTAssertEqual(KeyAction(combo: media, isDown: true).events, [])

        let system = try XCTUnwrap(map.bindings["home"])
        XCTAssertEqual(system.keyCode, 126)
        XCTAssertEqual(system.flags, CGEventFlags.maskControl.rawValue)
        XCTAssertEqual(system.text, "system:mission_control")

        XCTAssertEqual(KeyCombo.displayText("none"), "無効")
        XCTAssertEqual(KeyCombo.displayText("media:mute"), "ミュート")
        XCTAssertEqual(KeyCombo.displayText("system:spotlight"), "Spotlight")
        XCTAssertThrowsError(try KeyCombo("media:nosuch"))
        XCTAssertThrowsError(try KeyCombo("system:nosuch"))

        // 一覧の項目はすべて読み込める
        for item in ActionCatalog.mediaItems + ActionCatalog.systemItems {
            XCTAssertNoThrow(try KeyCombo(item.id), item.id)
        }
        XCTAssertNil(KeyMap.defaultBindings["play_pause"])
    }

    func testInjectedEventOrder() throws {
        let ctrl = CGEventFlags.maskControl.rawValue
        let cmd = CGEventFlags.maskCommand.rawValue
        let ctrlT = try KeyCombo("ctrl+t")
        XCTAssertEqual(KeyAction(combo: ctrlT, isDown: true).events, [
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 59, flags: ctrl),
            InjectedKeyEvent(kind: .keyDown, keyCode: 17, flags: ctrl),
        ])
        XCTAssertEqual(KeyAction(combo: ctrlT, isDown: false).events, [
            InjectedKeyEvent(kind: .keyUp, keyCode: 17, flags: ctrl),
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 59, flags: 0),
        ])

        // 複数の修飾キーは押した順と逆に離す
        let both = try KeyCombo("cmd+ctrl+a")
        XCTAssertEqual(KeyAction(combo: both, isDown: false).events, [
            InjectedKeyEvent(kind: .keyUp, keyCode: 0, flags: ctrl | cmd),
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 55, flags: ctrl),
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 59, flags: 0),
        ])

        // 修飾キーのないキーと、修飾キー単体
        XCTAssertEqual(KeyAction(combo: try KeyCombo("return"), isDown: true).events,
                       [InjectedKeyEvent(kind: .keyDown, keyCode: 36, flags: 0)])
        let fn = try KeyCombo("fn")
        XCTAssertEqual(KeyAction(combo: fn, isDown: true).events, [
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 63, flags: CGEventFlags.maskSecondaryFn.rawValue),
        ])
        XCTAssertEqual(KeyAction(combo: fn, isDown: false).events, [
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 63, flags: 0),
        ])
    }

    func testVoiceKeyReleaseIsDelayedAndKeepsOrder() throws {
        var posted: [KeyAction] = []
        let router = ButtonKeyRouter(map: try KeyMap(["voice": "fn"]), voiceButton: "voice", voiceReleaseDelay: 60) {
            posted.append($0)
        }
        let fn = try KeyCombo("fn")
        router.process(ButtonEvent(name: "voice", isDown: true))
        router.process(ButtonEvent(name: "voice", isDown: false))
        XCTAssertEqual(posted, [KeyAction(combo: fn, isDown: true)])
        // 遅延中に押し直しても、解放 → 押下 の順を保つ
        router.process(ButtonEvent(name: "voice", isDown: true))
        XCTAssertEqual(posted, [KeyAction(combo: fn, isDown: true), KeyAction(combo: fn, isDown: false),
                                KeyAction(combo: fn, isDown: true)])
        router.releaseAll()
        XCTAssertEqual(posted.last, KeyAction(combo: fn, isDown: false))
    }

    func testKeyMapperPressReleaseAndCleanup() throws {
        var mapper = KeyMapper(map: try KeyMap(KeyMap.defaultBindings))
        let ret = try KeyCombo("return")
        XCTAssertEqual(mapper.process(ButtonEvent(name: "select", isDown: true)), KeyAction(combo: ret, isDown: true))
        XCTAssertNil(mapper.process(ButtonEvent(name: "select", isDown: true)))
        XCTAssertEqual(mapper.process(ButtonEvent(name: "select", isDown: false)), KeyAction(combo: ret, isDown: false))
        XCTAssertNil(mapper.process(ButtonEvent(name: "select", isDown: false)))
                XCTAssertNil(mapper.process(ButtonEvent(name: "mute", isDown: true)))

        _ = mapper.process(ButtonEvent(name: "select", isDown: true))
        XCTAssertEqual(mapper.releaseAll(), [KeyAction(combo: ret, isDown: false)])
        XCTAssertEqual(mapper.releaseAll(), [])
    }

    func testSystemUsagesForSuppression() {
        let p = FireTVRemoteProfile()
        XCTAssertEqual(p.systemUsage(of: "dpad_up"), 0x7_0000_0052)
        XCTAssertEqual(p.systemUsage(of: "select"), 0x7_0000_0058)
        XCTAssertEqual(p.systemUsage(of: "back"), 0x7_0000_00F1)
        XCTAssertEqual(p.systemUsage(of: "play_pause"), 0xC_0000_00CD)
        XCTAssertEqual(p.systemUsage(of: "voice"), 0xC_0000_0221)
        XCTAssertNil(p.systemUsage(of: "nosuch"))
        XCTAssertEqual(KeySuppressor.mappingJSON(usages: []), "{\"UserKeyMapping\":[]}")
        XCTAssertEqual(KeySuppressor.mappingJSON(usages: [1]),
                       "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":1,\"HIDKeyboardModifierMappingDst\":0}]}")
    }

    func testAudioDeviceResolve() throws {
        let list = [
            AudioDeviceInfo(id: 1, uid: "BlackHole2ch_UID", name: "BlackHole 2ch", inputChannels: 2, outputChannels: 2),
            AudioDeviceInfo(id: 2, uid: "BlackHole16ch_UID", name: "BlackHole 16ch", inputChannels: 16, outputChannels: 16),
        ]
        XCTAssertEqual(try AudioDevices.resolve("BlackHole2ch_UID", in: list).id, 1)
        XCTAssertEqual(try AudioDevices.resolve("blackhole 16", in: list).id, 2)
        XCTAssertThrowsError(try AudioDevices.resolve("BlackHole", in: list))
        XCTAssertThrowsError(try AudioDevices.resolve("none", in: list))
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

        // 発話の間の無音は欠落にも最大間隔にも数えない
        var sessions = AudioStats()
        for start: UInt64 in [0, 5_000] {
            sessions.beginSession()
            for ms: UInt64 in [0, 20, 40] {
                sessions.record(timestampNs: (start + ms) * 1_000_000, payload: [0xB8], decodeFailed: false)
            }
        }
        XCTAssertEqual(sessions.estimatedLostPackets, 0)
        XCTAssertEqual(sessions.maxGapNs, 20_000_000)
        XCTAssertEqual(sessions.spanSeconds, 0.08, accuracy: 0.001)
    }
}
