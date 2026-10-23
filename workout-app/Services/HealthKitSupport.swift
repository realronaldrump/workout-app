import Foundation
import HealthKit

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case authorizationFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Health isn't available on this device."
        case .authorizationFailed(let message):
            return "Couldn't get Health access: \(message)"
        case .queryFailed(let message):
            return "Couldn't read Health data: \(message)"
        }
    }
}

// MARK: - Workout Activity Type Display Name

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .traditionalStrengthTraining:
            return "Strength Training"
        case .functionalStrengthTraining:
            return "Functional Strength"
        case .running:
            return "Running"
        case .cycling:
            return "Cycling"
        case .walking:
            return "Walking"
        case .swimming:
            return "Swimming"
        case .yoga:
            return "Yoga"
        case .pilates:
            return "Pilates"
        case .highIntensityIntervalTraining:
            return "HIIT"
        case .crossTraining:
            return "Cross Training"
        case .flexibility:
            return "Flexibility"
        case .cooldown:
            return "Cooldown"
        case .coreTraining:
            return "Core Training"
        case .elliptical:
            return "Elliptical"
        case .rowing:
            return "Rowing"
        case .stairClimbing:
            return "Stair Climbing"
        default:
            return "Workout"
        }
    }
}

// MARK: - Batch Workout Day Metrics

/// Only values whose query window is identical for every workout on the same day.
/// Workout-window samples and the pre-workout sleep window are intentionally separate.
nonisolated struct WorkoutDayHealthMetrics: Sendable {
    var bodyMass: Double?
    var bodyFatPercentage: Double?
    var bodyTemperature: Double?
    var bloodPressureSystolic: Double?
    var bloodPressureDiastolic: Double?
    var bloodGlucose: Double?
    var basalBodyTemperature: Double?
    var dailyActiveEnergy: Double?
    var dailyBasalEnergy: Double?
    var dietaryWater: Double?
    var dietaryEnergyConsumed: Double?
    var dietaryProtein: Double?
    var dietaryCarbohydrates: Double?
    var dietaryFatTotal: Double?
    var mindfulSessionDuration: Double?
    var dailySteps: Int?
    var dailyExerciseMinutes: Double?
    var dailyMoveMinutes: Double?
    var dailyStandMinutes: Double?
    var vo2Max: Double?
    var heartRateRecovery: Double?
    var walkingHeartRateAverage: Double?

    func apply(to healthData: inout WorkoutHealthData) {
        healthData.bodyMass = bodyMass
        healthData.bodyFatPercentage = bodyFatPercentage
        healthData.bodyTemperature = bodyTemperature
        healthData.bloodPressureSystolic = bloodPressureSystolic
        healthData.bloodPressureDiastolic = bloodPressureDiastolic
        healthData.bloodGlucose = bloodGlucose
        healthData.basalBodyTemperature = basalBodyTemperature
        healthData.dailyActiveEnergy = dailyActiveEnergy
        healthData.dailyBasalEnergy = dailyBasalEnergy
        healthData.dietaryWater = dietaryWater
        healthData.dietaryEnergyConsumed = dietaryEnergyConsumed
        healthData.dietaryProtein = dietaryProtein
        healthData.dietaryCarbohydrates = dietaryCarbohydrates
        healthData.dietaryFatTotal = dietaryFatTotal
        healthData.mindfulSessionDuration = mindfulSessionDuration
        healthData.dailySteps = dailySteps
        healthData.dailyExerciseMinutes = dailyExerciseMinutes
        healthData.dailyMoveMinutes = dailyMoveMinutes
        healthData.dailyStandMinutes = dailyStandMinutes
        healthData.vo2Max = vo2Max
        healthData.heartRateRecovery = heartRateRecovery
        healthData.walkingHeartRateAverage = walkingHeartRateAverage
    }
}

/// Owned by a single sync batch, so a later refresh always reads current HealthKit data.
/// Failed queries are never cached; a subsequent workout can retry the same day.
@MainActor
final class WorkoutDayHealthMetricsCache {
    private var values: [Date: WorkoutDayHealthMetrics] = [:]

    func value(
        for dayStart: Date,
        load: () async throws -> WorkoutDayHealthMetrics
    ) async throws -> WorkoutDayHealthMetrics {
        if let value = values[dayStart] { return value }
        let value = try await load()
        values[dayStart] = value
        return value
    }
}
