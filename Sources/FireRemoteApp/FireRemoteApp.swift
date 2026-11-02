import AppKit
import RemoteCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Window シーンは起動時に自動で開くため、常駐アプリとして閉じておく
        guard !CommandLine.arguments.contains("--show-window") else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        DispatchQueue.main.async {
            NSApp.windows.filter { $0.identifier?.rawValue == "settings" }.forEach { $0.close() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct FireRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
                .onAppear { delegate.model = model }
        } label: {
            Image(systemName: model.micOn ? "mic.fill" : (model.connected ? "appletvremote.gen4" : "appletvremote.gen4.fill"))
        }
        .menuBarExtraStyle(.window)

        Window("Fire Remote", id: "settings") {
            SettingsView(model: model)
                .onAppear { delegate.model = model }
        }
        .windowResizability(.contentSize)
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.connected ? "リモコン: 接続中" : "リモコン: 未接続",
                  systemImage: model.connected ? "checkmark.circle.fill" : "xmark.circle")
            Label(model.micOn ? "マイク: 動作中" : "マイク: 停止中", systemImage: model.micOn ? "mic.fill" : "mic.slash")
            if let error = model.startError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Divider()
            Button("設定とログを開く…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("終了") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var edited: [String: String] = [:]

    var body: some View {
        TabView {
            general.tabItem { Text("一般") }
            keymap.tabItem { Text("キー割り当て") }
            logs.tabItem { Text("ログ") }
        }
        .padding()
        .frame(width: 520, height: 460)
        .onAppear {
            edited = model.bindings
            model.refreshDevices()
            model.refreshPermissions()
        }
    }

    private var general: some View {
        Form {
            LabeledContent("リモコン", value: model.connected ? "接続中" : "未接続")
            LabeledContent("マイク", value: model.micOn ? "動作中" : "停止中")
            Picker("音声の出力先", selection: $model.selectedDeviceUID) {
                Text("なし").tag(String?.none)
                ForEach(model.outputDevices, id: \.uid) { Text($0.name).tag(String?.some($0.uid)) }
            }
            Text("他のアプリで使うには BlackHole などの仮想デバイスを選びます。システムの既定デバイスは変更しません。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("ログイン時に起動", isOn: Binding(get: { model.loginItemEnabled }, set: { model.setLoginItem($0) }))
            permission("入力監視", granted: model.inputMonitoringGranted, action: model.requestInputMonitoring)
            permission("アクセシビリティ(キー送信)", granted: model.accessibilityGranted, action: model.requestAccessibility)
        }
    }

    private func permission(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            if granted { Text("許可済み") } else { Button("許可を求める", action: action) }
        }
    }

    private var keymap: some View {
        VStack(alignment: .leading) {
            Text("例: up / return / cmd+shift+p。空欄は割り当てなしです。").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Grid(alignment: .leading) {
                    ForEach(AppModel.mappableButtons, id: \.self) { button in
                        GridRow {
                            Text(button)
                            TextField(button, text: Binding(get: { edited[button, default: ""] },
                                                            set: { edited[button] = $0 }))
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                        }
                    }
                }
            }
            if let error = model.keymapError { Text(error).font(.caption).foregroundStyle(.red) }
            Button("保存") { model.saveBindings(edited) }
        }
    }

    private var logs: some View {
        ScrollView {
            Text(model.logs.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
