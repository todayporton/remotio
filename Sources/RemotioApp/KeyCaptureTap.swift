import CoreGraphics
import Foundation

/// キー割り当ての待ち受け中だけ、キー入力を他のアプリより先に受け取り、後ろへ送らない。
/// イベント経路の先頭に入るので、他のアプリのショートカットが先に動くことを防げる。
/// 有効にするにはアクセシビリティの権限が必要。
final class KeyCaptureTap {
    /// 種類、キーコード、修飾フラグを main スレッドで受け取る
    private let handler: (CGEventType, CGKeyCode, CGEventFlags) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(handler: @escaping (CGEventType, CGKeyCode, CGEventFlags) -> Void) {
        self.handler = handler
    }

    deinit { stop() }

    /// 開始できたら true。権限がなければ false。
    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let me = Unmanaged<KeyCaptureTap>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type, event)
            },
            userInfo: context
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // 処理の遅延などで無効にされたら、待ち受けを続けるために戻す
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        DispatchQueue.main.async { [weak self] in self?.handler(type, keyCode, flags) }
        return nil
    }
}
