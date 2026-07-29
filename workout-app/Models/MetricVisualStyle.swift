import SwiftUI
import UIKit

/// How a metric's series should be drawn.
nonisolated enum MetricChartForm: Sendable {
    /// Discrete daily totals that reset at midnight. Reads best as columns.
    case bars
    /// A continuously drifting measurement. Reads best as a line over a typical-range band.
    case ribbon
}

/// Which direction of change counts as an improvement.
nonisolated enum MetricPolarity: Sendable {
    case higherIsBetter
    case lowerIsBetter
    case neutral

    /// Returns true when `value` sits on the favourable side of `reference`.
    nonisolated func isFavourable(_ value: Double, comparedTo reference: Double) -> Bool {
        switch self {
        case .higherIsBetter: return value > reference
        case .lowerIsBetter: return value < reference
        case .neutral: return false
        }
    }
}

/// Per-metric visual identity.
///
/// Health metrics used to inherit a single color from their category, so a screen
/// showing eight activity metrics rendered as eight identical yellow cards. Each
/// metric now owns a distinct hue drawn from this curated palette.
enum MetricVisualStyle {
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    // Hues are spread far enough apart that every metric inside a single category
    // stays distinguishable at a glance. Light values are dark enough to carry text
    // on ivory; dark values are bright enough to carry a line on charcoal.
    static let amber   = adaptive(light: 0xC2710C, dark: 0xFBBF24)
    static let flame   = adaptive(light: 0xDC2626, dark: 0xFB923C)
    static let ember   = adaptive(light: 0x9A3412, dark: 0xFDBA74)
    static let lime    = adaptive(light: 0x4D7C0F, dark: 0xA3E635)
    static let emerald = adaptive(light: 0x047857, dark: 0x34D399)
    static let teal    = adaptive(light: 0x0F766E, dark: 0x2DD4BF)
    static let cyan    = adaptive(light: 0x0E7490, dark: 0x22D3EE)
    static let indigo  = adaptive(light: 0x4338CA, dark: 0x818CF8)
    static let violet  = adaptive(light: 0x6D28D9, dark: 0xA78BFA)
    static let crimson = adaptive(light: 0xBE123C, dark: 0xFB7185)
    static let rose    = adaptive(light: 0xBE185D, dark: 0xF472B6)
    static let fuchsia = adaptive(light: 0xA21CAF, dark: 0xE879F9)
    static let plum    = adaptive(light: 0x7E22CE, dark: 0xD8B4FE)
    static let sky     = adaptive(light: 0x0369A1, dark: 0x38BDF8)
    static let azure   = adaptive(light: 0x1D4ED8, dark: 0x60A5FA)
    static let gold    = adaptive(light: 0xA16207, dark: 0xFACC15)
}

extension HealthMetric {

    /// The metric's own hue. Distinct from every sibling in the same category.
    var accentColor: Color {
        switch self {
        // Activity — eight hues spread across the wheel so the category screen
        // reads as a set of individuals rather than one repeated card.
        case .steps: return MetricVisualStyle.amber
        case .activeEnergy: return MetricVisualStyle.flame
        case .basalEnergy: return MetricVisualStyle.ember
        case .exerciseMinutes: return MetricVisualStyle.lime
        case .moveMinutes: return MetricVisualStyle.emerald
        case .standMinutes: return MetricVisualStyle.teal
        case .distanceWalkingRunning: return MetricVisualStyle.cyan
        case .flightsClimbed: return MetricVisualStyle.indigo

        case .sleep: return MetricVisualStyle.violet

        // Heart
        case .restingHeartRate: return MetricVisualStyle.crimson
        case .walkingHeartRateAverage: return MetricVisualStyle.rose
        case .heartRateVariability: return MetricVisualStyle.fuchsia
        case .heartRateRecovery: return MetricVisualStyle.plum

        // Vitals
        case .bloodOxygen: return MetricVisualStyle.sky
        case .respiratoryRate: return MetricVisualStyle.azure
        case .bodyTemperature: return MetricVisualStyle.gold

        case .vo2Max: return MetricVisualStyle.emerald

        // Body
        case .bodyMass: return MetricVisualStyle.indigo
        case .bodyFatPercentage: return MetricVisualStyle.amber
        }
    }

