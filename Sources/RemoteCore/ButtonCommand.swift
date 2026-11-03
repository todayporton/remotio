import AppKit
import Foundation

/// ボタンで実行するコマンド。設定には "url:<URL>" か "shell:<コマンド>" の形で保存する。
public enum ButtonCommand: Equatable, Sendable {
    /// URL を開く(raycast://… や https://… など)
    case openURL(URL)
    /// ログインシェルでコマンドを実行する
    case shell(String)

    static let urlPrefix = "url:"
    static let shellPrefix = "shell:"

    public init?(_ text: String) {
        if text.hasPrefix(Self.urlPrefix) {
            let value = text.dropFirst(Self.urlPrefix.count).trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: value), url.scheme?.isEmpty == false else { return nil }
            self = .openURL(url)
        } else if text.hasPrefix(Self.shellPrefix) {
            let value = text.dropFirst(Self.shellPrefix.count).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            self = .shell(value)
        } else {
            return nil
        }
    }

    /// コマンドの形式の文字列か(中身が正しいかは問わない)
    static func hasPrefix(_ text: String) -> Bool {
        text.hasPrefix(urlPrefix) || text.hasPrefix(shellPrefix)
    }

    /// 設定に保存する文字列
    public var text: String {
        switch self {
        case .openURL(let url): return Self.urlPrefix + url.absoluteString
        case .shell(let command): return Self.shellPrefix + command
        }
    }

    /// 入力欄に出す中身
    public var value: String {
        switch self {
        case .openURL(let url): return url.absoluteString
        case .shell(let command): return command
        }
    }

    /// メニューに出す名前。長いものは省略する
    public var displayText: String {
        let short = value.count > 24 ? String(value.prefix(23)) + "…" : value
        switch self {
        case .openURL: return "🔗 " + short
        case .shell: return "$ " + short
        }
    }

    /// 実行する。結果は log で知らせる
    public func run(log: @escaping (String) -> Void) {
        switch self {
        case .openURL(let url):
            if !NSWorkspace.shared.open(url) {
                log(String(localized: "URL を開けません: \(url.absoluteString)"))
            }
        case .shell(let command):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            let errors = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            process.terminationHandler = { finished in
                guard finished.terminationStatus != 0 else { return }
                let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let status = Int(finished.terminationStatus)
                DispatchQueue.main.async {
                    log(String(localized: "コマンドが失敗しました(終了コード \(status)): \(command) \(message)"))
                }
            }
            do {
                try process.run()
            } catch {
                log(String(localized: "コマンドを実行できません: \(String(describing: error))"))
            }
        }
    }
}
