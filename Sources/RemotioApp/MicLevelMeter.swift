import Foundation
import RemoteCore

/// 入力レベルの表示用の状態。音声パケットは毎秒 50 個届くので、設定画面全体を再描画しないよう
/// AppModel から分け、更新も間引く。
final class MicLevelMeter: ObservableObject {
    @Published private(set) var position = 0.0
    @Published private(set) var clipping = false

    private static let publishInterval = 0.05
    private static let clipHold = 1.0
    private var pendingPeak = 0.0
    private var lastPublish = Date.distantPast
    private var lastClip = Date.distantPast

    func update(peak: Double, clipped: Bool) {
        let now = Date()
        pendingPeak = max(pendingPeak, peak)
        if clipped { lastClip = now }
        guard now.timeIntervalSince(lastPublish) >= Self.publishInterval else { return }
        position = AudioGain.meterPosition(peak: pendingPeak)
        clipping = now.timeIntervalSince(lastClip) < Self.clipHold
        pendingPeak = 0
        lastPublish = now
    }

    func reset() {
        pendingPeak = 0
        lastClip = .distantPast
        position = 0
        clipping = false
    }
}
