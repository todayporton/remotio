import AppKit
import RemoteCore
import SwiftUI

// MARK: - ボタンの定義

struct RemoteButton: Identifiable {
    let id: String
    let title: String
    let symbol: String
    /// リモコン図の中の位置(幅・高さに対する割合)
    let position: CGPoint
    let size: CGFloat

    static let left: [RemoteButton] = [
        .init(id: "voice", title: "音声(Push-to-Talk)", symbol: "mic.fill", position: .init(x: 0.5, y: 0.075), size: 26),
        .init(id: "dpad_up", title: "上", symbol: "chevron.up", position: .init(x: 0.5, y: 0.165), size: 20),
        .init(id: "dpad_left", title: "左", symbol: "chevron.left", position: .init(x: 0.25, y: 0.235), size: 20),
        .init(id: "back", title: "戻る", symbol: "arrow.uturn.backward", position: .init(x: 0.22, y: 0.365), size: 26),
        .init(id: "rewind", title: "巻き戻し", symbol: "backward.fill", position: .init(x: 0.22, y: 0.445), size: 26),
        .init(id: "volume_up", title: "音量 +", symbol: "speaker.plus", position: .init(x: 0.5, y: 0.53), size: 26),
        .init(id: "mute", title: "ミュート", symbol: "speaker.slash", position: .init(x: 0.22, y: 0.61), size: 26),
        .init(id: "app_a1", title: "アプリ 1", symbol: "1.circle", position: .init(x: 0.3, y: 0.73), size: 26),
        .init(id: "app_a3", title: "アプリ 3", symbol: "3.circle", position: .init(x: 0.3, y: 0.83), size: 26),
    ]
    static let right: [RemoteButton] = [
        .init(id: "select", title: "決定", symbol: "circle.circle", position: .init(x: 0.5, y: 0.235), size: 30),
        .init(id: "dpad_right", title: "右", symbol: "chevron.right", position: .init(x: 0.75, y: 0.235), size: 20),
        .init(id: "dpad_down", title: "下", symbol: "chevron.down", position: .init(x: 0.5, y: 0.305), size: 20),
        .init(id: "home", title: "ホーム", symbol: "house", position: .init(x: 0.5, y: 0.365), size: 26),
        .init(id: "menu", title: "メニュー", symbol: "line.3.horizontal", position: .init(x: 0.78, y: 0.365), size: 26),
        .init(id: "play_pause", title: "再生・停止", symbol: "playpause.fill", position: .init(x: 0.5, y: 0.445), size: 26),
        .init(id: "fast_forward", title: "早送り", symbol: "forward.fill", position: .init(x: 0.78, y: 0.445), size: 26),
        .init(id: "volume_down", title: "音量 −", symbol: "speaker.minus", position: .init(x: 0.5, y: 0.61), size: 26),
        .init(id: "tv", title: "TV", symbol: "tv", position: .init(x: 0.78, y: 0.61), size: 26),
        .init(id: "app_a2", title: "アプリ 2", symbol: "2.circle", position: .init(x: 0.7, y: 0.73), size: 26),
        .init(id: "app_a4", title: "アプリ 4", symbol: "4.circle", position: .init(x: 0.7, y: 0.83), size: 26),
    ]
    static let all = left + right
}

// MARK: - 全体

enum SettingsPage: String, CaseIterable, Identifiable {
    case connection = "接続と音声", buttons = "ボタン", permissions = "権限", logs = "ログ"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .connection: return "link"
        case .buttons: return "keyboard"
        case .permissions: return "hand.raised"
        case .logs: return "list.bullet.rectangle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var page: SettingsPage

    init(model: AppModel) {
        self.model = model
        // 仮想マイクが未導入なら、インストールのボタンがある画面から始める
        _page = State(initialValue: model.driverDeviceAvailable || model.useCustomOutput ? .buttons : .connection)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                ForEach(SettingsPage.allCases) { item in
                    Button { page = item } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.symbol).font(.title2)
                            Text(item.rawValue).font(.caption)
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .contentShape(Rectangle())
                        .foregroundStyle(page == item ? Color.accentColor : Color.secondary)
                        .background(page == item ? Color.accentColor.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityLabel(item.rawValue)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 34)
            .frame(width: 112)
            .background(.regularMaterial)

            Group {
                switch page {
                case .connection: ConnectionPage(model: model)
                case .buttons: ButtonsPage(model: model)
                case .permissions: PermissionsPage(model: model)
                case .logs: LogsPage(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // 他のページでも、何もないところのクリックでフォーカスを外す
            .simultaneousGesture(TapGesture().onEnded { clearFocusIfOutsideControl() })
        }
        .frame(minWidth: 980, minHeight: 700)
        .onAppear {
            model.refreshDevices()
            model.refreshPermissions()
            DispatchQueue.main.async {
                NSApp.windows.first { $0.identifier?.rawValue == "settings" }?.center()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
            model.refreshDevices()
        }
    }
}

/// クリックした先が操作できる部品でなければフォーカスを外す
private func clearFocusIfOutsideControl() {
    guard let window = NSApp.keyWindow, let event = NSApp.currentEvent,
          let content = window.contentView else { return }
    let hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
    if !(hit is NSControl) && !(hit is NSTextView) {
        window.makeFirstResponder(nil)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.largeTitle.bold())
            Spacer()
            trailing
        }
    }
}

struct Card<Content: View>: View {
    var highlighted = false
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.08)))
    }
}

