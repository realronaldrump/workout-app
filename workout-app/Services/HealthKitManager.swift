import Foundation
import HealthKit
import Combine

/// Manages all interactions with Apple HealthKit.
/// Handles authorization, data fetching, and syncing health data during workout windows.
@MainActor
class HealthKitManager: ObservableObject {

    // MARK: - Published Properties

    @Published var authorizationStatus: HealthKitAuthorizationStatus = .notDetermined
    @Published var isSyncing = false
    @Published var isAutoSyncing = false
    @Published var syncProgress: Double = 0
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var healthDataStore: [UUID: WorkoutHealthData] = [:] // keyed by workout ID
    @Published var dailyHealthStore: [Date: DailyHealthData] = [:] // keyed by day start
    @Published var isDailySyncing = false
    @Published var dailySyncProgress: Double = 0
    @Published var lastDailySyncDate: Date?
    @Published var syncedWorkoutsCount: Int = 0

    // MARK: - Internal Properties (Used Across Multi-File Extensions)

    let healthStore: HKHealthStore?
    let userDefaults = UserDefaults.standard
    let lastSyncKey = "lastHealthSyncDate"
    let healthDataKey = "syncedHealthData"
    let lastDailySyncKey = "lastDailyHealthSyncDate"
    let dailyHealthDataKey = "dailyHealthDataStore"
    let dailyHealthStoreVersionKey = "dailyHealthStoreVersion"
    let currentDailyHealthStoreVersion = 2

    // MARK: - Health Data Types to Read

    /// All HealthKit data types the app will request read access to
    var allReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()

        // Quantity Types
        let quantityTypes: [HKQuantityTypeIdentifier] = [
            // Heart & Cardiovascular
            .heartRate,
            .restingHeartRate,
            .walkingHeartRateAverage,
            .heartRateVariabilitySDNN,
            .heartRateRecoveryOneMinute,

            // Energy
            .activeEnergyBurned,
            .basalEnergyBurned,

            // Activity
            .stepCount,
            .distanceWalkingRunning,
            .distanceCycling,
            .flightsClimbed,
            .appleExerciseTime,
            .appleMoveTime,
            .appleStandTime,

            // Workout Metrics
            .runningSpeed,
            .runningPower,
            .cyclingSpeed,
            .cyclingPower,
            .runningStrideLength,
            .runningGroundContactTime,
            .runningVerticalOscillation,

            // Vitals
            .oxygenSaturation,
            .respiratoryRate,
            .bodyTemperature,

            // Body Measurements
            .bodyMass,
            .bodyFatPercentage,
            .leanBodyMass,
            .bodyMassIndex,

            // Other
            .vo2Max,
            .walkingSpeed,
            .walkingStepLength,
            .walkingAsymmetryPercentage,
            .walkingDoubleSupportPercentage,
            .stairAscentSpeed,
            .stairDescentSpeed
        ]

        for identifier in quantityTypes {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        // Category Types
        let categoryTypes: [HKCategoryTypeIdentifier] = [
            .sleepAnalysis,
            .appleStandHour,
            .lowHeartRateEvent,
            .highHeartRateEvent,
            .irregularHeartRhythmEvent
        ]

        for identifier in categoryTypes {
            if let type = HKCategoryType.categoryType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        // Workout Type
        types.insert(HKObjectType.workoutType())

        // Activity Summary
        types.insert(HKObjectType.activitySummaryType())

        return types
    }

    // MARK: - Initialization

    init() {
        if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
            loadPersistedData()
            loadPersistedDailyHealthData()
            checkAuthorizationStatus()
        } else {
            self.healthStore = nil
            self.authorizationStatus = .unavailable
        }
    }

    // MARK: - Public Methods

    /// Check if HealthKit is available on this device
    func isHealthKitAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable() && healthStore != nil
    }

    /// Refresh the current authorization status
    func refreshAuthorizationStatus() {
        checkAuthorizationStatus()
    }

    /// Access cached health data for a workout
    func getHealthData(for workoutId: UUID) -> WorkoutHealthData? {
        healthDataStore[workoutId]
    }

    /// Request authorization to read health data
    func requestAuthorization() async throws {
        guard let healthStore = healthStore else {
            authorizationStatus = .unavailable
            throw HealthKitError.notAvailable
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: allReadTypes)
            checkAuthorizationStatus()
        } catch {
            authorizationStatus = .denied
            throw HealthKitError.authorizationFailed(error.localizedDescription)
        }
    }
}