    /// Secondary hue for gradient strokes and fills. Sits a step around the wheel
    /// from `accentColor` so lines have depth instead of reading as flat ink.
    var accentColorSecondary: Color {
        switch self {
        case .steps: return MetricVisualStyle.flame
        case .activeEnergy: return MetricVisualStyle.amber
        case .basalEnergy: return MetricVisualStyle.amber
        case .exerciseMinutes: return MetricVisualStyle.emerald
        case .moveMinutes: return MetricVisualStyle.teal
        case .standMinutes: return MetricVisualStyle.cyan
        case .distanceWalkingRunning: return MetricVisualStyle.sky
        case .flightsClimbed: return MetricVisualStyle.violet
        case .sleep: return MetricVisualStyle.indigo
        case .restingHeartRate: return MetricVisualStyle.rose
        case .walkingHeartRateAverage: return MetricVisualStyle.crimson
        case .heartRateVariability: return MetricVisualStyle.plum
        case .heartRateRecovery: return MetricVisualStyle.fuchsia
        case .bloodOxygen: return MetricVisualStyle.cyan
        case .respiratoryRate: return MetricVisualStyle.sky
        case .bodyTemperature: return MetricVisualStyle.ember
        case .vo2Max: return MetricVisualStyle.lime
        case .bodyMass: return MetricVisualStyle.violet
        case .bodyFatPercentage: return MetricVisualStyle.ember
        }
    }

    /// Stroke gradient for line and bar marks.
    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentColorSecondary, accentColor],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    nonisolated var chartForm: MetricChartForm {
        switch self {
        case .steps, .activeEnergy, .basalEnergy, .exerciseMinutes, .moveMinutes,
             .standMinutes, .distanceWalkingRunning, .flightsClimbed, .sleep:
            return .bars
        case .restingHeartRate, .walkingHeartRateAverage, .heartRateVariability,
             .heartRateRecovery, .bloodOxygen, .respiratoryRate, .bodyTemperature,
             .vo2Max, .bodyMass, .bodyFatPercentage:
            return .ribbon
        }
    }

    /// Whether the value climbs through the day and is therefore incomplete until
    /// midnight. Today's partial total must never headline a period summary.
    nonisolated var accumulatesDuringDay: Bool {
        switch self {
        // Sleep is logged once per night rather than accruing through the day.
        case .sleep: return false
        default: return chartForm == .bars
        }
    }

    nonisolated var polarity: MetricPolarity {
        switch self {
        case .steps, .activeEnergy, .exerciseMinutes, .moveMinutes, .standMinutes,
             .distanceWalkingRunning, .flightsClimbed, .sleep, .heartRateVariability,
             .heartRateRecovery, .bloodOxygen, .vo2Max:
            return .higherIsBetter
        case .restingHeartRate, .walkingHeartRateAverage, .respiratoryRate:
            return .lowerIsBetter
        case .basalEnergy, .bodyTemperature, .bodyMass, .bodyFatPercentage:
            return .neutral
        }
    }

    /// Lowercase noun used mid-sentence in generated copy. Avoids the
    /// "Your steps is up 11%" grammar the old string interpolation produced.
    nonisolated var narrativeNoun: String {
        switch self {
        case .steps: return "step count"
        case .activeEnergy: return "active energy"
        case .basalEnergy: return "resting energy"
        case .exerciseMinutes: return "exercise time"
        case .moveMinutes: return "move time"
        case .standMinutes: return "stand time"
        case .distanceWalkingRunning: return "walking distance"
        case .flightsClimbed: return "flight count"
        case .sleep: return "sleep"
        case .restingHeartRate: return "resting heart rate"
        case .walkingHeartRateAverage: return "walking heart rate"
        case .heartRateVariability: return "HRV"
        case .heartRateRecovery: return "heart rate recovery"
        case .bloodOxygen: return "blood oxygen"
        case .respiratoryRate: return "respiratory rate"
        case .bodyTemperature: return "body temperature"
        case .vo2Max: return "VO2 max"
        case .bodyMass: return "body mass"
        case .bodyFatPercentage: return "body fat"
        }
    }

    /// Noun for one observation of this metric ("day" for steps, "night" for sleep).
    nonisolated var dailyNoun: String {
        self == .sleep ? "night" : "day"
    }

    /// Formats a value already in display units and attaches its unit.
    func formatWithUnit(_ displayValue: Double) -> String {
        let formatted = formatDisplay(displayValue)
        switch displayUnit {
        case "": return formatted
        case "%": return "\(formatted)%"
        case "°C": return "\(formatted)°C"
        default: return "\(formatted) \(displayUnit)"
        }
    }
}
