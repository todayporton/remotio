import Foundation

public struct VoiceReports: Equatable, Sendable {
    public let audioReportID: UInt8
    public let micEnableReportID: UInt8
    public let audioPayloadBytes: Int
}

public struct ButtonEvent: Equatable, Sendable {
    public let name: String
    public let isDown: Bool
}

/// リモコン機種ごとの差分。別機種へ対応するときはこの protocol を実装する。
public protocol RemoteProfile: Sendable {
    var displayName: String { get }
    var vendorID: Int { get }
    /// 同じボタン配置と音声の送り方を持つ製品の ID(互換品を含む)
    var productIDs: [Int] { get }
    /// 製品 ID ごとの表示名。なければ nil(デバイスが名乗る名前を使う)
    func modelName(productID: Int) -> String?
    var voiceButtonName: String { get }
    /// Descriptor から音声・マイク制御の Report を特定する。不明なら nil。
    func voiceReports(in reports: [HIDReportInfo]) -> VoiceReports?
    /// Report の payload(Report ID を除く)から、現在押されているボタン名を返す。
    /// ボタン用 Report でなければ nil。
    func pressedButtons(reportID: UInt8, payload: [UInt8]) -> Set<String>?
    /// ボタンが Mac へ送る HID usage(上位 32bit が usage page)。不明なら nil。
    func systemUsage(of button: String) -> UInt64?
    /// ボタンの標準動作の名前。動作を確認できていないものは nil。
    func standardActionName(of button: String) -> String?
    /// 標準動作と同じ操作を Remotio から送るときの設定(例: "media:mute")。元のキー入力を止めて
    /// 押し方を判定するボタンで、タップを「標準」のままにしたときに使う。なければ nil。
    func standardKey(of button: String) -> String?
    /// 押している間を報告するボタンか。押下と解放をまとめて送るボタンは長押しも2回押しも判定できない
    func reportsHold(of button: String) -> Bool
    /// 設定画面でボタン名の横に出す注意書き。なければ nil
    func note(of button: String) -> String?
}

/// Fire TV Stick 4K 付属リモコン。コード表は fire-remote-client (MIT) の調査結果に基づく。
public struct FireTVRemoteProfile: RemoteProfile {
    public init() {}

    public let displayName = "Amazon Remote"
    public let vendorID = 0x0171
    /// 0x042F は Fire TV Stick 4K 付属リモコン、0x0425 は Amazon Remote Pro の互換品(実機で確認)。
    /// どちらも Report Descriptor が同じ
    public let productIDs = [0x042F, 0x0425]

    public func modelName(productID: Int) -> String? {
        switch productID {
        case 0x042F: return "Amazon Remote"
        case 0x0425: return "Amazon Remote Pro"
        default: return nil
        }
    }
    public let voiceButtonName = "voice"

    static let keyboard: [UInt16: String] = [
        0x4F: "dpad_right", 0x50: "dpad_left", 0x51: "dpad_down", 0x52: "dpad_up",
        0x58: "select", 0x28: "select", 0xF1: "back", 0x66: "power",
    ]
    static let consumer: [UInt16: String] = [
        0x0221: "voice", 0x0223: "home", 0x0224: "back", 0x0040: "menu", 0x00E2: "mute",
        0x00E9: "volume_up", 0x00EA: "volume_down", 0x00CD: "play_pause",
        0x00B4: "rewind", 0x00B3: "fast_forward", 0x008D: "tv",
        // Amazon Remote Pro だけにあるボタン(互換品で確認)
        0x0280: "headphones", 0x0033: "settings", 0x009C: "channel_up", 0x009D: "channel_down",
        0x027E: "custom_1", 0x027F: "custom_2",
    ]
    static let apps: [UInt16: String] = [
        0xA1: "app_a1", 0xA2: "app_a2", 0xA3: "app_a3", 0xA4: "app_a4",
    ]

    /// 音声 = 最大の Input、マイク制御 = 最小の Output(参考実装と同じ判定)。
    public func voiceReports(in reports: [HIDReportInfo]) -> VoiceReports? {
        guard let audio = reports.filter({ $0.inputBytes > 0 }).max(by: { $0.inputBytes < $1.inputBytes }),
              let enable = reports.filter({ $0.outputBytes > 0 }).min(by: { $0.outputBytes < $1.outputBytes })
        else { return nil }
        return VoiceReports(audioReportID: audio.id, micEnableReportID: enable.id,
                            audioPayloadBytes: audio.inputBytes)
    }

