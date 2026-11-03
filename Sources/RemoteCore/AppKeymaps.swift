/// アプリごとの割り当て。共通の割り当てに対する差分として持つ。
public enum AppKeymaps {
    /// 差分の中で「標準」(共通の割り当てを消して Mac の標準動作に戻す)を表す値
    public static let standardValue = "standard"

    /// 共通の割り当てに、アプリの差分を重ねる
    public static func merge(_ global: [String: String], _ overrides: [String: String]?) -> [String: String] {
        var result = global
        for (key, value) in overrides ?? [:] {
            result[key] = value == standardValue ? nil : value
        }
        return result
    }
}
