import AppKit
import Foundation
import IOKit.hid
import RemoteCore
import ServiceManagement

final class AppModel: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var micOn = false
    @Published private(set) var outputDevices: [AudioDeviceInfo] = []
    @Published private(set) var logs: [String] = []
    @Published private(set) var startError: String?
    @Published private(set) var accessibilityGranted = KeyInjector.isTrusted
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var loginItemEnabled = SMAppService.mainApp.status == .enabled
    @Published var keymapError: String?
    @Published private(set) var driverInstalled = DriverInstaller.isInstalled
    @Published private(set) var driverDeviceAvailable = false
    @Published private(set) var driverBusy = false
    @Published private(set) var driverError: String?
    /// 押されているボタン(画面のリモコン図とカードに反映する)
    @Published private(set) var pressedButtons: Set<String> = []
    @Published private(set) var bindings: [String: String] = KeyMap.defaultBindings
    /// 「他の出力デバイスを使う」がオフのときは、内蔵の仮想マイクへ送る
    @Published var useCustomOutput: Bool {
        didSet {
            guard useCustomOutput != oldValue else { return }
            UserDefaults.standard.set(useCustomOutput, forKey: "useCustomOutput")
            rebuildOutput()
        }
    }
    /// 「他の出力デバイスを使う」で選んだデバイス
    @Published var selectedDeviceUID: String? {
        didSet {
            guard selectedDeviceUID != oldValue else { return }
            UserDefaults.standard.set(selectedDeviceUID, forKey: "customOutputDeviceUID")
            rebuildOutput()
        }
    }

    /// マイクのゲイン(dB)
    @Published var micGainDecibels: Double {
        didSet { UserDefaults.standard.set(micGainDecibels, forKey: "micGainDecibels") }
    }
    let micMeter = MicLevelMeter()

    private let profile = FireTVRemoteProfile()
    private var session: VoiceSession?
    private var output: PCMOutput?
    private var router: ButtonKeyRouter?
    private var suppressor: KeySuppressor?

    private var keymapURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Remotio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("keymap.json")
    }

    init() {
        micGainDecibels = AudioGain.clamp(decibels: UserDefaults.standard.double(forKey: "micGainDecibels"))
        useCustomOutput = UserDefaults.standard.bool(forKey: "useCustomOutput")
        selectedDeviceUID = UserDefaults.standard.string(forKey: "customOutputDeviceUID")
        if let data = try? Data(contentsOf: keymapURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            bindings = saved
        }
        refreshDevices()
        refreshPermissions()
        rebuildMapping()
        // SwiftUI がシーンを作っている最中に状態を変えないよう、次の周回で始める
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    private func log(_ message: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        logs.append("\(f.string(from: Date())) \(message)")
        if logs.count > 300 { logs.removeFirst(logs.count - 300) }
    }

    private func start() {
        do {
            let session = try VoiceSession(profile: profile)
            session.onLog = { [weak self] in self?.log($0) }
            session.onPCM = { [weak self] samples in
                guard let self else { return }
                let result = AudioGain.apply(samples, decibels: self.micGainDecibels)
                self.micMeter.update(peak: result.peak, clipped: result.clipped)
                self.output?.enqueue(result.samples)
            }
            session.onMicChange = { [weak self] enabled in
                self?.micOn = enabled
                self?.micMeter.setActive(enabled)
                if enabled { self?.output?.beginSession() } else { self?.output?.endSession() }
            }
            session.onButton = { [weak self] event in self?.handle(event) }
            session.onDisconnect = { [weak self] in
                self?.connected = false
                self?.pressedButtons = []
                self?.releaseKeys()
            }
            session.remote.onConnectExtra = { [weak self] in
                self?.connected = true
                self?.applySuppression()
            }
            self.session = session
            let result = session.start()
            if result != kIOReturnSuccess {
                startError = "リモコンを開けません: \(ioReturnDescription(result))"
                log(startError!)
            }
        } catch {
            startError = "\(error)"
            log("起動エラー: \(error)")
        }
    }

    private func handle(_ event: ButtonEvent) {
        if event.isDown { pressedButtons.insert(event.name) } else { pressedButtons.remove(event.name) }
        router?.process(event)
    }

    /// 設定画面かセットアップの案内を操作している間か
    private var isSettingsWindowActive: Bool {
        guard NSApp.isActive, let id = NSApp.keyWindow?.identifier?.rawValue else { return false }
        return id == "settings" || id == "setup"
    }

    private func post(_ action: KeyAction) {
        // 設定画面を操作している間は送らない。解放は押しっぱなしを防ぐために常に送る
        if action.isDown && isSettingsWindowActive { return }
        guard KeyInjector.isTrusted else {
            if action.isDown { log("アクセシビリティの権限がないためキーを送信しません") }
            return
        }
        KeyInjector.post(action)
    }

    private func releaseKeys() {
        router?.releaseAll()
    }

    private func rebuildMapping() {
        releaseKeys()
        do {
            let map = try KeyMap(bindings)
            router = ButtonKeyRouter(map: map, voiceButton: profile.voiceButtonName) { [weak self] in self?.post($0) }
            suppressor = KeySuppressor(profile: profile, buttons: map.suppressedButtons + [profile.voiceButtonName])
        } catch {
            keymapError = "\(error)"
        }
    }

    private func applySuppression() {
        guard let suppressor else { return }
        log("元のキー入力の無効化: \(suppressor.apply() ? "成功" : "失敗")")
    }

    /// 今の設定で音声を送る先。使えるものがなければ nil。
    private var outputTarget: AudioDeviceInfo? {
        if useCustomOutput {
            guard let uid = selectedDeviceUID else { return nil }
            return AudioDevices.device(uid: uid)
        }
        return AudioDevices.device(uid: AudioDevices.builtInOutputUID)
    }

    private func rebuildOutput() {
        output?.stop()
        output = nil
        guard let device = outputTarget else { return }
        do {
            let new = try PCMOutput(device: device)
            new.onLog = { [weak self] in self?.log($0) }
            try new.start()
            output = new
            log("音声の送り先: \(device.name)")
        } catch {
            log("音声出力を開始できません: \(error)")
        }
    }

    func refreshDevices() {
        // 内蔵マイクの入力側は出力を持たないので、この一覧には出ない
        outputDevices = AudioDevices.all().filter { $0.outputChannels > 0 }
        driverInstalled = DriverInstaller.isInstalled
        driverDeviceAvailable = AudioDevices.device(uid: AudioDevices.builtInOutputUID) != nil
            && AudioDevices.device(uid: AudioDevices.builtInMicrophoneUID) != nil
        // Core Audio の再起動後などに、送り先へ出力し直す
        if output == nil, outputTarget != nil { rebuildOutput() }
    }

    func installDriver() { runDriverTask(DriverInstaller.install) }
    func uninstallDriver() { runDriverTask(DriverInstaller.uninstall) }

    private func runDriverTask(_ task: @escaping () -> String?) {
        driverBusy = true
        driverError = nil
        output?.stop()
        output = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let error = task()
            DispatchQueue.main.async {
                self?.driverError = error
                if let error { self?.log("ドライバの処理に失敗: \(error)") }
                self?.waitForAudioSystem(attemptsLeft: 10)
            }
        }
    }

    /// Core Audio の再起動を待ってから状態を更新する
    private func waitForAudioSystem(attemptsLeft: Int) {
        refreshDevices()
        let settled = driverInstalled == driverDeviceAvailable
        if settled || attemptsLeft <= 1 {
            driverBusy = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.waitForAudioSystem(attemptsLeft: attemptsLeft - 1)
        }
    }

    var setupProgress: SetupProgress {
        SetupProgress(inputMonitoringGranted: inputMonitoringGranted,
                      accessibilityGranted: accessibilityGranted,
                      remoteConnected: connected,
                      microphoneReady: driverDeviceAvailable || useCustomOutput)
    }

    /// 案内を自動で開くか
    var shouldOpenSetup: Bool {
        setupProgress.shouldOpenAutomatically(dismissed: UserDefaults.standard.bool(forKey: "setupDismissed"))
    }

    /// 「完了」や「後で設定する」を選んだら、次回から自動で開かない
    func dismissSetup() { UserDefaults.standard.set(true, forKey: "setupDismissed") }

    /// 起動後に許可した入力監視は、開き直すまで反映されない
    var needsRelaunch: Bool { startError != nil }

    func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            log("アプリを開き直せません: \(error)")
        }
    }

    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshPermissions() {
        accessibilityGranted = KeyInjector.isTrusted
        inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        loginItemEnabled = SMAppService.mainApp.status == .enabled
    }

    func requestAccessibility() {
        KeyInjector.requestTrust()
        refreshPermissions()
        if !accessibilityGranted { openPrivacySettings("Privacy_Accessibility") }
    }

    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshPermissions()
        if !inputMonitoringGranted { openPrivacySettings("Privacy_ListenEvent") }
    }

    /// 一度記録された権限ではダイアログが出ないため、システム設定の該当ページを開く
    private func openPrivacySettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    func setLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log("ログイン時の起動を変更できません: \(error.localizedDescription)")
        }
        refreshPermissions()
    }

    /// 1 ボタンの割り当てを変更して保存する。nil で割り当てなし。
    func setBinding(_ button: String, to key: String?) {
        var edited = bindings
        edited[button] = key
        save(edited)
    }

    /// メニューとボタンに出す、何も割り当てていないときの名前
    func unassignedTitle(_ button: String) -> String {
        if button == profile.voiceButtonName { return "キーなし" }
        guard profile.systemUsage(of: button) != nil else { return "割り当てなし" }
        return profile.standardActionName(of: button).map { "標準(\($0))" } ?? "標準"
    }

    func restoreDefaultBindings() { save(KeyMap.defaultBindings) }

    private func save(_ edited: [String: String]) {
        do {
            _ = try KeyMap(edited)
            try JSONEncoder().encode(edited).write(to: keymapURL)
            bindings = edited
            keymapError = nil
            rebuildMapping()
            if connected { applySuppression() }
            log("キー割り当てを保存しました")
        } catch {
            keymapError = "\(error)"
        }
    }

    func shutdown() {
        releaseKeys()
        KeyInjector.flush()
        session?.shutdown()
        if connected, let suppressor, !suppressor.clear() { log("元のキー入力の設定を戻せませんでした") }
        output?.stop()
    }
}
