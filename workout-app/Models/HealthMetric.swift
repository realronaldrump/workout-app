import SwiftUI
import HealthKit

enum HealthHubCategory: String, CaseIterable, Identifiable {
    case activity
    case sleep
    case heart
    case vitals
    case cardio
    case body
    case sessions

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "Activity"
        case .sleep: return "Sleep"
        case .heart: return "Heart"
        case .vitals: return "Vitals"
        case .cardio: return "Cardio"
        case .body: return "Body"
        case .sessions: return "Workout health"
        }
    }

    var subtitle: String {
        switch self {
        case .activity: return "Steps, energy, exercise, and standing"
        case .sleep: return "Time asleep and sleep stages"
        case .heart: return "Resting rate, HRV, and recovery"
        case .vitals: return "Blood oxygen, breathing, temperature"
        case .cardio: return "VO2 max"
        case .body: return "Weight and body fat"
        case .sessions: return "Heart rate and sleep around workouts"
        }
    }

    var icon: String {
        switch self {
        case .activity: return "flame.fill"
        case .sleep: return "moon.zzz.fill"
        case .heart: return "heart.fill"
        case .vitals: return "cross.case.fill"
        case .cardio: return "figure.run"
        case .body: return "figure.arms.open"
        case .sessions: return "waveform.path.ecg.rectangle"
        }
    }

    /// A category borrows its lead metric's hue so the hub and its screens agree.
    var tint: Color {
        switch self {
        case .activity: return HealthMetric.steps.accentColor
        case .sleep: return HealthMetric.sleep.accentColor
        case .heart: return HealthMetric.restingHeartRate.accentColor
        case .vitals: return HealthMetric.bloodOxygen.accentColor
        case .cardio: return HealthMetric.vo2Max.accentColor
        case .body: return HealthMetric.bodyMass.accentColor
        case .sessions: return Theme.Colors.textPrimary
        }
    }

    var primaryMetric: HealthMetric? {
        switch self {
        case .activity: return .steps
        case .sleep: return .sleep
        case .heart: return .restingHeartRate
        case .vitals: return .bloodOxygen
        case .cardio: return .vo2Max
        case .body: return .bodyMass
        case .sessions: return nil
        }
    }
}

enum HealthMetric: String, CaseIterable, Identifiable, Sendable {
    case steps
    case activeEnergy
    case basalEnergy
    case exerciseMinutes
    case moveMinutes
    case standMinutes
    case distanceWalkingRunning
    case flightsClimbed

    case sleep

    case restingHeartRate
    case walkingHeartRateAverage
    case heartRateVariability
    case heartRateRecovery

    case bloodOxygen
    case respiratoryRate
    case bodyTemperature

    case vo2Max

