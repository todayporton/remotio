import AppKit
import RemoteCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct RemotioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
                .onAppear { delegate.model = model }
        } label: {
            MenuBarLabel(model: model, delegate: delegate)
        }
        .menuBarExtraStyle(.window)

        Window("Remotio", id: "settings") {
            SettingsView(model: model)
                .onAppear { delegate.model = model }
        }
        .windowResizability(.contentMinSize)

        Window("Remotio のセットアップ", id: "setup") {
            SetupView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

/// メニューバーのアイコン。アプリの起動時に必ず表示されるので、起動時の処理もここで行う。
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image(
            symbolName: model.micOn ? "mic.fill" : (model.connected ? "appletvremote.gen4" : "appletvremote.gen4.fill")
        ))
        .onAppear {
            delegate.model = model
            // シーンの構築が終わってから開く
            DispatchQueue.main.async {
                if model.shouldOpenSetup { openWindow(id: "setup") }
            }
        }
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
            if !model.driverDeviceAvailable && !model.useCustomOutput {
                Label("仮想マイクが未インストールです", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let error = model.startError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Divider()
            Button("設定とログを開く…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("セットアップを開く…") {
                openWindow(id: "setup")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("終了") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
    }
}
