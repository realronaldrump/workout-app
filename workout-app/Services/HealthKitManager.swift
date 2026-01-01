import Foundation
import HealthKit
import Combine

/// Manages all interactions with Apple HealthKit
/// Handles authorization, data fetching, and syncing health data during workout windows
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
    
    // MARK: - Private Properties
    
    private let healthStore: HKHealthStore?
    private let userDefaults = UserDefaults.standard
    private let lastSyncKey = "lastHealthSyncDate"
    private let healthDataKey = "syncedHealthData"
    
    // MARK: - Health Data Types to Read
    
    /// All HealthKit data types the app will request read access to
    private var allReadTypes: Set<HKObjectType> {
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
            checkAuthorizationStatus()
        } else {
            self.healthStore = nil
            self.authorizationStatus = .unavailable
        }
    }
    
    // MARK: - Public Methods
    
    /// Check if HealthKit is available on this device
    func isHealthKitAvailable() -> Bool {
        return HKHealthStore.isHealthDataAvailable() && healthStore != nil
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
    
    /// Sync health data for a single workout
    func syncHealthDataForWorkout(_ workout: Workout) async throws -> WorkoutHealthData {
        guard healthStore != nil else {
            throw HealthKitError.notAvailable
        }
        
        // Calculate workout time window
        let (startTime, endTime) = calculateWorkoutWindow(workout)
        
        // Fetch all health data for this window
        var healthData = WorkoutHealthData(
            workoutId: workout.id,
            workoutDate: workout.date,
            workoutStartTime: startTime,
            workoutEndTime: endTime
        )
        
        // Fetch heart rate data
        let heartRateSamples = try await fetchHeartRateSamples(from: startTime, to: endTime)
        healthData.heartRateSamples = heartRateSamples
        if !heartRateSamples.isEmpty {
            let values = heartRateSamples.map { $0.value }
            healthData.avgHeartRate = values.reduce(0, +) / Double(values.count)
            healthData.maxHeartRate = values.max()
            healthData.minHeartRate = values.min()
        }
        
        // Fetch calories
        healthData.activeCalories = try await fetchQuantitySum(
            type: .activeEnergyBurned,
            from: startTime,
            to: endTime,
            unit: .kilocalorie()
        )
        
        healthData.basalCalories = try await fetchQuantitySum(
            type: .basalEnergyBurned,
            from: startTime,
            to: endTime,
            unit: .kilocalorie()
        )
        
        // Fetch distance
        healthData.distance = try await fetchQuantitySum(
            type: .distanceWalkingRunning,
            from: startTime,
            to: endTime,
            unit: .meter()
        )
        
        // Fetch step count
        if let steps = try await fetchQuantitySum(
            type: .stepCount,
            from: startTime,
            to: endTime,
            unit: .count()
        ) {
            healthData.stepCount = Int(steps)
        }
        
        // Fetch flights climbed
        if let flights = try await fetchQuantitySum(
            type: .flightsClimbed,
            from: startTime,
            to: endTime,
            unit: .count()
        ) {
            healthData.flightsClimbed = Int(flights)
        }
        
        // Fetch HRV samples
        healthData.hrvSamples = try await fetchHRVSamples(from: startTime, to: endTime)
        
        // Fetch resting heart rate (from day of workout)
        healthData.restingHeartRate = try await fetchLatestQuantity(
            type: .restingHeartRate,
            from: Calendar.current.startOfDay(for: workout.date),
            to: endTime,
            unit: HKUnit(from: "count/min")
        )
        
        // Fetch blood oxygen samples
        healthData.bloodOxygenSamples = try await fetchBloodOxygenSamples(from: startTime, to: endTime)
        
        // Fetch respiratory rate samples
        healthData.respiratoryRateSamples = try await fetchRespiratoryRateSamples(from: startTime, to: endTime)
        
        // Fetch body measurements (from around workout time)
        let dayStart = Calendar.current.startOfDay(for: workout.date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

        healthData.bodyMass = try await fetchLatestQuantity(
            type: .bodyMass,
            from: dayStart,
            to: dayEnd,
            unit: .gramUnit(with: .kilo)
        )

        healthData.bodyFatPercentage = try await fetchLatestQuantity(
            type: .bodyFatPercentage,
            from: dayStart,
            to: dayEnd,
            unit: .percent()
        )

        healthData.bodyTemperature = try await fetchLatestQuantity(
            type: .bodyTemperature,
            from: dayStart,
            to: dayEnd,
            unit: .degreeCelsius()
        )

        // Fetch sleep summary (night before workout)
        let sleepWindowStart = Calendar.current.date(byAdding: .hour, value: -18, to: dayStart) ?? dayStart
        healthData.sleepSummary = try await fetchSleepSummary(from: sleepWindowStart, to: dayEnd)

        // Daily activity totals
        healthData.dailyActiveEnergy = try await fetchQuantitySum(
            type: .activeEnergyBurned,
            from: dayStart,
            to: dayEnd,
            unit: .kilocalorie()
        )

        healthData.dailyBasalEnergy = try await fetchQuantitySum(
            type: .basalEnergyBurned,
            from: dayStart,
            to: dayEnd,
            unit: .kilocalorie()
        )

        if let steps = try await fetchQuantitySum(
            type: .stepCount,
            from: dayStart,
            to: dayEnd,
            unit: .count()
        ) {
            healthData.dailySteps = Int(steps)
        }

        healthData.dailyExerciseMinutes = try await fetchQuantitySum(
            type: .appleExerciseTime,
            from: dayStart,
            to: dayEnd,
            unit: .minute()
        )

        healthData.dailyMoveMinutes = try await fetchQuantitySum(
            type: .appleMoveTime,
            from: dayStart,
            to: dayEnd,
            unit: .minute()
        )

        healthData.dailyStandMinutes = try await fetchQuantitySum(
            type: .appleStandTime,
            from: dayStart,
            to: dayEnd,
            unit: .minute()
        )

        // Cardio fitness metrics near workout day
        let vo2WindowStart = Calendar.current.date(byAdding: .day, value: -45, to: dayStart) ?? dayStart
        healthData.vo2Max = try await fetchLatestQuantity(
            type: .vo2Max,
            from: vo2WindowStart,
            to: dayEnd,
            unit: HKUnit(from: "ml/(kg*min)")
        )

        healthData.heartRateRecovery = try await fetchLatestQuantity(
            type: .heartRateRecoveryOneMinute,
            from: vo2WindowStart,
            to: dayEnd,
            unit: HKUnit(from: "count/min")
        )

        healthData.walkingHeartRateAverage = try await fetchLatestQuantity(
            type: .walkingHeartRateAverage,
            from: vo2WindowStart,
            to: dayEnd,
            unit: HKUnit(from: "count/min")
        )
        
        // Fetch Apple workout if it exists for this window
        if let appleWorkout = try await fetchAppleWorkout(from: startTime, to: endTime) {
            healthData.appleWorkoutType = appleWorkout.workoutActivityType.name
            healthData.appleWorkoutDuration = appleWorkout.duration
            
            // Get additional metrics from Apple workout
            if let avgSpeed = appleWorkout.statistics(for: HKQuantityType(.runningSpeed))?.averageQuantity() {
                healthData.avgSpeed = avgSpeed.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))
            }
            if let avgPower = appleWorkout.statistics(for: HKQuantityType(.runningPower))?.averageQuantity() {
                healthData.avgPower = avgPower.doubleValue(for: .watt())
            }
        }
        
        // Store in local cache
        healthDataStore[workout.id] = healthData
        persistData()
        lastSyncDate = Date()
        userDefaults.set(lastSyncDate, forKey: lastSyncKey)
        
        return healthData
    }
    
    // MARK: - Persistence
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    private var dataFileURL: URL {
        getDocumentsDirectory().appendingPathComponent("health_data_store.json")
    }
    
    private func persistData() {
        Task {
            do {
                let data = try JSONEncoder().encode(Array(healthDataStore.values))
                try data.write(to: dataFileURL, options: [.atomic, .completeFileProtection])
                print("Successfully saved \(data.count) bytes of health data to \(dataFileURL.path)")
            } catch {
                print("Failed to persist health data: \(error)")
            }
        }
    }
    
    private func loadPersistedData() {
        cleanupLegacyUserDefaults()
        do {
            guard FileManager.default.fileExists(atPath: dataFileURL.path) else { return }
            let data = try Data(contentsOf: dataFileURL)
            let healthDataArray = try JSONDecoder().decode([WorkoutHealthData].self, from: data)
            healthDataStore = Dictionary(uniqueKeysWithValues: healthDataArray.map { ($0.workoutId, $0) })
            print("Loaded \(healthDataStore.count) health records")
        } catch {
            print("Failed to load persisted health data: \(error)")
        }
        
        lastSyncDate = userDefaults.object(forKey: lastSyncKey) as? Date
    }
    
    /// Clears all health data from memory and disk
    func clearAllData() {
        // Clear memory
        healthDataStore.removeAll()
        lastSyncDate = nil
        syncProgress = 0
        syncedWorkoutsCount = 0
        syncError = nil
        
        // Clear persistence
        cleanupLegacyUserDefaults()
        userDefaults.removeObject(forKey: lastSyncKey)
        
        do {
            if FileManager.default.fileExists(atPath: dataFileURL.path) {
                try FileManager.default.removeItem(at: dataFileURL)
                print("Deleted health data store file")
            }
        } catch {
            print("Failed to delete health data file: \(error)")
        }
    }
    
    // MARK: - Sync Methods
    
    @Published var syncedWorkoutsCount: Int = 0

    /// Lightweight background sync for the most recent workouts that are missing data.
    func syncRecentWorkoutsIfNeeded(_ workouts: [Workout]) async {
        guard authorizationStatus == .authorized else { return }
        guard isHealthKitAvailable() else { return }
        guard !isAutoSyncing else { return }

        let missing = workouts.filter { healthDataStore[$0.id] == nil }
        let recentMissing = Array(missing.prefix(3))
        guard !recentMissing.isEmpty else { return }

        isAutoSyncing = true
        syncProgress = 0
        syncedWorkoutsCount = 0

        for (index, workout) in recentMissing.enumerated() {
            do {
                let _ = try await syncHealthDataForWorkout(workout)
            } catch {
                print("Auto sync failed for workout \(workout.id): \(error)")
            }

            syncedWorkoutsCount = index + 1
            syncProgress = Double(index + 1) / Double(recentMissing.count)
        }

        isAutoSyncing = false
        lastSyncDate = Date()
        userDefaults.set(lastSyncDate, forKey: lastSyncKey)
        persistData()
    }
    
    /// Sync health data for all workouts
    func syncAllWorkouts(_ workouts: [Workout]) async throws -> [WorkoutHealthData] {
        guard isHealthKitAvailable() else {
            throw HealthKitError.notAvailable
        }
        
        isSyncing = true
        syncProgress = 0
        syncedWorkoutsCount = 0
        syncError = nil
        
        var results: [WorkoutHealthData] = []
        let total = Double(workouts.count)
        
        for (index, workout) in workouts.enumerated() {
            do {
                let healthData = try await syncHealthDataForWorkout(workout)
                results.append(healthData)
            } catch {
                print("Failed to sync workout \(workout.id): \(error)")
            }
            
            // Update progress on main actor
            await MainActor.run {
                self.syncedWorkoutsCount = index + 1
                self.syncProgress = Double(index + 1) / total
            }
        }
        
        isSyncing = false
        lastSyncDate = Date()
        userDefaults.set(lastSyncDate, forKey: lastSyncKey)
        
        // Persist final result
        persistData()
        
        return results
    }

    // MARK: - Authorization

    private func checkAuthorizationStatus() {
        guard let healthStore = healthStore else {
            authorizationStatus = .unavailable
            return
        }

        healthStore.getRequestStatusForAuthorization(toShare: [], read: allReadTypes) { [weak self] status, error in
            guard let self = self else { return }
            Task { @MainActor in
                if let error = error {
                    self.authorizationStatus = .denied
                    self.syncError = error.localizedDescription
                    return
                }

                switch status {
                case .unnecessary:
                    self.authorizationStatus = .authorized
                case .shouldRequest, .unknown:
                    self.authorizationStatus = .notDetermined
                @unknown default:
                    self.authorizationStatus = .notDetermined
                }
            }
        }
    }

    // MARK: - Workout Window

    private func calculateWorkoutWindow(_ workout: Workout) -> (Date, Date) {
        let startTime = workout.date
        let durationMinutes = parseDurationMinutes(workout.duration) ?? 60
        let safeMinutes = durationMinutes > 0 ? durationMinutes : 60
        let endTime = startTime.addingTimeInterval(TimeInterval(safeMinutes * 60))
        return (startTime, endTime)
    }

    private func parseDurationMinutes(_ duration: String) -> Int? {
        let trimmed = duration.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // Handle HH:mm:ss or H:mm:ss format (e.g., "01:15:00" or "1:15:00")
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").compactMap { Int($0) }
            if parts.count == 3 {
                // HH:mm:ss
                return parts[0] * 60 + parts[1]
            } else if parts.count == 2 {
                // mm:ss
                return parts[0]
            }
        }

        var hours = 0
        var minutes = 0
        var matched = false

        if let hourMatch = trimmed.range(of: "(\\d+)\\s*h", options: .regularExpression) {
            let hourString = String(trimmed[hourMatch]).replacingOccurrences(of: "h", with: "")
            hours = Int(hourString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            matched = true
        }

        if let minuteMatch = trimmed.range(of: "(\\d+)\\s*m", options: .regularExpression) {
            let minuteString = String(trimmed[minuteMatch]).replacingOccurrences(of: "m", with: "")
            minutes = Int(minuteString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            matched = true
        }

        if matched {
            return (hours * 60) + minutes
        }

        return Int(trimmed)
    }

    // MARK: - HealthKit Queries

    private func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        let unit = HKUnit(from: "count/min")
        let samples = try await fetchQuantitySamples(type: .heartRate, from: start, to: end)
        return samples.map { sample in
            HeartRateSample(timestamp: sample.startDate, value: sample.quantity.doubleValue(for: unit))
        }
    }

    private func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] {
        let unit = HKUnit.secondUnit(with: .milli)
        let samples = try await fetchQuantitySamples(type: .heartRateVariabilitySDNN, from: start, to: end)
        return samples.map { sample in
            HRVSample(timestamp: sample.startDate, value: sample.quantity.doubleValue(for: unit))
        }
    }

    private func fetchBloodOxygenSamples(from start: Date, to end: Date) async throws -> [BloodOxygenSample] {
        let unit = HKUnit.percent()
        let samples = try await fetchQuantitySamples(type: .oxygenSaturation, from: start, to: end)
        return samples.map { sample in
            let percentage = sample.quantity.doubleValue(for: unit) * 100
            return BloodOxygenSample(timestamp: sample.startDate, value: percentage)
        }
    }

    private func fetchRespiratoryRateSamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] {
        let unit = HKUnit(from: "count/min")
        let samples = try await fetchQuantitySamples(type: .respiratoryRate, from: start, to: end)
        return samples.map { sample in
            RespiratoryRateSample(timestamp: sample.startDate, value: sample.quantity.doubleValue(for: unit))
        }
    }

    private func fetchQuantitySum(
        type: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        unit: HKUnit
    ) async throws -> Double? {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: type) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                let sum = result?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: sum)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatestQuantity(
        type: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        unit: HKUnit
    ) async throws -> Double? {
        let samples = try await fetchQuantitySamples(type: type, from: start, to: end, limit: 1, ascending: false)
        return samples.first?.quantity.doubleValue(for: unit)
    }

    private func fetchAppleWorkout(from start: Date, to end: Date) async throws -> HKWorkout? {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                let workout = samples?.first as? HKWorkout
                continuation.resume(returning: workout)
            }
            healthStore.execute(query)
        }
    }

    private func fetchQuantitySamples(
        type: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        limit: Int = HKObjectQueryNoLimit,
        ascending: Bool = true
    ) async throws -> [HKQuantitySample] {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: type) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func fetchSleepSummary(from start: Date, to end: Date) async throws -> SleepSummary? {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                let sleepSamples = samples as? [HKCategorySample] ?? []
                guard !sleepSamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                var stageDurations: [SleepStage: TimeInterval] = [:]
                var totalSleep: TimeInterval = 0
                var inBed: TimeInterval = 0
                var startTime = sleepSamples.first?.startDate ?? start
                var endTime = sleepSamples.first?.endDate ?? end

                for sample in sleepSamples {
                    let duration = max(sample.endDate.timeIntervalSince(sample.startDate), 0)
                    startTime = min(startTime, sample.startDate)
                    endTime = max(endTime, sample.endDate)

                    let stage = Self.mapSleepStage(sample.value)
                    stageDurations[stage, default: 0] += duration

                    switch stage {
                    case .inBed:
                        inBed += duration
                    case .core, .deep, .rem:
                        totalSleep += duration
                    default:
                        break
                    }
                }

                let summary = SleepSummary(
                    totalSleep: totalSleep,
                    inBed: inBed,
                    stageDurations: stageDurations,
                    start: startTime,
                    end: endTime
                )

                continuation.resume(returning: summary)
            }
            healthStore.execute(query)
        }
    }

    private nonisolated static func mapSleepStage(_ value: Int) -> SleepStage {
        guard let stage = HKCategoryValueSleepAnalysis(rawValue: value) else {
            return .unknown
        }

        switch stage {
        case .awake:
            return .awake
        case .inBed:
            return .inBed
        case .asleepREM:
            return .rem
        case .asleepDeep:
            return .deep
        case .asleepCore:
            return .core
        case .asleepUnspecified:
            return .core
        case .asleep:
            return .core
        @unknown default:
            return .unknown
        }
    }

    private func cleanupLegacyUserDefaults() {
        if userDefaults.data(forKey: healthDataKey) != nil {
            userDefaults.removeObject(forKey: healthDataKey)
        }
    }

    private nonisolated static func isNoDataError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == HKErrorDomain &&
            nsError.code == HKError.Code.errorNoData.rawValue
    }

}

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

// MARK: - Workout Activity Type Extension

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