struct StatusPill: View {
    let connected: Bool

    var body: some View {
        Label(connected ? "接続中" : "未接続", systemImage: "circle.fill")
            .font(.callout)
            .labelStyle(StatusLabelStyle())
            .foregroundStyle(connected ? Color.green : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background((connected ? Color.green : Color.secondary).opacity(0.14), in: Capsule())
    }
}

private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 7))
            configuration.title
        }
    }
}

// MARK: - リモコン図

struct RemoteFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private let mapSpace = "buttonMap"

struct RemoteDrawing: View {
    var pressed: Set<String> = []
    var selected: String?
    var onSelect: ((String) -> Void)?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: geo.size.width * 0.3)
                    .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.1)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                Circle()
                    .fill(Color(white: 0.05))
                    .frame(width: geo.size.width * 0.78)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.235)
                ForEach(RemoteButton.all) { button in
                    let active = pressed.contains(button.id) || selected == button.id
                    let isSelect = button.id == "select"
                    let isDpad = button.id.hasPrefix("dpad")
                    Button { onSelect?(button.id) } label: {
                        ZStack {
                            if !isDpad {
                                Circle().fill(active ? Color.accentColor : Color(white: isSelect ? 0.22 : 0.16))
                            }
                            if !isSelect {
                                Image(systemName: button.symbol)
                                    .font(.system(size: button.size * 0.46, weight: .semibold))
                                    .foregroundStyle(isDpad && active ? Color.accentColor : .white)
                            }
                        }
                        .frame(width: button.size, height: button.size)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("リモコン \(button.title)")
                    .background(GeometryReader { g in
                        Color.clear.preference(key: RemoteFrameKey.self,
                                               value: ["remote:\(button.id)": g.frame(in: .named(mapSpace))])
                    })
                    .position(x: geo.size.width * button.position.x, y: geo.size.height * button.position.y)
                }
            }
        }
    }
}

// MARK: - ボタンのページ

