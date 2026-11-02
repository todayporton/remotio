import AppKit
import CoreGraphics
import Foundation

/// キー割り当ての待ち受け中だけ、キー入力を他のアプリより先に受け取り、後ろへ送らない。
/// HID 段階のタップの先頭に入るので、他のアプリのショートカットが先に動くことを防げる。
/// 有効にするにはアクセシビリティの権限が必要。
final class KeyCaptureTap {
    /// 種類、キーコード、修飾フラグを main スレッドで受け取る
    private let handler: (CGEventType, CGKeyCode, CGEventFlags) -> Void
    /// 明るさや音量などの特殊キー(NX_KEYTYPE)の押下を main スレッドで受け取る
    private let systemKeyHandler: (Int32, CGEventFlags) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// NX_SYSDEFINED。CGEventType に定義がない
    private static let systemDefinedType: UInt32 = 14
    /// NSEvent の特殊キーのサブタイプ。他のサブタイプはマウスのボタンなどなので素通しする
    private static let systemKeySubtype: Int16 = 8

    init(handler: @escaping (CGEventType, CGKeyCode, CGEventFlags) -> Void,
         systemKeyHandler: @escaping (Int32, CGEventFlags) -> Void) {
        self.handler = handler
        self.systemKeyHandler = systemKeyHandler
    }

    deinit { stop() }

    /// 開始できたら true。権限がなければ false。
    func start() -> Bool {
        guard let tap = makeTap(at: .cghidEventTap) ?? makeTap(at: .cgSessionEventTap) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    private func makeTap(at location: CGEventTapLocation) -> CFMachPort? {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << Self.systemDefinedType)
        return CGEvent.tapCreate(
            tap: location, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let me = Unmanaged<KeyCaptureTap>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
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
        if type.rawValue == Self.systemDefinedType {
            guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == Self.systemKeySubtype else {
                return Unmanaged.passUnretained(event)
            }
            let key = Int32((ns.data1 & 0xFFFF_0000) >> 16)
            let isDown = (ns.data1 & 0xFF00) >> 8 == 0x0A
            let flags = event.flags
            if isDown {
                DispatchQueue.main.async { [weak self] in self?.systemKeyHandler(key, flags) }
            }
            return nil
        }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        DispatchQueue.main.async { [weak self] in self?.handler(type, keyCode, flags) }
        return nil
    }
}
