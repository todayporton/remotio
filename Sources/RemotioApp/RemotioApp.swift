import AppKit
import RemoteCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) { model.start() }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// remotio://settings/buttons のような URL で、設定画面の各ページやセットアップの案内を開く
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.compactMap(WindowRequest.init(url:)).last.map { model.windowRequest = $0 }
    }
}

@main
struct RemotioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Window("Remotio", id: "settings") {
            SettingsView(model: delegate.model)
        }
        .windowResizability(.contentMinSize)

        Window("Remotio のセットアップ", id: "setup") {
            SetupView(model: delegate.model)
        }
        .windowResizability(.contentSize)
    }
}

/// メニューバーのアイコン。アプリの起動時に必ず表示されるので、起動時の処理もここで行う。
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image(
            symbolName: model.micOn ? "mic.fill" : (model.connected ? "appletvremote.gen4" : "appletvremote.gen4.fill")
        ))
        .onAppear {
            // シーンの構築が終わってから開く
            DispatchQueue.main.async {
                if model.shouldOpenSetup { openWindow(id: "setup") }
            }
        }
        // URL で開くよう求められたウインドウを開く。このアイコンは常に表示されているので、ここで受け取る
        .onReceive(model.$windowRequest.compactMap { $0 }) { request in
            openWindow(id: request.windowID)
            NSApp.activate(ignoringOtherApps: true)
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
