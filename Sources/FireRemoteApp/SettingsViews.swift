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
    @State private var page = SettingsPage.buttons

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
    @State private var heldModifier: UInt16?
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
        .onDisappear(perform: stopRecording)
    }

    private var map: some View {
        ZStack {
            leaderLines.allowsHitTesting(false)
            HStack(alignment: .top, spacing: 40) {
                column(RemoteButton.left)
                RemoteDrawing(pressed: model.pressedButtons, selected: selected ?? recording) { id in
                    selected = id
                    startRecording(id)
                }
                .frame(width: 112, height: 540)
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
                Text(button.title).font(.callout.weight(.medium)).lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    selected = button.id
                    isRecording ? stopRecording() : startRecording(button.id)
                } label: {
                    Text(isRecording ? "キーを入力…" : (binding.map(KeyCombo.displayText) ?? "未設定"))
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .frame(minWidth: 72)
                }
                .accessibilityLabel("\(button.title) のキー")
                .accessibilityValue(binding ?? "未設定")
                if binding != nil && !isRecording {
                    Button {
                        model.setBinding(button.id, to: nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(button.title) の割り当てを解除")
                }
            }
        }
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
                    Text("「\(name)」に割り当てるキーを押してください。修飾キーだけ(Fn、右 ⌥ など)も押して離すと設定できます。")
                        .font(.callout)
                } else {
                    Text("カードかリモコン図のボタンをクリックして、割り当てるキーを押します。音声ボタンは、押している間マイクが動き、割り当てたキーも押され続けます。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if recording != nil { Button("キャンセル", action: stopRecording) }
                Button("初期設定に戻す") {
                    stopRecording()
                    model.restoreDefaultBindings()
                }
            }
        }
    }

    private func startRecording(_ id: String) {
        stopRecording()
        recording = id
        heldModifier = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleRecording(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        heldModifier = nil
    }

    private func handleRecording(_ event: NSEvent) {
        guard let id = recording else { return }
        if event.type == .keyDown {
            var flags: CGEventFlags = []
            let modifiers = event.modifierFlags
            if modifiers.contains(.command) { flags.insert(.maskCommand) }
            if modifiers.contains(.shift) { flags.insert(.maskShift) }
            if modifiers.contains(.option) { flags.insert(.maskAlternate) }
            if modifiers.contains(.control) { flags.insert(.maskControl) }
            guard let text = KeyCombo.recordedText(keyCode: event.keyCode, flags: flags) else {
                model.keymapError = "このキーは割り当てできません"
                return
            }
            model.setBinding(id, to: text)
            stopRecording()
            return
        }
        // 修飾キー: 他のキーと組み合わせずに離したときだけ単体として記録する
        let isPress = KeyCombo.recordedModifierText(keyCode: event.keyCode) != nil
            && event.modifierFlags.intersection([.command, .shift, .option, .control, .function]).isEmpty == false
        if isPress {
            heldModifier = event.keyCode
        } else if let held = heldModifier, held == event.keyCode,
                  let text = KeyCombo.recordedModifierText(keyCode: held) {
            model.setBinding(id, to: text)
            stopRecording()
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
                        VStack(alignment: .leading, spacing: 12) {
                            Text("音声の出力先").font(.headline)
                            HStack {
                                Picker("出力先", selection: $model.selectedDeviceUID) {
                                    Text("なし").tag(String?.none)
                                    ForEach(model.outputDevices, id: \.uid) {
                                        Text($0.name).tag(String?.some($0.uid))
                                    }
                                }
                                .labelsHidden()
                                Button("更新", action: model.refreshDevices)
                            }
                            Text(outputHint).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
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

    private var outputHint: String {
        if model.selectedDeviceUID == nil {
            return "他のアプリのマイクとして使うには、BlackHole などの仮想デバイスを選びます。"
        }
        if model.hasVirtualDeviceSelected {
            return "使うアプリの入力に、同じデバイスを選んでください。"
        }
        return "このデバイスには入力がありません。音声はスピーカーなどから再生されます。"
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
