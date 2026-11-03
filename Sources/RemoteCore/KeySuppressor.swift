import Foundation

/// 対象リモコンのボタンが Mac へ通常のキー入力として届かないようにする。
/// 占有モード(kIOHIDOptionsTypeSeizeDevice)は一般ユーザーでは kIOReturnNotPrivileged になるため、
/// hidutil の UserKeyMapping で対象デバイスのキーだけを無効化する。
/// 設定はこのデバイスの接続中のみ有効で、再接続時には再設定が必要。
public struct KeySuppressor {
    private let matchings: [String]
    private let usages: [UInt64]

    /// 1台だけを対象にする。シリアル番号がなければ同じ製品のリモコンすべてが対象になる
    public init(profile: any RemoteProfile, remote: HIDRemote.Remote, buttons: some Sequence<String>) {
        // JSON に埋め込むので、英数字以外を含むシリアル番号は使わない
        let usable = remote.serial.flatMap { serial in
            serial.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } ? serial : nil
        }
        let serial = usable.map { ",\"SerialNumber\":\"\($0)\"" } ?? ""
        matchings = ["{\"VendorID\":\(profile.vendorID),\"ProductID\":\(remote.productID)\(serial)}"]
        usages = buttons.compactMap { profile.systemUsage(of: $0) }.sorted()
    }

    /// 対応する製品のリモコンすべてを対象にする
    public init(profile: any RemoteProfile, buttons: some Sequence<String>) {
        matchings = profile.productIDs.map { "{\"VendorID\":\(profile.vendorID),\"ProductID\":\($0)}" }
        usages = buttons.compactMap { profile.systemUsage(of: $0) }.sorted()
    }

    /// hidutil に渡す設定の JSON
    public static func mappingJSON(usages: [UInt64]) -> String {
        let items = usages.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0),\"HIDKeyboardModifierMappingDst\":0}"
        }
        return "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"
    }

    public func apply() -> Bool { set(Self.mappingJSON(usages: usages)) }
    public func clear() -> Bool { set(Self.mappingJSON(usages: [])) }

    /// 製品 ID ごとに設定する。つながっていない製品は hidutil が何もしないだけなので、成否は問わない
    private func set(_ json: String) -> Bool {
        matchings.map { set(json, matching: $0) }.contains(true)
    }

    private func set(_ json: String, matching: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--matching", matching, "--set", json]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
