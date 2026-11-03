import Foundation
import IOKit.hid

public struct InputReport {
    public let reportID: UInt8
    /// Report ID を除いた内容
    public let payload: [UInt8]
    public let timestampNs: UInt64
    /// 送ってきたリモコン(HIDRemote.Remote.id)
    public var remoteID: UInt64 = 0
}

public func ioReturnDescription(_ r: IOReturn) -> String {
    switch r {
    case kIOReturnSuccess: return "success"
    case kIOReturnNotPermitted: return String(localized: "kIOReturnNotPermitted(入力監視の権限がない可能性)")
    case kIOReturnNotPrivileged: return "kIOReturnNotPrivileged"
    case kIOReturnExclusiveAccess: return String(localized: "kIOReturnExclusiveAccess(他が占有中)")
    case kIOReturnNotOpen: return "kIOReturnNotOpen"
    case kIOReturnTimeout: return "kIOReturnTimeout"
    case kIOReturnUnsupported: return "kIOReturnUnsupported"
    default: return String(format: "0x%08X", UInt32(bitPattern: r))
    }
}

/// IOHIDManager 経由で対象リモコンを扱う。複数台を同時に扱える。
/// リモコンのスリープ復帰による再接続も matching callback で処理される。
public final class HIDRemote {
    /// つながっているリモコン1台の情報
    public struct Remote {
        /// IORegistry のエントリ ID。接続している間は変わらない
        public let id: UInt64
        /// 設定を保存するときの名前。再接続しても同じ。シリアル番号がなければ製品 ID
        public var key: String { serial.map { "serial:\($0)" } ?? "product:\(productID)" }
        public let name: String
        public let productID: Int
        /// シリアル番号。名乗らない機種では nil
        public let serial: String?
        public let reports: [HIDReportInfo]
        public let voiceReports: VoiceReports?
    }

    public let profile: any RemoteProfile
    public private(set) var remotes: [UInt64: Remote] = [:]

    public var onConnect: ((Remote) -> Void)?
    public var onDisconnect: ((Remote) -> Void)?
    /// 接続のたびに呼ばれる追加処理(VoiceSession が onConnect を使うため別に用意)
    public var onConnectExtra: ((Remote) -> Void)?
    public var onReport: ((InputReport) -> Void)?

    /// 1台ごとの受信バッファとコールバックの文脈
    private final class Connection {
        let device: IOHIDDevice
        let remote: Remote
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        weak var owner: HIDRemote?

        init(device: IOHIDDevice, remote: Remote, owner: HIDRemote) {
            self.device = device
            self.remote = remote
            self.owner = owner
        }

        deinit { buffer.deallocate() }
    }

    private let manager: IOHIDManager
    private let seize: Bool
    private var connections: [UInt64: Connection] = [:]
    private let writeQueue = DispatchQueue(label: "remotio.hid.write")
    private let timebase: mach_timebase_info_data_t = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return t
    }()

    public init(profile: any RemoteProfile, seize: Bool = false) {
        self.profile = profile
        self.seize = seize
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, profile.productIDs.map {
            [kIOHIDVendorIDKey: profile.vendorID, kIOHIDProductIDKey: $0] as CFDictionary
        } as CFArray)
    }

    /// 開かずに、現在見えているデバイスを返す。
    public func connectedDevices() -> [IOHIDDevice] {
        (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>).map(Array.init) ?? []
    }

    public static func descriptor(of device: IOHIDDevice) -> [UInt8] {
        (IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data).map { [UInt8]($0) } ?? []
    }

    static func registryID(of device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }

    /// 監視を開始する。接続・切断・Report は main run loop 上で通知される。
    public func start() -> IOReturn {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<HIDRemote>.fromOpaque(ctx!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            Unmanaged<HIDRemote>.fromOpaque(ctx!).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let option = seize ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone
        return IOHIDManagerOpen(manager, IOOptionBits(option))
    }

    public func stop() {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func attach(_ device: IOHIDDevice) {
        let id = Self.registryID(of: device)
        guard connections[id] == nil else { return }
        let reports = HIDReportDescriptor.parse(Self.descriptor(of: device))
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let name = profile.modelName(productID: productID)
            ?? IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
            ?? profile.displayName
        let serial = (IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let remote = Remote(id: id, name: name, productID: productID, serial: serial, reports: reports,
                            voiceReports: profile.voiceReports(in: reports))
        let connection = Connection(device: device, remote: remote, owner: self)
        connections[id] = connection
        remotes[id] = remote
        IOHIDDeviceRegisterInputReportWithTimeStampCallback(
            device, connection.buffer, 1024,
            { ctx, _, _, _, reportID, report, length, timestamp in
                let connection = Unmanaged<Connection>.fromOpaque(ctx!).takeUnretainedValue()
                connection.owner?.handle(connection.remote, reportID: UInt8(truncatingIfNeeded: reportID),
                                         report: report, length: length, timestamp: timestamp)
            },
            Unmanaged.passUnretained(connection).toOpaque())
        onConnect?(remote)
        onConnectExtra?(remote)
    }

    private func detach(_ device: IOHIDDevice) {
        let id = Self.registryID(of: device)
        guard let connection = connections.removeValue(forKey: id) else { return }
        remotes[id] = nil
        onDisconnect?(connection.remote)
        // 届きかけのコールバックが終わってからバッファを手放す
        DispatchQueue.main.async { withExtendedLifetime(connection) {} }
    }

    private func handle(_ remote: Remote, reportID: UInt8, report: UnsafePointer<UInt8>, length: CFIndex,
                        timestamp: UInt64) {
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        let expected = remote.reports.first { $0.id == reportID }?.inputBytes
        let ns = timestamp &* UInt64(timebase.numer) / UInt64(timebase.denom)
        onReport?(InputReport(reportID: reportID,
                              payload: stripReportID(reportID, from: bytes, expectedPayload: expected),
                              timestampNs: ns, remoteID: remote.id))
    }

    /// マイク状態を送る。SetReport は同期 API のため別キューで実行し、順序は保つ。
    public func setMic(_ remoteID: UInt64, enabled: Bool, completion: @escaping (IOReturn) -> Void) {
        guard let connection = connections[remoteID], let voiceReports = connection.remote.voiceReports else {
            completion(kIOReturnNotOpen)
            return
        }
        let device = connection.device
        let id = voiceReports.micEnableReportID
        let bytes: [UInt8] = [id, enabled ? 0x01 : 0x00]
        writeQueue.async {
            let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(id), bytes, bytes.count)
            DispatchQueue.main.async { completion(r) }
        }
    }

    /// 終了前に、キュー内の送信が終わるまで待つ。
    public func flushWrites() { writeQueue.sync {} }
}
