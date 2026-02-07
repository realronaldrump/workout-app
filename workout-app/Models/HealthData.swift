import Foundation

// MARK: - Core Health Data Model

/// Represents all health data synced from Apple Health for a specific workout window
struct WorkoutHealthData: Identifiable, Codable {
    let id: UUID
    let workoutId: UUID
    let workoutDate: Date
    let workoutStartTime: Date
    let workoutEndTime: Date
    let syncedAt: Date

    // MARK: - Heart Rate Data
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var minHeartRate: Double?
    var heartRateSamples: [HeartRateSample]

    // MARK: - Calorie Data
    var activeCalories: Double?
    var basalCalories: Double?
    var totalCalories: Double? {
        guard let active = activeCalories, let basal = basalCalories else {
            return activeCalories ?? basalCalories
        }
        return active + basal
    }

    // MARK: - Workout Metrics
    var distance: Double? // in meters
    var avgSpeed: Double? // in m/s
    var avgPower: Double? // in watts
    var stepCount: Int?
    var flightsClimbed: Int?

    // MARK: - Recovery & Vitals
    var hrvSamples: [HRVSample]
    var avgHRV: Double? {
        guard !hrvSamples.isEmpty else { return nil }
        return hrvSamples.map { $0.value }.reduce(0, +) / Double(hrvSamples.count)
    }

    var restingHeartRate: Double?
    var bloodOxygenSamples: [BloodOxygenSample]
    var avgBloodOxygen: Double? {
        guard !bloodOxygenSamples.isEmpty else { return nil }
        return bloodOxygenSamples.map { $0.value }.reduce(0, +) / Double(bloodOxygenSamples.count)
    }

    var respiratoryRateSamples: [RespiratoryRateSample]
    var avgRespiratoryRate: Double? {
        guard !respiratoryRateSamples.isEmpty else { return nil }
        return respiratoryRateSamples.map { $0.value }.reduce(0, +) / Double(respiratoryRateSamples.count)
    }

    // MARK: - Body Measurements (captured around workout time)
    var bodyMass: Double? // in kg
    var bodyFatPercentage: Double?
    var bodyTemperature: Double? // in Celsius

    // MARK: - Sleep Summary
    var sleepSummary: SleepSummary?

    // MARK: - Daily Activity
    var dailyActiveEnergy: Double?
    var dailyBasalEnergy: Double?
    var dailySteps: Int?
    var dailyExerciseMinutes: Double?
    var dailyMoveMinutes: Double?
    var dailyStandMinutes: Double?

    // MARK: - Cardio Fitness
    var vo2Max: Double?
    var heartRateRecovery: Double?
    var walkingHeartRateAverage: Double?

    // MARK: - Workout from Apple Health
    var appleWorkoutType: String?
    var appleWorkoutDuration: TimeInterval?

