import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// メニューから選べる操作の一覧。設定には media:xxx / system:xxx の形で保存する。
public enum ActionCatalog {
    public struct Item: Identifiable, Sendable {
        public let id: String
        public let title: String
    }

    /// メディアキー(NX_KEYTYPE の値)
    static let mediaKeys: [String: (title: String, key: Int32)] = [
        "play_pause": ("再生・停止", 16), "next": ("次へ", 17), "previous": ("前へ", 18),
        "fast_forward": ("早送り", 19), "rewind": ("巻き戻し", 20),
        "volume_up": ("音量を上げる", 0), "volume_down": ("音量を下げる", 1), "mute": ("ミュート", 7),
        "brightness_up": ("画面を明るく", 2), "brightness_down": ("画面を暗く", 3),
    ]

    /// macOS の既定のショートカットで実行する操作
    static let systemActions: [String: (title: String, combo: String)] = [
        "mission_control": ("Mission Control", "ctrl+up"),
        "app_windows": ("アプリケーションウインドウ", "ctrl+down"),
        "space_left": ("左の操作スペース", "ctrl+left"),
        "space_right": ("右の操作スペース", "ctrl+right"),
        "show_desktop": ("デスクトップを表示", "f11"),
        "spotlight": ("Spotlight", "cmd+space"),
        "screenshot": ("スクリーンショット", "shift+cmd+5"),
        "lock_screen": ("画面をロック", "ctrl+cmd+q"),
    ]

    public static let mediaItems: [Item] = [
        "play_pause", "next", "previous", "fast_forward", "rewind",
        "volume_up", "volume_down", "mute", "brightness_up", "brightness_down",
    ].map { Item(id: "media:\($0)", title: mediaKeys[$0]!.title) }

    public static let systemItems: [Item] = [
        "mission_control", "app_windows", "space_left", "space_right",
        "show_desktop", "spotlight", "screenshot", "lock_screen",
    ].map { Item(id: "system:\($0)", title: systemActions[$0]!.title) }

