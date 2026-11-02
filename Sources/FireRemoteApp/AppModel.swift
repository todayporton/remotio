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
    /// 押されているボタン(画面のリモコン図とカードに反映する)
    @Published private(set) var pressedButtons: Set<String> = []
    @Published private(set) var bindings: [String: String] = KeyMap.defaultBindings
    @Published var selectedDeviceUID: String? {
        didSet {
            guard selectedDeviceUID != oldValue else { return }
            UserDefaults.standard.set(selectedDeviceUID, forKey: "outputDeviceUID")
            rebuildOutput()
        }
    }

    private let profile = FireTVRemoteProfile()
    private var session: VoiceSession?
    private var output: PCMOutput?
    private var router: ButtonKeyRouter?
    private var suppressor: KeySuppressor?

    private var keymapURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FireRemote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("keymap.json")
    }

    init() {
        selectedDeviceUID = UserDefaults.standard.string(forKey: "outputDeviceUID")
        if let data = try? Data(contentsOf: keymapURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            bindings = saved
        }
        refreshDevices()
        refreshPermissions()
        rebuildMapping()
        rebuildOutput()
        start()
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
            session.onPCM = { [weak self] in self?.output?.enqueue($0) }
            session.onMicChange = { [weak self] enabled in
                self?.micOn = enabled
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

    private func post(_ action: KeyAction) {
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
            suppressor = KeySuppressor(profile: profile, buttons: Array(map.bindings.keys) + [profile.voiceButtonName])
        } catch {
            keymapError = "\(error)"
        }
    }

    private func applySuppression() {
        guard let suppressor else { return }
        log("元のキー入力の無効化: \(suppressor.apply() ? "成功" : "失敗")")
    }

    private func rebuildOutput() {
        output?.stop()
        output = nil
        guard let uid = selectedDeviceUID else { return }
        guard let device = AudioDevices.all().first(where: { $0.uid == uid }) else {
            log("出力先が見つかりません: \(uid)")
            return
        }
        do {
            let new = try PCMOutput(device: device)
            new.onLog = { [weak self] in self?.log($0) }
            try new.start()
            output = new
            log("音声の出力先: \(device.name)")
        } catch {
            log("音声出力を開始できません: \(error)")
        }
    }

    func refreshDevices() {
        outputDevices = AudioDevices.all().filter { $0.outputChannels > 0 }
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

    var hasVirtualDeviceSelected: Bool {
        guard let uid = selectedDeviceUID else { return false }
        return outputDevices.first { $0.uid == uid }?.inputChannels ?? 0 > 0
    }

    func shutdown() {
        releaseKeys()
        session?.shutdown()
        if connected, let suppressor, !suppressor.clear() { log("元のキー入力の設定を戻せませんでした") }
        output?.stop()
    }
}
