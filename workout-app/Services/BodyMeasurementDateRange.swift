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

    private static func startOfRecentDays(_ count: Int, today: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
    }
}