struct ButtonsPage: View {
    @ObservedObject var model: AppModel
    @State private var selected: String?
    @State private var recording: String?
    @State private var monitor: Any?
    @State private var captureTap: KeyCaptureTap?
    @State private var heldModifier: CGKeyCode?
    @State private var frames: [String: CGRect] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "ボタン") { StatusPill(connected: model.connected) }
            ScrollView {
                map
                    .coordinateSpace(name: mapSpace)
                    .onPreferenceChange(RemoteFrameKey.self) { frames = $0 }
                    .padding(.vertical, 2)
            }
            footer
        }
        .padding(22)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: clearSelection)
        .onDisappear(perform: stopRecording)
    }

    private var map: some View {
        ZStack {
            leaderLines.allowsHitTesting(false)
            HStack(alignment: .top, spacing: 40) {
                column(RemoteButton.left)
                RemoteDrawing(pressed: model.pressedButtons, selected: selected ?? recording) { id in
                    startRecording(id)
                }
                .frame(width: 112, height: 490)
                .padding(.top, 14)
                column(RemoteButton.right)
            }
        }
    }

    private func column(_ buttons: [RemoteButton]) -> some View {
        VStack(spacing: 6) {
            ForEach(buttons) { button in
                card(button)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: RemoteFrameKey.self,
                                               value: ["card:\(button.id)": g.frame(in: .named(mapSpace))])
                    })
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func card(_ button: RemoteButton) -> some View {
        let isRecording = recording == button.id
        let active = isRecording || selected == button.id || model.pressedButtons.contains(button.id)
        let binding = model.bindings[button.id]
        return Card(highlighted: active, padding: 8) {
            HStack(spacing: 8) {
                Image(systemName: button.symbol).frame(width: 20).foregroundStyle(.secondary)
                Text(button.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(binding == ActionCatalog.disabled ? Color.secondary : Color.primary)
                Spacer(minLength: 4)
                if isRecording {
                    Button("キーを入力…", action: clearSelection)
                        .frame(minWidth: 84)
                        .accessibilityLabel("\(button.title) のキー入力を中止")
                } else {
                    actionMenu(button, binding: binding)
                }
            }
        }
    }

    private func actionMenu(_ button: RemoteButton, binding: String?) -> some View {
        Menu {
            Button("キーを入力…") { startRecording(button.id) }
            Divider()
            Button(model.unassignedTitle(button.id)) { assign(button, nil) }
            Button("無効") { assign(button, ActionCatalog.disabled) }
            Divider()
            Menu("メディア操作") {
                ForEach(ActionCatalog.mediaItems) { item in
                    Button(item.title) { assign(button, item.id) }
                }
            }
            Menu("システム操作") {
                ForEach(ActionCatalog.systemItems) { item in
                    Button(item.title) { assign(button, item.id) }
                }
            }
        } label: {
            Text(binding.map(KeyCombo.displayText) ?? model.unassignedTitle(button.id))
                .font(.body.weight(.medium))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("\(button.title) の操作")
        .accessibilityValue(binding ?? model.unassignedTitle(button.id))
    }

    /// 操作を選び終えたら、選択状態とフォーカスを解除する
    private func assign(_ button: RemoteButton, _ value: String?) {
        model.setBinding(button.id, to: value)
        clearSelection()
    }

    private func clearSelection() {
        stopRecording()
        selected = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private var leaderLines: some View {
        Canvas { context, _ in
            for button in RemoteButton.all {
                guard let from = frames["remote:\(button.id)"], let to = frames["card:\(button.id)"] else { continue }
                let onLeft = to.midX < from.midX
                let end = CGPoint(x: onLeft ? to.maxX : to.minX, y: to.midY)
                let start = CGPoint(x: from.midX, y: from.midY)
                var path = Path()
                path.move(to: start)
                let bend = abs(end.x - start.x) * 0.55
                path.addCurve(to: end,
                              control1: CGPoint(x: start.x + (onLeft ? -bend : bend), y: start.y),
                              control2: CGPoint(x: end.x + (onLeft ? bend : -bend), y: end.y))
                let active = selected == button.id || recording == button.id || model.pressedButtons.contains(button.id)
                context.stroke(path, with: .color(active ? .accentColor : .secondary.opacity(0.35)),
                               lineWidth: active ? 2 : 1)
            }
        }
    }

    private var footer: some View {
        Card {
            HStack(spacing: 14) {
                if let error = model.keymapError {
                    Text(error).font(.callout).foregroundStyle(.red)
                } else if let recording {
                    let name = RemoteButton.all.first { $0.id == recording }?.title ?? recording
                    Text("「\(name)」に割り当てるキーを押してください。修飾キーだけ(Fn、右 ⌥ など)も押して離すと設定できます。待ち受け中のキー入力は他のアプリへ送りません。")
                        .font(.callout)
                } else {
                    Text("各ボタンのメニューから操作を選びます。「標準」は Mac の標準動作をそのまま通し、「無効」は何もしません。この画面を操作している間は、リモコンから割り当てたキーを送りません。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if recording != nil { Button("キャンセル", action: clearSelection) }
                Button("初期設定に戻す") {
                    clearSelection()
                    model.restoreDefaultBindings()
                }
            }
        }
    }

    private func startRecording(_ id: String) {
        stopRecording()
        selected = id
        recording = id
        heldModifier = nil
        // 他のアプリのショートカットより先に受け取る。権限がなければアプリ内だけで受け取る
        let tap = KeyCaptureTap(handler: { type, keyCode, flags in
            handleRecording(type, keyCode: keyCode, flags: flags)
        }, systemKeyHandler: { key, flags in
            handleRecordingSystemKey(key, flags: flags)
        })
        if tap.start() {
            captureTap = tap
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleRecording(event.type == .keyDown ? .keyDown : .flagsChanged,
                            keyCode: event.keyCode,
                            flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
            return nil
        }
    }

    private func stopRecording() {
        captureTap?.stop()
        captureTap = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        heldModifier = nil
    }

    /// 明るさや音量などの特殊キー。修飾キーと組み合わせた形では送れないので、単独のときだけ記録する
    private func handleRecordingSystemKey(_ key: Int32, flags: CGEventFlags) {
        guard let id = recording else { return }
        heldModifier = nil
        let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        if flags.intersection(modifiers).isEmpty, let text = KeyCombo.recordedMediaText(key: key) {
            model.setBinding(id, to: text)
            clearSelection()
        } else {
            model.keymapError = "F キーとして割り当てるには、Fn も一緒に押してください"
        }
    }

    private func handleRecording(_ type: CGEventType, keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let id = recording else { return }
        if type == .keyDown {
            guard let text = KeyCombo.recordedText(keyCode: keyCode, flags: flags) else {
                model.keymapError = "このキーは割り当てできません"
                return
            }
            model.setBinding(id, to: text)
            clearSelection()
            return
        }
        guard type == .flagsChanged else { return }
        // 修飾キー: 他のキーと組み合わせずに離したときだけ単体として記録する
        let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]
        let isPress = KeyCombo.recordedModifierText(keyCode: keyCode) != nil
            && !flags.intersection(modifierMask).isEmpty
        if isPress {
            heldModifier = keyCode
        } else if let held = heldModifier, held == keyCode,
                  let text = KeyCombo.recordedModifierText(keyCode: held) {
            model.setBinding(id, to: text)
            clearSelection()
        }
    }
}

// MARK: - 接続と音声

struct ConnectionPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "接続と音声") { EmptyView() }
            HStack(alignment: .top, spacing: 18) {
                Card {
                    VStack(spacing: 14) {
                        Text("Amazon Remote").font(.title3.bold())
                        StatusPill(connected: model.connected)
                        RemoteDrawing(pressed: model.pressedButtons)
                            .frame(width: 92, height: 420)
                            .coordinateSpace(name: mapSpace)
                        Label(model.micOn ? "マイク動作中" : "音声ボタンを押している間だけマイクが動きます",
                              systemImage: model.micOn ? "mic.fill" : "mic")
                            .font(.callout)
                            .foregroundStyle(model.micOn ? Color.accentColor : Color.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 300)

                VStack(spacing: 18) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("仮想マイク").font(.headline)
                                Spacer()
                                if model.driverBusy {
                                    ProgressView().controlSize(.small)
                                } else if !model.driverInstalled {
                                    Button("インストール", action: model.installDriver)
                                } else if !model.driverDeviceAvailable {
                                    Button("再インストール", action: model.installDriver)
                                } else {
                                    Button("アンインストール", action: model.uninstallDriver)
                                }
                            }
                            Text(driverStatus).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let error = model.driverError {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                            Divider()
                            Toggle("他の出力デバイスを使う", isOn: $model.useCustomOutput)
                            if model.useCustomOutput {
                                HStack {
                                    Picker("送り先", selection: $model.selectedDeviceUID) {
                                        Text("なし").tag(String?.none)
                                        ForEach(model.outputDevices, id: \.uid) {
                                            Text($0.name).tag(String?.some($0.uid))
                                        }
                                    }
                                    .labelsHidden()
                                    Button("更新", action: model.refreshDevices)
                                }
                                Text("BlackHole などを選ぶと、リモコンの音声をそのデバイスへ送ります。使うアプリの入力には同じデバイスを選びます。")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text("システムの既定の入出力デバイスは変更しません。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Card {
                        Toggle("ログイン時に起動", isOn: Binding(get: { model.loginItemEnabled },
                                                          set: { model.setLoginItem($0) }))
                    }
                    if let error = model.startError {
                        Card { Text(error).font(.callout).foregroundStyle(.red) }
                    }
                    Spacer()
                }
            }
        }
        .padding(22)
        .padding(.top, 8)
    }

    private var driverStatus: String {
        if model.driverInstalled && model.driverDeviceAvailable {
            return "使用できます。音声入力を使うアプリの入力に「Remotio Microphone」を選んでください。"
        }
        if model.driverInstalled {
            return "新しいバージョンへの更新が必要です。再インストールしてください。解決しない場合は Mac を再起動してください。"
        }
        return "他のアプリのマイクとして使うために必要です。管理者パスワードの入力が必要で、処理の間は Mac の音声が一瞬止まります。"
    }
}

// MARK: - 権限

struct PermissionsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "権限") { EmptyView() }
            row("入力監視", "リモコンのボタンと音声を受け取るために必要です。変更後はアプリを開き直してください。",
                granted: model.inputMonitoringGranted, action: model.requestInputMonitoring)
            row("アクセシビリティ", "割り当てたキーを送信するために必要です。",
                granted: model.accessibilityGranted, action: model.requestAccessibility)
            Spacer()
        }
        .padding(22)
        .padding(.top, 8)
    }

    private func row(_ title: String, _ detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if granted {
                    Label("許可済み", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("許可を求める", action: action)
                }
            }
        }
    }
}

// MARK: - ログ

struct LogsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "ログ") { EmptyView() }
            Card {
                ScrollView {
                    Text(model.logs.isEmpty ? "まだログはありません。" : model.logs.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(22)
        .padding(.top, 8)
    }
}
