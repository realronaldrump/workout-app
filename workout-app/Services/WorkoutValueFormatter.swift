import Foundation

enum WorkoutValueFormatter {
    nonisolated static func numberText(_ value: Double, decimals: Int) -> String {
        if value.isFinite,
           value.truncatingRemainder(dividingBy: 1) == 0,
           abs(value) < 1e15 {
            return String(Int(value))
        }
        let format = "%.\(decimals)f"
        return String(format: format, locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// Editable values must round-trip unchanged. Fixed display precision silently
    /// changed fractional plates (1.25 -> 1.2) when a field was copied or committed.
    nonisolated static func weightText(_ weight: Double) -> String {
        editableNumberText(weight)
    }

    nonisolated static func distanceText(_ distance: Double) -> String {
        editableNumberText(distance)
    }

    nonisolated private static func editableNumberText(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == 0 { return "0" }
        let text = String(value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    /// Format seconds as `m:ss` or `h:mm:ss`, retaining fractional seconds.
    /// Invalid imported values must never trap during floating-point conversion.
    nonisolated static func durationText(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "" }
        let wholeSeconds = Int(seconds)
        let hours = wholeSeconds / 3600
        let minutes = (wholeSeconds % 3600) / 60
        let secs = wholeSeconds % 60
        let base = hours > 0
            ? "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", secs))"
            : "\(minutes):\(String(format: "%02d", secs))"

        // Decimal text avoids subtraction artifacts such as 61.1 - 61 producing
        // 0.10000000000000142. It also expands tiny scientific-notation fractions.
        let decimalText = NSDecimalNumber(string: String(seconds), locale: Locale(identifier: "en_US_POSIX")).stringValue
        guard let point = decimalText.firstIndex(of: ".") else { return base }
        let fraction = decimalText[decimalText.index(after: point)...]
        return fraction.allSatisfy({ $0 == "0" }) ? base : "\(base).\(fraction)"
    }

    /// Accept either keypad decimal separator, but never nonfinite values,
    /// hexadecimal literals, or ambiguous/malformed numeric strings.
    nonisolated static func parseDecimal(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard normalized.range(
            of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#,
            options: .regularExpression
        ) != nil, let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    /// Accept pasted whole decimals like `8.0`, without silently rounding `8.5`.
    nonisolated static func parseWholeNumber(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let integer = Int(trimmed), integer >= 0 { return integer }
        guard let value = parseDecimal(trimmed), value >= 0, value < Double(Int.max),
              value.rounded(.towardZero) == value else { return nil }
        return Int(value)
    }

    /// Parses minutes (`12.5`), `m:ss`, or `h:mm:ss`. Colon components must
    /// be present; minutes after hours and seconds must each be below 60.
    nonisolated static func parseDurationSeconds(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let totalSeconds: Double

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 || parts.count == 3,
                  parts.dropLast().allSatisfy({ part in
                      !part.isEmpty && part.allSatisfy { $0 >= "0" && $0 <= "9" }
                  }),
                  let first = Double(parts[0]), first.isFinite,
                  let last = parts.last,
                  last.range(of: #"^[0-9]+(?:[.,][0-9]+)?$"#, options: .regularExpression) != nil,
                  let seconds = parseDecimal(last), seconds >= 0, seconds < 60 else { return nil }

            if parts.count == 3 {
                guard let minutes = Double(parts[1]), minutes >= 0, minutes < 60 else { return nil }
                totalSeconds = first * 3600 + minutes * 60 + seconds
            } else {
                totalSeconds = first * 60 + seconds
            }
        } else {
            guard let minutes = parseDecimal(trimmed), minutes >= 0 else { return nil }
            totalSeconds = minutes * 60
        }

        guard totalSeconds.isFinite, totalSeconds >= 0, totalSeconds < Double(Int.max) else { return nil }
        return totalSeconds
    }
}
