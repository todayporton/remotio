import AppKit
import RemoteCore
import SwiftUI

// MARK: - ボタンの定義

struct RemoteButton: Identifiable {
    enum Shape: Equatable {
        case round, arrow, select, voice
        /// 音量の縦長ボタンの上半分か下半分
        case volume
        /// アプリボタン(実機の色と文字の色)
        case app(fill: Color, label: Color)
    }

    let id: String
    let title: String
    let symbol: String
    /// リモコン図の中の中心の位置(x は幅、y は高さに対する割合)
    let position: CGPoint
    /// 大きさ(幅も高さもリモコン図の幅に対する割合)
    let size: CGSize
    var shape: Shape = .round
    /// 図に描く記号(一覧と違うときだけ)
    var glyph: String?

    private static func button(_ id: String, _ title: String, _ symbol: String, _ x: CGFloat, _ y: CGFloat,
                               size: CGFloat = 0.23, shape: Shape = .round, glyph: String? = nil) -> RemoteButton {
        RemoteButton(id: id, title: title, symbol: symbol, position: .init(x: x, y: y),
                     size: .init(width: size, height: size), shape: shape, glyph: glyph)
    }

    private static func app(_ id: String, _ title: String, _ number: Int, _ x: CGFloat, _ y: CGFloat,
                            fill: Color, label: Color) -> RemoteButton {
        RemoteButton(id: id, title: title, symbol: "\(number).circle", position: .init(x: x, y: y),
                     size: .init(width: 0.37, height: 0.135), shape: .app(fill: fill, label: label), glyph: "\(number)")
    }

    // 位置と大きさは Fire TV Stick 4K の Alexa 対応音声認識リモコン(第3世代)に合わせている
    static let left: [RemoteButton] = [
        button("voice", String(localized: "音声(Push-to-Talk)"), "mic.fill", 0.5, 0.108, size: 0.24, shape: .voice),
        button("dpad_up", String(localized: "上"), "chevron.up", 0.5, 0.18, size: 0.16, shape: .arrow),
        button("dpad_left", String(localized: "左"), "chevron.left", 0.2, 0.258, size: 0.16, shape: .arrow),
        button("back", String(localized: "戻る"), "arrow.uturn.backward", 0.19, 0.42),
        button("rewind", String(localized: "巻き戻し"), "backward.fill", 0.19, 0.49),
        button("volume_up", String(localized: "音量 +"), "speaker.plus", 0.5, 0.578, shape: .volume, glyph: "plus"),
        button("mute", String(localized: "ミュート"), "speaker.slash", 0.19, 0.575),
        app("app_a1", String(localized: "アプリ 1"), 1, 0.29, 0.712, fill: Color(red: 0.12, green: 0.45, blue: 0.75), label: .white),
        app("app_a3", String(localized: "アプリ 3"), 3, 0.29, 0.772, fill: Color(white: 0.86), label: Color(white: 0.15)),
    ]
    static let right: [RemoteButton] = [
        button("select", String(localized: "決定"), "circle.circle", 0.5, 0.258, size: 0.4, shape: .select),
        button("dpad_right", String(localized: "右"), "chevron.right", 0.8, 0.258, size: 0.16, shape: .arrow),
        button("dpad_down", String(localized: "下"), "chevron.down", 0.5, 0.336, size: 0.16, shape: .arrow),
        button("home", String(localized: "ホーム"), "house", 0.5, 0.42),
        button("menu", String(localized: "メニュー"), "line.3.horizontal", 0.81, 0.42),
        button("play_pause", String(localized: "再生・停止"), "playpause.fill", 0.5, 0.49),
        button("fast_forward", String(localized: "早送り"), "forward.fill", 0.81, 0.49),
        button("volume_down", String(localized: "音量 −"), "speaker.minus", 0.5, 0.645, shape: .volume, glyph: "minus"),
        button("tv", "TV", "tv", 0.81, 0.575),
        app("app_a2", String(localized: "アプリ 2"), 2, 0.71, 0.712, fill: .white, label: Color(red: 0.85, green: 0.1, blue: 0.12)),
        app("app_a4", String(localized: "アプリ 4"), 4, 0.71, 0.772, fill: .white, label: Color(red: 0.1, green: 0.15, blue: 0.3)),
    ]
    static let all = left + right

