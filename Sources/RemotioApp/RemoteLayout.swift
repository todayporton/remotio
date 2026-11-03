import CoreGraphics
import Foundation

/// リモコン図の1ボタン
struct RemoteButton: Identifiable {
    enum Shape: Equatable {
        case round, arrow, select, voice
        /// 縦長のボタン(音量やチャンネル)の上半分か下半分
        case rocker
        /// 記号ではなく文字を描く丸いボタン(Pro のカスタムボタン)
        case text
        /// アプリボタン(横長。割り当てるサービスは地域で違うので、番号だけ描く)
        case app
    }

    let id: String
    let title: String
    let symbol: String
    /// リモコン図の中の中心の位置(x は幅、y は高さに対する割合)
    let position: CGPoint
    /// 大きさ(幅も高さもリモコン図の幅に対する割合)
    let size: CGSize
    var shape: Shape = .round
    /// 図に描く記号か文字(一覧と違うときだけ)
    var glyph: String?
}

/// 機種ごとのリモコン図。位置は実機の写真から測った値
struct RemoteLayout {
    let left: [RemoteButton]
    let right: [RemoteButton]
    /// 幅 ÷ 高さ
    let aspect: CGFloat
    /// 方向ボタンのリングの中心(割合)と直径(幅に対する割合)
    let ringCenter: CGPoint
    let ringDiameter: CGFloat
    /// 縦長ボタンの土台。中心は割合、大きさは幅に対する割合
    let rockers: [(center: CGPoint, size: CGSize)]

    var all: [RemoteButton] { left + right }

    static func of(productID: Int?) -> RemoteLayout {
        productID == 0x0425 ? pro : standard
    }

    /// どの機種にもあるボタンを含む、すべてのボタン名
    static let allButtonIDs: Set<String> = Set((standard.all + pro.all).map(\.id))

    // MARK: 部品

    private static func button(_ id: String, _ title: String, _ symbol: String, _ x: CGFloat, _ y: CGFloat,
                               size: CGFloat = 0.23, shape: RemoteButton.Shape = .round,
                               glyph: String? = nil) -> RemoteButton {
        RemoteButton(id: id, title: title, symbol: symbol, position: .init(x: x, y: y),
                     size: .init(width: size, height: size), shape: shape, glyph: glyph)
    }

    private static func app(_ number: Int, _ x: CGFloat, _ y: CGFloat, width: CGFloat, height: CGFloat) -> RemoteButton {
        RemoteButton(id: "app_a\(number)", title: String(localized: "アプリ \(number)"), symbol: "\(number).circle",
                     position: .init(x: x, y: y), size: .init(width: width, height: height), shape: .app,
                     glyph: "\(number)")
    }

    private static let powerTitle = String(localized: "電源")
    private static let voiceTitle = String(localized: "音声(Push-to-Talk)")

    // MARK: Fire TV Stick 4K 付属リモコン(第3世代)

    static let standard = RemoteLayout(
        left: [
            button("power", powerTitle, "power", 0.15, 0.048, size: 0.15),
            button("voice", voiceTitle, "mic.fill", 0.5, 0.108, size: 0.24, shape: .voice),
            button("dpad_up", String(localized: "上"), "chevron.up", 0.5, 0.18, size: 0.16, shape: .arrow),
            button("dpad_left", String(localized: "左"), "chevron.left", 0.2, 0.258, size: 0.16, shape: .arrow),
            button("back", String(localized: "戻る"), "arrow.uturn.backward", 0.19, 0.42),
            button("rewind", String(localized: "巻き戻し"), "backward.fill", 0.19, 0.49),
            button("volume_up", String(localized: "音量 +"), "speaker.plus", 0.5, 0.578, shape: .rocker, glyph: "plus"),
            button("mute", String(localized: "ミュート"), "speaker.slash", 0.19, 0.575),
            app(1, 0.29, 0.712, width: 0.37, height: 0.135),
            app(3, 0.29, 0.772, width: 0.37, height: 0.135),
        ],
        right: [
            button("select", String(localized: "決定"), "circle.circle", 0.5, 0.258, size: 0.4, shape: .select),
            button("dpad_right", String(localized: "右"), "chevron.right", 0.8, 0.258, size: 0.16, shape: .arrow),
            button("dpad_down", String(localized: "下"), "chevron.down", 0.5, 0.336, size: 0.16, shape: .arrow),
            button("home", String(localized: "ホーム"), "house", 0.5, 0.42),
            button("menu", String(localized: "メニュー"), "line.3.horizontal", 0.81, 0.42),
            button("play_pause", String(localized: "再生・停止"), "playpause.fill", 0.5, 0.49),
            button("fast_forward", String(localized: "早送り"), "forward.fill", 0.81, 0.49),
            button("volume_down", String(localized: "音量 −"), "speaker.minus", 0.5, 0.645, shape: .rocker, glyph: "minus"),
            button("tv", "TV", "tv", 0.81, 0.575),
            app(2, 0.71, 0.712, width: 0.37, height: 0.135),
            app(4, 0.71, 0.772, width: 0.37, height: 0.135),
        ],
        aspect: 1 / 3.66,
        ringCenter: .init(x: 0.5, y: 0.258), ringDiameter: 0.82,
        rockers: [(.init(x: 0.5, y: 0.6115), .init(width: 0.24, height: 0.5))]
    )

