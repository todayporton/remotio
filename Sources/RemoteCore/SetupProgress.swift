/// 初回セットアップの進み具合
public struct SetupProgress: Equatable {
    public enum Step: CaseIterable, Equatable {
        case inputMonitoring, accessibility, pairing, microphone
    }

    public var inputMonitoringGranted: Bool
    public var accessibilityGranted: Bool
    public var remoteConnected: Bool
    /// 仮想マイクが使える、または他の出力デバイスを使う設定になっている
    public var microphoneReady: Bool

    public init(inputMonitoringGranted: Bool, accessibilityGranted: Bool,
                remoteConnected: Bool, microphoneReady: Bool) {
        self.inputMonitoringGranted = inputMonitoringGranted
        self.accessibilityGranted = accessibilityGranted
        self.remoteConnected = remoteConnected
        self.microphoneReady = microphoneReady
    }

    public func isDone(_ step: Step) -> Bool {
        switch step {
        case .inputMonitoring: return inputMonitoringGranted
        case .accessibility: return accessibilityGranted
        case .pairing: return remoteConnected
        case .microphone: return microphoneReady
        }
    }

    /// 次に行う手順。すべて終わっていれば nil。
    public var currentStep: Step? { Step.allCases.first { !isDone($0) } }

    /// 起動時に案内を自動で開くか。リモコンはスリープ中だと未接続に見えるので、判定に含めない。
    public func shouldOpenAutomatically(dismissed: Bool) -> Bool {
        !dismissed && !(inputMonitoringGranted && accessibilityGranted && microphoneReady)
    }
}