    public func pressedButtons(reportID: UInt8, payload: [UInt8]) -> Set<String>? {
        switch reportID {
        case 0x01:
            return names(payload.map(UInt16.init), Self.keyboard, prefix: "kbd")
        case 0x02:
            var usages: [UInt16] = []
            var i = 0
            while i + 1 < payload.count {
                usages.append(UInt16(payload[i]) | UInt16(payload[i + 1]) << 8)
                i += 2
            }
            return names(usages, Self.consumer, prefix: "consumer")
        case 0xEF:
            return names(payload.prefix(1).map(UInt16.init), Self.apps, prefix: "app")
        default:
            return nil
        }
    }

    public func standardActionName(of button: String) -> String? {
        [
            "dpad_up": "↑", "dpad_down": "↓", "dpad_left": "←", "dpad_right": "→",
            "select": "Enter", "play_pause": String(localized: "再生・停止"), "rewind": String(localized: "巻き戻し"), "fast_forward": String(localized: "早送り"),
            "volume_up": String(localized: "音量を上げる"), "volume_down": String(localized: "音量を下げる"), "mute": String(localized: "ミュート"),
        ][button]
    }

    public func standardKey(of button: String) -> String? {
        [
            "dpad_up": "up", "dpad_down": "down", "dpad_left": "left", "dpad_right": "right", "select": "return",
            "play_pause": "media:play_pause", "rewind": "media:rewind", "fast_forward": "media:fast_forward",
            "volume_up": "media:volume_up", "volume_down": "media:volume_down", "mute": "media:mute",
        ][button]
    }

    /// 電源ボタンは押してから約1秒後に押下と解放をまとめて送る(実機で確認)
    public func reportsHold(of button: String) -> Bool { button != "power" }

    public func note(of button: String) -> String? {
        button == "power" ? String(localized: "約1秒遅れて反応します") : nil
    }

    public func systemUsage(of button: String) -> UInt64? {
        if let code = Self.keyboard.first(where: { $0.value == button && $0.key != 0x28 })?.key {
            return 0x7_0000_0000 | UInt64(code)
        }
        if let code = Self.consumer.first(where: { $0.value == button && $0.key != 0x0224 })?.key {
            return 0xC_0000_0000 | UInt64(code)
        }
        return nil
    }

    private func names(_ codes: [UInt16], _ table: [UInt16: String], prefix: String) -> Set<String> {
        Set(codes.filter { $0 != 0 }.map { table[$0] ?? String(format: "%@_0x%04x", prefix, $0) })
    }
}

/// Report を押下・解放イベントへ変換する。
public struct ButtonTracker {
    private let profile: any RemoteProfile
    private var pressed: [UInt8: Set<String>] = [:]

    public init(profile: any RemoteProfile) { self.profile = profile }

    /// 押されたままのボタンをすべて解放したことにする(切断時に使う)
    public mutating func releaseAll() -> [ButtonEvent] {
        let names = pressed.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        pressed = [:]
        return names.sorted().map { ButtonEvent(name: $0, isDown: false) }
    }

    public mutating func process(reportID: UInt8, payload: [UInt8]) -> [ButtonEvent] {
        guard let now = profile.pressedButtons(reportID: reportID, payload: payload) else { return [] }
        let before = pressed[reportID] ?? []
        pressed[reportID] = now
        return before.subtracting(now).sorted().map { ButtonEvent(name: $0, isDown: false) }
            + now.subtracting(before).sorted().map { ButtonEvent(name: $0, isDown: true) }
    }
}

/// 音声ボタンの押下・解放からマイク制御を決める。マイクは押下を受けてからでないと有効にならない。
public struct VoiceController {
    public private(set) var micEnabled = false
    private let voiceButton: String

    public init(voiceButton: String) { self.voiceButton = voiceButton }

    /// 送るべきマイク状態を返す。変更不要なら nil。
    public mutating func process(_ event: ButtonEvent) -> Bool? {
        guard event.name == voiceButton, event.isDown != micEnabled else { return nil }
        micEnabled = event.isDown
        return micEnabled
    }
}

/// macOS の Report バッファ先頭に Report ID が含まれる場合だけ取り除く。
public func stripReportID(_ reportID: UInt8, from bytes: [UInt8], expectedPayload: Int?) -> [UInt8] {
    guard bytes.first == reportID else { return bytes }
    if let expectedPayload, bytes.count == expectedPayload { return bytes }
    return Array(bytes.dropFirst())
}
