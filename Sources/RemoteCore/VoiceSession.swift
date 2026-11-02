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

    private var tracker: ButtonTracker
    private var voice: VoiceController
    private var decoder: OpusDecoder

    public init(profile: any RemoteProfile, seize: Bool = false) throws {
        remote = HIDRemote(profile: profile, seize: seize)
        tracker = ButtonTracker(profile: profile)
        voice = VoiceController(voiceButton: profile.voiceButtonName)
        decoder = try OpusDecoder()

        remote.onConnect = { [unowned self] _ in
            if let v = remote.voiceReports {
                onLog?(String(format: "[接続] audio=0x%02X micEnable=0x%02X", v.audioReportID, v.micEnableReportID))
            } else {
                onLog?("[接続] Descriptor から音声 Report を特定できません")
            }
        }
        remote.onDisconnect = { [unowned self] in
            // ボタン解放を受け取れないまま切断された場合に状態を戻す
            tracker = ButtonTracker(profile: remote.profile)
            if voice.micEnabled {
                voice = VoiceController(voiceButton: remote.profile.voiceButtonName)
                onMicChange?(false)
            }
            onLog?("[切断]")
        }
        remote.onReport = { [unowned self] in handle($0) }
    }

    public func start() -> IOReturn { remote.start() }

    public var micEnabled: Bool { voice.micEnabled }

    /// 終了前に呼ぶ。マイクが有効なら停止を送り、完了まで待つ。
    public func shutdown() {
        guard voice.micEnabled else { return }
        remote.setMic(enabled: false) { _ in }
        remote.flushWrites()
    }

    private func handle(_ report: InputReport) {
        onReport?(report)
        if report.reportID == remote.voiceReports?.audioReportID {
            var failed = false
            do { onPCM?(try decoder.decode(report.payload)) } catch {
                failed = true
                onLog?("デコード失敗: \(error)")
            }
            stats.record(timestampNs: report.timestampNs, payload: report.payload, decodeFailed: failed)
            return
        }
        for event in tracker.process(reportID: report.reportID, payload: report.payload) {
            onLog?("\(event.isDown ? "押下" : "解放"): \(event.name)")
            guard let enable = voice.process(event) else { continue }
            if enable {
                if let fresh = try? OpusDecoder() { decoder = fresh }
                stats.beginSession()
            }
            remote.setMic(enabled: enable) { [unowned self] r in
                onLog?("マイク\(enable ? "有効化" : "停止"): \(ioReturnDescription(r))")
            }
            onMicChange?(enable)
            if enable {
                let before = stats.packets
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, voice.micEnabled, stats.packets == before else { return }
                    onLog?("警告: マイク有効化から1.5秒経っても音声 Report が届きません")
                }
            }
        }
    }
}
