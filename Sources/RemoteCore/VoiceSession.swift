import Foundation
import IOKit

/// ボタン監視、音声ボタンとマイクの連動、Opus デコードをまとめて扱う。
public final class VoiceSession {
    public let remote: HIDRemote
    public private(set) var stats = AudioStats()

    public var onLog: ((String) -> Void)?
    public var onReport: ((InputReport) -> Void)?
    public var onPCM: (([Int16]) -> Void)?
    /// マイク状態の変更時に呼ばれる(true = 発話開始)
    public var onMicChange: ((Bool) -> Void)?
    /// ボタンの押下・解放と、押したリモコン(HIDRemote.Remote.id)
    public var onButton: ((ButtonEvent, UInt64) -> Void)?
    public var onDisconnect: ((HIDRemote.Remote) -> Void)?

    /// リモコンごとのボタンの状態
    private var trackers: [UInt64: ButtonTracker] = [:]
    /// 今マイクを使っているリモコン。同時に話せるのは1台だけ
    public private(set) var micOwner: UInt64?
    private var decoder: OpusDecoder
    private let voiceButton: String

    public init(profile: any RemoteProfile, seize: Bool = false) throws {
        remote = HIDRemote(profile: profile, seize: seize)
        voiceButton = profile.voiceButtonName
        decoder = try OpusDecoder()

        remote.onConnect = { [unowned self] r in
            if let v = r.voiceReports {
                onLog?(String(localized: "[接続] \(r.name) audio=\(String(format: "0x%02X", v.audioReportID)) micEnable=\(String(format: "0x%02X", v.micEnableReportID))"))
            } else {
                onLog?(String(localized: "[接続] \(r.name) Descriptor から音声 Report を特定できません"))
            }
        }
        remote.onDisconnect = { [unowned self] r in
            // ボタン解放を受け取れないまま切断された場合に、押されたままのボタンを離したことにする
            if var tracker = trackers.removeValue(forKey: r.id) {
                for event in tracker.releaseAll() { dispatch(event, from: r.id, connected: false) }
            }
            onLog?(String(localized: "[切断] \(r.name)"))
            onDisconnect?(r)
        }
        remote.onReport = { [unowned self] in handle($0) }
    }

    public func start() -> IOReturn { remote.start() }

    public var micEnabled: Bool { micOwner != nil }

    /// 終了前に呼ぶ。マイクが有効なら停止を送り、完了まで待つ。
    public func shutdown() {
        guard let micOwner else { return }
        remote.setMic(micOwner, enabled: false) { _ in }
        remote.flushWrites()
    }

    private func handle(_ report: InputReport) {
        onReport?(report)
        if report.reportID == remote.remotes[report.remoteID]?.voiceReports?.audioReportID {
            // マイクを使っているリモコン以外の音声は使わない
            guard report.remoteID == micOwner else { return }
            var failed = false
            do { onPCM?(try decoder.decode(report.payload)) } catch {
                failed = true
                onLog?(String(localized: "デコード失敗: \(String(describing: error))"))
            }
            stats.record(timestampNs: report.timestampNs, payload: report.payload, decodeFailed: failed)
            return
        }
        var tracker = trackers[report.remoteID] ?? ButtonTracker(profile: remote.profile)
        let events = tracker.process(reportID: report.reportID, payload: report.payload)
        trackers[report.remoteID] = tracker
        for event in events { dispatch(event, from: report.remoteID, connected: true) }
    }

    private func dispatch(_ event: ButtonEvent, from remoteID: UInt64, connected: Bool) {
        onLog?(event.isDown ? String(localized: "押下: \(event.name)") : String(localized: "解放: \(event.name)"))
        guard event.name == voiceButton else {
            onButton?(event, remoteID)
            return
        }
        // 音声ボタンは、マイクを使っているリモコンのものだけを扱う。2台目が話し始めても割り込まない
        if event.isDown {
            guard micOwner == nil else {
                onLog?(String(localized: "別のリモコンが話しているため、音声ボタンを無視しました"))
                return
            }
            micOwner = remoteID
        } else {
            guard micOwner == remoteID else { return }
            micOwner = nil
        }
        onButton?(event, remoteID)
        let enable = event.isDown
        if enable {
            if let fresh = try? OpusDecoder() { decoder = fresh }
            stats.beginSession()
        }
        if connected {
            remote.setMic(remoteID, enabled: enable) { [unowned self] r in
                onLog?(enable ? String(localized: "マイク有効化: \(ioReturnDescription(r))") : String(localized: "マイク停止: \(ioReturnDescription(r))"))
            }
        }
        onMicChange?(enable)
        if enable {
            let before = stats.packets
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, micOwner == remoteID, stats.packets == before else { return }
                onLog?(String(localized: "警告: マイク有効化から1.5秒経っても音声 Report が届きません"))
            }
        }
    }
}