    case bodyMass
    case bodyFatPercentage

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Steps"
        case .activeEnergy: return "Active energy"
        case .basalEnergy: return "Resting energy"
        case .exerciseMinutes: return "Exercise minutes"
        case .moveMinutes: return "Move minutes"
        case .standMinutes: return "Stand minutes"
        case .distanceWalkingRunning: return "Walking + running"
        case .flightsClimbed: return "Flights climbed"
        case .sleep: return "Sleep"
        case .restingHeartRate: return "Resting heart rate"
        case .walkingHeartRateAverage: return "Walking heart rate"
        case .heartRateVariability: return "HRV (SDNN)"
        case .heartRateRecovery: return "Heart rate recovery"
        case .bloodOxygen: return "Blood oxygen"
        case .respiratoryRate: return "Respiratory rate"
        case .bodyTemperature: return "Body temperature"
        case .vo2Max: return "VO2 max"
        case .bodyMass: return "Body mass"
        case .bodyFatPercentage: return "Body fat"
        }
    }

    var category: HealthHubCategory {
        switch self {
        case .steps, .activeEnergy, .basalEnergy, .exerciseMinutes, .moveMinutes, .standMinutes, .distanceWalkingRunning, .flightsClimbed:
            return .activity
        case .sleep:
            return .sleep
        case .restingHeartRate, .walkingHeartRateAverage, .heartRateVariability, .heartRateRecovery:
            return .heart
        case .bloodOxygen, .respiratoryRate, .bodyTemperature:
            return .vitals
        case .vo2Max:
            return .cardio
        case .bodyMass, .bodyFatPercentage:
            return .body
        }
    }

    var icon: String {
        switch self {
        case .steps: return "figure.walk"
        case .activeEnergy: return "flame.fill"
        case .basalEnergy: return "bolt.heart"
        case .exerciseMinutes: return "bolt.fill"
        case .moveMinutes: return "figure.walk.motion"
        case .standMinutes: return "figure.stand"
        case .distanceWalkingRunning: return "ruler"
        case .flightsClimbed: return "arrow.up.right.circle"
        case .sleep: return "moon.zzz.fill"
        case .restingHeartRate: return "heart"
        case .walkingHeartRateAverage: return "heart.circle"
        case .heartRateVariability: return "waveform.path.ecg"
        case .heartRateRecovery: return "heart.text.square"
        case .bloodOxygen: return "lungs.fill"
        case .respiratoryRate: return "wind"
        case .bodyTemperature: return "thermometer"
        case .vo2Max: return "figure.run"
        case .bodyMass: return "scalemass"
        case .bodyFatPercentage: return "percent"
        }
    }

    /// Every metric used to inherit its category's single color, which rendered a
    /// category screen as a stack of identical cards. Each metric now owns a hue —
    /// see `accentColor` in `MetricVisualStyle.swift`.
    var chartColor: Color { accentColor }

    var quantityType: HKQuantityTypeIdentifier? {
        switch self {
        case .sleep:
            return nil
        case .steps:
            return .stepCount
        case .activeEnergy:
            return .activeEnergyBurned
        case .basalEnergy:
            return .basalEnergyBurned
        case .exerciseMinutes:
            return .appleExerciseTime
        case .moveMinutes:
            return .appleMoveTime
        case .standMinutes:
            return .appleStandTime
        case .distanceWalkingRunning:
            return .distanceWalkingRunning
        case .flightsClimbed:
            return .flightsClimbed
        case .restingHeartRate:
            return .restingHeartRate
        case .walkingHeartRateAverage:
            return .walkingHeartRateAverage
        case .heartRateVariability:
            return .heartRateVariabilitySDNN
        case .heartRateRecovery:
            return .heartRateRecoveryOneMinute
        case .bloodOxygen:
            return .oxygenSaturation
        case .respiratoryRate:
            return .respiratoryRate
        case .bodyTemperature:
            return .bodyTemperature
        case .vo2Max:
            return .vo2Max
        case .bodyMass:
            return .bodyMass
        case .bodyFatPercentage:
            return .bodyFatPercentage
        }
    }

    var statisticsOption: HKStatisticsOptions? {
        switch self {
        case .sleep:
            return nil
        case .steps,
             .activeEnergy,
             .basalEnergy,
             .exerciseMinutes,
             .moveMinutes,
             .standMinutes,
             .distanceWalkingRunning,
             .flightsClimbed:
            return .cumulativeSum
        case .restingHeartRate,
             .walkingHeartRateAverage,
             .heartRateVariability,
             .heartRateRecovery,
             .bloodOxygen,
             .respiratoryRate,
             .bodyTemperature,
             .vo2Max,
             .bodyMass,
             .bodyFatPercentage:
            return .discreteAverage
        }
    }

    var unit: HKUnit? {
        switch self {
        case .sleep:
            return nil
        case .steps:
            return .count()
        case .activeEnergy, .basalEnergy:
            return .kilocalorie()
        case .exerciseMinutes, .moveMinutes, .standMinutes:
            return .minute()
        case .distanceWalkingRunning:
            return .meter()
        case .flightsClimbed:
            return .count()
        case .restingHeartRate, .walkingHeartRateAverage, .heartRateRecovery:
            return HKUnit(from: "count/min")
        case .heartRateVariability:
            return HKUnit.secondUnit(with: .milli)
        case .bloodOxygen:
            return .percent()
        case .respiratoryRate:
            return HKUnit(from: "count/min")
        case .bodyTemperature:
            return .degreeCelsius()
        case .vo2Max:
            return HKUnit(from: "ml/(kg*min)")
        case .bodyMass:
            return .gramUnit(with: .kilo)
        case .bodyFatPercentage:
            return .percent()
        }
    }

    var displayUnit: String {
        switch self {
        case .steps: return "steps"
        case .activeEnergy, .basalEnergy: return "cal"
        case .exerciseMinutes, .moveMinutes, .standMinutes: return "min"
        case .distanceWalkingRunning: return "mi"
        case .flightsClimbed: return "flights"
        case .sleep: return "h"
        case .restingHeartRate, .walkingHeartRateAverage, .heartRateRecovery: return "bpm"
        case .heartRateVariability: return "ms"
        case .bloodOxygen: return "%"
        case .respiratoryRate: return "br/min"
        case .bodyTemperature: return "°C"
        case .vo2Max: return "ml/kg/min"
        case .bodyMass: return "lb"
        case .bodyFatPercentage: return "%"
        }
    }

    var supportsSamples: Bool {
        switch self {
        case .restingHeartRate,
             .walkingHeartRateAverage,
             .heartRateVariability,
             .bloodOxygen,
             .respiratoryRate,
             .bodyTemperature,
             .bodyMass,
             .bodyFatPercentage:
            return true
        default:
            return false
        }
    }

    nonisolated var valueMultiplier: Double {
        switch self {
        case .bloodOxygen:
            return 100
        default:
            return 1
        }
    }

    nonisolated func storedValue(from raw: Double) -> Double {
        raw * valueMultiplier
    }

    /// Converts a stored value into the units shown in the UI (matches `displayUnit`).
    /// - Important: This is used for chart axes/interaction so the user sees the same units everywhere.
    nonisolated func displayValue(from stored: Double) -> Double {
        switch self {
        case .distanceWalkingRunning:
            return stored / 1609.34
        case .bodyMass:
            return stored * 2.20462
        case .bodyFatPercentage:
            return stored * 100
        default:
            return stored
        }
    }

    /// Formats a value that is already in display units (matches `displayValue(from:)`).
    func formatDisplay(_ displayValue: Double) -> String {
        switch self {
        case .steps:
            return Int(displayValue).formatted()
        case .activeEnergy, .basalEnergy:
            return Int(displayValue).formatted()
        case .exerciseMinutes, .moveMinutes, .standMinutes:
            return Int(displayValue).formatted()
        case .distanceWalkingRunning:
            return String(format: "%.2f", displayValue)
        case .flightsClimbed:
            return "\(Int(displayValue))"
        case .sleep:
            return String(format: "%.1f", displayValue)
        case .restingHeartRate, .walkingHeartRateAverage, .heartRateRecovery:
            return "\(Int(displayValue))"
        case .heartRateVariability:
            return "\(Int(displayValue))"
        case .bloodOxygen:
            return String(format: "%.0f", displayValue)
        case .respiratoryRate:
            return String(format: "%.1f", displayValue)
        case .bodyTemperature:
            return String(format: "%.1f", displayValue)
        case .vo2Max:
            return String(format: "%.1f", displayValue)
        case .bodyMass:
            return String(format: "%.1f", displayValue)
        case .bodyFatPercentage:
            return String(format: "%.1f", displayValue)
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .steps:
            return Int(value).formatted()
        case .activeEnergy, .basalEnergy:
            return Int(value).formatted()
        case .exerciseMinutes, .moveMinutes, .standMinutes:
            return Int(value).formatted()
        case .distanceWalkingRunning:
            return String(format: "%.2f", value / 1609.34)
        case .flightsClimbed:
            return "\(Int(value))"
        case .sleep:
            return String(format: "%.1f", value)
        case .restingHeartRate, .walkingHeartRateAverage, .heartRateRecovery:
            return "\(Int(value))"
        case .heartRateVariability:
            return "\(Int(value))"
        case .bloodOxygen:
            return String(format: "%.0f", value)
        case .respiratoryRate:
            return String(format: "%.1f", value)
        case .bodyTemperature:
            return String(format: "%.1f", value)
        case .vo2Max:
            return String(format: "%.1f", value)
        case .bodyMass:
            return String(format: "%.1f", value * 2.20462)
        case .bodyFatPercentage:
            return String(format: "%.1f", value * 100)
        }
    }

    static var dailyQuantityMetrics: [HealthMetric] {
        allCases.filter { $0.quantityType != nil }
    }

    static func metrics(for category: HealthHubCategory) -> [HealthMetric] {
        allCases.filter { $0.category == category }
    }
}

nonisolated struct HealthMetricSample: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let value: Double

    init(id: UUID = UUID(), timestamp: Date, value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}
