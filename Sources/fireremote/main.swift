import Foundation
import IOKit.hid
import RemoteCore

setvbuf(stdout, nil, _IOLBF, 0)

let usage = """
使い方: fireremote <command>
  probe                     デバイス・権限・HID Descriptor を表示
  listen [--seconds N] [--seize]
                            全 Report とボタンイベントを表示(マイクは操作しない)
  record [--out 名前] [--seconds N] [--seize]
                            音声ボタンを押している間を captures/名前.{bin,wav} に保存
  decode <入力.bin> <出力.wav> [--audio-report 0xF0]
                            記録済みの生 Report を WAV に変換
"""

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

func accessDescription(_ a: IOHIDAccessType) -> String {
    switch a {
    case kIOHIDAccessTypeGranted: return "許可済み"
    case kIOHIDAccessTypeDenied: return "拒否"
    default: return "未決定"
    }
}

func onSignal(_ handler: @escaping () -> Void) -> [DispatchSourceSignal] {
    [SIGINT, SIGTERM].map { sig in
        signal(sig, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        s.setEventHandler(handler: handler)
        s.resume()
        return s
    }
}

func startOrExit(_ remote: HIDRemote) {
    let r = remote.start()
    print("IOHIDManagerOpen: \(ioReturnDescription(r))")
    if r != kIOReturnSuccess {
        print("入力監視の権限: \(accessDescription(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)))")
        exit(2)
    }
}

func probe() {
    print("入力監視の権限: \(accessDescription(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)))")
    let remote = HIDRemote(profile: FireTVRemoteProfile())
    let devices = remote.connectedDevices()
    print("検出数: \(devices.count)")
    for device in devices {
        for key in [kIOHIDProductKey, kIOHIDTransportKey, kIOHIDVendorIDKey, kIOHIDProductIDKey,
                    kIOHIDPrimaryUsagePageKey, kIOHIDPrimaryUsageKey, kIOHIDMaxInputReportSizeKey,
                    kIOHIDMaxOutputReportSizeKey, kIOHIDMaxFeatureReportSizeKey] {
            print("  \(key): \(IOHIDDeviceGetProperty(device, key as CFString) ?? "-" as CFString)")
        }
        let descriptor = HIDRemote.descriptor(of: device)
        print("  Descriptor(\(descriptor.count)B): \(hex(descriptor))")
        let reports = HIDReportDescriptor.parse(descriptor)
        for r in reports {
            print(String(format: "  Report 0x%02X page=0x%04X input=%dB output=%dB feature=%dB",
                         r.id, r.usagePage, r.inputBytes, r.outputBytes, r.featureBytes))
        }
        if let v = remote.profile.voiceReports(in: reports) {
            print(String(format: "  推定: audio=0x%02X(%dB) micEnable=0x%02X",
                         v.audioReportID, v.audioPayloadBytes, v.micEnableReportID))
        }
        let open = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        print("  IOHIDDeviceOpen(非占有): \(ioReturnDescription(open))")
        if open == kIOReturnSuccess { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
    }
}

func listen(_ args: [String]) {
    let remote = HIDRemote(profile: FireTVRemoteProfile(), seize: args.contains("--seize"))
    var tracker = ButtonTracker(profile: remote.profile)
    remote.onConnect = { _ in print("[接続]") }
    remote.onDisconnect = { print("[切断]") }
    remote.onReport = { report in
        print(String(format: "report 0x%02X (%dB) %@", report.reportID, report.payload.count, hex(report.payload)))
        for e in tracker.process(reportID: report.reportID, payload: report.payload) {
            print("  \(e.isDown ? "押下" : "解放"): \(e.name)")
        }
    }
    startOrExit(remote)
    let signals = onSignal { exit(0) }
    _ = signals
    if let s = option("--seconds", in: args).flatMap(Double.init) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { exit(0) }
    }
    print("ボタンを押してください。Ctrl-C で終了します。")
    CFRunLoopRun()
}

func record(_ args: [String]) throws {
    let name = option("--out", in: args) ?? {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "voice-\(f.string(from: Date()))"
    }()
    try FileManager.default.createDirectory(atPath: "captures", withIntermediateDirectories: true)
    let binURL = URL(fileURLWithPath: "captures/\(name).bin")
    let wavURL = URL(fileURLWithPath: "captures/\(name).wav")
    FileManager.default.createFile(atPath: binURL.path, contents: nil)
    let bin = try FileHandle(forWritingTo: binURL)
    let wav = try WAVWriter(url: wavURL)
    let decoder = try OpusDecoder()

    let remote = HIDRemote(profile: FireTVRemoteProfile(), seize: args.contains("--seize"))
    var tracker = ButtonTracker(profile: remote.profile)
    var voice = VoiceController(voiceButton: remote.profile.voiceButtonName)
    var stats = AudioStats()

    func finish() {
        if voice.micEnabled {
            remote.setMic(enabled: false) { _ in }
            remote.flushWrites()
        }
        try? bin.close()
        try? wav.close()
        print("統計: \(stats.summary)")
        print(String(format: "WAV: %@ (%.2f秒)", wavURL.path, Double(wav.sampleCount) / 16_000))
        print("生Report: \(binURL.path)")
        exit(stats.packets > 0 ? 0 : 1)
    }

    remote.onConnect = { _ in
        if let v = remote.voiceReports {
            print(String(format: "[接続] audio=0x%02X micEnable=0x%02X", v.audioReportID, v.micEnableReportID))
        } else {
            print("[接続] Descriptor から音声 Report を特定できません")
        }
    }
    remote.onDisconnect = { print("[切断]") }
    remote.onReport = { report in
        try? bin.write(contentsOf: CaptureFile.encode(timestampNs: report.timestampNs,
                                                      reportID: report.reportID, payload: report.payload))
        if report.reportID == remote.voiceReports?.audioReportID {
            var failed = false
            do { try wav.append(try decoder.decode(report.payload)) } catch {
                failed = true
                print("デコード失敗: \(error)")
            }
            if stats.packets == 0 { print("音声受信開始 先頭: \(hex(Array(report.payload.prefix(8))))") }
            stats.record(timestampNs: report.timestampNs, payload: report.payload, decodeFailed: failed)
            return
        }
        print(String(format: "report 0x%02X %@", report.reportID, hex(report.payload)))
        for event in tracker.process(reportID: report.reportID, payload: report.payload) {
            print("  \(event.isDown ? "押下" : "解放"): \(event.name)")
            guard let enable = voice.process(event) else { continue }
            remote.setMic(enabled: enable) { r in
                print("  マイク\(enable ? "有効化" : "停止"): \(ioReturnDescription(r))")
            }
            if enable {
                let before = stats.packets
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if voice.micEnabled && stats.packets == before {
                        print("  警告: マイク有効化から1.5秒経っても音声 Report が届きません")
                    }
                }
            } else {
                // 停止後に届く残りを受けてから終了する
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { finish() }
            }
        }
    }

    startOrExit(remote)
    let signals = onSignal { finish() }
    _ = signals
    let seconds = option("--seconds", in: args).flatMap(Double.init) ?? 60
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { finish() }
    print("音声ボタンを押している間だけ録音します(最大\(Int(seconds))秒待機)。")
    CFRunLoopRun()
}

