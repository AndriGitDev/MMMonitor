import Foundation

@MainActor
enum MetricFormatting {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static let rate: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .decimal
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func percentage(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }

    static func byteCount(_ value: UInt64) -> String {
        bytes.string(fromByteCount: Int64(clamping: value))
    }

    static func milliampHours(_ value: Int) -> String {
        "\(value.formatted()) mAh"
    }

    static func bytesPerSecond(_ value: Double) -> String {
        "\(rate.string(fromByteCount: Int64(max(0, value))))/s"
    }

    static func compactRate(_ value: Double) -> String {
        let safeValue = max(0, value)
        if safeValue >= 999_500_000 {
            return compactValue(min(safeValue / 1_000_000_000, 999), unit: "G")
        }
        if safeValue >= 999_500 {
            return compactValue(safeValue / 1_000_000, unit: "M")
        }
        return compactValue(safeValue / 1_000, unit: "K")
    }

    static func compactPercentage(_ value: Double) -> String {
        let percentage = Int((min(1, max(0, value)) * 100).rounded())
        return String(format: "%3d%%", percentage)
    }

    private static func compactValue(_ value: Double, unit: Character) -> String {
        if value < 9.95 {
            return String(format: "%4.1f%@", value, String(unit))
        }
        return String(format: "%4.0f%@", value, String(unit))
    }

    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func uptime(_ interval: TimeInterval) -> String {
        let totalHours = max(0, Int(interval / 3_600))
        let days = totalHours / 24
        let hours = totalHours % 24
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h"
    }
}
