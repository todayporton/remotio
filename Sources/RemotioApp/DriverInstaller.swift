import Foundation

/// 同梱の仮想マイクドライバを /Library/Audio/Plug-Ins/HAL へ入れる・取り除く。
/// 管理者権限が必要で、処理の間は Mac 全体の音声が一瞬止まる。
enum DriverInstaller {
    private static let bundleName = "RemotioMicrophone.driver"
    private static let installedPath = "/Library/Audio/Plug-Ins/HAL/\(bundleName)"

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: installedPath) }

    private static var bundledDriver: URL? {
        Bundle.main.resourceURL?.appendingPathComponent(bundleName)
    }

    /// 成功なら nil、失敗ならエラーの内容を返す。キャンセルも失敗として扱う。
    static func install() -> String? {
        guard let source = bundledDriver, FileManager.default.fileExists(atPath: source.path) else {
            return String(localized: "アプリにドライバが同梱されていません")
        }
        let command = """
        /bin/rm -rf \(quoted(installedPath)) && \
        /usr/bin/ditto \(quoted(source.path)) \(quoted(installedPath)) && \
        /usr/bin/xattr -dr com.apple.quarantine \(quoted(installedPath)) ; \
        /usr/bin/killall -9 coreaudiod
        """
        return runAsAdministrator(command)
    }

    static func uninstall() -> String? {
        runAsAdministrator("/bin/rm -rf \(quoted(installedPath)) && /usr/bin/killall -9 coreaudiod")
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAsAdministrator(_ command: String) -> String? {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error.map { $0[NSAppleScript.errorMessage] as? String ?? "\($0)" }
    }
}
