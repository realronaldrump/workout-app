import Foundation

/// Calendar-based, end-exclusive ranges for body measurements. Preset day counts
/// include today; custom selections include every instant of the selected end day.
enum BodyMeasurementDateRange {
    static func resolve(
        selection: AppTimeRange,
        reference: Date,
        earliest: Date? = nil,
        custom: DateInterval? = nil,
        calendar: Calendar = .current
    ) -> DateInterval {
        let today = calendar.startOfDay(for: reference)
        let start: Date
        var end = reference

        switch selection {
        case .week:
            start = startOfRecentDays(7, today: today, calendar: calendar)
        case .fourWeeks:
            start = startOfRecentDays(28, today: today, calendar: calendar)
        case .sixWeeks:
            start = startOfRecentDays(42, today: today, calendar: calendar)
        case .threeMonths:
            start = calendar.date(byAdding: .month, value: -3, to: today) ?? today
        case .sixMonths:
            start = calendar.date(byAdding: .month, value: -6, to: today) ?? today
        case .year:
            start = calendar.date(byAdding: .year, value: -1, to: today) ?? today
        case .allTime:
            start = earliest.map { calendar.startOfDay(for: $0) }
                ?? startOfRecentDays(30, today: today, calendar: calendar)
        case .custom:
            if let custom {
                start = calendar.startOfDay(for: custom.start)
                let lastSelectedDay = calendar.startOfDay(for: custom.end)
                let nextDay = calendar.date(byAdding: .day, value: 1, to: lastSelectedDay) ?? custom.end
                end = min(nextDay, reference)
            } else {
                start = startOfRecentDays(30, today: today, calendar: calendar)
            }
        }

        // A selection entirely in the future resolves to an empty range at now.
        // Clamping before construction also protects against invalid reversed bounds.
        return DateInterval(start: min(start, end), end: end)
    }

    fileprivate static func startOfRecentDays(_ count: Int, today: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
    }
}

enum BodyChartRange: String, CaseIterable, Identifiable {
    case sinceStart = "Since start"
    case week = "7D"
    case twoWeeks = "14D"
    case fourWeeks = "4W"
    case eightWeeks = "8W"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case yearToDate = "YTD"
    case year = "1Y"
    case twoYears = "2Y"
    case all = "All"

    var id: String { rawValue }

    private var days: Int? {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .fourWeeks: return 28
        case .eightWeeks: return 56
        case .threeMonths: return 91
        case .sixMonths: return 182
        case .year: return 365
        case .twoYears: return 730
        case .sinceStart, .yearToDate, .all: return nil
        }
    }

    var title: String {
        switch self {
        case .sinceStart: return "Since start"
        case .week: return "7 days"
        case .twoWeeks: return "14 days"
        case .fourWeeks: return "4 weeks"
        case .eightWeeks: return "8 weeks"
        case .threeMonths: return "3 months"
        case .sixMonths: return "6 months"
        case .yearToDate: return "Year to date"
        case .year: return "1 year"
        case .twoYears: return "2 years"
        case .all: return "All time"
        }
    }

    var comparesPreviousPeriod: Bool { days != nil }

    /// Include every calendar day through today. Statistics and chart bounds share this start.
    func interval(reference: Date, earliest: Date?, comparisonStart: Date?, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: reference)
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? reference
        let start: Date
        switch self {
        case .sinceStart:
            start = comparisonStart.map { calendar.startOfDay(for: $0) }
                ?? BodyMeasurementDateRange.startOfRecentDays(91, today: today, calendar: calendar)
        case .yearToDate:
            start = calendar.dateInterval(of: .year, for: today)?.start ?? today
        case .all:
            start = earliest.map { calendar.startOfDay(for: $0) } ?? today
        default:
            start = BodyMeasurementDateRange.startOfRecentDays(days ?? 91, today: today, calendar: calendar)
        }
        return DateInterval(start: min(start, today), end: end)
    }

    func showsReadings(in interval: DateInterval, calendar: Calendar) -> Bool {
        guard self != .all else { return false }
        return (calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0) <= 182
    }
}
