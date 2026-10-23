import SwiftUI

/// Number and date wording for the Body screen, so every section says the same thing the same way.
enum BodyFormat {
    static let weightTint = HealthMetric.bodyMass.accentColor
    static let bodyFatTint = HealthMetric.bodyFatPercentage.accentColor

    /// One decimal, true minus sign.
    static func number(_ value: Double, decimals: Int = 1) -> String {
        let text = String(format: "%.\(decimals)f", abs(value))
        return value < 0 && text != String(format: "%.\(decimals)f", 0.0) ? "−" + text : text
    }

    static func signed(_ value: Double, decimals: Int = 1) -> String {
        let text = String(format: "%.\(decimals)f", abs(value))
        guard text != String(format: "%.\(decimals)f", 0.0) else { return text }
        return (value < 0 ? "−" : "+") + text
    }

    static func weight(_ value: Double) -> String { number(value) + " lb" }
    static func signedWeight(_ value: Double) -> String { signed(value) + " lb" }

    static func value(_ value: Double, kind: BodyCompositionMetricKind) -> String {
        kind == .weight ? weight(value) : number(value) + "%"
    }

    static func signedValue(_ value: Double, kind: BodyCompositionMetricKind) -> String {
        kind == .weight ? signedWeight(value) : signed(value) + " pts"
    }

    /// "Oct 3", or "Oct 3, 2025" outside the current year.
    static func shortDate(_ date: Date, calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Wed, Oct 21".
    static func weekdayDate(_ date: Date, calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    /// "today, 7:42 AM", "yesterday, 7:42 AM", or "Oct 3, 19 days ago".
    static func whenWeighed(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "today, \(time)" }
        if calendar.isDateInYesterday(date) { return "yesterday, \(time)" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        return "\(shortDate(date, calendar: calendar)), \(days) days ago"
    }

    /// "Last 4 weeks" for whole weeks, otherwise "Last 18 days".
    static func window(days: Int) -> String {
        days.isMultiple(of: 7) ? "Last \(days / 7) weeks" : "Last \(days) days"
    }

    static func directionSymbol(for rate: BodyRate) -> String {
        if rate.isSteady { return "arrow.right" }
        return rate.perWeek < 0 ? "arrow.down.right" : "arrow.up.right"
    }

    static func rateHeadline(_ rate: BodyRate, kind: BodyCompositionMetricKind = .weight) -> String {
        if rate.isSteady { return "Holding steady" }
        let unit = kind == .weight ? "lb" : "pts"
        return "\(rate.perWeek < 0 ? "Down" : "Up") \(number(abs(rate.perWeek))) \(unit) a week"
    }

    /// How a reading sits against the trend: "0.7 above trend".
    static func versusTrend(_ difference: Double, kind: BodyCompositionMetricKind = .weight) -> String {
        let amount = number(abs(difference))
        if amount == number(0) { return "on trend" }
        return "\(amount) \(difference > 0 ? "above" : "below") trend"
    }

    static func flagExplanation(_ flag: BodyDayFlag, difference: Double) -> String {
        switch flag {
        case .high:
            return "\(number(abs(difference))) lb above trend. Usually water or food still in the gut, not fat."
        case .low:
            return "\(number(abs(difference))) lb below trend. Usually fluid, not fat."
        }
    }
}
