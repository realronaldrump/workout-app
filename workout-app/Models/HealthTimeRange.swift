import Foundation

enum HealthTimeRange: String, CaseIterable, Identifiable {
    case week = "1w"
    case fourWeeks = "4w"
    case twelveWeeks = "12w"
    case sixMonths = "6m"
    case year = "1y"
    case all = "All"
    case custom = "Custom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "1w"
        case .fourWeeks: return "4w"
        case .twelveWeeks: return "12w"
        case .sixMonths: return "6m"
        case .year: return "1y"
        case .all: return "All"
        case .custom: return "Custom"
        }
    }

    func interval(reference: Date, earliest: Date?, custom: DateInterval) -> DateInterval {
        let calendar = Calendar.current
        switch self {
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .fourWeeks:
            let start = calendar.date(byAdding: .day, value: -28, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .twelveWeeks:
            let start = calendar.date(byAdding: .day, value: -84, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .sixMonths:
            let start = calendar.date(byAdding: .month, value: -6, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .all:
            let start = earliest ?? calendar.date(byAdding: .day, value: -30, to: reference) ?? reference
            return DateInterval(start: start, end: reference)
        case .custom:
            let start = calendar.startOfDay(for: custom.start)
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: custom.end) ?? custom.end
            return DateInterval(start: start, end: min(end, reference))
        }
    }
}