    init(
        id: UUID = UUID(),
        workoutId: UUID,
        workoutDate: Date,
        workoutStartTime: Date,
        workoutEndTime: Date,
        syncedAt: Date = Date(),
        avgHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        minHeartRate: Double? = nil,
        heartRateSamples: [HeartRateSample] = [],
        activeCalories: Double? = nil,
        basalCalories: Double? = nil,
        distance: Double? = nil,
        avgSpeed: Double? = nil,
        avgPower: Double? = nil,
        stepCount: Int? = nil,
        flightsClimbed: Int? = nil,
        hrvSamples: [HRVSample] = [],
        restingHeartRate: Double? = nil,
        bloodOxygenSamples: [BloodOxygenSample] = [],
        respiratoryRateSamples: [RespiratoryRateSample] = [],
        bodyMass: Double? = nil,
        bodyFatPercentage: Double? = nil,
        bodyTemperature: Double? = nil,
        sleepSummary: SleepSummary? = nil,
        dailyActiveEnergy: Double? = nil,
        dailyBasalEnergy: Double? = nil,
        dailySteps: Int? = nil,
        dailyExerciseMinutes: Double? = nil,
        dailyMoveMinutes: Double? = nil,
        dailyStandMinutes: Double? = nil,
        vo2Max: Double? = nil,
        heartRateRecovery: Double? = nil,
        walkingHeartRateAverage: Double? = nil,
        appleWorkoutType: String? = nil,
        appleWorkoutDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.workoutDate = workoutDate
        self.workoutStartTime = workoutStartTime
        self.workoutEndTime = workoutEndTime
        self.syncedAt = syncedAt
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.minHeartRate = minHeartRate
        self.heartRateSamples = heartRateSamples
        self.activeCalories = activeCalories
        self.basalCalories = basalCalories
        self.distance = distance
        self.avgSpeed = avgSpeed
        self.avgPower = avgPower
        self.stepCount = stepCount
        self.flightsClimbed = flightsClimbed
        self.hrvSamples = hrvSamples
        self.restingHeartRate = restingHeartRate
        self.bloodOxygenSamples = bloodOxygenSamples
        self.respiratoryRateSamples = respiratoryRateSamples
        self.bodyMass = bodyMass
        self.bodyFatPercentage = bodyFatPercentage
        self.bodyTemperature = bodyTemperature
        self.sleepSummary = sleepSummary
        self.dailyActiveEnergy = dailyActiveEnergy
        self.dailyBasalEnergy = dailyBasalEnergy
        self.dailySteps = dailySteps
        self.dailyExerciseMinutes = dailyExerciseMinutes
        self.dailyMoveMinutes = dailyMoveMinutes
        self.dailyStandMinutes = dailyStandMinutes
        self.vo2Max = vo2Max
        self.heartRateRecovery = heartRateRecovery
        self.walkingHeartRateAverage = walkingHeartRateAverage
        self.appleWorkoutType = appleWorkoutType
        self.appleWorkoutDuration = appleWorkoutDuration
    }

    /// Checks if meaningful health data was synced
    var hasHealthData: Bool {
        avgHeartRate != nil ||
        !heartRateSamples.isEmpty ||
        activeCalories != nil ||
        distance != nil ||
        sleepSummary != nil ||
        dailyActiveEnergy != nil ||
        dailyBasalEnergy != nil ||
        vo2Max != nil ||
        !hrvSamples.isEmpty ||
        !bloodOxygenSamples.isEmpty ||
        appleWorkoutType != nil
    }
}

// MARK: - Sample Types

struct HeartRateSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let value: Double // beats per minute

    init(id: UUID = UUID(), timestamp: Date, value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}

struct HRVSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let value: Double // SDNN in milliseconds

    init(id: UUID = UUID(), timestamp: Date, value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}

struct BloodOxygenSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let value: Double // percentage (0-100)

    init(id: UUID = UUID(), timestamp: Date, value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}

struct RespiratoryRateSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let value: Double // breaths per minute

    init(id: UUID = UUID(), timestamp: Date, value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}

// MARK: - Sync Status

enum HealthSyncStatus: Codable {
    case notSynced
    case syncing
    case synced(Date)
    case failed(String)

    var isSynced: Bool {
        if case .synced = self { return true }
        return false
    }

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}

// MARK: - Authorization Status

enum HealthKitAuthorizationStatus {
    case notDetermined
    case authorized
    case denied
    case unavailable

    var displayText: String {
        switch self {
        case .notDetermined:
            return "Not Set Up"
        case .authorized:
            return "Connected"
        case .denied:
            return "Access Denied"
        case .unavailable:
            return "Not Available"
        }
    }

    var iconName: String {
        switch self {
        case .notDetermined:
            return "questionmark.circle"
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }

    var iconColor: String {
        switch self {
        case .notDetermined:
            return "gray"
        case .authorized:
            return "green"
        case .denied:
            return "red"
        case .unavailable:
            return "orange"
        }
    }
}
