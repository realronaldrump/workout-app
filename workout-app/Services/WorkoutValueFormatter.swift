import Foundation

enum WorkoutValueFormatter {
    nonisolated static func weightText(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(weight))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), weight)
    }
}
