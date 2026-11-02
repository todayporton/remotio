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
  devices                   オーディオデバイスの一覧を表示
  stream --device 名前 [--seconds N] [--seize] [--no-suppress]
                            音声ボタンを押している間の音声を指定デバイスへ出力
  run [--config 割り当て.json] [--device 名前] [--dry-run] [--no-suppress] [--seconds N]
                            キー割り当てを有効化。--device 指定時は音声も出力
  send-key <キー>           指定キーを 1 回送信(検証用。例: cmd+shift+a)
  replay <入力.bin> --device 名前
                            記録済みの音声を指定デバイスへ出力(経路の検証用)
  capture-input --device 名前 --out 出力.wav [--seconds N]
                            デバイスの入力を WAV に保存(経路の検証用)
  decode <入力.bin> <出力.wav> [--audio-report 0xF0]
                            記録済みの生 Report を WAV に変換
"""

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func timestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
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

func startOrExit(_ session: VoiceSession) {
    startOrExit(session.start())
}

func startOrExit(_ remote: HIDRemote) {
    startOrExit(remote.start())
}

func startOrExit(_ r: IOReturn) {
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
    let session = try VoiceSession(profile: FireTVRemoteProfile(), seize: args.contains("--seize"))

    func finish() {
        session.shutdown()
        try? bin.close()
        try? wav.close()
        print("統計: \(session.stats.summary)")
        print(String(format: "WAV: %@ (%.2f秒)", wavURL.path, Double(wav.sampleCount) / 16_000))
        print("生Report: \(binURL.path)")
        exit(session.stats.packets > 0 ? 0 : 1)
    }

    session.onLog = { print($0) }
    session.onReport = { report in
        try? bin.write(contentsOf: CaptureFile.encode(timestampNs: report.timestampNs,
                                                      reportID: report.reportID, payload: report.payload))
    }
    session.onPCM = { try? wav.append($0) }
    session.onMicChange = { enabled in
        // 停止後に届く残りを受けてから終了する
        if !enabled { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { finish() } }
    }

    startOrExit(session)
    let signals = onSignal { finish() }
    _ = signals
    let seconds = option("--seconds", in: args).flatMap(Double.init) ?? 60
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { finish() }
    print("音声ボタンを押している間だけ録音します(最大\(Int(seconds))秒待機)。")
    CFRunLoopRun()
}

func outputDevice(_ args: [String]) throws -> AudioDeviceInfo {
    guard let query = option("--device", in: args) else {
        print("--device で出力先を指定してください(一覧: fireremote devices)")
        exit(64)
    }
    return try AudioDevices.resolve(query, in: AudioDevices.all())
}

func devices() {
    let defaultIn = AudioDevices.defaultDevice(input: true)
    let defaultOut = AudioDevices.defaultDevice(input: false)
    for d in AudioDevices.all() {
        let marks = (d.id == defaultIn ? " [既定入力]" : "") + (d.id == defaultOut ? " [既定出力]" : "")
        print("\(d.name)  in=\(d.inputChannels) out=\(d.outputChannels)  uid=\(d.uid)\(marks)")
    }
}

/// 既定デバイスを変更していないことを終了時に確認する。
/// Bluetooth 機器は再接続で数値 ID が変わるため UID で比較する。
func defaultsSnapshot() -> () -> Void {
    func current() -> [String] {
        let all = AudioDevices.all()
        return [true, false].map { input in
            let id = AudioDevices.defaultDevice(input: input)
            return all.first { $0.id == id }?.uid ?? "不明"
        }
    }
    let before = current()
    return {
        let after = current()
        print("既定の入出力デバイス: \(before == after ? "変更なし" : "変更あり \(before) -> \(after)")")
    }
}

func stream(_ args: [String]) throws {
    let device = try outputDevice(args)
    let output = try PCMOutput(device: device)
    output.onLog = { print("\(timestamp()) \($0)") }
    let profile = FireTVRemoteProfile()
    let session = try VoiceSession(profile: profile, seize: args.contains("--seize"))
    // 音声ボタンで Spotlight が開かないようにする
    let suppressor = args.contains("--no-suppress") ? nil : KeySuppressor(profile: profile, buttons: [profile.voiceButtonName])
    let checkDefaults = defaultsSnapshot()
    try output.start()
    session.remote.onConnectExtra = {
        if let suppressor {
            print("\(timestamp()) 音声ボタンのキー入力の無効化: \(suppressor.apply() ? "成功" : "失敗")")
        }
    }

    func finish() {
        session.shutdown()
        if let suppressor, !suppressor.clear() { print("警告: 元のキー入力の設定を戻せませんでした") }
        output.stop()
        print("統計: \(session.stats.summary)")
        checkDefaults()
        exit(0)
    }

    session.onLog = { print("\(timestamp()) \($0)") }
    session.onPCM = { output.enqueue($0) }
    session.onMicChange = { enabled in
        if enabled { output.beginSession() } else { output.endSession() }
    }

    startOrExit(session)
    let signals = onSignal { finish() }
    _ = signals
    if let s = option("--seconds", in: args).flatMap(Double.init) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { finish() }
    }
    print("出力先: \(device.name)。音声ボタンを押している間だけ送ります。Ctrl-C で終了します。")
    CFRunLoopRun()
}

/// キー割り当てを有効にして常駐する。割り当てたボタンの元のキー入力は止めて、二重に届かないようにする。
func run(_ args: [String]) throws {
    let profile = FireTVRemoteProfile()
    let dryRun = args.contains("--dry-run")
    let map: KeyMap
    if let path = option("--config", in: args) {
        map = try KeyMap.load(url: URL(fileURLWithPath: path))
    } else {
        map = try KeyMap(KeyMap.defaultBindings)
    }
    if !dryRun && !KeyInjector.isTrusted {
        print("アクセシビリティの権限がないためキーを送信できません。--dry-run なら権限なしで確認できます。")
        exit(2)
    }

    let output: PCMOutput?
    if option("--device", in: args) != nil {
        output = try PCMOutput(device: try outputDevice(args))
        output?.onLog = { print("\(timestamp()) \($0)") }
        try output?.start()
    } else {
        output = nil
    }

    let session = try VoiceSession(profile: profile)
    let suppressor = args.contains("--no-suppress") ? nil : KeySuppressor(profile: profile, buttons: Array(map.bindings.keys) + [profile.voiceButtonName])
    let router = ButtonKeyRouter(map: map, voiceButton: profile.voiceButtonName) { action in
        print("\(timestamp()) キー\(action.isDown ? "押下" : "解放"): \(action.combo.text)\(dryRun ? " (dry-run)" : "")")
        if !dryRun { KeyInjector.post(action) }
    }
    func finish() {
        router.releaseAll()
        session.shutdown()
        if let suppressor, !suppressor.clear() { print("警告: 元のキー入力の設定を戻せませんでした") }
        output?.stop()
        print("統計: \(session.stats.summary)")
        exit(0)
    }

    session.onLog = { print("\(timestamp()) \($0)") }
    session.onPCM = { output?.enqueue($0) }
    session.onMicChange = { enabled in
        if enabled { output?.beginSession() } else { output?.endSession() }
    }
    session.onButton = { router.process($0) }
    session.onDisconnect = { router.releaseAll() }
    session.remote.onConnectExtra = {
        if let suppressor {
            print("\(timestamp()) 元のキー入力の無効化: \(suppressor.apply() ? "成功" : "失敗")")
        }
    }

    startOrExit(session)
    let signals = onSignal { finish() }
    _ = signals
    if let s = option("--seconds", in: args).flatMap(Double.init) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { finish() }
    }
    print("キー割り当てを開始しました。Ctrl-C で終了します。")
    CFRunLoopRun()
}

/// 指定したキーを 1 回送る(キー送信の検証用)。
func sendKey(_ args: [String]) throws {
    guard let text = args.first else {
        print(usage)
        exit(64)
    }
    let combo = try KeyCombo(text)
    guard KeyInjector.isTrusted else {
        print("アクセシビリティの権限がありません")
        exit(2)
    }
    KeyInjector.post(KeyAction(combo: combo, isDown: true))
    KeyInjector.post(KeyAction(combo: combo, isDown: false))
    print("送信: \(text)")
}

/// 記録済みの音声を実際の到着間隔で出力する。リモコンなしで音声経路を検証するために使う。
func replay(_ args: [String]) throws {
    guard let path = args.first, !path.hasPrefix("--") else {
        print(usage)
        exit(64)
    }
    let device = try outputDevice(args)
    let output = try PCMOutput(device: device)
    output.onLog = { print($0) }
    let decoder = try OpusDecoder()
    let packets = CaptureFile.decode(try Data(contentsOf: URL(fileURLWithPath: path))).filter { $0.reportID == 0xF0 }
    guard let first = packets.first else {
        print("音声 Report がありません")
        exit(1)
    }
    let checkDefaults = defaultsSnapshot()
    try output.start()
    output.beginSession()
    for p in packets {
        let pcm = try decoder.decode(p.payload)
        let delay = Double(p.timestampNs - first.timestampNs) / 1e9
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { output.enqueue(pcm) }
    }
    let span = Double(packets.last!.timestampNs - first.timestampNs) / 1e9
    DispatchQueue.main.asyncAfter(deadline: .now() + span + 0.5) {
        output.stop()
        print(String(format: "%d パケットを %@ へ出力(%.2f秒)", packets.count, device.name, span))
        checkDefaults()
        exit(0)
    }
    CFRunLoopRun()
}

func captureInput(_ args: [String]) throws {
    guard let query = option("--device", in: args), let out = option("--out", in: args) else {
        print(usage)
        exit(64)
    }
    let device = try AudioDevices.resolve(query, in: AudioDevices.all())
    let recorder = try DeviceInputRecorder(device: device, url: URL(fileURLWithPath: out))
    let status = recorder.start()
    guard status == noErr else {
        print("入力の開始に失敗: OSStatus \(status)")
        exit(1)
    }
    let seconds = option("--seconds", in: args).flatMap(Double.init) ?? 5
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        print("nominal=\(AudioDevices.nominalSampleRate(device.id)) actual=\(AudioDevices.actualSampleRate(device.id))")
        do { try recorder.stop() } catch { print("エラー: \(error)") }
        print("保存: \(out)")
        exit(0)
    }
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
    case "devices": devices()
    case "run": try run(Array(args.dropFirst()))
    case "send-key": try sendKey(Array(args.dropFirst()))
    case "stream": try stream(Array(args.dropFirst()))
    case "replay": try replay(Array(args.dropFirst()))
    case "capture-input": try captureInput(Array(args.dropFirst()))
    default:
        print(usage)
        exit(64)
    }
} catch {
    print("エラー: \(error)")
    exit(1)
}
