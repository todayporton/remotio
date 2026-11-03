import AppKit
import SwiftUI

/// ログの保管。ボタンを押すたびに増えるので、AppModel から分けて、ログのページ以外を描き直さないようにする
final class LogStore: ObservableObject {
    struct Line: Identifiable {
        let id: Int
        let text: String
    }

    /// 残す行数。超えたら古い行をまとめて消し、ログのページの全体の描き直しを減らす
    private static let keep = 300
    private static let trimAt = 400

    @Published private(set) var lines: [Line] = []
    private var nextID = 0
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func append(_ message: String) {
        lines.append(Line(id: nextID, text: "\(formatter.string(from: Date())) \(message)"))
        nextID += 1
        if lines.count > Self.trimAt { lines.removeFirst(lines.count - Self.keep) }
    }
}

/// ログを表示する。増えた行だけを末尾に足し、最下部を見ているときは追いかけてスクロールする
struct LogTextView: NSViewRepresentable {
    let lines: [LogStore.Line]

    final class Coordinator {
        var firstID: Int?
        var lastID: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = .zero
        text.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView, let storage = text.textStorage else { return }
        let state = context.coordinator
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        let atBottom = scroll.contentView.bounds.maxY >= text.bounds.maxY - 4
        if lines.first?.id != state.firstID {
            // 古い行が消えたら全体を作り直す
            let all = lines.map(\.text).joined(separator: "\n")
            storage.setAttributedString(NSAttributedString(string: all, attributes: attributes))
        } else if let lastID = state.lastID {
            let added = lines.filter { $0.id > lastID }.map { "\n" + $0.text }.joined()
            guard !added.isEmpty else { return }
            storage.append(NSAttributedString(string: added, attributes: attributes))
        }
        state.firstID = lines.first?.id
        state.lastID = lines.last?.id
        if atBottom { text.scrollToEndOfDocument(nil) }
    }
}