    /// 何もしない(Mac の標準動作も止める)
    public static let disabled = "none"
}

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
    /// メディアキーのとき、その NX_KEYTYPE の値
    public let mediaKey: Int32?
    /// 修飾キー単体のとき、そのキーのフラグ(Push-to-Talk で Fn などを押し続けるために使う)
    public let modifierOnlyFlag: UInt64?

    static let modifierOnlyKeys: [String: (code: CGKeyCode, flag: CGEventFlags)] = [
        "cmd": (55, .maskCommand), "rcmd": (54, .maskCommand),
        "shift": (56, .maskShift), "rshift": (60, .maskShift),
        "opt": (58, .maskAlternate), "alt": (58, .maskAlternate), "ropt": (61, .maskAlternate),
        "ctrl": (59, .maskControl), "rctrl": (62, .maskControl),
        "fn": (63, .maskSecondaryFn),
    ]

    /// 修飾キーを押す順序とキーコード
    static let modifierKeyCodes: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55),
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
        let lowered = text.lowercased()
        if lowered.hasPrefix("system:") {
            guard let action = ActionCatalog.systemActions[String(lowered.dropFirst(7))] else {
                throw KeyMapError.unknownKey(text)
            }
            let resolved = try KeyCombo(action.combo)
            self.init(keyCode: resolved.keyCode, flags: resolved.flags, text: lowered,
                      mediaKey: nil, modifierOnlyFlag: resolved.modifierOnlyFlag)
            return
        }
        if lowered.hasPrefix("media:") {
            guard let media = ActionCatalog.mediaKeys[String(lowered.dropFirst(6))] else {
                throw KeyMapError.unknownKey(text)
            }
            self.init(keyCode: 0, flags: 0, text: lowered, mediaKey: media.key, modifierOnlyFlag: nil)
            return
        }
        var parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.popLast() else { throw KeyMapError.unknownKey(text) }
        var flags: CGEventFlags = []
        for part in parts {
            guard let modifier = Self.modifiers[part] else { throw KeyMapError.unknownKey(text) }
            flags.insert(modifier)
        }
        if parts.isEmpty, let modifier = Self.modifierOnlyKeys[keyName] {
            self.init(keyCode: modifier.code, flags: flags.rawValue, text: lowered,
                      mediaKey: nil, modifierOnlyFlag: modifier.flag.rawValue)
        } else if let code = Self.keys[keyName] {
            self.init(keyCode: code, flags: flags.rawValue, text: lowered, mediaKey: nil, modifierOnlyFlag: nil)
        } else {
            throw KeyMapError.unknownKey(text)
        }
    }

    private init(keyCode: CGKeyCode, flags: UInt64, text: String, mediaKey: Int32?, modifierOnlyFlag: UInt64?) {
        self.keyCode = keyCode
        self.flags = flags
        self.text = text
        self.mediaKey = mediaKey
        self.modifierOnlyFlag = modifierOnlyFlag
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
        let lowered = text.lowercased()
        if lowered == ActionCatalog.disabled { return "無効" }
        if lowered.hasPrefix("media:"), let item = ActionCatalog.mediaKeys[String(lowered.dropFirst(6))] {
            return item.title
        }
        if lowered.hasPrefix("system:"), let item = ActionCatalog.systemActions[String(lowered.dropFirst(7))] {
            return item.title
        }
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

/// ボタン名から操作への割り当て。JSON は {"dpad_up": "up", "mute": "none", "tv": "media:play_pause"} の形式。
/// 指定のないボタンは、Mac の標準動作をそのまま通す。
public struct KeyMap: Sendable {
    public let bindings: [String: KeyCombo]
    /// "none" を指定したボタン(標準動作も止める)
    public let disabledButtons: Set<String>

    public static let defaultBindings = [
        "dpad_up": "up", "dpad_down": "down", "dpad_left": "left", "dpad_right": "right",
        "select": "return", "back": "escape",
    ]

    /// Mac へ届く元のキー入力を止めるボタン
    public var suppressedButtons: [String] { Array(bindings.keys) + Array(disabledButtons) }

    public init(_ bindings: [String: String]) throws {
        disabledButtons = Set(bindings.filter { $0.value.lowercased() == ActionCatalog.disabled }.keys)
        self.bindings = try bindings
            .filter { $0.value.lowercased() != ActionCatalog.disabled }
            .mapValues { try KeyCombo($0) }
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

/// 送信するキーイベント 1 つ分
public struct InjectedKeyEvent: Equatable, Sendable {
    public enum Kind: Sendable { case keyDown, keyUp, flagsChanged }
    public let kind: Kind
    public let keyCode: CGKeyCode
    public let flags: UInt64
}

public extension KeyAction {
    /// 実際のキーボードと同じ順序のイベント列を返す。
    /// キーの状態を flagsChanged で追跡するアプリがあるため、修飾キーも個別のイベントとして送る。
    /// 例: ctrl+t の押下は ctrl(flagsChanged) → t(keyDown)、解放は t(keyUp) → ctrl(flagsChanged)。
    var events: [InjectedKeyEvent] {
        if combo.mediaKey != nil { return [] }
        if let flag = combo.modifierOnlyFlag {
            return [InjectedKeyEvent(kind: .flagsChanged, keyCode: combo.keyCode, flags: isDown ? flag : 0)]
        }
        // 順に押した状態を積み上げる
        var held: UInt64 = 0
        var modifierDowns: [InjectedKeyEvent] = []
        var modifierUps: [InjectedKeyEvent] = []
        for (flag, keyCode) in KeyCombo.modifierKeyCodes where combo.flags & flag.rawValue != 0 {
            let before = held
            held |= flag.rawValue
            modifierDowns.append(InjectedKeyEvent(kind: .flagsChanged, keyCode: keyCode, flags: held))
            modifierUps.insert(InjectedKeyEvent(kind: .flagsChanged, keyCode: keyCode, flags: before), at: 0)
        }
        if isDown {
            return modifierDowns + [InjectedKeyEvent(kind: .keyDown, keyCode: combo.keyCode, flags: held)]
        }
        return [InjectedKeyEvent(kind: .keyUp, keyCode: combo.keyCode, flags: held)] + modifierUps
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

    /// CGEventSource.keyState(.hidSystemState) で押下中と判定されるよう、HID の状態を持つソースから送る
    private static let source = CGEventSource(stateID: .hidSystemState)

    /// イベントの間隔。修飾キーの直後に通常キーを送ると、システムの修飾キーの状態が更新される前に
    /// 届き、状態を確認し直すアプリ(Amical など)で修飾キーが押されていないと判定されることがある。
    private static let eventInterval: useconds_t = 40_000

    private static let queue = DispatchQueue(label: "remotio.key-injector", qos: .userInteractive)

    /// キューに積んで順に送る。呼び出し元(main スレッド)を待たせない。
    public static func post(_ action: KeyAction) {
        let events = action.events
        let mediaKey = action.combo.mediaKey
        let isDown = action.isDown
        queue.async {
            if let mediaKey { postMediaKey(mediaKey, isDown: isDown) }
            for (index, item) in events.enumerated() {
                if index > 0 { usleep(eventInterval) }
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: item.keyCode,
                                          keyDown: item.kind == .keyDown) else { continue }
                if item.kind == .flagsChanged { event.type = .flagsChanged }
                event.flags = CGEventFlags(rawValue: item.flags)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// メディアキーはキーボードイベントではなく、システム定義のイベントとして送る
    private static func postMediaKey(_ key: Int32, isDown: Bool) {
        let state = isDown ? 0xA : 0xB
        let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
            timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
            data1: Int(key) << 16 | state << 8, data2: -1)
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    /// 終了前に呼ぶ。キューに残ったキー操作を送り終えるまで待つ。
    public static func flush() { queue.sync {} }
}
