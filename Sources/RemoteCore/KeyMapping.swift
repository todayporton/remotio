import ApplicationServices
import CoreGraphics
import Foundation

public enum KeyMapError: Error, CustomStringConvertible, Equatable {
    case unknownKey(String)
    public var description: String {
        switch self {
        case .unknownKey(let k): return "不明なキー指定: \(k)"
        }
    }
}

/// "cmd+shift+a" 形式のキーの組み合わせ。
public struct KeyCombo: Equatable, Sendable {
    public let keyCode: CGKeyCode
    public let flags: UInt64
    public let text: String
    /// 修飾キー単体のとき、そのキーのフラグ(Push-to-Talk で Fn などを押し続けるために使う)
    public let modifierOnlyFlag: UInt64?

    static let modifierOnlyKeys: [String: (code: CGKeyCode, flag: CGEventFlags)] = [
        "cmd": (55, .maskCommand), "rcmd": (54, .maskCommand),
        "shift": (56, .maskShift), "rshift": (60, .maskShift),
        "opt": (58, .maskAlternate), "alt": (58, .maskAlternate), "ropt": (61, .maskAlternate),
        "ctrl": (59, .maskControl), "rctrl": (62, .maskControl),
        "fn": (63, .maskSecondaryFn),
    ]

    static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "shift": .maskShift, "opt": .maskAlternate, "alt": .maskAlternate, "ctrl": .maskControl,
    ]

    // macOS の仮想キーコード(US 配列の物理位置)
    static let keys: [String: CGKeyCode] = {
        var k: [String: CGKeyCode] = [
            "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "esc": 53,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
            "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
            "-": 27, "=": 24, "[": 33, "]": 30, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "\\": 42, "`": 50,
        ]
        let letters: [(String, CGKeyCode)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
            ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("o", 31), ("u", 32),
            ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("k", 40), ("n", 45), ("m", 46),
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("9", 25), ("7", 26), ("8", 28), ("0", 29),
        ]
        for (name, code) in letters { k[name] = code }
        return k
    }()

    public init(_ text: String) throws {
        var parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.popLast() else { throw KeyMapError.unknownKey(text) }
        var flags: CGEventFlags = []
        for part in parts {
            guard let modifier = Self.modifiers[part] else { throw KeyMapError.unknownKey(text) }
            flags.insert(modifier)
        }
        if parts.isEmpty, let modifier = Self.modifierOnlyKeys[keyName] {
            keyCode = modifier.code
            modifierOnlyFlag = modifier.flag.rawValue
        } else if let code = Self.keys[keyName] {
            keyCode = code
            modifierOnlyFlag = nil
        } else {
            throw KeyMapError.unknownKey(text)
        }
        self.flags = flags.rawValue
        self.text = text.lowercased()
    }

    /// 物理キーのキーコードと修飾フラグから、設定用の文字列を作る(キー入力の記録に使う)。
    public static func recordedText(keyCode: CGKeyCode, flags: CGEventFlags) -> String? {
        let preferred = keys.filter { $0.value == keyCode && $0.key != "enter" && $0.key != "esc" }.keys.sorted().first
        guard let name = preferred else { return nil }
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskAlternate) { parts.append("opt") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskCommand) { parts.append("cmd") }
        return (parts + [name]).joined(separator: "+")
    }

    /// 修飾キー単体を記録するときの文字列
    public static func recordedModifierText(keyCode: CGKeyCode) -> String? {
        modifierOnlyKeys.filter { $0.value.code == keyCode && $0.key != "alt" }.keys.sorted().first
    }

    /// 画面表示用の文字列(例: cmd+shift+p → ⌘⇧P)
    public static func displayText(_ text: String) -> String {
        let symbols = [
            "cmd": "⌘", "shift": "⇧", "opt": "⌥", "alt": "⌥", "ctrl": "⌃", "fn": "fn",
            "rcmd": "右⌘", "rshift": "右⇧", "ropt": "右⌥", "rctrl": "右⌃",
            "return": "↩", "enter": "↩", "escape": "⎋", "esc": "⎋", "tab": "⇥", "space": "Space", "delete": "⌫",
            "up": "↑", "down": "↓", "left": "←", "right": "→",
        ]
        return text.lowercased().split(separator: "+")
            .map { symbols[String($0)] ?? String($0).uppercased() }
            .joined()
    }
}

