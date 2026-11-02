import Foundation

/// マイク音声のゲインと入力レベルの計算
public enum AudioGain {
    public static let minDecibels = -12.0
    public static let maxDecibels = 24.0
    /// メーターの下限
    public static let meterFloorDecibels = -60.0

    public struct Result: Equatable {
        public let samples: [Int16]
        /// ゲイン適用後のピーク(0...1)
        public let peak: Double
        /// ゲイン適用後に上限で切り詰めたサンプルがあるか
        public let clipped: Bool
    }

    public static func clamp(decibels: Double) -> Double {
        min(max(decibels, minDecibels), maxDecibels)
    }

    public static func apply(_ samples: [Int16], decibels: Double) -> Result {
        let factor = pow(10, clamp(decibels: decibels) / 20)
        var peak = 0.0
        var clipped = false
        let output = samples.map { sample -> Int16 in
            let value = Double(sample) * factor
            let limited = min(max(value, Double(Int16.min)), Double(Int16.max))
            if limited != value { clipped = true }
            peak = max(peak, abs(limited) / 32768)
            return Int16(limited.rounded())
        }
        return Result(samples: output, peak: peak, clipped: clipped)
    }

    /// ピークをメーターの位置(0...1)に変換する。-60 dB 以下は 0、0 dB は 1。
    public static func meterPosition(peak: Double) -> Double {
        guard peak > 0 else { return 0 }
        let decibels = 20 * log10(peak)
        return min(max((decibels - meterFloorDecibels) / -meterFloorDecibels, 0), 1)
    }
}