    // MARK: Amazon Remote Pro(互換品で確認。無印より約11%長い)

    static let pro = RemoteLayout(
        left: [
            button("power", powerTitle, "power", 0.156, 0.05, size: 0.15),
            button("voice", voiceTitle, "mic.fill", 0.5, 0.111, size: 0.24, shape: .voice),
            button("dpad_up", String(localized: "上"), "chevron.up", 0.5, 0.186, size: 0.16, shape: .arrow),
            button("dpad_left", String(localized: "左"), "chevron.left", 0.19, 0.261, size: 0.16, shape: .arrow),
            button("back", String(localized: "戻る"), "arrow.uturn.backward", 0.19, 0.415),
            button("home", String(localized: "ホーム"), "house", 0.5, 0.415),
            button("rewind", String(localized: "巻き戻し"), "backward.fill", 0.19, 0.491),
            button("play_pause", String(localized: "再生・停止"), "playpause.fill", 0.5, 0.491),
            button("volume_up", String(localized: "音量 +"), "speaker.plus", 0.19, 0.569, shape: .rocker, glyph: "plus"),
            button("volume_down", String(localized: "音量 −"), "speaker.minus", 0.19, 0.644, shape: .rocker, glyph: "minus"),
            button("mute", String(localized: "ミュート"), "speaker.slash", 0.19, 0.721),
            button("custom_1", String(localized: "カスタム 1"), "1.square", 0.5, 0.721, shape: .text, glyph: "1"),
            app(1, 0.27, 0.79, width: 0.39, height: 0.16),
            app(3, 0.27, 0.852, width: 0.39, height: 0.16),
        ],
        right: [
            button("headphones", String(localized: "ヘッドホン"), "headphones", 0.844, 0.05, size: 0.15),
            button("select", String(localized: "決定"), "circle.circle", 0.5, 0.261, size: 0.46, shape: .select),
            button("dpad_right", String(localized: "右"), "chevron.right", 0.81, 0.261, size: 0.16, shape: .arrow),
            button("dpad_down", String(localized: "下"), "chevron.down", 0.5, 0.336, size: 0.16, shape: .arrow),
            button("menu", String(localized: "メニュー"), "line.3.horizontal", 0.81, 0.415),
            button("fast_forward", String(localized: "早送り"), "forward.fill", 0.81, 0.491),
            button("tv", "TV", "tv", 0.5, 0.567),
            button("channel_up", String(localized: "チャンネル +"), "arrowtriangle.up", 0.81, 0.569,
                   shape: .rocker, glyph: "arrowtriangle.up.fill"),
            button("settings", String(localized: "設定"), "gearshape", 0.5, 0.645),
            button("channel_down", String(localized: "チャンネル −"), "arrowtriangle.down", 0.81, 0.644,
                   shape: .rocker, glyph: "arrowtriangle.down.fill"),
            button("custom_2", String(localized: "カスタム 2"), "2.square", 0.81, 0.721, shape: .text, glyph: "2"),
            app(2, 0.73, 0.79, width: 0.39, height: 0.16),
            app(4, 0.73, 0.852, width: 0.39, height: 0.16),
        ],
        aspect: 1 / 4.06,
        ringCenter: .init(x: 0.5, y: 0.261), ringDiameter: 0.84,
        rockers: [(.init(x: 0.19, y: 0.6065), .init(width: 0.235, height: 0.55)),
                  (.init(x: 0.81, y: 0.6065), .init(width: 0.235, height: 0.55))]
    )
}
