import AppKit
import Foundation
import IOKit.hid
import RemoteCore
import ServiceManagement

final class AppModel: ObservableObject {
    /// つながっているリモコンの名前(接続順ではなく名前順)
    @Published private(set) var connectedRemotes: [String] = []
    var connected: Bool { !connectedRemotes.isEmpty }
    @Published private(set) var micOn = false
    @Published private(set) var outputDevices: [AudioDeviceInfo] = []
    /// ログ。ボタンを押すたびに増えるので、変更を設定画面全体へ伝えないよう別に持つ
    let logStore = LogStore()
    @Published private(set) var startError: String?
    @Published private(set) var accessibilityGranted = KeyInjector.isTrusted
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var loginItemEnabled = SMAppService.mainApp.status == .enabled
    @Published var keymapError: String?
    @Published private(set) var driverInstalled = DriverInstaller.isInstalled
    @Published private(set) var driverDeviceAvailable = false
    @Published private(set) var driverBusy = false
    @Published private(set) var driverError: String?
    /// 編集中のリモコンで押されているボタン(画面のリモコン図とカードに反映する)
    @Published private(set) var pressedButtons: Set<String> = []
    /// これまでにつないだリモコンと、それぞれの割り当て(HIDRemote.Remote.key → 設定)
    @Published private(set) var knownRemotes: [String: StoredRemote] = [:]
    /// 設定画面で編集しているリモコン。まだ1台もつないでいなければ nil(新しいリモコンの初期設定を編集する)
    @Published var editingRemote: String? {
        didSet {
            guard editingRemote != oldValue else { return }
            loadEditingTarget()
            if let app = editingApp, appBindings[app] == nil { editingApp = nil }
            refreshPressed()
        }
    }
    /// 編集中のリモコンの既定の割り当て(アプリごとの割り当てがないときに使う)
    @Published private(set) var bindings: [String: String] = KeyMap.defaultBindings
    /// 編集中のリモコンのアプリごとの割り当て(バンドル ID → 既定の割り当てとの差分)
    @Published private(set) var appBindings: [String: [String: String]] = [:]
    /// 設定画面で編集している対象。nil なら既定
    @Published var editingApp: String?
    /// 割り当てに使っている前面のアプリ。Remotio 自身が前面のときは直前のアプリのまま
    @Published private(set) var activeApp: String?
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
    /// URL で求められたウインドウ。開いたページは設定画面が受け取る
    @Published var windowRequest: WindowRequest?

    private let profile = FireTVRemoteProfile()
    private var session: VoiceSession?
    private var output: PCMOutput?
    /// つながっているリモコンごとの割り当ての処理
    private var live: [UInt64: LiveRemote] = [:]
    /// 新しいリモコンに最初に使う割り当て(リモコンごとに分ける前の設定ファイル)
    private var templateBindings: [String: String] = KeyMap.defaultBindings
    private var templateAppBindings: [String: [String: String]] = [:]

    private var supportDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Remotio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var keymapURL: URL { supportDirectory.appendingPathComponent("keymap.json") }
    private var appKeymapsURL: URL { supportDirectory.appendingPathComponent("app-keymaps.json") }
    private var remotesURL: URL { supportDirectory.appendingPathComponent("remotes.json") }
    private var activationObserver: NSObjectProtocol?

