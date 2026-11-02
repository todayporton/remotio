import Foundation

/// HID Report Descriptor から得た、Report ID ごとのサイズ情報(Report ID 自体は含まない)。
public struct HIDReportInfo: Equatable, Sendable {
    public let id: UInt8
    public var inputBytes = 0
    public var outputBytes = 0
    public var featureBytes = 0
    public var usagePage: UInt32 = 0

    public init(id: UInt8) { self.id = id }
}

public enum HIDReportDescriptor {
    /// Report ID / Size / Count を追跡する最小限のパーサ。
    public static func parse(_ bytes: [UInt8]) -> [HIDReportInfo] {
        var reports: [UInt8: HIDReportInfo] = [:]
        var bits: [UInt8: (input: Int, output: Int, feature: Int)] = [:]
        var reportID: UInt8 = 0, reportSize = 0, reportCount = 0
        var usagePage: UInt32 = 0
        var i = 0

        while i < bytes.count {
            let prefix = bytes[i]
            i += 1
            if prefix == 0xFE { // long item
                guard i < bytes.count else { break }
                i += 2 + Int(bytes[i])
                continue
            }
            let tag = prefix >> 4, type = (prefix >> 2) & 3
            let length = [0, 1, 2, 4][Int(prefix & 3)]
            guard i + length <= bytes.count else { break }
            var value: UInt32 = 0
            for n in 0..<length { value |= UInt32(bytes[i + n]) << UInt32(8 * n) }
            i += length

            switch (type, tag) {
            case (1, 0x0): usagePage = value
            case (1, 0x7): reportSize = Int(value)
            case (1, 0x8): reportID = UInt8(truncatingIfNeeded: value)
            case (1, 0x9): reportCount = Int(value)
            case (0, 0x8), (0, 0x9), (0, 0xB):
                var info = reports[reportID] ?? HIDReportInfo(id: reportID)
                info.usagePage = usagePage
                reports[reportID] = info
                var b = bits[reportID] ?? (0, 0, 0)
                let n = reportSize * reportCount
                if tag == 0x8 { b.input += n } else if tag == 0x9 { b.output += n } else { b.feature += n }
                bits[reportID] = b
            default: break
            }
        }

        return reports.values.map { report in
            var r = report
            let b = bits[r.id] ?? (0, 0, 0)
            r.inputBytes = b.input / 8
            r.outputBytes = b.output / 8
            r.featureBytes = b.feature / 8
            return r
        }.sorted { $0.id < $1.id }
    }
}
