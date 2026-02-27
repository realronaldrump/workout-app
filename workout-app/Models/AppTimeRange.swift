import Foundation

/// Unified time range enum for consistent range selection across the app.
/// Each consumer specifies which subset of cases it supports via static arrays.
enum AppTimeRange: String, CaseIterable, Identifiable, Hashable {
    case week       = "1W"
    case fourWeeks  = "4W"
    case sixWeeks   = "6W"
    case threeMonths = "3M"
    case sixMonths  = "6M"
    case year       = "1Y"
    case allTime    = "All"
    case custom     = "Custom"

    var id: String { rawValue }

    /// Short label for pill pickers.
    var shortLabel: String { rawValue }

    /// Longer label for menus/dropdowns.
    var menuTitle: String {
        switch self {
        case .week:        return "Last week"
        case .fourWeeks:   return "Last 4 weeks"
        case .sixWeeks:    return "Last 6 weeks"
        case .threeMonths: return "Last 3 months"
        case .sixMonths:   return "Last 6 months"
        case .year:        return "Last year"
        case .allTime:     return "All time"
        case .custom:      return "Custom range"
        }
    }

    /// Common presets for workout-focused views.
    static let workoutPresets: [AppTimeRange] = [.week, .fourWeeks, .threeMonths, .year, .allTime]

    /// Presets for health-focused views.
    static let healthPresets: [AppTimeRange] = [.week, .fourWeeks, .threeMonths, .sixMonths, .year, .allTime]

    /// Presets for exercise analysis (includes sixWeeks for progress charts).
    static let exercisePresets: [AppTimeRange] = [.sixWeeks, .threeMonths, .sixMonths, .year, .allTime]

    /// Computes the date interval for this range.
    /// - Parameters:
    ///   - reference: The end date (typically `Date()`).
    ///   - earliest: The earliest available data date (used for `.allTime`).
    ///   - custom: Custom date interval (used for `.custom`).
    func interval(
        reference: Date = Date(),
        earliest: Date? = nil,
        custom: DateInterval? = nil
    ) -> DateInterval {
        let calendar = Calendar.current
        switch self {
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .fourWeeks:
            let start = calendar.date(byAdding: .day, value: -28, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .sixWeeks:
            let start = calendar.date(byAdding: .day, value: -42, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .threeMonths:
            let start = calendar.date(byAdding: .month, value: -3, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .sixMonths:
            let start = calendar.date(byAdding: .month, value: -6, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .allTime:
            let start = earliest ?? calendar.date(byAdding: .day, value: -30, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .custom:
            guard let custom else {
                let start = calendar.date(byAdding: .day, value: -30, to: reference) ?? reference
                return DateInterval(start: start, end: reference)
            }
            let start = calendar.startOfDay(for: custom.start)
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: custom.end) ?? custom.end
            return DateInterval(start: start, end: min(end, reference))
        }
    }

    /// Converts from HealthTimeRange for backward compatibility.
    init(from healthRange: HealthTimeRange) {
        switch healthRange {
        case .week:        self = .week
        case .fourWeeks:   self = .fourWeeks
        case .twelveWeeks: self = .threeMonths
        case .sixMonths:   self = .sixMonths
        case .year:        self = .year
        case .all:         self = .allTime
        case .custom:      self = .custom
        }
    }
}
