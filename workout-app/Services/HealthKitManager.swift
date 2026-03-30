import Combine
import Foundation
import HealthKit

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
    @Published var dailyHealthCoverage: Set<Date> = []
    @Published var isDailySyncing = false
    @Published var dailySyncProgress: Double = 0
    @Published var lastDailySyncDate: Date?
    @Published var earliestAvailableDailyHealthDate: Date?
    @Published var isResolvingDailyHealthHistory = false
    @Published var syncedWorkoutsCount: Int = 0

    var authorizationTask: Task<Void, Error>?
    var workoutRouteAuthorizationTask: Task<Void, Error>?

    // MARK: - Internal Properties (Used Across Multi-File Extensions)

    let healthStore: HKHealthStore?
    let userDefaults = UserDefaults.standard
    let lastSyncKey = "lastHealthSyncDate"
    let healthDataKey = "syncedHealthData"
    let lastDailySyncKey = "lastDailyHealthSyncDate"
    let dailyHealthDataKey = "dailyHealthDataStore"
    let dailyHealthCoverageKey = "dailyHealthCoverageStore"
    let earliestAvailableDailyHealthDateKey = "earliestAvailableDailyHealthDate"
    let preferredSleepSourceKey = "preferredSleepSourceKey"
    let preferredSleepSourceNameKey = "preferredSleepSourceName"
    let pendingWorkoutSleepSummaryRefreshKey = "pendingWorkoutSleepSummaryRefresh"
    let dailyHealthStoreVersionKey = "dailyHealthStoreVersion"
    let currentDailyHealthStoreVersion = 3

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
            .stairDescentSpeed,

            // Expanded Metrics
            .distanceSwimming,
            .swimmingStrokeCount,
            .distanceWheelchair,
            .pushCount,
            .distanceDownhillSnowSports,
            .bloodPressureSystolic,
            .bloodPressureDiastolic,
            .bloodGlucose,
            .basalBodyTemperature,
            .dietaryWater,
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal
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
            .irregularHeartRhythmEvent,
            .mindfulSession
        ]

        for identifier in categoryTypes {
            if let type = HKCategoryType.categoryType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        // Workout Type
        types.insert(HKObjectType.workoutType())
        types.insert(HKSeriesType.workoutRoute())

        // Activity Summary
        types.insert(HKObjectType.activitySummaryType())

        return types
    }

    static func normalizedAuthorizationReadTypes<S: Sequence>(
        for requestedTypes: S
    ) -> Set<HKObjectType> where S.Element == HKObjectType {
        var normalizedTypes = Set(requestedTypes)

        if normalizedTypes.contains(where: { $0.identifier == HKSeriesType.workoutRoute().identifier }) {
            normalizedTypes.insert(HKObjectType.workoutType())
        }

        return normalizedTypes
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

    var allTimeDailyHealthStartDate: Date? {
        earliestAvailableDailyHealthDate ?? dailyHealthStore.keys.min()
    }

    var selectedSleepSourceKey: String? {
        Self.normalizedSleepSourceKey(userDefaults.string(forKey: preferredSleepSourceKey))
    }

    var selectedSleepSourceName: String? {
        let trimmed = userDefaults.string(forKey: preferredSleepSourceNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var hasPendingWorkoutSleepSummaryRefresh: Bool {
        userDefaults.bool(forKey: pendingWorkoutSleepSummaryRefreshKey)
    }

    /// Request authorization to read health data
    func requestAuthorization() async throws {
        if authorizationStatus == .authorized {
            return
        }

        if let authorizationTask {
            return try await authorizationTask.value
        }

        AppAnalytics.shared.track(AnalyticsSignal.healthAuthorizationStarted)

        let task = Task { @MainActor in
            guard let healthStore = healthStore else {
                authorizationStatus = .unavailable
                AppAnalytics.shared.track(
                    AnalyticsSignal.healthAuthorizationFailed,
                    payload: ["Health.status": "unavailable"]
                )
                throw HealthKitError.notAvailable
            }

            do {
                try await healthStore.requestAuthorization(
                    toShare: [],
                    read: Self.normalizedAuthorizationReadTypes(for: allReadTypes)
                )
                // Await status update so callers can safely continue without a race.
                await checkAuthorizationStatusAsync()
                AppAnalytics.shared.track(
                    AnalyticsSignal.healthAuthorizationCompleted,
                    payload: ["Health.status": authorizationStatus.analyticsLabel]
                )
            } catch {
                authorizationStatus = .denied
                AppAnalytics.shared.track(
                    AnalyticsSignal.healthAuthorizationFailed,
                    payload: [
                        "Health.status": authorizationStatus.analyticsLabel,
                        "Health.errorDomain": String(describing: type(of: error))
                    ]
                )
                throw HealthKitError.authorizationFailed(error.localizedDescription)
            }
        }

        authorizationTask = task
        defer { authorizationTask = nil }
        try await task.value
    }
}

private extension HealthKitAuthorizationStatus {
    var analyticsLabel: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .unavailable:
            return "unavailable"
        }
    }
}