/// ボタン名からキーへの割り当て。JSON は {"dpad_up": "up", "play_pause": "cmd+shift+p"} の形式。
public struct KeyMap: Sendable {
    public let bindings: [String: KeyCombo]

    public static let defaultBindings = [
        "dpad_up": "up", "dpad_down": "down", "dpad_left": "left", "dpad_right": "right",
        "select": "return", "back": "escape", "play_pause": "space",
    ]

    public init(_ bindings: [String: String]) throws {
        self.bindings = try bindings.mapValues { try KeyCombo($0) }
    }

    public static func load(url: URL) throws -> KeyMap {
        try KeyMap(try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url)))
    }
}

public struct KeyAction: Equatable, Sendable {
    public let combo: KeyCombo
    public let isDown: Bool

    public init(combo: KeyCombo, isDown: Bool) {
        self.combo = combo
        self.isDown = isDown
    }
}

/// ボタンイベントをキー操作へ変換する。押しっぱなしのまま残らないよう押下中のキーを覚える。
public struct KeyMapper {
    private let map: KeyMap
    private var held: [String: KeyCombo] = [:]

    public init(map: KeyMap) { self.map = map }

    public mutating func process(_ event: ButtonEvent) -> KeyAction? {
        if event.isDown {
            guard held[event.name] == nil, let combo = map.bindings[event.name] else { return nil }
            held[event.name] = combo
            return KeyAction(combo: combo, isDown: true)
        }
        return held.removeValue(forKey: event.name).map { KeyAction(combo: $0, isDown: false) }
    }

    /// 切断時や終了時に呼ぶ。押下中のキーをすべて解放する。
    public mutating func releaseAll() -> [KeyAction] {
        defer { held.removeAll() }
        return held.values.map { KeyAction(combo: $0, isDown: false) }
    }
}

/// ボタンイベントをキー送信へつなぐ。
/// 音声ボタンのキー解放だけは少し遅らせ、話し終わりの音声が届く前に Push-to-Talk が切れないようにする。
public final class ButtonKeyRouter {
    private var mapper: KeyMapper
    private let voiceButton: String
    private let voiceReleaseDelay: TimeInterval
    private let post: (KeyAction) -> Void
    private var pending: (work: DispatchWorkItem, action: KeyAction)?

    /// voiceReleaseDelay の既定値は出力前の待機(60ms)と到着のゆらぎ(実測で最大約43ms)の合計に余裕を持たせた値。
    public init(map: KeyMap, voiceButton: String, voiceReleaseDelay: TimeInterval = 0.12,
                post: @escaping (KeyAction) -> Void) {
        mapper = KeyMapper(map: map)
        self.voiceButton = voiceButton
        self.voiceReleaseDelay = voiceReleaseDelay
        self.post = post
    }

    public func process(_ event: ButtonEvent) {
        if event.isDown { flushPending() }
        guard let action = mapper.process(event) else { return }
        if event.name == voiceButton && !event.isDown {
            let work = DispatchWorkItem { [weak self] in self?.flushPending() }
            pending = (work, action)
            DispatchQueue.main.asyncAfter(deadline: .now() + voiceReleaseDelay, execute: work)
        } else {
            post(action)
        }
    }

    /// 切断時や終了時に呼ぶ。押下中のキーをすべて解放する。
    public func releaseAll() {
        flushPending()
        mapper.releaseAll().forEach(post)
    }

    private func flushPending() {
        guard let pending else { return }
        self.pending = nil
        pending.work.cancel()
        post(pending.action)
    }
}

public enum KeyInjector {
    /// キー送信に必要なアクセシビリティ権限の有無
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// システムの許可ダイアログを表示する
    public static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static func post(_ action: KeyAction) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: action.combo.keyCode, keyDown: action.isDown)
        else { return }
        if let flag = action.combo.modifierOnlyFlag {
            event.type = .flagsChanged
            event.flags = action.isDown ? CGEventFlags(rawValue: flag) : []
        } else {
            event.flags = CGEventFlags(rawValue: action.combo.flags)
        }
        event.post(tap: .cghidEventTap)
    }
}