func decode(_ args: [String]) throws {
    let paths = args.enumerated().filter { i, a in
        !a.hasPrefix("--") && (i == 0 || args[i - 1] != "--audio-report")
    }.map(\.element)
    guard paths.count == 2 else {
        print(usage)
        exit(64)
    }
    let audioID = option("--audio-report", in: args)
        .flatMap { UInt8($0.replacingOccurrences(of: "0x", with: ""), radix: 16) } ?? 0xF0
    let decoder = try OpusDecoder()
    let wav = try WAVWriter(url: URL(fileURLWithPath: paths[1]))
    var stats = AudioStats()
    for r in CaptureFile.decode(try Data(contentsOf: URL(fileURLWithPath: paths[0]))) where r.reportID == audioID {
        var failed = false
        do { try wav.append(try decoder.decode(r.payload)) } catch { failed = true }
        stats.record(timestampNs: r.timestampNs, payload: r.payload, decodeFailed: failed)
    }
    try wav.close()
    print("統計: \(stats.summary)")
    print(String(format: "WAV: %@ (%.2f秒)", paths[1], Double(wav.sampleCount) / 16_000))
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "probe": probe()
    case "listen": listen(Array(args.dropFirst()))
    case "record": try record(Array(args.dropFirst()))
    case "decode": try decode(Array(args.dropFirst()))
    default:
        print(usage)
        exit(64)
    }
} catch {
    print("エラー: \(error)")
    exit(1)
}