    /// 図の縦横比(実機に合わせて幅 : 高さ = 1 : 3.9)
    static let drawingAspect: CGFloat = 1 / 3.9
}

// MARK: - 全体

enum SettingsPage: String, CaseIterable, Identifiable {
    case connection, buttons, permissions, logs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .connection: return String(localized: "接続と音声")
        case .buttons: return String(localized: "ボタン")
        case .permissions: return String(localized: "権限")
        case .logs: return String(localized: "ログ")
        }
    }
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
        // URL でページの指定があればそのページ、なければ仮想マイクが未導入ならインストールのボタンがある画面から始める
        let fallback: SettingsPage = model.driverDeviceAvailable || model.useCustomOutput ? .buttons : .connection
        _page = State(initialValue: model.windowRequest?.page ?? fallback)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                ForEach(SettingsPage.allCases) { item in
                    Button { page = item } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.symbol).font(.title2)
                            Text(item.title).font(.caption)
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .contentShape(Rectangle())
                        .foregroundStyle(page == item ? Color.accentColor : Color.secondary)
                        .background(page == item ? Color.accentColor.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityLabel(item.title)
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
                case .logs: LogsPage(store: model.logStore)
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
        .onReceive(model.$windowRequest.compactMap { $0?.page }) { page = $0 }
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

    private static let voiceBlue = Color(red: 0.1, green: 0.66, blue: 0.9)
    /// 塗りつぶしの記号は横に広く大きく見えるので、ほかより小さく描く
    private static let mediaKeys: Set<String> = ["rewind", "play_pause", "fast_forward"]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // 本体
                RoundedRectangle(cornerRadius: w * 0.32)
                    .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.08)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.32).strokeBorder(Color.white.opacity(0.08)))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                // マイクの穴と電源ボタン(電源は Mac に届かないので飾り)
                Capsule().fill(Color.black).frame(width: w * 0.025, height: w * 0.06)
                    .position(x: w * 0.5, y: h * 0.038)
                Circle().fill(Color(white: 0.2))
                    .overlay(Image(systemName: "power").font(.system(size: w * 0.07, weight: .semibold))
                        .foregroundStyle(Color(white: 0.75)))
                    .frame(width: w * 0.15, height: w * 0.15)
                    .position(x: w * 0.15, y: h * 0.048)
                // 方向ボタンのリング
                Circle()
                    .fill(Color(white: 0.04))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.07)))
                    .frame(width: w * 0.82, height: w * 0.82)
                    .position(x: w * 0.5, y: h * 0.258)
                // 音量の縦長ボタン
                Capsule().fill(Color(white: 0.17))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
                    .frame(width: w * 0.24, height: w * 0.5)
                    .position(x: w * 0.5, y: h * 0.6115)
                ForEach(RemoteButton.all) { button in
                    key(button, active: pressed.contains(button.id) || selected == button.id, width: w)
                        .position(x: w * button.position.x, y: h * button.position.y)
                }
            }
        }
        .aspectRatio(RemoteButton.drawingAspect, contentMode: .fit)
    }

    private func key(_ button: RemoteButton, active: Bool, width w: CGFloat) -> some View {
        let size = CGSize(width: button.size.width * w, height: button.size.height * w)
        let glyph = Image(systemName: button.glyph ?? button.symbol)
            .font(.system(size: min(size.width, size.height) * (Self.mediaKeys.contains(button.id) ? 0.34 : 0.46),
                          weight: .semibold))
        return Button { onSelect?(button.id) } label: {
            ZStack {
                switch button.shape {
                case .round:
                    Circle().fill(active ? Color.accentColor : Color(white: 0.17))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.08)))
                    glyph.foregroundStyle(.white)
                case .voice:
                    Circle().fill(active ? Color.accentColor : Self.voiceBlue)
                    glyph.foregroundStyle(.white)
                case .arrow:
                    // 実機のリングには印がないので、押したときと選んだときだけ目立たせる
                    glyph.foregroundStyle(active ? Color.accentColor : Color(white: 0.4))
                case .select:
                    Circle().fill(active ? Color.accentColor : Color(white: 0.13))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.08)))
                case .volume:
                    if active { Circle().fill(Color.accentColor) }
                    glyph.foregroundStyle(.white)
                case .app(let fill, let label):
                    Capsule().fill(active ? Color.accentColor : fill)
                    Text(button.glyph ?? "")
                        .font(.system(size: size.height * 0.62, weight: .bold, design: .rounded))
                        .foregroundStyle(active ? .white : label)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("リモコン \(button.title)")
        .background(GeometryReader { g in
            Color.clear.preference(key: RemoteFrameKey.self,
                                   value: ["remote:\(button.id)": g.frame(in: .named(mapSpace))])
        })
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
    /// 長押しと2回押しの設定を開いているボタン
    @State private var editingGestures: String?
    /// 入力中のコマンド(URL かシェルコマンド)
    @State private var commandEdit: CommandEdit?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: SettingsPage.buttons.title) {
                HStack(spacing: 12) {
                    targetMenu
                    StatusPill(connected: model.connected)
                }
            }
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
        .sheet(item: $commandEdit) { edit in
            CommandEditor(edit: edit) { text in
                assign(edit.id, text)
                commandEdit = nil
            } cancel: {
                commandEdit = nil
            }
        }
    }

    private var map: some View {
        ZStack {
            leaderLines.allowsHitTesting(false)
            HStack(alignment: .top, spacing: 40) {
                column(RemoteButton.left)
                RemoteDrawing(pressed: model.pressedButtons, selected: selected ?? recording) { id in
                    startRecording(id)
                }
                .frame(width: 126, height: 490)
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
        let binding = model.displayedBindings[button.id]
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
                    actionMenu(id: button.id, title: button.title, binding: binding,
                               unassigned: model.unassignedTitle(button.id), allowsDisabled: true)
                    if button.id != model.voiceButtonName { gestureButton(button) }
                }
            }
        }
    }

    private func actionMenu(id: String, title: String, binding: String?, unassigned: String,
                            allowsDisabled: Bool) -> some View {
        Menu {
            Button("キーを入力…") { startRecording(id) }
            Divider()
            if model.isOverridden(id) {
                Button("既定に戻す") {
                    model.useGlobalBinding(id)
                    clearSelection()
                }
            }
            Button(unassigned) { assign(id, nil) }
            if allowsDisabled { Button("無効") { assign(id, ActionCatalog.disabled) } }
            Divider()
            Menu("音声入力") {
                ForEach(ActionCatalog.dictationItems) { item in
                    Button(item.title) { assign(id, item.id) }
                }
            }
            Menu("メディア操作") {
                ForEach(ActionCatalog.mediaItems) { item in
                    Button(item.title) { assign(id, item.id) }
                }
            }
            Menu("システム操作") {
                ForEach(ActionCatalog.systemItems) { item in
                    Button(item.title) { assign(id, item.id) }
                }
            }
            Divider()
            Button("URL を開く…") { editCommand(id: id, title: title, kind: .url, current: binding) }
            Button("シェルコマンドを実行…") { editCommand(id: id, title: title, kind: .shell, current: binding) }
        } label: {
            Text(menuTitle(id: id, binding: binding, unassigned: unassigned))
                .font(.body.weight(.medium))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        // アプリの編集中に、既定の割り当てを上書きしている項目は色を付ける
        .background(model.isOverridden(id) ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(model.isOverridden(id) ? Color.accentColor : Color.clear))
        .accessibilityLabel("\(title) の操作")
        .accessibilityValue(binding ?? unassigned)
    }

    private func editCommand(id: String, title: String, kind: CommandEdit.Kind, current: String?) {
        // 同じ種類のコマンドが割り当て済みなら、その中身から編集を始める
        var text = ""
        switch current.flatMap(ButtonCommand.init) {
        case .openURL(let url) where kind == .url: text = url.absoluteString
        case .shell(let command) where kind == .shell: text = command
        default: break
        }
        commandEdit = CommandEdit(id: id, title: title, kind: kind, text: text)
    }

    /// メニューに出す名前。アプリの編集中は、上書きしていない項目を「既定」と出す
    private func menuTitle(id: String, binding: String?, unassigned: String) -> String {
        if model.editingApp != nil && !model.isOverridden(id) { return String(localized: "既定") }
        return binding.map(KeyCombo.displayText) ?? unassigned
    }

    /// 長押しと2回押しの設定を開くボタン。設定済みなら塗りつぶしのアイコンにする
    private func gestureButton(_ button: RemoteButton) -> some View {
        let configured = model.displayedBindings["\(button.id)\(KeyMap.longSuffix)"] != nil
            || model.displayedBindings["\(button.id)\(KeyMap.doubleSuffix)"] != nil
        return Button {
            editingGestures = button.id
        } label: {
            Image(systemName: configured ? "hand.tap.fill" : "hand.tap")
                .foregroundStyle(configured ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help("長押しと2回押し")
        .accessibilityLabel("\(button.title) の長押しと2回押し")
        .popover(isPresented: Binding(get: { editingGestures == button.id },
                                      set: { if !$0 { editingGestures = nil } })) {
            gestureEditor(button)
        }
    }

    private func gestureEditor(_ button: RemoteButton) -> some View {
        let longID = "\(button.id)\(KeyMap.longSuffix)"
        let doubleID = "\(button.id)\(KeyMap.doubleSuffix)"
        let modeID = "\(button.id)\(KeyMap.longModeSuffix)"
        let mode = model.displayedBindings[modeID].flatMap(LongPressMode.init(rawValue:)) ?? .once
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(button.title) の押し方").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("長押し")
                    gestureMenu(id: longID, title: String(localized: "\(button.title) の長押し"))
                }
                GridRow {
                    Text("送り方")
                    Picker("送り方", selection: Binding(get: { mode },
                                                     set: { model.setBinding(modeID, to: $0.rawValue) })) {
                        Text("1回送る").tag(LongPressMode.once)
                        Text("押している間").tag(LongPressMode.hold)
                        Text("リピート").tag(LongPressMode.repeat)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(model.displayedBindings[longID] == nil)
                }
                GridRow {
                    Text("2回押し")
                    gestureMenu(id: doubleID, title: String(localized: "\(button.title) の2回押し"))
                }
            }
            Text("長押しか2回押しを割り当てると、Mac の標準動作は止まり、タップの操作は Remotio から送ります。2回押しを割り当てると、タップは約0.3秒遅れます。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 400)
    }

    private func gestureMenu(id: String, title: String) -> some View {
        Group {
            if recording == id {
                Button("キーを入力…", action: clearSelection)
                    .accessibilityLabel("\(title) のキー入力を中止")
            } else {
                actionMenu(id: id, title: title, binding: model.displayedBindings[id],
                           unassigned: String(localized: "割り当てなし"), allowsDisabled: false)
            }
        }
    }

    /// 操作を選び終えたら、選択状態とフォーカスを解除する
    private func assign(_ id: String, _ value: String?) {
        model.setBinding(id, to: value)
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
                    let name = recordingTitle(recording)
                    Text("「\(name)」に割り当てるキーを押してください。修飾キーだけ(Fn、右 ⌥ など)も押して離すと設定できます。待ち受け中のキー入力は他のアプリへ送りません。")
                        .font(.callout)
                } else if let app = model.editingApp {
                    Text("「\(AppInfo.name(of: app))」が前面にあるときだけ使う割り当てです。「既定」の項目は既定の割り当てに従います。色の付いた項目はこのアプリだけの割り当てで、メニューの「既定に戻す」で戻せます。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("各ボタンのメニューから操作を選びます。「標準」は Mac の標準動作をそのまま通し、「無効」は何もしません。この画面を操作している間は、リモコンから割り当てたキーを送りません。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if recording != nil { Button("キャンセル", action: clearSelection) }
                Button(model.editingApp == nil ? String(localized: "初期設定に戻す") : String(localized: "すべて既定に戻す")) {
                    clearSelection()
                    model.restoreDefaultBindings()
                }
            }
        }
    }

    /// 編集する対象(既定か、個別の割り当てを持つアプリ)を選ぶ
    private var targetMenu: some View {
        let apps = model.appBindings.keys.sorted { AppInfo.name(of: $0) < AppInfo.name(of: $1) }
        let addable = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { $0 != Bundle.main.bundleIdentifier && model.appBindings[$0] == nil }
        return Menu {
            Button("既定") { selectTarget(nil) }
            if !apps.isEmpty {
                Divider()
                ForEach(apps, id: \.self) { app in
                    Button(AppInfo.name(of: app)) { selectTarget(app) }
                }
            }
            Divider()
            Menu("アプリを追加") {
                ForEach(Array(Set(addable)).sorted { AppInfo.name(of: $0) < AppInfo.name(of: $1) }, id: \.self) { app in
                    Button(AppInfo.name(of: app)) { addApp(app) }
                }
                Divider()
                Button("その他のアプリ…", action: chooseOtherApp)
            }
            if let app = model.editingApp {
                Divider()
                Button("「\(AppInfo.name(of: app))」の割り当てを削除") {
                    clearSelection()
                    model.removeApp(app)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let app = model.editingApp, let icon = AppInfo.icon(of: app) {
                    Image(nsImage: icon)
                } else {
                    Image(systemName: "square.grid.2x2")
                }
                Text(model.editingApp.map(AppInfo.name(of:)) ?? String(localized: "既定"))
            }
        }
        .fixedSize()
        .accessibilityLabel("割り当ての対象")
    }

    private func selectTarget(_ app: String?) {
        clearSelection()
        model.editingApp = app
    }

    private func addApp(_ app: String) {
        clearSelection()
        model.addApp(app)
    }

    private func chooseOtherApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        addApp(id)
    }

    /// 待ち受け中の割り当ての名前(例: 「TV の長押し」)
    private func recordingTitle(_ id: String) -> String {
        for button in RemoteButton.all {
            if id == button.id { return button.title }
            if id == button.id + KeyMap.longSuffix { return String(localized: "\(button.title) の長押し") }
            if id == button.id + KeyMap.doubleSuffix { return String(localized: "\(button.title) の2回押し") }
        }
        return id
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
            model.keymapError = String(localized: "F キーとして割り当てるには、Fn も一緒に押してください")
        }
    }

    private func handleRecording(_ type: CGEventType, keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let id = recording else { return }
        if type == .keyDown {
            guard let text = KeyCombo.recordedText(keyCode: keyCode, flags: flags) else {
                model.keymapError = String(localized: "このキーは割り当てできません")
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

/// マイクのゲインと入力レベル
struct MicInputSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var meter: MicLevelMeter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("マイク入力").font(.headline)
            HStack(spacing: 10) {
                Text("ゲイン")
                Slider(value: $model.micGainDecibels,
                       in: AudioGain.minDecibels...AudioGain.maxDecibels, step: 1)
                    .accessibilityLabel("マイクのゲイン")
                Text(String(format: "%+.0f dB", model.micGainDecibels))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
                Button("リセット") { model.micGainDecibels = 0 }
                    .disabled(model.micGainDecibels == 0)
            }
            HStack(spacing: 10) {
                Text("レベル")
                MicMeterBar(position: meter.position)
                    .frame(height: 10)
                    .accessibilityLabel("入力レベル")
                    .accessibilityValue("\(Int(meter.position * 100))%")
            }
            Text(meter.clipping ? "音が割れています。ゲインを下げてください。"
                 : "音声ボタンを押して普通に話し、音の山が線(-12 dB)に届くくらいが目安です。設定画面が前面の間は、割り当てたキーを送りません。")
                .font(.caption)
                .foregroundStyle(meter.clipping ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MicMeterBar: View {
    let position: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                LinearGradient(stops: [
                    .init(color: .green, location: 0),
                    .init(color: .green, location: 0.85),
                    .init(color: .yellow, location: 0.9),
                    .init(color: .red, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
                .mask(alignment: .leading) {
                    Capsule().frame(width: geometry.size.width * position)
                }
                // 普通に話したときのピークの目安
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2, height: geometry.size.height + 6)
                    .offset(x: geometry.size.width * AudioGain.meterPosition(decibels: AudioGain.targetPeakDecibels) - 1)
            }
        }
    }
}

struct ConnectionPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: SettingsPage.connection.title) { EmptyView() }
            HStack(alignment: .top, spacing: 18) {
                Card {
                    VStack(spacing: 14) {
                        Text("Amazon Remote").font(.title3.bold())
                        StatusPill(connected: model.connected)
                        RemoteDrawing(pressed: model.pressedButtons)
                            .frame(width: 108, height: 420)
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
                    Card { MicInputSection(model: model, meter: model.micMeter) }
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
            return String(localized: "使用できます。音声入力を使うアプリの入力に「Remotio Microphone」を選んでください。")
        }
        if model.driverInstalled {
            return String(localized: "新しいバージョンへの更新が必要です。再インストールしてください。解決しない場合は Mac を再起動してください。")
        }
        return String(localized: "他のアプリのマイクとして使うために必要です。管理者パスワードの入力が必要で、処理の間は Mac の音声が一瞬止まります。")
    }
}

// MARK: - 権限

struct PermissionsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: SettingsPage.permissions.title) { EmptyView() }
            row(String(localized: "入力監視"), String(localized: "リモコンのボタンと音声を受け取るために必要です。変更後はアプリを開き直してください。"),
                granted: model.inputMonitoringGranted, action: model.requestInputMonitoring)
            row(String(localized: "アクセシビリティ"), String(localized: "割り当てたキーを送信するために必要です。"),
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
    @ObservedObject var store: LogStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: SettingsPage.logs.title) { EmptyView() }
            Card {
                if store.lines.isEmpty {
                    Text("まだログはありません。").font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    LogTextView(lines: store.lines)
                }
            }
        }
        .padding(22)
        .padding(.top, 8)
    }
}

