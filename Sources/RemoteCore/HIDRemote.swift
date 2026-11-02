import Foundation
import IOKit.hid

public struct InputReport {
    public let reportID: UInt8
    /// Report ID を除いた内容
    public let payload: [UInt8]
    public let timestampNs: UInt64
}

public func ioReturnDescription(_ r: IOReturn) -> String {
    switch r {
    case kIOReturnSuccess: return "success"
    case kIOReturnNotPermitted: return "kIOReturnNotPermitted(入力監視の権限がない可能性)"
    case kIOReturnNotPrivileged: return "kIOReturnNotPrivileged"
    case kIOReturnExclusiveAccess: return "kIOReturnExclusiveAccess(他が占有中)"
    case kIOReturnNotOpen: return "kIOReturnNotOpen"
    case kIOReturnTimeout: return "kIOReturnTimeout"
    case kIOReturnUnsupported: return "kIOReturnUnsupported"
    default: return String(format: "0x%08X", UInt32(bitPattern: r))
    }
}

/// IOHIDManager 経由で対象リモコンを扱う。リモコンのスリープ復帰による再接続も matching callback で処理される。
public final class HIDRemote {
    public let profile: any RemoteProfile
    public private(set) var reports: [HIDReportInfo] = []
    public private(set) var voiceReports: VoiceReports?

    public var onConnect: ((IOHIDDevice) -> Void)?
    public var onDisconnect: (() -> Void)?
    /// 接続のたびに呼ばれる追加処理(VoiceSession が onConnect を使うため別に用意)
    public var onConnectExtra: (() -> Void)?
    public var onReport: ((InputReport) -> Void)?

    private let manager: IOHIDManager
    private let seize: Bool
    private var device: IOHIDDevice?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    private let writeQueue = DispatchQueue(label: "remoteinput.hid.write")
    private let timebase: mach_timebase_info_data_t = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return t
    }()

    public init(profile: any RemoteProfile, seize: Bool = false) {
        self.profile = profile
        self.seize = seize
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: profile.vendorID,
            kIOHIDProductIDKey: profile.productID,
        ] as CFDictionary)
    }

    deinit { buffer.deallocate() }

    /// 開かずに、現在見えているデバイスを返す。
    public func connectedDevices() -> [IOHIDDevice] {
        (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>).map(Array.init) ?? []
    }

    public static func descriptor(of device: IOHIDDevice) -> [UInt8] {
        (IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data).map { [UInt8]($0) } ?? []
    }

    /// 監視を開始する。接続・切断・Report は main run loop 上で通知される。
    public func start() -> IOReturn {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<HIDRemote>.fromOpaque(ctx!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            let me = Unmanaged<HIDRemote>.fromOpaque(ctx!).takeUnretainedValue()
            me.device = nil
            me.onDisconnect?()
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
        self.device = device
        reports = HIDReportDescriptor.parse(Self.descriptor(of: device))
        voiceReports = profile.voiceReports(in: reports)
        IOHIDDeviceRegisterInputReportWithTimeStampCallback(
            device, buffer, 1024,
            { ctx, _, _, _, reportID, report, length, timestamp in
                Unmanaged<HIDRemote>.fromOpaque(ctx!).takeUnretainedValue()
                    .handle(reportID: UInt8(truncatingIfNeeded: reportID), report: report, length: length, timestamp: timestamp)
            },
            Unmanaged.passUnretained(self).toOpaque())
        onConnect?(device)
        onConnectExtra?()
    }

    private func handle(reportID: UInt8, report: UnsafePointer<UInt8>, length: CFIndex, timestamp: UInt64) {
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        let expected = reports.first { $0.id == reportID }?.inputBytes
        let ns = timestamp &* UInt64(timebase.numer) / UInt64(timebase.denom)
        onReport?(InputReport(reportID: reportID,
                              payload: stripReportID(reportID, from: bytes, expectedPayload: expected),
                              timestampNs: ns))
    }

    /// マイク状態を送る。SetReport は同期 API のため別キューで実行し、順序は保つ。
    public func setMic(enabled: Bool, completion: @escaping (IOReturn) -> Void) {
        guard let device, let voiceReports else {
            completion(kIOReturnNotOpen)
            return
        }
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