    init() {
        micGainDecibels = AudioGain.clamp(decibels: UserDefaults.standard.double(forKey: "micGainDecibels"))
        useCustomOutput = UserDefaults.standard.bool(forKey: "useCustomOutput")
        selectedDeviceUID = UserDefaults.standard.string(forKey: "customOutputDeviceUID")
        if let data = try? Data(contentsOf: keymapURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            templateBindings = saved
        }
        if let data = try? Data(contentsOf: appKeymapsURL),
           let saved = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            templateAppBindings = saved
        }
        if let data = try? Data(contentsOf: remotesURL),
           let saved = try? JSONDecoder().decode([String: StoredRemote].self, from: data) {
            knownRemotes = saved
        }
        editingRemote = remoteKeys.first
        loadEditingTarget()
        activeApp = Self.frontmostAppID()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostAppChanged(app?.bundleIdentifier)
        }
        refreshDevices()
        refreshPermissions()
    }

    private func log(_ message: String) {
        logStore.append(message)
    }

    /// リモコンとの接続を始める。接続時に別プロセスの終了を待つ処理があり、起動処理の途中で走ると
    /// applicationDidFinishLaunching が呼ばれなくなるので、起動完了の後に呼ぶ。
    func start() {
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
            session.onButton = { [weak self] event, remoteID in self?.handle(event, from: remoteID) }
            // 切断したリモコンの押されたままのボタンは、VoiceSession が先に解放を送っている
            session.onDisconnect = { [weak self, unowned session] remote in
                guard let self else { return }
                live[remote.id]?.router?.releaseAll()
                live[remote.id] = nil
                connectedRemotes = Self.names(session.remote.remotes)
                connectedKeys = Set(live.values.map(\.key))
                refreshPressed()
            }
            session.remote.onConnectExtra = { [weak self, unowned session] remote in
                guard let self else { return }
                remoteConnected(remote)
                connectedRemotes = Self.names(session.remote.remotes)
            }
            self.session = session
            let result = session.start()
            if result != kIOReturnSuccess {
                startError = String(localized: "リモコンを開けません: \(ioReturnDescription(result))")
                log(startError!)
            }
        } catch {
            startError = "\(error)"
            log(String(localized: "起動エラー: \(String(describing: error))"))
        }
    }

    private static func names(_ remotes: [UInt64: HIDRemote.Remote]) -> [String] {
        remotes.values.map(\.name).sorted()
    }

    /// 初めてのリモコンなら、新しいリモコンの初期設定で登録する
    private func remoteConnected(_ remote: HIDRemote.Remote) {
        if knownRemotes[remote.key] == nil {
            var all = knownRemotes
            all[remote.key] = StoredRemote(name: remote.name, productID: remote.productID,
                                           bindings: templateBindings, appBindings: templateAppBindings)
            saveRemotes(all)
            log(String(localized: "新しいリモコンを登録しました: \(remote.name)"))
        }
        if editingRemote == nil { editingRemote = remote.key }
        live[remote.id] = LiveRemote(remote: remote)
        connectedKeys = Set(live.values.map(\.key))
        rebuild(remote.id)
        applySuppression(remote.id)
    }

    private func handle(_ event: ButtonEvent, from remoteID: UInt64) {
        guard var entry = live[remoteID] else { return }
        if event.isDown { entry.pressed.insert(event.name) } else { entry.pressed.remove(event.name) }
        live[remoteID] = entry
        // 対応表にない入力は、新しいボタンや別機種への対応を調べられるようにログへ残す
        if event.isDown && !RemoteLayout.allButtonIDs.contains(event.name) {
            log(String(localized: "未対応のボタンの入力: \(event.name)"))
        }
        // 設定画面を見ながら別のリモコンのボタンを押したら、そのリモコンの設定に切り替える
        if event.isDown && isSettingsWindowActive && editingRemote != entry.key {
            editingRemote = entry.key
        }
        refreshPressed()
        entry.router?.process(event)
    }

    private func refreshPressed() {
        let pressed = live.values.filter { $0.key == editingRemote }
            .reduce(into: Set<String>()) { $0.formUnion($1.pressed) }
        if pressed != pressedButtons { pressedButtons = pressed }
    }

    /// 設定画面かセットアップの案内を操作している間か
    private var isSettingsWindowActive: Bool {
        guard NSApp.isActive, let id = NSApp.keyWindow?.identifier?.rawValue else { return false }
        return id == "settings" || id == "setup"
    }

    private func post(_ action: KeyAction) {
        // 設定画面を操作している間は送らない。解放は押しっぱなしを防ぐために常に送る
        if action.isDown && isSettingsWindowActive { return }
        // コマンドは押したときに1回だけ実行する。アクセシビリティの権限は要らない
        if let command = action.combo.command {
            if action.isDown { command.run { [weak self] in self?.log($0) } }
            return
        }
        guard KeyInjector.isTrusted else {
            if action.isDown { log(String(localized: "アクセシビリティの権限がないためキーを送信しません")) }
            return
        }
        KeyInjector.post(action)
    }

    private func releaseKeys() {
        for entry in live.values { entry.router?.releaseAll() }
    }

    private static func frontmostAppID() -> String? {
        let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return id == Bundle.main.bundleIdentifier ? nil : id
    }

    /// 前面のアプリが変わったら、そのアプリの割り当てに切り替える
    private func frontmostAppChanged(_ bundleID: String?) {
        guard let bundleID, bundleID != Bundle.main.bundleIdentifier, bundleID != activeApp else { return }
        let hasOverrides = { (app: String?) in
            app.map { app in self.knownRemotes.values.contains { $0.appBindings[app] != nil } } ?? false
        }
        let before = hasOverrides(activeApp)
        activeApp = bundleID
        // どのリモコンにもどちらのアプリの個別の割り当てがなければ、作り直す必要はない
        guard before || hasOverrides(bundleID) else { return }
        log(hasOverrides(bundleID) ? String(localized: "割り当てを切り替えました: \(AppInfo.name(of: bundleID))")
                                   : String(localized: "既定の割り当てに戻しました"))
        rebuildMapping()
    }

    /// そのリモコンで、前面のアプリに使う割り当て
    private func activeBindings(for key: String) -> [String: String] {
        guard let stored = knownRemotes[key] else { return templateBindings }
        return AppKeymaps.merge(stored.bindings, activeApp.flatMap { stored.appBindings[$0] })
    }

    /// つながっているすべてのリモコンの割り当てを作り直し、止めるボタンが変わったものだけ掛け直す
    private func rebuildMapping() {
        for id in live.keys {
            rebuild(id)
            applySuppressionIfChanged(id)
        }
    }

    private func rebuild(_ id: UInt64) {
        guard var entry = live[id] else { return }
        entry.router?.releaseAll()
        do {
            // 押している間が分からないボタンは、保存済みの長押しと2回押しの設定を使わない
            let bindings = activeBindings(for: entry.key).filter { key, _ in
                guard let dot = key.firstIndex(of: ".") else { return true }
                return profile.reportsHold(of: String(key[..<dot]))
            }
            let map = try KeyMap(bindings, standardKeys: standardKeys)
            entry.router = ButtonKeyRouter(map: map, voiceButton: profile.voiceButtonName) { [weak self] in self?.post($0) }
            entry.wantedSuppression = Set(map.suppressedButtons)
            entry.suppressor = KeySuppressor(profile: profile, remote: entry.remote,
                                             buttons: map.suppressedButtons + [profile.voiceButtonName])
            live[id] = entry
        } catch {
            keymapError = "\(error)"
        }
    }

    /// 止めるボタンが変わる場合だけ元のキー入力の無効化を掛け直す
    private func applySuppressionIfChanged(_ id: UInt64) {
        guard let entry = live[id], entry.wantedSuppression != entry.appliedSuppression else { return }
        applySuppression(id)
    }

    /// 押し方を判定するボタンで、タップが「標準」のときに送る操作
    private var standardKeys: [String: String] {
        Dictionary(uniqueKeysWithValues: RemoteLayout.allButtonIDs.compactMap { id in
            profile.standardKey(of: id).map { (id, $0) }
        })
    }

    private func applySuppression(_ id: UInt64) {
        guard var entry = live[id], let suppressor = entry.suppressor else { return }
        entry.appliedSuppression = entry.wantedSuppression
        live[id] = entry
        log(suppressor.apply() ? String(localized: "元のキー入力の無効化: 成功") : String(localized: "元のキー入力の無効化: 失敗"))
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
            log(String(localized: "音声の送り先: \(device.name)"))
        } catch {
            log(String(localized: "音声出力を開始できません: \(String(describing: error))"))
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
                if let error { self?.log(String(localized: "ドライバの処理に失敗: \(error)")) }
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
            log(String(localized: "アプリを開き直せません: \(String(describing: error))"))
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
            log(String(localized: "ログイン時の起動を変更できません: \(error.localizedDescription)"))
        }
        refreshPermissions()
    }

    /// 1 ボタンの割り当てを変更して保存する。nil で割り当てなし。
    var voiceButtonName: String { profile.voiceButtonName }

    /// 設定画面でボタン名の横に出す注意書き
    func buttonNote(_ button: String) -> String? { profile.note(of: button) }

    /// 長押しと2回押しを設定できるボタンか
    func supportsGestures(_ button: String) -> Bool {
        button != profile.voiceButtonName && profile.reportsHold(of: button)
    }

    /// 設定画面に表示する割り当て(編集中の対象のもの)
    var displayedBindings: [String: String] {
        editingApp.map { AppKeymaps.merge(bindings, appBindings[$0]) } ?? bindings
    }

    /// 編集中のアプリで、既定の割り当てを上書きしている項目か
    func isOverridden(_ id: String) -> Bool {
        editingApp.flatMap { appBindings[$0]?[id] } != nil
    }

    func setBinding(_ button: String, to key: String?) {
        if let app = editingApp {
            var overrides = appBindings[app] ?? [:]
            overrides[button] = key ?? AppKeymaps.standardValue
            saveApp(app, overrides)
            return
        }
        var edited = bindings
        edited[button] = key
        save(edited)
    }

    /// 編集中のアプリの項目を、既定の割り当てに戻す
    func useGlobalBinding(_ id: String) {
        guard let app = editingApp, var overrides = appBindings[app] else { return }
        overrides[id] = nil
        saveApp(app, overrides)
    }

    /// アプリを個別の割り当ての対象に加え、編集を始める
    func addApp(_ bundleID: String) {
        if appBindings[bundleID] == nil { saveApp(bundleID, [:]) }
        editingApp = bundleID
    }

    func removeApp(_ bundleID: String) {
        var all = appBindings
        all[bundleID] = nil
        saveAppBindings(all)
        if editingApp == bundleID { editingApp = nil }
    }

    private func saveApp(_ app: String, _ overrides: [String: String]) {
        do {
            _ = try KeyMap(AppKeymaps.merge(bindings, overrides))
        } catch {
            keymapError = "\(error)"
            return
        }
        var all = appBindings
        all[app] = overrides
        saveAppBindings(all)
    }

    private func saveAppBindings(_ all: [String: [String: String]]) {
        persist(bindings: bindings, appBindings: all)
    }

    /// メニューとボタンに出す、何も割り当てていないときの名前
    func unassignedTitle(_ button: String) -> String {
        if button == profile.voiceButtonName { return String(localized: "キーなし") }
        guard profile.systemUsage(of: button) != nil else { return String(localized: "割り当てなし") }
        // 長押しか2回押しがあると元のキー入力を止めるので、Remotio から送れない標準動作は使えない
        let shown = displayedBindings
        let hasGestures = shown[button + KeyMap.longSuffix] != nil || shown[button + KeyMap.doubleSuffix] != nil
        if hasGestures && profile.standardKey(of: button) == nil { return String(localized: "割り当てなし") }
        return profile.standardActionName(of: button).map { String(localized: "標準(\($0))") } ?? String(localized: "標準")
    }

    /// 既定の割り当てを初期設定に戻す。アプリの編集中は、そのアプリの上書きをすべて消す
    func restoreDefaultBindings() {
        if let app = editingApp {
            saveApp(app, [:])
        } else {
            save(KeyMap.defaultBindings)
        }
    }

    private func save(_ edited: [String: String]) {
        do {
            _ = try KeyMap(edited)
        } catch {
            keymapError = "\(error)"
            return
        }
        persist(bindings: edited, appBindings: appBindings)
    }

    /// 編集中のリモコンの割り当てを保存する。リモコンが1台もなければ、新しいリモコンの初期設定として保存する
    private func persist(bindings edited: [String: String], appBindings editedApps: [String: [String: String]]) {
        do {
            if let key = editingRemote, var stored = knownRemotes[key] {
                stored.bindings = edited
                stored.appBindings = editedApps
                var all = knownRemotes
                all[key] = stored
                try writeRemotes(all)
            } else {
                try JSONEncoder().encode(edited).write(to: keymapURL)
                try JSONEncoder().encode(editedApps).write(to: appKeymapsURL)
                templateBindings = edited
                templateAppBindings = editedApps
            }
            bindings = edited
            appBindings = editedApps
            keymapError = nil
            rebuildMapping()
            log(String(localized: "キー割り当てを保存しました"))
        } catch {
            keymapError = "\(error)"
        }
    }

    private func writeRemotes(_ all: [String: StoredRemote]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(all).write(to: remotesURL)
        knownRemotes = all
    }

    private func saveRemotes(_ all: [String: StoredRemote]) {
        do { try writeRemotes(all) } catch { keymapError = "\(error)" }
    }

    /// 編集の対象を切り替えたとき、その割り当てを画面用に読み込む
    private func loadEditingTarget() {
        if let key = editingRemote, let stored = knownRemotes[key] {
            bindings = stored.bindings
            appBindings = stored.appBindings
        } else {
            bindings = templateBindings
            appBindings = templateAppBindings
        }
    }

    // MARK: リモコンの一覧

    /// つながっているリモコン(HIDRemote.Remote.key)
    @Published private(set) var connectedKeys: Set<String> = []

    /// 登録済みのリモコン。つながっているものを先に、名前順に並べる
    var remoteKeys: [String] {
        knownRemotes.keys.sorted {
            let a = connectedKeys.contains($0), b = connectedKeys.contains($1)
            if a != b { return a }
            return (remoteTitle($0), $0) < (remoteTitle($1), $1)
        }
    }

    /// 一覧に出す名前。同じ機種が2台以上あれば、シリアル番号の末尾を付けて見分ける
    func remoteTitle(_ key: String) -> String {
        guard let stored = knownRemotes[key] else { return "Amazon Remote" }
        let sameName = knownRemotes.values.filter { $0.name == stored.name }.count > 1
        guard sameName, key.hasPrefix("serial:") else { return stored.name }
        return "\(stored.name)(…\(key.suffix(4)))"
    }

    /// 編集中のリモコンの図
    var editingLayout: RemoteLayout {
        RemoteLayout.of(productID: editingRemote.flatMap { knownRemotes[$0]?.productID })
    }

    /// つながっていないリモコンの設定を消す
    func removeRemote(_ key: String) {
        guard !connectedKeys.contains(key) else { return }
        var all = knownRemotes
        all[key] = nil
        saveRemotes(all)
        if editingRemote == key { editingRemote = remoteKeys.first }
    }

    func shutdown() {
        releaseKeys()
        KeyInjector.flush()
        session?.shutdown()
        for entry in live.values {
            if let suppressor = entry.suppressor, !suppressor.clear() {
                log(String(localized: "元のキー入力の設定を戻せませんでした"))
            }
        }
        output?.stop()
    }
}