/// バンドル ID からアプリの名前とアイコンを引く
enum AppInfo {
    static func url(of bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(of bundleID: String) -> String {
        guard let url = url(of: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(of bundleID: String) -> NSImage? {
        guard let url = url(of: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

/// コマンドの入力中の状態
struct CommandEdit: Identifiable {
    enum Kind { case url, shell }
    let id: String
    let title: String
    let kind: Kind
    var text: String
}

/// URL かシェルコマンドを入力するシート
struct CommandEditor: View {
    @State var edit: CommandEdit
    let save: (String) -> Void
    let cancel: () -> Void

    private var command: ButtonCommand? {
        let value = edit.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ButtonCommand((edit.kind == .url ? "url:" : "shell:") + value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(edit.kind == .url ? "「\(edit.title)」で開く URL" : "「\(edit.title)」で実行するシェルコマンド")
                .font(.headline)
            TextField(edit.kind == .url ? "raycast://extensions/… や https://…" : "open -a Safari",
                      text: $edit.text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .lineLimit(1...4)
                .frame(width: 440)
            Text(edit.kind == .url
                 ? "ボタンを押したときに、この URL を開きます。Raycast などのアプリの URL も使えます。"
                 : "ボタンを押したときに、ログインシェル(zsh)で実行します。あなたの権限で実行されるので、内容を確認してから設定してください。失敗したときはログに出ます。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("キャンセル", action: cancel).keyboardShortcut(.cancelAction)
                Button("保存") { command.map { save($0.text) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(command == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
