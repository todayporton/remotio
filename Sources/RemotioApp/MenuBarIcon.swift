import AppKit

/// メニューバーのアイコン。SF Symbols は記号ごとに幅が違い、そのまま出すと状態が変わるたびに
/// メニューバー全体がずれるので、同じ大きさの画像の中央に描く。
enum MenuBarIcon {
    static let canvasSize = NSSize(width: 22, height: 18)
    private static let pointSize: CGFloat = 14

    static func image(symbolName: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let image = NSImage(size: canvasSize, flipped: false) { bounds in
            guard let symbol else { return false }
            let scale = min(1, bounds.width / symbol.size.width, bounds.height / symbol.size.height)
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
            symbol.draw(in: NSRect(origin: origin, size: size))
            return true
        }
        image.isTemplate = true
        return image
    }
}
