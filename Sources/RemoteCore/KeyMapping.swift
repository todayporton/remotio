import ApplicationServices
import CoreGraphics
import Foundation

public enum KeyMapError: Error, CustomStringConvertible, Equatable {
    case unknownKey(String), voiceReserved
    public var description: String {
        switch self {
        case .unknownKey(let k): return "不明なキー指定: \(k)"
        case .voiceReserved: return "音声ボタンは Push-to-Talk 専用のため割り当てできません"
        }
    }
}

/// "cmd+shift+a" 形式のキーの組み合わせ。
public struct KeyCombo: Equatable, Sendable {
    public let keyCode: CGKeyCode
    public let flags: UInt64
    public let text: String

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
        guard let keyName = parts.popLast(), let code = Self.keys[keyName] else {
            throw KeyMapError.unknownKey(text)
        }
        var flags: CGEventFlags = []
        for part in parts {
            guard let modifier = Self.modifiers[part] else { throw KeyMapError.unknownKey(text) }
            flags.insert(modifier)
        }
        keyCode = code
        self.flags = flags.rawValue
        self.text = text
    }
}

/// ボタン名からキーへの割り当て。JSON は {"dpad_up": "up", "play_pause": "cmd+shift+p"} の形式。
public struct KeyMap: Sendable {
    public let bindings: [String: KeyCombo]

    public static let defaultBindings = [
        "dpad_up": "up", "dpad_down": "down", "dpad_left": "left", "dpad_right": "right",
        "select": "return", "back": "escape", "play_pause": "space",
    ]

    public init(_ bindings: [String: String], voiceButton: String) throws {
        guard bindings[voiceButton] == nil else { throw KeyMapError.voiceReserved }
        self.bindings = try bindings.mapValues { try KeyCombo($0) }
    }

    public static func load(url: URL, voiceButton: String) throws -> KeyMap {
        try KeyMap(try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url)), voiceButton: voiceButton)
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

public enum KeyInjector {
    /// キー送信に必要なアクセシビリティ権限の有無
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    public static func post(_ action: KeyAction) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: action.combo.keyCode, keyDown: action.isDown)
        else { return }
        event.flags = CGEventFlags(rawValue: action.combo.flags)
        event.post(tap: .cghidEventTap)
    }
}
