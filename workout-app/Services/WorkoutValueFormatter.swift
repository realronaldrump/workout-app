import Foundation

enum WorkoutValueFormatter {
    nonisolated static func weightText(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(weight))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), weight)
    }

    nonisolated static func rpeText(_ rpe: Double) -> String {
        let rounded = (rpe * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }
}
