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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "Activity"
        case .sleep: return "Sleep"
        case .heart: return "Heart"
        case .vitals: return "Vitals"
        case .cardio: return "Cardio"
        case .body: return "Body"
        case .sessions: return "Sessions"
        }
    }

    var subtitle: String {
        switch self {
        case .activity: return "Move, exercise, steps"
        case .sleep: return "Sleep and recovery"
        case .heart: return "Heart trends"
        case .vitals: return "SpO2, respiration, temp"
        case .cardio: return "Fitness metrics"
        case .body: return "Body composition"
        case .sessions: return "Workout insights"
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
        case .sessions: return "clock.arrow.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .activity: return Theme.Colors.warning
        case .sleep: return Theme.Colors.accentSecondary
        case .heart: return Theme.Colors.error
        case .vitals: return Theme.Colors.accent
        case .cardio: return Theme.Colors.success
        case .body: return Theme.Colors.accent
        case .sessions: return Theme.Colors.textPrimary
        }
    }
}

enum HealthMetric: String, CaseIterable, Identifiable {
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Steps"
        case .activeEnergy: return "Active Energy"
        case .basalEnergy: return "Resting Energy"
        case .exerciseMinutes: return "Exercise Minutes"
        case .moveMinutes: return "Move Minutes"
        case .standMinutes: return "Stand Minutes"
        case .distanceWalkingRunning: return "Walking + Running"
        case .flightsClimbed: return "Flights Climbed"
        case .sleep: return "Sleep"
        case .restingHeartRate: return "Resting Heart Rate"
        case .walkingHeartRateAverage: return "Walking Heart Rate"
        case .heartRateVariability: return "HRV (SDNN)"
        case .heartRateRecovery: return "Heart Rate Recovery"
        case .bloodOxygen: return "Blood Oxygen"
        case .respiratoryRate: return "Respiratory Rate"
        case .bodyTemperature: return "Body Temperature"
        case .vo2Max: return "VO2 Max"
        case .bodyMass: return "Body Mass"
        case .bodyFatPercentage: return "Body Fat"
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

    var chartColor: Color {
        switch category {
        case .activity: return Theme.Colors.warning
        case .sleep: return Theme.Colors.accentSecondary
        case .heart: return Theme.Colors.error
        case .vitals: return Theme.Colors.accent
        case .cardio: return Theme.Colors.success
        case .body: return Theme.Colors.accent
        case .sessions: return Theme.Colors.textPrimary
        }
    }

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

    var valueMultiplier: Double {
        switch self {
        case .bloodOxygen:
            return 100
        default:
            return 1
        }
    }

    func storedValue(from raw: Double) -> Double {
        raw * valueMultiplier
    }

    /// Converts a stored value into the units shown in the UI (matches `displayUnit`).
    /// - Important: This is used for chart axes/interaction so the user sees the same units everywhere.
    func displayValue(from stored: Double) -> Double {
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
            return "\(Int(displayValue))"
        case .activeEnergy, .basalEnergy:
            return "\(Int(displayValue))"
        case .exerciseMinutes, .moveMinutes, .standMinutes:
            return "\(Int(displayValue))"
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
            return "\(Int(value))"
        case .activeEnergy, .basalEnergy:
            return "\(Int(value))"
        case .exerciseMinutes, .moveMinutes, .standMinutes:
            return "\(Int(value))"
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

struct HealthMetricSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let value: Double

    init(id: UUID = UUID(), timestamp: Date, value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}
