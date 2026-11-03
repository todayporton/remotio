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
        XCTAssertEqual(KeyCombo.recordedMediaText(key: 2), "media:brightness_up")
        XCTAssertNil(KeyCombo.recordedMediaText(key: 999))
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
        // 修飾キーのフラグには、実際のキーボードと同じく左右を示すフラグも付く
        let ctrl = CGEventFlags.maskControl.rawValue | 0x1
        let cmd = CGEventFlags.maskCommand.rawValue | 0x8
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

        // 矢印キーには実際のキーボードと同じフラグを付ける。修飾キーのイベントには付けない
        let arrowFlags = CGEventFlags.maskSecondaryFn.rawValue | CGEventFlags.maskNumericPad.rawValue
        let opt = CGEventFlags.maskAlternate.rawValue | 0x20
        XCTAssertEqual(KeyAction(combo: try KeyCombo("ctrl+opt+left"), isDown: true).events, [
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 59, flags: ctrl),
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 58, flags: ctrl | opt),
            InjectedKeyEvent(kind: .keyDown, keyCode: 123, flags: ctrl | opt | arrowFlags),
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
        XCTAssertEqual(p.standardActionName(of: "volume_up"), "音量を上げる")
        XCTAssertNil(p.standardActionName(of: "home"))
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

    func testGainAmplifiesAttenuatesAndClips() {
        let unity = AudioGain.apply([1000, -1000], decibels: 0)
        XCTAssertEqual(unity.samples, [1000, -1000])
        XCTAssertFalse(unity.clipped)

        let up = AudioGain.apply([1000], decibels: 20)
        XCTAssertEqual(up.samples, [10000])
        XCTAssertEqual(AudioGain.apply([1000], decibels: -6).samples[0], 501, accuracy: 1)

        let clipped = AudioGain.apply([20000, -20000], decibels: 24)
        XCTAssertEqual(clipped.samples, [Int16.max, Int16.min])
        XCTAssertTrue(clipped.clipped)
        XCTAssertEqual(clipped.peak, 1, accuracy: 0.001)
    }

    func testGainIsClampedToItsRange() {
        XCTAssertEqual(AudioGain.clamp(decibels: 100), AudioGain.maxDecibels)
        XCTAssertEqual(AudioGain.clamp(decibels: -100), AudioGain.minDecibels)
        XCTAssertEqual(AudioGain.apply([100], decibels: 100).samples, AudioGain.apply([100], decibels: 24).samples)
    }

    func testMeterPosition() {
        XCTAssertEqual(AudioGain.meterPosition(peak: 0), 0)
        XCTAssertEqual(AudioGain.meterPosition(peak: 0.0001), 0, accuracy: 0.001)
        XCTAssertEqual(AudioGain.meterPosition(peak: 1), 1, accuracy: 0.001)
        XCTAssertEqual(AudioGain.meterPosition(peak: 0.1), 2.0 / 3, accuracy: 0.001)
        XCTAssertEqual(AudioGain.meterPosition(decibels: AudioGain.targetPeakDecibels), 0.8, accuracy: 0.001)
    }

    func testMeterClearsAndIgnoresLatePacketsAfterMicStops() {
        let meter = MicLevelMeter()
        meter.update(peak: 1, clipped: true)
        XCTAssertEqual(meter.position, 0)

        meter.setActive(true)
        meter.update(peak: 1, clipped: true)
        XCTAssertEqual(meter.position, 1, accuracy: 0.001)
        XCTAssertTrue(meter.clipping)

        meter.setActive(false)
        XCTAssertEqual(meter.position, 0)
        XCTAssertFalse(meter.clipping)
        meter.update(peak: 1, clipped: true)
        XCTAssertEqual(meter.position, 0)
        XCTAssertFalse(meter.clipping)
    }

    func testSetupProgressFollowsTheOrderOfSteps() {
        var progress = SetupProgress(inputMonitoringGranted: false, accessibilityGranted: false,
                                     remoteConnected: false, microphoneReady: false)
        XCTAssertEqual(progress.currentStep, .inputMonitoring)
        progress.inputMonitoringGranted = true
        XCTAssertEqual(progress.currentStep, .accessibility)
        progress.accessibilityGranted = true
        XCTAssertEqual(progress.currentStep, .pairing)
        progress.remoteConnected = true
        XCTAssertEqual(progress.currentStep, .microphone)
        progress.microphoneReady = true
        XCTAssertNil(progress.currentStep)
    }

    func testSetupOpensAutomaticallyOnlyWhenNeeded() {
        let missing = SetupProgress(inputMonitoringGranted: true, accessibilityGranted: false,
                                    remoteConnected: true, microphoneReady: true)
        XCTAssertTrue(missing.shouldOpenAutomatically(dismissed: false))
        XCTAssertFalse(missing.shouldOpenAutomatically(dismissed: true))
        // スリープ中のリモコンは未接続に見えるので、それだけでは開かない
        let sleeping = SetupProgress(inputMonitoringGranted: true, accessibilityGranted: true,
                                     remoteConnected: false, microphoneReady: true)
        XCTAssertFalse(sleeping.shouldOpenAutomatically(dismissed: false))
    }

    func testDictationTriggerTapsTheModifierTwiceOnPressAndRelease() throws {
        let combo = try KeyCombo("dictation:ctrl")
        XCTAssertTrue(combo.isDoubleTap)
        let ctrl = CGEventFlags.maskControl.rawValue | 0x1
        let expected = [
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 59, flags: ctrl),
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 59, flags: 0),
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 59, flags: ctrl),
            InjectedKeyEvent(kind: .flagsChanged, keyCode: 59, flags: 0),
        ]
        XCTAssertEqual(KeyAction(combo: combo, isDown: true).events, expected)
        XCTAssertEqual(KeyAction(combo: combo, isDown: false).events, expected)

        XCTAssertEqual(try KeyCombo("dictation:fn").keyCode, 63)
        XCTAssertEqual(try KeyCombo("dictation:rcmd").keyCode, 54)
        // 左右の Command は、左右を示すフラグで区別する
        XCTAssertEqual(KeyAction(combo: try KeyCombo("dictation:rcmd"), isDown: true).events.first?.flags,
                       CGEventFlags.maskCommand.rawValue | 0x10)
        XCTAssertEqual(KeyAction(combo: try KeyCombo("dictation:lcmd"), isDown: true).events.first?.flags,
                       CGEventFlags.maskCommand.rawValue | 0x8)
        XCTAssertEqual(try KeyCombo("dictation:lcmd").keyCode, 55)
        XCTAssertThrowsError(try KeyCombo("dictation:shift"))
        XCTAssertEqual(KeyCombo.displayText("dictation:ctrl"), "音声入力(Control キーを2回押す)")
        XCTAssertEqual(ActionCatalog.dictationItems.count, 4)
    }

    /// 押し方の判定用の時計。指定時刻まで進め、その間の予定を順に実行する
    private final class FakeClock {
        var now: TimeInterval = 0
        private var tasks: [(id: Int, at: TimeInterval, work: () -> Void)] = []
        private var nextID = 0

        lazy var schedule: GestureScheduler = { [unowned self] delay, work in
            let id = self.nextID
            self.nextID += 1
            self.tasks.append((id, self.now + delay, work))
            return { [weak self] in self?.tasks.removeAll { $0.id == id } }
        }

        func advance(to time: TimeInterval) {
            while let next = tasks.filter({ $0.at <= time }).min(by: { $0.at < $1.at }) {
                tasks.removeAll { $0.id == next.id }
                now = next.at
                next.work()
            }
            now = time
        }
    }

    private func gestureRouter(_ bindings: [String: String], clock: FakeClock,
                               posted: @escaping (String) -> Void) throws -> ButtonKeyRouter {
        let map = try KeyMap(bindings, standardKeys: ["mute": "media:mute"])
        return ButtonKeyRouter(map: map, voiceButton: "voice", voiceReleaseDelay: 0, schedule: clock.schedule,
                               repeatInterval: 0.1, keyRepeatDelay: 0.4) {
            posted("\($0.combo.text)\($0.isRepeat ? "↻" : $0.isDown ? "↓" : "↑")")
        }
    }

    func testTapLongAndDoublePress() throws {
        let clock = FakeClock()
        var log: [String] = []
        let router = try gestureRouter(["tv": "a", "tv.long": "b", "tv.double": "c"], clock: clock) { log.append($0) }

        // タップは、2回押しの待ち時間が過ぎてから送る
        router.process(ButtonEvent(name: "tv", isDown: true)); clock.advance(to: 0.1)
        router.process(ButtonEvent(name: "tv", isDown: false)); clock.advance(to: 0.35)
        XCTAssertEqual(log, [])
        clock.advance(to: 0.5)
        XCTAssertEqual(log, ["a↓", "a↑"])

        // 2回押しは、2回目の押下で送る
        log = []
        clock.advance(to: 1)
        router.process(ButtonEvent(name: "tv", isDown: true)); clock.advance(to: 1.1)
        router.process(ButtonEvent(name: "tv", isDown: false)); clock.advance(to: 1.2)
        router.process(ButtonEvent(name: "tv", isDown: true))
        XCTAssertEqual(log, ["c↓", "c↑"])
        router.process(ButtonEvent(name: "tv", isDown: false)); clock.advance(to: 2)
        XCTAssertEqual(log, ["c↓", "c↑"])

        // 長押しは 0.5 秒で1回送り、離してもタップは送らない
        log = []
        router.process(ButtonEvent(name: "tv", isDown: true)); clock.advance(to: 2.4)
        XCTAssertEqual(log, [])
        clock.advance(to: 2.6)
        XCTAssertEqual(log, ["b↓", "b↑"])
        router.process(ButtonEvent(name: "tv", isDown: false)); clock.advance(to: 3.5)
        XCTAssertEqual(log, ["b↓", "b↑"])
    }

    func testLongPressHoldAndRepeat() throws {
        let clock = FakeClock()
        var log: [String] = []
        let router = try gestureRouter(["tv.long": "b", "tv.long.mode": "hold",
                                        "menu.long": "d", "menu.long.mode": "repeat"], clock: clock) { log.append($0) }

        // 押している間: 判定したら押し、離したら離す
        router.process(ButtonEvent(name: "tv", isDown: true)); clock.advance(to: 1)
        XCTAssertEqual(log, ["b↓"])
        router.process(ButtonEvent(name: "tv", isDown: false))
        XCTAssertEqual(log, ["b↓", "b↑"])

        // リピート: 判定したら送り、間隔ごとに送り続け、離したら止める
        log = []
        router.process(ButtonEvent(name: "menu", isDown: true)); clock.advance(to: 1.4)
        XCTAssertEqual(log, [])
        clock.advance(to: 1.75)
        XCTAssertEqual(log, ["d↓", "d↑", "d↓", "d↑", "d↓", "d↑"])
        router.process(ButtonEvent(name: "menu", isDown: false)); clock.advance(to: 3)
        XCTAssertEqual(log.count, 6)

        // 押している間の途中で切断したら、押したままのキーを離す
        log = []
        router.process(ButtonEvent(name: "tv", isDown: true)); clock.advance(to: 4)
        router.releaseAll()
        XCTAssertEqual(log, ["b↓", "b↑"])
    }

    func testGesturesKeepOtherButtonsImmediateAndUseStandardTap() throws {
        let clock = FakeClock()
        var log: [String] = []
        let router = try gestureRouter(["select": "return", "mute.double": "c", "voice": "fn", "voice.long": "b"],
                                       clock: clock) { log.append($0) }
        // 長押しも2回押しもないボタンは、押した瞬間に送る
        router.process(ButtonEvent(name: "select", isDown: true))
        XCTAssertEqual(log, ["return↓"])
        router.process(ButtonEvent(name: "select", isDown: false))

        // タップが「標準」なら、標準と同じ操作を Remotio から送る
        log = []
        router.process(ButtonEvent(name: "mute", isDown: true))
        router.process(ButtonEvent(name: "mute", isDown: false)); clock.advance(to: 1)
        XCTAssertEqual(log, ["media:mute↓", "media:mute↑"])

        // 音声ボタンは Push-to-Talk を保つため、長押しを割り当てても押した瞬間に送る
        log = []
        router.process(ButtonEvent(name: "voice", isDown: true))
        XCTAssertEqual(log, ["fn↓"])
    }

    func testKeyMapParsesGestureBindings() throws {
        let map = try KeyMap(["tv": "a", "tv.long": "b", "tv.long.mode": "repeat", "menu.long.mode": "hold"])
        XCTAssertEqual(map.bindings.keys.sorted(), ["tv"])
        XCTAssertEqual(map.gestures["tv"]?.long?.text, "b")
        XCTAssertEqual(map.gestures["tv"]?.longMode, .repeat)
        // 送り方だけでは判定しない
        XCTAssertNil(map.gestures["menu"])
        XCTAssertEqual(Set(map.suppressedButtons), ["tv"])
        XCTAssertThrowsError(try KeyMap(["tv.long.mode": "sometimes"]))
    }

    func testAppOverridesReplaceOnlyTheirButtons() throws {
        let global = ["select": "return", "back": "escape", "tv.long": "b"]
        let merged = AppKeymaps.merge(global, ["select": "space", "back": AppKeymaps.standardValue, "menu": "cmd+w"])
        XCTAssertEqual(merged, ["select": "space", "menu": "cmd+w", "tv.long": "b"])
        XCTAssertEqual(AppKeymaps.merge(global, nil), global)
        XCTAssertNoThrow(try KeyMap(merged))
    }

    func testHeldKeysRepeatLikeAKeyboard() throws {
        let clock = FakeClock()
        var log: [String] = []
        let router = try gestureRouter(["select": "ctrl+t", "back": "fn", "menu": "dictation:ctrl", "tv": "media:volume_up"],
                                       clock: clock) { log.append($0) }
        // 通常のキーは、リピートまでの時間が過ぎると間隔ごとに押下を繰り返し、離すと止まる
        router.process(ButtonEvent(name: "select", isDown: true)); clock.advance(to: 0.35)
        XCTAssertEqual(log, ["ctrl+t↓"])
        clock.advance(to: 0.65)
        XCTAssertEqual(log, ["ctrl+t↓", "ctrl+t↻", "ctrl+t↻", "ctrl+t↻"])
        router.process(ButtonEvent(name: "select", isDown: false)); clock.advance(to: 2)
        XCTAssertEqual(log.last, "ctrl+t↑")
        XCTAssertEqual(log.count, 5)

        // 修飾キーだけと、音声入力の2回押しは繰り返さない
        log = []
        router.process(ButtonEvent(name: "back", isDown: true))
        router.process(ButtonEvent(name: "menu", isDown: true)); clock.advance(to: 4)
        XCTAssertEqual(log.filter { $0.hasSuffix("↻") }, [])

        // メディアキーも繰り返す。切断したら止まる
        log = []
        router.process(ButtonEvent(name: "tv", isDown: true)); clock.advance(to: 4.45)
        XCTAssertEqual(log, ["media:volume_up↓", "media:volume_up↻"])
        router.releaseAll(); clock.advance(to: 6)
        XCTAssertFalse(log.dropFirst(2).contains("media:volume_up↻"))

        // 繰り返しのイベントは通常キーの押下だけで、修飾キーは押したまま
        let repeatEvents = KeyAction(combo: try KeyCombo("ctrl+t"), isDown: true, isRepeat: true).events
        XCTAssertEqual(repeatEvents, [InjectedKeyEvent(kind: .keyDown, keyCode: 17,
                                                       flags: CGEventFlags.maskControl.rawValue | 0x1)])
    }

    func testCommandsKeepTheirTextAndDoNotSendKeys() throws {
        let url = try KeyCombo("url:raycast://extensions/raycast/Clipboard-History")
        XCTAssertEqual(url.command, .openURL(URL(string: "raycast://extensions/raycast/Clipboard-History")!))
        XCTAssertEqual(url.text, "url:raycast://extensions/raycast/Clipboard-History")
        XCTAssertEqual(KeyAction(combo: url, isDown: true).events, [])
        XCTAssertFalse(url.repeatsWhileHeld)

        let shell = try KeyCombo("shell:open -a Safari")
        XCTAssertEqual(shell.command, .shell("open -a Safari"))
        XCTAssertEqual(KeyCombo.displayText("shell:open -a Safari"), "$ open -a Safari")
        XCTAssertTrue(KeyCombo.displayText("url:https://example.com/a/very/long/path").hasPrefix("🔗 https://example.com"))

        // 中身のないものや、スキームのない URL は受け付けない
        XCTAssertThrowsError(try KeyCombo("shell:  "))
        XCTAssertThrowsError(try KeyCombo("url:not a url"))
        XCTAssertNoThrow(try KeyMap(["tv": "shell:say hi", "tv.long": "url:https://example.com"]))
    }
}
