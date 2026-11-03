import AppKit
import Foundation

/// 指定秒数後に処理を呼び、取り消し用の関数を返す。テストでは時計を差し替える
public typealias GestureScheduler = (TimeInterval, @escaping () -> Void) -> () -> Void

public enum GestureTiming {
    /// 長押しと判定するまでの時間
    public static let longPress: TimeInterval = 0.5
    /// 1回目を離してから2回目の押下を待つ時間
    public static let doublePress: TimeInterval = 0.3
    /// リピートの間隔。Mac のキーリピートの設定に合わせる
    public static var repeatInterval: TimeInterval { NSEvent.keyRepeatInterval }

    public static let mainQueue: GestureScheduler = { delay, work in
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}

/// 1つのボタンの押し方(タップ、長押し、2回押し)を判定して、キー操作を送る。
/// 長押しも2回押しも割り当てていないボタンには使わない(押した瞬間に送れないため)。
final class GestureRecognizer {
    private let tap: KeyCombo?
    private let gestures: ButtonGestures
    private let schedule: GestureScheduler
    private let repeatInterval: TimeInterval
    private let post: (KeyAction) -> Void

    private enum State {
        case idle
        /// 押している。長押しの判定待ちか、判定済み
        case pressed(longFired: Bool)
        /// 1回目を離して、2回目の押下を待っている
        case waitingSecond
        /// 2回押しを送った後、離すのを待っている
        case secondPressed
    }

    private var state = State.idle
    private var cancelTimer: (() -> Void)?
    private var holding = false

    init(tap: KeyCombo?, gestures: ButtonGestures, schedule: @escaping GestureScheduler,
         repeatInterval: TimeInterval, post: @escaping (KeyAction) -> Void) {
        self.tap = tap
        self.gestures = gestures
        self.schedule = schedule
        self.repeatInterval = repeatInterval
        self.post = post
    }

    func process(isDown: Bool) {
        switch (state, isDown) {
        case (.idle, true):
            state = .pressed(longFired: false)
            if gestures.long != nil {
                startTimer(GestureTiming.longPress) { [weak self] in self?.fireLong() }
            }
        case (.waitingSecond, true):
            stopTimer()
            state = .secondPressed
            gestures.double.map(sendOnce)
        case (.pressed(let longFired), false):
            stopTimer()
            if longFired {
                releaseHold()
                state = .idle
            } else if gestures.double != nil {
                state = .waitingSecond
                startTimer(GestureTiming.doublePress) { [weak self] in
                    self?.state = .idle
                    self?.tap.map { self?.sendOnce($0) }
                }
            } else {
                state = .idle
                tap.map(sendOnce)
            }
        case (.secondPressed, false):
            state = .idle
        default:
            break
        }
    }

    /// 切断時や終了時に呼ぶ。待っている判定を捨て、押したままのキーを離す
    func reset() {
        stopTimer()
        releaseHold()
        state = .idle
    }

    private func fireLong() {
        guard case .pressed = state, let long = gestures.long else { return }
        state = .pressed(longFired: true)
        switch gestures.longMode {
        case .once:
            sendOnce(long)
        case .hold:
            holding = true
            post(KeyAction(combo: long, isDown: true))
        case .repeat:
            sendOnce(long)
            repeatLong(long)
        }
    }

    private func repeatLong(_ combo: KeyCombo) {
        startTimer(repeatInterval) { [weak self] in
            self?.sendOnce(combo)
            self?.repeatLong(combo)
        }
    }

    private func releaseHold() {
        guard holding, let long = gestures.long else { return }
        holding = false
        post(KeyAction(combo: long, isDown: false))
    }

    private func sendOnce(_ combo: KeyCombo) {
        post(KeyAction(combo: combo, isDown: true))
        post(KeyAction(combo: combo, isDown: false))
    }

    private func startTimer(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        stopTimer()
        cancelTimer = schedule(delay, work)
    }

    private func stopTimer() {
        cancelTimer?()
        cancelTimer = nil
    }
}
