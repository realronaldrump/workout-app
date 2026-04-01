import CoreLocation
import Foundation

nonisolated enum WorkoutLocationSource: String, Codable, Sendable {
    case route
    case metadata
}

// MARK: - Core Health Data Model

/// Represents all health data synced from Apple Health for a specific workout window
nonisolated struct WorkoutHealthData: Identifiable, Codable {
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
    var storedHRVAverage: Double?
    nonisolated var avgHRV: Double? {
        guard !hrvSamples.isEmpty else { return storedHRVAverage }
        return hrvSamples.map { $0.value }.reduce(0, +) / Double(hrvSamples.count)
    }

    var restingHeartRate: Double?
    var bloodOxygenSamples: [BloodOxygenSample]
    var storedBloodOxygenAverage: Double?
    nonisolated var avgBloodOxygen: Double? {
        guard !bloodOxygenSamples.isEmpty else { return storedBloodOxygenAverage }
        return bloodOxygenSamples.map { $0.value }.reduce(0, +) / Double(bloodOxygenSamples.count)
    }

    var respiratoryRateSamples: [RespiratoryRateSample]
    var storedRespiratoryRateAverage: Double?
    nonisolated var avgRespiratoryRate: Double? {
        guard !respiratoryRateSamples.isEmpty else { return storedRespiratoryRateAverage }
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

    // MARK: - Extended Metrics
    var distanceSwimming: Double?
    var swimmingStrokeCount: Int?
    var distanceWheelchair: Double?
    var pushCount: Int?
    var distanceDownhillSnowSports: Double?
    var bloodPressureSystolic: Double?
    var bloodPressureDiastolic: Double?
    var bloodGlucose: Double?
    var basalBodyTemperature: Double?
    var dietaryWater: Double?
    var dietaryEnergyConsumed: Double?
    var dietaryProtein: Double?
    var dietaryCarbohydrates: Double?
    var dietaryFatTotal: Double?
    var mindfulSessionDuration: Double?

    // MARK: - Workout from Apple Health
    var appleWorkoutType: String?
    var appleWorkoutDuration: TimeInterval?
    var appleWorkoutUUID: UUID?

    // MARK: - Workout Route (Start Location)
    /// If present, derived from an `HKWorkoutRoute` associated with the matching Apple workout.
    var workoutRouteStartLatitude: Double?
    var workoutRouteStartLongitude: Double?
    /// Best available workout location derived from Apple Health workout data.
    var workoutLocationLatitude: Double?
    var workoutLocationLongitude: Double?
    var workoutLocationSource: WorkoutLocationSource?

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
        storedHRVAverage: Double? = nil,
        restingHeartRate: Double? = nil,
        bloodOxygenSamples: [BloodOxygenSample] = [],
        storedBloodOxygenAverage: Double? = nil,
        respiratoryRateSamples: [RespiratoryRateSample] = [],
        storedRespiratoryRateAverage: Double? = nil,
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
        appleWorkoutDuration: TimeInterval? = nil,
        appleWorkoutUUID: UUID? = nil,
        workoutRouteStartLatitude: Double? = nil,
        workoutRouteStartLongitude: Double? = nil,
        workoutLocationLatitude: Double? = nil,
        workoutLocationLongitude: Double? = nil,
        workoutLocationSource: WorkoutLocationSource? = nil,
        distanceSwimming: Double? = nil,
        swimmingStrokeCount: Int? = nil,
        distanceWheelchair: Double? = nil,
        pushCount: Int? = nil,
        distanceDownhillSnowSports: Double? = nil,
        bloodPressureSystolic: Double? = nil,
        bloodPressureDiastolic: Double? = nil,
        bloodGlucose: Double? = nil,
        basalBodyTemperature: Double? = nil,
        dietaryWater: Double? = nil,
        dietaryEnergyConsumed: Double? = nil,
        dietaryProtein: Double? = nil,
        dietaryCarbohydrates: Double? = nil,
        dietaryFatTotal: Double? = nil,
        mindfulSessionDuration: Double? = nil
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
        self.storedHRVAverage = storedHRVAverage
        self.restingHeartRate = restingHeartRate
        self.bloodOxygenSamples = bloodOxygenSamples
        self.storedBloodOxygenAverage = storedBloodOxygenAverage
        self.respiratoryRateSamples = respiratoryRateSamples
        self.storedRespiratoryRateAverage = storedRespiratoryRateAverage
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
        self.appleWorkoutUUID = appleWorkoutUUID
        self.workoutRouteStartLatitude = workoutRouteStartLatitude
        self.workoutRouteStartLongitude = workoutRouteStartLongitude
        self.workoutLocationLatitude = workoutLocationLatitude
        self.workoutLocationLongitude = workoutLocationLongitude
        self.workoutLocationSource = workoutLocationSource
        self.distanceSwimming = distanceSwimming
        self.swimmingStrokeCount = swimmingStrokeCount
        self.distanceWheelchair = distanceWheelchair
        self.pushCount = pushCount
        self.distanceDownhillSnowSports = distanceDownhillSnowSports
        self.bloodPressureSystolic = bloodPressureSystolic
        self.bloodPressureDiastolic = bloodPressureDiastolic
        self.bloodGlucose = bloodGlucose
        self.basalBodyTemperature = basalBodyTemperature
        self.dietaryWater = dietaryWater
        self.dietaryEnergyConsumed = dietaryEnergyConsumed
        self.dietaryProtein = dietaryProtein
        self.dietaryCarbohydrates = dietaryCarbohydrates
        self.dietaryFatTotal = dietaryFatTotal
        self.mindfulSessionDuration = mindfulSessionDuration
    }

    var resolvedWorkoutLocationCoordinate: CLLocationCoordinate2D? {
        if let latitude = workoutLocationLatitude, let longitude = workoutLocationLongitude {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        if let latitude = workoutRouteStartLatitude, let longitude = workoutRouteStartLongitude {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        return nil
    }

    var hasRawSamples: Bool {
        !heartRateSamples.isEmpty ||
        !hrvSamples.isEmpty ||
        !bloodOxygenSamples.isEmpty ||
        !respiratoryRateSamples.isEmpty
    }

    nonisolated mutating func captureRawSampleSummaries() {
        if !hrvSamples.isEmpty {
            storedHRVAverage = hrvSamples.map(\.value).reduce(0, +) / Double(hrvSamples.count)
        }
        if !bloodOxygenSamples.isEmpty {
            storedBloodOxygenAverage = bloodOxygenSamples.map(\.value).reduce(0, +) / Double(bloodOxygenSamples.count)
        }
        if !respiratoryRateSamples.isEmpty {
            storedRespiratoryRateAverage = respiratoryRateSamples.map(\.value).reduce(0, +) / Double(respiratoryRateSamples.count)
        }
    }

    nonisolated mutating func removeRawSamplesPreservingSummaries() {
        captureRawSampleSummaries()
        heartRateSamples = []
        hrvSamples = []
        bloodOxygenSamples = []
        respiratoryRateSamples = []
    }

    /// Checks if meaningful health data was synced
    nonisolated var hasHealthData: Bool {
        avgHeartRate != nil ||
        !heartRateSamples.isEmpty ||
        activeCalories != nil ||
        distance != nil ||
        sleepSummary != nil ||
        dailyActiveEnergy != nil ||
        dailyBasalEnergy != nil ||
        vo2Max != nil ||
        avgHRV != nil ||
        avgBloodOxygen != nil ||
        avgRespiratoryRate != nil ||
        appleWorkoutType != nil ||
        distanceSwimming != nil ||
        distanceWheelchair != nil ||
        distanceDownhillSnowSports != nil ||
        bloodPressureSystolic != nil ||
        bloodGlucose != nil ||
        dietaryEnergyConsumed != nil ||
        mindfulSessionDuration != nil
    }
}

// MARK: - Sample Types

nonisolated struct HeartRateSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let value: Double // beats per minute

    init(id: UUID = UUID(), timestamp: Date, value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}

nonisolated struct HRVSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let value: Double // SDNN in milliseconds

    init(id: UUID = UUID(), timestamp: Date, value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}

nonisolated struct BloodOxygenSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let value: Double // percentage (0-100)

    init(id: UUID = UUID(), timestamp: Date, value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}

nonisolated struct RespiratoryRateSample: Identifiable, Codable {
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