/// 1台のリモコンの保存した設定
struct StoredRemote: Codable, Equatable {
    var name: String
    var productID: Int
    var bindings: [String: String]
    var appBindings: [String: [String: String]]
}

/// つながっているリモコン1台の割り当ての処理
private struct LiveRemote {
    let remote: HIDRemote.Remote
    var key: String { remote.key }
    var router: ButtonKeyRouter?
    var suppressor: KeySuppressor?
    /// 今の割り当てで止めたいボタンと、実際に止めているボタン
    var wantedSuppression: Set<String> = []
    var appliedSuppression: Set<String>?
    var pressed: Set<String> = []

    init(remote: HIDRemote.Remote) { self.remote = remote }
}

/// remotio://settings/<ページ> と remotio://setup の求め
struct WindowRequest: Equatable {
    let id = UUID()
    let windowID: String
    let page: SettingsPage?

    init?(url: URL) {
        guard url.scheme?.lowercased() == "remotio" else { return nil }
        switch url.host?.lowercased() {
        case "settings":
            windowID = "settings"
            let name = url.pathComponents.dropFirst().first?.lowercased()
            page = name.flatMap(SettingsPage.init(rawValue:))
        case "setup":
            windowID = "setup"
            page = nil
        default:
            return nil
        }
    }
}
