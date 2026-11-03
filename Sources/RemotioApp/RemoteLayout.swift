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

    /// y は「幅を1とした上端からの長さ」で書き、図の高さで割って割合にする
    private static func button(_ id: String, _ title: String, _ symbol: String, _ x: CGFloat, _ y: CGFloat,
                               height: CGFloat, size: CGFloat = 0.23, shape: RemoteButton.Shape = .round,
                               glyph: String? = nil) -> RemoteButton {
        RemoteButton(id: id, title: title, symbol: symbol, position: .init(x: x, y: y / height),
                     size: .init(width: size, height: size), shape: shape, glyph: glyph)
    }

    private static func app(_ number: Int, _ x: CGFloat, _ y: CGFloat, height: CGFloat) -> RemoteButton {
        RemoteButton(id: "app_a\(number)", title: String(localized: "アプリ \(number)"), symbol: "\(number).circle",
                     position: .init(x: x, y: y / height), size: .init(width: 0.37, height: 0.135), shape: .app,
                     glyph: "\(number)")
    }

    // 2機種は上から早送りの段まで同じ配置。Pro は音量の段の並びが違い、ミュートとカスタムボタンの段が
    // 1段増えたぶん下に長い。大きさは幅を1とした値
    private static let rowSpacing: CGFloat = 0.256
    private static let topY: CGFloat = 0.176
    private static let voiceY: CGFloat = 0.395
    private static let ringY: CGFloat = 0.944
    private static let ringDiameter: CGFloat = 0.82
    private static let arrowOffset: CGFloat = 0.3
    private static let backRowY: CGFloat = 1.537
    private static let rewindRowY = backRowY + rowSpacing
    /// 縦長ボタンの上と下のボタン
    private static let rockerTopY: CGFloat = 2.115
    private static let rockerBottomY: CGFloat = 2.361
    private static let rockerSize = CGSize(width: 0.24, height: 0.5)
    /// Pro で増えた段のぶん(無印との長さの差)
    private static let proExtra: CGFloat = 0.406
    private static let standardHeight: CGFloat = 3.66
    private static let proHeight = standardHeight + proExtra
    private static let appRowY: CGFloat = 2.606
    private static let appRowSpacing: CGFloat = 0.22

    /// 2機種に共通の上半分(電源から早送りまで)
    private static func topHalf(height h: CGFloat) -> (left: [RemoteButton], right: [RemoteButton]) {
        let arrowY = arrowOffset
        return (
            left: [
                button("power", String(localized: "電源"), "power", 0.15, topY, height: h, size: 0.15),
                button("voice", String(localized: "音声(Push-to-Talk)"), "mic.fill", 0.5, voiceY, height: h,
                       size: 0.24, shape: .voice),
                button("dpad_up", String(localized: "上"), "chevron.up", 0.5, ringY - arrowY, height: h,
                       size: 0.16, shape: .arrow),
                button("dpad_left", String(localized: "左"), "chevron.left", 0.5 - arrowOffset, ringY, height: h,
                       size: 0.16, shape: .arrow),
                button("back", String(localized: "戻る"), "arrow.uturn.backward", 0.19, backRowY, height: h),
            ],
            right: [
                button("select", String(localized: "決定"), "circle.circle", 0.5, ringY, height: h,
                       size: 0.4, shape: .select),
                button("dpad_right", String(localized: "右"), "chevron.right", 0.5 + arrowOffset, ringY, height: h,
                       size: 0.16, shape: .arrow),
                button("dpad_down", String(localized: "下"), "chevron.down", 0.5, ringY + arrowY, height: h,
                       size: 0.16, shape: .arrow),
                button("menu", String(localized: "メニュー"), "line.3.horizontal", 0.81, backRowY, height: h),
            ]
        )
    }

    private static func home(_ h: CGFloat) -> RemoteButton {
        button("home", String(localized: "ホーム"), "house", 0.5, backRowY, height: h)
    }
    private static func rewind(_ h: CGFloat) -> RemoteButton {
        button("rewind", String(localized: "巻き戻し"), "backward.fill", 0.19, rewindRowY, height: h)
    }
    private static func playPause(_ h: CGFloat) -> RemoteButton {
        button("play_pause", String(localized: "再生・停止"), "playpause.fill", 0.5, rewindRowY, height: h)
    }
    private static func fastForward(_ h: CGFloat) -> RemoteButton {
        button("fast_forward", String(localized: "早送り"), "forward.fill", 0.81, rewindRowY, height: h)
    }
    private static func volumeUp(_ x: CGFloat, _ h: CGFloat) -> RemoteButton {
        button("volume_up", String(localized: "音量 +"), "speaker.plus", x, rockerTopY, height: h,
               shape: .rocker, glyph: "plus")
    }
    private static func volumeDown(_ x: CGFloat, _ h: CGFloat) -> RemoteButton {
        button("volume_down", String(localized: "音量 −"), "speaker.minus", x, rockerBottomY, height: h,
               shape: .rocker, glyph: "minus")
    }
    private static func rocker(_ x: CGFloat, _ h: CGFloat) -> (center: CGPoint, size: CGSize) {
        (.init(x: x, y: (rockerTopY + rockerBottomY) / 2 / h), rockerSize)
    }

    // MARK: Fire TV Stick 4K 付属リモコン(第3世代)

    static let standard: RemoteLayout = {
        let h = standardHeight
        let top = topHalf(height: h)
        return RemoteLayout(
            left: top.left + [
                rewind(h),
                volumeUp(0.5, h),
                button("mute", String(localized: "ミュート"), "speaker.slash", 0.19, rockerTopY, height: h),
                app(1, 0.29, appRowY, height: h),
                app(3, 0.29, appRowY + appRowSpacing, height: h),
            ],
            right: [top.right[0], top.right[1], top.right[2], home(h), top.right[3], playPause(h), fastForward(h),
                    volumeDown(0.5, h),
                    button("tv", "TV", "tv", 0.81, rockerTopY, height: h),
                    app(2, 0.71, appRowY, height: h),
                    app(4, 0.71, appRowY + appRowSpacing, height: h)],
            aspect: 1 / h,
            ringCenter: .init(x: 0.5, y: ringY / h), ringDiameter: ringDiameter,
            rockers: [rocker(0.5, h)]
        )
    }()

    // MARK: Amazon Remote Pro(互換品で確認)

    static let pro: RemoteLayout = {
        let h = proHeight
        let top = topHalf(height: h)
        let customRowY = rockerBottomY + 0.3
        return RemoteLayout(
            left: top.left + [
                home(h), rewind(h), playPause(h),
                volumeUp(0.19, h), volumeDown(0.19, h),
                button("mute", String(localized: "ミュート"), "speaker.slash", 0.19, customRowY, height: h),
                button("custom_1", String(localized: "カスタム 1"), "1.square", 0.5, customRowY, height: h,
                       shape: .text, glyph: "1"),
                app(1, 0.29, appRowY + proExtra, height: h),
                app(3, 0.29, appRowY + proExtra + appRowSpacing, height: h),
            ],
            right: [
                button("headphones", String(localized: "ヘッドホン"), "headphones", 0.85, topY, height: h, size: 0.15),
            ] + top.right + [
                fastForward(h),
                button("tv", "TV", "tv", 0.5, rockerTopY, height: h),
                button("channel_up", String(localized: "チャンネル +"), "arrowtriangle.up", 0.81, rockerTopY, height: h,
                       shape: .rocker, glyph: "arrowtriangle.up.fill"),
                button("channel_down", String(localized: "チャンネル −"), "arrowtriangle.down", 0.81, rockerBottomY,
                       height: h, shape: .rocker, glyph: "arrowtriangle.down.fill"),
                button("settings", String(localized: "設定"), "gearshape", 0.5, rockerBottomY, height: h),
                button("custom_2", String(localized: "カスタム 2"), "2.square", 0.81, customRowY, height: h,
                       shape: .text, glyph: "2"),
                app(2, 0.71, appRowY + proExtra, height: h),
                app(4, 0.71, appRowY + proExtra + appRowSpacing, height: h),
            ],
            aspect: 1 / h,
            ringCenter: .init(x: 0.5, y: ringY / h), ringDiameter: ringDiameter,
            rockers: [rocker(0.19, h), rocker(0.81, h)]
        )
    }()
}
