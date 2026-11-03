import RemoteCore
import SwiftUI

/// 初回セットアップの案内
struct SetupView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var progress: SetupProgress { model.setupProgress }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remotio のセットアップ").font(.largeTitle.bold())
            Text("順番に進めると、リモコンをマイクとボタンとして使えるようになります。")
                .foregroundStyle(.secondary)

            inputMonitoringStep
            accessibilityStep
            pairingStep
            microphoneStep

            if progress.currentStep == nil {
                Text("準備ができました。音声入力を使うアプリで、入力に「Remotio Microphone」を選んでください。ボタンの割り当ては設定画面で変更できます。")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                if progress.currentStep == nil {
                    Button("設定画面を開く") {
                        openWindow(id: "settings")
                        finish()
                    }
                    Button("完了", action: finish).keyboardShortcut(.defaultAction)
                } else {
                    Button("後で設定する", action: finish)
                }
            }
        }
        .padding(24)
        .frame(width: 620, height: 640)
        .onAppear {
            model.refreshPermissions()
            model.refreshDevices()
            NSApp.activate(ignoringOtherApps: true)
        }
        // 権限はシステム設定で変更されるので、変化を待つ
        .onReceive(timer) { _ in model.refreshPermissions() }
    }

    private func finish() {
        model.dismissSetup()
        dismiss()
    }

    private var inputMonitoringStep: some View {
        SetupStepCard(number: 1, title: "入力監視を許可する",
                      detail: "リモコンのボタンと音声を受け取るために必要です。システム設定の一覧に Remotio がなければ、「+」から追加してオンにします。",
                      step: .inputMonitoring, progress: progress) {
            Button("許可する", action: model.requestInputMonitoring)
        } extra: {
            // 許可は起動中のアプリに反映されないことがあるので、完了するまで常に案内する
            if !progress.inputMonitoringGranted || model.needsRelaunch {
                HStack {
                    Text("許可したら、アプリを開き直すと反映されます。").font(.callout)
                    Spacer()
                    Button("開き直す", action: model.relaunch)
                }
            }
        }
    }

    private var accessibilityStep: some View {
        SetupStepCard(number: 2, title: "アクセシビリティを許可する",
                      detail: "割り当てたキーを送信するために必要です。システム設定の一覧で Remotio をオンにします。",
                      step: .accessibility, progress: progress) {
            Button("許可する", action: model.requestAccessibility)
        } extra: {
            EmptyView()
        }
    }

    private var pairingStep: some View {
        SetupStepCard(number: 3, title: "リモコンをペアリングする",
                      detail: "ホームボタンを約10秒押し続けてペアリング待ちにし、Bluetooth の設定で「Amazon Remote」を接続します。Fire TV とのペアリングは解除される場合があります。接続できない場合は、Fire TV の電源を切ってから試してください。",
                      step: .pairing, progress: progress) {
            Button("Bluetooth 設定を開く", action: model.openBluetoothSettings)
        } extra: {
            EmptyView()
        }
    }

    private var microphoneStep: some View {
        SetupStepCard(number: 4, title: "仮想マイクをインストールする",
                      detail: "他のアプリのマイクとして使うために必要です。管理者パスワードの入力が必要で、処理の間は Mac の音声が一瞬止まります。",
                      step: .microphone, progress: progress) {
            if model.driverBusy {
                ProgressView().controlSize(.small)
            } else {
                Button("インストール", action: model.installDriver)
            }
        } extra: {
            if let error = model.driverError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

private struct SetupStepCard<Action: View, Extra: View>: View {
    let number: Int
    let title: String
    let detail: String
    let step: SetupProgress.Step
    let progress: SetupProgress
    @ViewBuilder var action: Action
    @ViewBuilder var extra: Extra

    var body: some View {
        let done = progress.isDone(step)
        Card(highlighted: progress.currentStep == step) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                        .font(.title2)
                        .foregroundStyle(done ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline)
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if done {
                        Text("完了").foregroundStyle(.green)
                            .accessibilityLabel("\(title): 完了")
                    } else {
                        action
                    }
                }
                extra
            }
        }
    }
}
