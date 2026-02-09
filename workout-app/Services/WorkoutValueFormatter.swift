import Foundation

enum WorkoutValueFormatter {
    nonisolated static func numberText(_ value: Double, decimals: Int) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        let format = "%.\(decimals)f"
        return String(format: format, locale: Locale(identifier: "en_US_POSIX"), value)
    }

    nonisolated static func weightText(_ weight: Double) -> String {
        numberText(weight, decimals: 1)
    }

    nonisolated static func distanceText(_ distance: Double) -> String {
        numberText(distance, decimals: 2)
    }

    /// Format seconds as `m:ss` or `h:mm:ss`.
    nonisolated static func durationText(seconds: Double) -> String {
        let totalSeconds = max(0, Int(round(seconds)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Parses duration from:
    /// - `h:mm:ss` or `m:ss` (contains `:`)
    /// - a plain number (treated as minutes; may be decimal)
    nonisolated static func parseDurationSeconds(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").map { String($0) }
            let ints = parts.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard ints.count == parts.count else { return nil }

            if ints.count == 3 {
                return Double(ints[0] * 3600 + ints[1] * 60 + ints[2])
            }
            if ints.count == 2 {
                return Double(ints[0] * 60 + ints[1])
            }
            return nil
        }

        // Treat as minutes (supports decimals like 12.5).
        if let minutes = Double(trimmed) {
            return minutes * 60.0
        }
        return nil
    }
}
