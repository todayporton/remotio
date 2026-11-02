import Foundation

/// 対象リモコンのボタンが Mac へ通常のキー入力として届かないようにする。
/// 占有モード(kIOHIDOptionsTypeSeizeDevice)は一般ユーザーでは kIOReturnNotPrivileged になるため、
/// hidutil の UserKeyMapping で対象デバイスのキーだけを無効化する。
/// 設定はこのデバイスの接続中のみ有効で、再接続時には再設定が必要。
public struct KeySuppressor {
    private let matching: String
    private let usages: [UInt64]

    public init(profile: any RemoteProfile, buttons: some Sequence<String>) {
        matching = "{\"VendorID\":\(profile.vendorID),\"ProductID\":\(profile.productID)}"
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

    private func set(_ json: String) -> Bool {
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
