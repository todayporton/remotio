import Combine
import Foundation

/// 入力レベルの表示用の状態。音声パケットは毎秒 50 個届くので、設定画面全体を再描画しないよう
/// AppModel から分け、更新も間引く。
public final class MicLevelMeter: ObservableObject {
    @Published public private(set) var position = 0.0
    @Published public private(set) var clipping = false

    private static let publishInterval = 0.05
    private static let clipHold = 1.0
    private var pendingPeak = 0.0
    private var lastPublish = Date.distantPast
    private var lastClip = Date.distantPast
    private var active = false

    public init() {}

    public func update(peak: Double, clipped: Bool) {
        // マイクを止めた後にも残りのパケットが届くので、バーを残さないよう無視する
        guard active else { return }
        let now = Date()
        pendingPeak = max(pendingPeak, peak)
        if clipped { lastClip = now }
        guard now.timeIntervalSince(lastPublish) >= Self.publishInterval else { return }
        position = AudioGain.meterPosition(peak: pendingPeak)
        clipping = now.timeIntervalSince(lastClip) < Self.clipHold
        pendingPeak = 0
        lastPublish = now
    }

    /// マイクの開始と停止のときに呼ぶ。表示は 0 に戻す。
    public func setActive(_ active: Bool) {
        self.active = active
        pendingPeak = 0
        lastPublish = .distantPast
        lastClip = .distantPast
        position = 0
        clipping = false
    }
}
