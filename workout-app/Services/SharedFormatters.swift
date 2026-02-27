import Foundation
import SwiftUI

/// Centralized formatting utilities shared across views.
/// Eliminates ~10 duplicated `formatVolume`, `formatElapsed`, `formatDurationMinutes`, and
/// `startOfWeekSunday` implementations scattered throughout the codebase.
enum SharedFormatters {

    // MARK: - Volume Formatting

    /// Compact volume string without units. e.g. "1.2M", "45k", "890"
    static func volumeCompact(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        }
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }

    /// Volume string with "lbs" unit. e.g. "1.2M lbs", "45k lbs", "890 lbs"
    static func volumeWithUnit(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM lbs", volume / 1_000_000)
        }
        if volume >= 1000 {
            return String(format: "%.1fk lbs", volume / 1000)
        }
        return "\(Int(volume)) lbs"
    }

    /// Volume string with one decimal for mid-range. e.g. "1.2M", "45.3k", "890"
    static func volumePrecise(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        }
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }

    // MARK: - Elapsed Time Formatting

    /// Formats a `TimeInterval` as `h:mm:ss` or `m:ss`.
    static func elapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(0, interval))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Duration in Minutes

    /// Formats minutes as a human-readable string. e.g. "1h 30m", "45m"
    static func durationMinutes(_ minutes: Double) -> String {
        let value = Int(round(minutes))
        if value >= 60 {
            return "\(value / 60)h \(value % 60)m"
        }
        return "\(value)m"
    }

    // MARK: - Calendar Helpers

    /// Returns the start of the week (Sunday) for a given date.
    static func startOfWeekSunday(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    // MARK: - Insight Helpers

    /// Sanitizes insight messages for display by removing technical deltas and ratios.
    static func sanitizedHighlightValue(from message: String) -> String {
        let parts = message
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let filtered = parts.filter { part in
            let lower = part.lowercased()
            return !lower.contains("delta") && !lower.contains("n=") && !lower.contains("ratio")
        }

        if !filtered.isEmpty {
            return filtered.joined(separator: " • ")
        }
        return message
    }

    /// Returns the theme color associated with an insight type.
    static func highlightTint(for type: InsightType) -> Color {
        switch type {
        case .personalRecord:
            return Theme.Colors.gold
        case .strengthGain:
            return Theme.Colors.success
        case .baseline:
            return Theme.Colors.accentSecondary
        case .progressiveOverload:
            return Theme.Colors.accent
        case .milestone:
            return Theme.Colors.warning
        case .consistency:
            return Theme.Colors.error
        }
    }
}
