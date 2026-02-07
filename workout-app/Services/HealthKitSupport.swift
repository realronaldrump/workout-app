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
            return "HealthKit is not available on this device."
        case .authorizationFailed(let message):
            return "Failed to authorize HealthKit access: \(message)"
        case .queryFailed(let message):
            return "Failed to query health data: \(message)"
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
