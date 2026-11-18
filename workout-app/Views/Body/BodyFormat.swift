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

    /// Recent timestamps or the date alone for older readings.
    static func whenWeighed(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "today, \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday, \(time)"
        }
        return shortDate(date, calendar: calendar)
    }

    /// "Last 4 weeks" for whole weeks, otherwise "Last 18 days".
    static func window(days: Int) -> String {
        days.isMultiple(of: 7) ? "Last \(days / 7) weeks" : "Last \(days) days"
    }

    static func trendPeriod(days: Int, through end: Date, now: Date, calendar: Calendar) -> String {
        let age = calendar.dateComponents([.day], from: end, to: calendar.startOfDay(for: now)).day ?? 0
        guard (days > 28 || age > 7), let start = calendar.date(byAdding: .day, value: 1 - days, to: end) else {
            return window(days: days)
        }
        return "\(shortDate(start, calendar: calendar)) – \(shortDate(end, calendar: calendar))"
    }

    static func directionSymbol(for rate: BodyRate) -> String {
        if rate.isSteady { return "arrow.right" }
        return rate.perWeek < 0 ? "arrow.down.right" : "arrow.up.right"
    }

    static func rateHeadline(_ rate: BodyRate, kind: BodyCompositionMetricKind = .weight) -> String {
        if rate.isSteady { return abs(rate.change) < 0.5 ? "Steady" : "No clear change" }
        let unit = kind == .weight ? "lb" : "pts"
        return "\(rate.perWeek < 0 ? "Down" : "Up") \(number(abs(rate.perWeek))) \(unit) a week"
    }

}
