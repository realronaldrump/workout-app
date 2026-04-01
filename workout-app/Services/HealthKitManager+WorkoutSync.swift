import CoreLocation
import Foundation
import HealthKit

private enum DefaultHealthSyncPlan {
    nonisolated static let initialWorkoutYearsBack = 1
    nonisolated static let initialWorkoutMaxCount = 120
    nonisolated static let initialDailyMonthsBack = 12
    nonisolated static let autoSyncRecentCount = 3
    nonisolated static let batchAppleWorkoutCandidateLimit = 200
    nonisolated static let batchAppleWorkoutRangeLimitDays = 400
}

extension HealthKitManager {
    func recommendedInitialWorkoutSyncTargets(
        from workouts: [Workout],
        yearsBack: Int = DefaultHealthSyncPlan.initialWorkoutYearsBack,
        maxCount: Int = DefaultHealthSyncPlan.initialWorkoutMaxCount
    ) -> [Workout] {
        guard !workouts.isEmpty else { return [] }

        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .year, value: -yearsBack, to: now) ?? now

        let sorted = workouts.sorted { $0.date > $1.date }
        let missingRecent = sorted.filter { workout in
            workout.date >= cutoff && healthDataStore[workout.id] == nil
        }

        return Array(missingRecent.prefix(maxCount))
    }

    func recommendedInitialDailySyncRange(
        reference: Date = Date(),
        monthsBack: Int = DefaultHealthSyncPlan.initialDailyMonthsBack
    ) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -monthsBack, to: reference)
            ?? reference.addingTimeInterval(-31_536_000)
        let rangeStart = calendar.startOfDay(for: start)
        let rangeEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: reference) ?? reference
        return DateInterval(start: rangeStart, end: rangeEnd)
    }

    func applySleepSourcePreference(
        key: String?,
        name: String?,
        workouts: [Workout]
    ) async {
        let normalizedKey = Self.normalizedSleepSourceKey(key)
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentKey = selectedSleepSourceKey
        let currentName = userDefaults.string(forKey: preferredSleepSourceNameKey) ?? ""

        guard currentKey != normalizedKey || currentName != normalizedName else { return }

        if let normalizedKey {
            userDefaults.set(normalizedKey, forKey: preferredSleepSourceKey)
        } else {
            userDefaults.removeObject(forKey: preferredSleepSourceKey)
        }

        if normalizedName.isEmpty {
            userDefaults.removeObject(forKey: preferredSleepSourceNameKey)
        } else {
            userDefaults.set(normalizedName, forKey: preferredSleepSourceNameKey)
        }

        invalidateDailyHealthCache()
        userDefaults.set(true, forKey: pendingWorkoutSleepSummaryRefreshKey)
        await refreshPendingWorkoutSleepSummariesIfNeeded(workouts: workouts)
    }

    func refreshPendingWorkoutSleepSummariesIfNeeded(workouts: [Workout]) async {
        guard hasPendingWorkoutSleepSummaryRefresh else { return }
        guard authorizationStatus == .authorized, healthStore != nil else { return }
        guard !healthDataStore.isEmpty else {
            userDefaults.removeObject(forKey: pendingWorkoutSleepSummaryRefreshKey)
            return
        }

        let workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
        let matchingWorkoutIDs = Set(workoutsByID.keys).intersection(healthDataStore.keys)
        guard !matchingWorkoutIDs.isEmpty else { return }

        var updatedStore = healthDataStore
        var refreshedAny = false
        var hadFailure = false

        for workoutID in matchingWorkoutIDs {
            guard let workout = workoutsByID[workoutID],
                  var healthData = updatedStore[workoutID] else {
                continue
            }

            let sleepRange = sleepSummaryWindow(for: workout)

            do {
                healthData.sleepSummary = try await fetchSleepSummary(
                    from: sleepRange.start,
                    to: sleepRange.end
                )
                updatedStore[workoutID] = healthData
                refreshedAny = true
            } catch {
                print("Failed to refresh sleep summary for \(workoutID): \(error)")
                hadFailure = true
            }
        }

        if refreshedAny {
            healthDataStore = updatedStore
            persistData(changedWorkoutIDs: Array(matchingWorkoutIDs))
        }

        if !hadFailure {
            userDefaults.removeObject(forKey: pendingWorkoutSleepSummaryRefreshKey)
        }
    }

    private func sleepSummaryWindow(for workout: Workout) -> (start: Date, end: Date) {
        let (startTime, _) = calculateWorkoutWindow(workout)
        let dayStart = Calendar.current.startOfDay(for: workout.date)
        let sleepWindowEnd = startTime
        let sleepWindowStart = Calendar.current.date(byAdding: .hour, value: -24, to: sleepWindowEnd) ?? dayStart
        return (sleepWindowStart, sleepWindowEnd)
    }

    private func prefetchedAppleWorkoutCandidates(for workouts: [Workout]) async throws -> [HKWorkout]? {
        guard !workouts.isEmpty else { return [] }
        guard workouts.count <= DefaultHealthSyncPlan.batchAppleWorkoutCandidateLimit else { return nil }

        let sorted = workouts.sorted { $0.date < $1.date }
        guard let firstWorkout = sorted.first, let lastWorkout = sorted.last else { return [] }

        let firstWindow = firstWorkout.estimatedWindow(defaultMinutes: 60)
        let lastWindow = lastWorkout.estimatedWindow(defaultMinutes: 60)
        let daySpan = Calendar.current.dateComponents([.day], from: firstWindow.start, to: lastWindow.end).day ?? 0
        guard daySpan <= DefaultHealthSyncPlan.batchAppleWorkoutRangeLimitDays else { return nil }

        let relaxedTolerance: TimeInterval = 12 * 60 * 60
        return try await fetchAppleWorkouts(
            from: firstWindow.start.addingTimeInterval(-relaxedTolerance),
            to: lastWindow.end.addingTimeInterval(relaxedTolerance)
        )
    }

    /// Sync health data for a single workout
    func syncHealthDataForWorkout(
        _ workout: Workout,
        persist: Bool = true,
        appleWorkoutCandidates: [HKWorkout]? = nil
    ) async throws -> WorkoutHealthData {
        guard healthStore != nil else {
            throw HealthKitError.notAvailable
        }
        guard authorizationStatus == .authorized else {
            throw HealthKitError.authorizationFailed("Health access is not authorized.")
        }

        // Calculate workout time window
        let (startTime, endTime) = calculateWorkoutWindow(workout)

        var healthData = WorkoutHealthData(
            workoutId: workout.id,
            workoutDate: workout.date,
            workoutStartTime: startTime,
            workoutEndTime: endTime
        )
        try await populateWorkoutWindowMetrics(&healthData, for: workout, startTime: startTime, endTime: endTime)
        try await populateWorkoutDayMetrics(&healthData, workoutDate: workout.date)
        try await populateAppleWorkoutMetrics(&healthData, for: workout, candidates: appleWorkoutCandidates)
        return cacheSyncedHealthData(healthData, workoutID: workout.id, persist: persist)
    }

    private func populateWorkoutWindowMetrics(
        _ healthData: inout WorkoutHealthData,
        for workout: Workout,
        startTime: Date,
        endTime: Date
    ) async throws {
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

        healthData.distanceSwimming = try await fetchQuantitySum(
            type: .distanceSwimming, from: startTime, to: endTime, unit: .meter()
        )

        healthData.distanceWheelchair = try await fetchQuantitySum(
            type: .distanceWheelchair, from: startTime, to: endTime, unit: .meter()
        )

        healthData.distanceDownhillSnowSports = try await fetchQuantitySum(
            type: .distanceDownhillSnowSports, from: startTime, to: endTime, unit: .meter()
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

        if let strokes = try await fetchQuantitySum(
            type: .swimmingStrokeCount, from: startTime, to: endTime, unit: .count()
        ) {
            healthData.swimmingStrokeCount = Int(strokes)
        }

        if let pushes = try await fetchQuantitySum(
            type: .pushCount, from: startTime, to: endTime, unit: .count()
        ) {
            healthData.pushCount = Int(pushes)
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
    }

    private func populateWorkoutDayMetrics(
        _ healthData: inout WorkoutHealthData,
        workoutDate: Date
    ) async throws {
        let startTime = healthData.workoutStartTime
        let endTime = healthData.workoutEndTime
        healthData.bloodOxygenSamples = try await fetchBloodOxygenSamples(from: startTime, to: endTime)
        healthData.respiratoryRateSamples = try await fetchRespiratoryRateSamples(from: startTime, to: endTime)
        let dayStart = Calendar.current.startOfDay(for: workoutDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(60 * 60 * 24)

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

        healthData.bloodPressureSystolic = try await fetchLatestQuantity(
            type: .bloodPressureSystolic, from: dayStart, to: dayEnd, unit: HKUnit.millimeterOfMercury()
        )

        healthData.bloodPressureDiastolic = try await fetchLatestQuantity(
            type: .bloodPressureDiastolic, from: dayStart, to: dayEnd, unit: HKUnit.millimeterOfMercury()
        )

        healthData.bloodGlucose = try await fetchLatestQuantity(
            type: .bloodGlucose, from: dayStart, to: dayEnd, unit: HKUnit(from: "mg/dL")
        )

        healthData.basalBodyTemperature = try await fetchLatestQuantity(
            type: .basalBodyTemperature, from: dayStart, to: dayEnd, unit: .degreeCelsius()
        )

        let sleepWindow = sleepSummaryWindow(
            startTime: healthData.workoutStartTime,
            workoutDate: workoutDate
        )
        healthData.sleepSummary = try await fetchSleepSummary(
            from: sleepWindow.start,
            to: sleepWindow.end
        )

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

        healthData.dietaryWater = try await fetchQuantitySum(
            type: .dietaryWater, from: dayStart, to: dayEnd, unit: .liter()
        )
        healthData.dietaryEnergyConsumed = try await fetchQuantitySum(
            type: .dietaryEnergyConsumed, from: dayStart, to: dayEnd, unit: .kilocalorie()
        )
        healthData.dietaryProtein = try await fetchQuantitySum(
            type: .dietaryProtein, from: dayStart, to: dayEnd, unit: .gram()
        )
        healthData.dietaryCarbohydrates = try await fetchQuantitySum(
            type: .dietaryCarbohydrates, from: dayStart, to: dayEnd, unit: .gram()
        )
        healthData.dietaryFatTotal = try await fetchQuantitySum(
            type: .dietaryFatTotal, from: dayStart, to: dayEnd, unit: .gram()
        )

        healthData.mindfulSessionDuration = try await fetchCategoryDurationSum(
            type: .mindfulSession, from: dayStart, to: dayEnd
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
    }

    private func populateAppleWorkoutMetrics(
        _ healthData: inout WorkoutHealthData,
        for workout: Workout,
        candidates appleWorkoutCandidates: [HKWorkout]?
    ) async throws {
        let matchedAppleWorkout: HKWorkout?
        if let appleWorkoutCandidates {
            matchedAppleWorkout = bestMatchingAppleWorkout(for: workout, candidates: appleWorkoutCandidates)
        } else {
            matchedAppleWorkout = try await fetchBestMatchingAppleWorkout(for: workout)
        }

        if let appleWorkout = matchedAppleWorkout {
            healthData.appleWorkoutType = appleWorkout.workoutActivityType.name
            healthData.appleWorkoutDuration = appleWorkout.duration
            healthData.appleWorkoutUUID = appleWorkout.uuid

            if let avgSpeed = appleWorkout.statistics(for: HKQuantityType(.runningSpeed))?.averageQuantity() {
                healthData.avgSpeed = avgSpeed.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))
            }
            if let avgPower = appleWorkout.statistics(for: HKQuantityType(.runningPower))?.averageQuantity() {
                healthData.avgPower = avgPower.doubleValue(for: .watt())
            }

            do {
                if let resolvedLocation = try await fetchWorkoutLocation(for: appleWorkout) {
                    healthData.workoutLocationLatitude = resolvedLocation.location.coordinate.latitude
                    healthData.workoutLocationLongitude = resolvedLocation.location.coordinate.longitude
                    healthData.workoutLocationSource = resolvedLocation.source
                    if resolvedLocation.source == .route {
                        healthData.workoutRouteStartLatitude = resolvedLocation.location.coordinate.latitude
                        healthData.workoutRouteStartLongitude = resolvedLocation.location.coordinate.longitude
                    }
                }
            } catch {
                // Workout location is optional; don't fail the overall health sync.
            }
        }
    }

    private func cacheSyncedHealthData(
        _ healthData: WorkoutHealthData,
        workoutID: UUID,
        persist: Bool
    ) -> WorkoutHealthData {
        var healthData = healthData
        healthData.captureRawSampleSummaries()
        healthDataStore[workoutID] = healthData
        if persist {
            persistData(changedWorkoutIDs: [workoutID])
            lastSyncDate = Date()
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
        }
        return healthData
    }

    func loadDetailedSamplesIfNeeded(for workoutID: UUID, force: Bool = false) async throws -> WorkoutHealthData? {
        guard healthStore != nil else {
            throw HealthKitError.notAvailable
        }
        guard authorizationStatus == .authorized else {
            throw HealthKitError.authorizationFailed("Health access is not authorized.")
        }
        guard var cached = healthDataStore[workoutID] else {
            return nil
        }
        guard force || !cached.hasRawSamples else {
            return cached
        }

        let start = cached.workoutStartTime
        let end = cached.workoutEndTime

        let heartRateSamples = try await fetchHeartRateSamples(from: start, to: end)
        cached.heartRateSamples = heartRateSamples
        if !heartRateSamples.isEmpty {
            let values = heartRateSamples.map(\.value)
            cached.avgHeartRate = values.reduce(0, +) / Double(values.count)
            cached.maxHeartRate = values.max()
            cached.minHeartRate = values.min()
        }

        cached.hrvSamples = try await fetchHRVSamples(from: start, to: end)
        cached.bloodOxygenSamples = try await fetchBloodOxygenSamples(from: start, to: end)
        cached.respiratoryRateSamples = try await fetchRespiratoryRateSamples(from: start, to: end)
        cached.captureRawSampleSummaries()

        healthDataStore[workoutID] = cached
        return cached
    }

    /// Lightweight background sync for the most recent workouts that are missing data.
    func syncRecentWorkoutsIfNeeded(_ workouts: [Workout]) async {
        guard authorizationStatus == .authorized else { return }
        guard isHealthKitAvailable() else { return }
        guard !isAutoSyncing else { return }

        let recentMissing = Array(
            workouts
                .sorted { $0.date > $1.date }
                .filter { healthDataStore[$0.id] == nil }
                .prefix(DefaultHealthSyncPlan.autoSyncRecentCount)
        )
        guard !recentMissing.isEmpty else { return }

        isAutoSyncing = true
        defer { isAutoSyncing = false }
        syncProgress = 0
        syncedWorkoutsCount = 0

        let appleWorkoutCandidates = try? await prefetchedAppleWorkoutCandidates(for: recentMissing)

        for (index, workout) in recentMissing.enumerated() {
            do {
                _ = try await syncHealthDataForWorkout(
                    workout,
                    persist: false,
                    appleWorkoutCandidates: appleWorkoutCandidates
                )
            } catch {
                print("Auto sync failed for workout \(workout.id): \(error)")
            }

            syncedWorkoutsCount = index + 1
            syncProgress = Double(index + 1) / Double(recentMissing.count)
        }

        lastSyncDate = Date()
        userDefaults.set(lastSyncDate, forKey: lastSyncKey)
        persistData(changedWorkoutIDs: recentMissing.map(\.id))
    }

    /// Sync health data for all workouts
    func syncAllWorkouts(_ workouts: [Workout]) async throws -> [WorkoutHealthData] {
        guard isHealthKitAvailable() else {
            throw HealthKitError.notAvailable
        }
        guard authorizationStatus == .authorized else {
            throw HealthKitError.authorizationFailed("Health access is not authorized.")
        }

        isSyncing = true
        defer { isSyncing = false }
        syncProgress = 0
        syncedWorkoutsCount = 0
        syncError = nil

        // Route access is optional for sync completeness, but request it once up front.
        // If denied, the rest of Health sync still proceeds.
        do {
            try await requestWorkoutRouteAuthorization()
        } catch {
            print("Workout route authorization unavailable during sync: \(error)")
        }

        var results: [WorkoutHealthData] = []
        guard !workouts.isEmpty else {
            // Avoid 0/0 progress UI and division-by-zero paths.
            syncProgress = 1
            lastSyncDate = Date()
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
            persistData(changedWorkoutIDs: [])
            return []
        }

        let total = Double(workouts.count)
        let appleWorkoutCandidates = try await prefetchedAppleWorkoutCandidates(for: workouts)

        for (index, workout) in workouts.enumerated() {
            do {
                let healthData = try await syncHealthDataForWorkout(
                    workout,
                    persist: false,
                    appleWorkoutCandidates: appleWorkoutCandidates
                )
                results.append(healthData)
            } catch {
                print("Failed to sync workout \(workout.id): \(error)")
            }

            await MainActor.run {
                self.syncedWorkoutsCount = index + 1
                self.syncProgress = Double(index + 1) / total
            }
        }

        lastSyncDate = Date()
        userDefaults.set(lastSyncDate, forKey: lastSyncKey)

        // Persist final result
        persistData(changedWorkoutIDs: results.map(\.workoutId))

        return results
    }

    /// Best-effort workout-location hydration for recent workouts.
    /// Used by gym discovery so it can work even when locations weren't previously cached.
    func hydrateRouteStartLocationsForRecentWorkouts(
        _ workouts: [Workout],
        maxWorkouts: Int = 120
    ) async throws -> Int {
        guard isHealthKitAvailable() else {
            throw HealthKitError.notAvailable
        }
        guard authorizationStatus == .authorized else {
            throw HealthKitError.authorizationFailed("Health access is not authorized.")
        }

        do {
            try await requestWorkoutRouteAuthorization()
        } catch {
            print("Workout route authorization unavailable during location hydration: \(error)")
        }

        let targets = recentLocationHydrationTargets(from: workouts, maxWorkouts: maxWorkouts)

        guard !targets.isEmpty else { return 0 }

        let windows = targets.map { $0.estimatedWindow(defaultMinutes: 60) }
        guard let minStart = windows.map(\.start).min(), let maxEnd = windows.map(\.end).max() else {
            return 0
        }

        let relaxedTolerance: TimeInterval = 12 * 60 * 60
        let appleWorkouts = try await fetchAppleWorkouts(
            from: minStart.addingTimeInterval(-relaxedTolerance),
            to: maxEnd.addingTimeInterval(relaxedTolerance)
        )

        guard !appleWorkouts.isEmpty else { return 0 }

        let appleByUUID = Dictionary(uniqueKeysWithValues: appleWorkouts.map { ($0.uuid, $0) })
        var locationByAppleUUID: [UUID: ResolvedWorkoutLocation] = [:]
        var appleUUIDsWithNoLocation: Set<UUID> = []
        var updated = 0
        var updatedWorkoutIDs: [UUID] = []

        for workout in targets {
            let cached = healthDataStore[workout.id]
            let appleWorkout = matchingAppleWorkout(
                for: workout,
                cachedAppleWorkoutUUID: cached?.appleWorkoutUUID,
                appleByUUID: appleByUUID,
                appleWorkouts: appleWorkouts,
                relaxedTolerance: relaxedTolerance
            )

            guard let appleWorkout else { continue }
            let resolvedLocation = await resolveHydratedLocation(
                for: appleWorkout,
                locationByAppleUUID: &locationByAppleUUID,
                appleUUIDsWithNoLocation: &appleUUIDsWithNoLocation
            )

            guard let resolvedLocation else { continue }

            let healthData = hydratedHealthData(
                for: workout,
                cached: cached,
                appleWorkout: appleWorkout,
                resolvedLocation: resolvedLocation
            )
            healthDataStore[workout.id] = healthData
            updated += 1
            updatedWorkoutIDs.append(workout.id)
        }

        if updated > 0 {
            persistData(changedWorkoutIDs: updatedWorkoutIDs)
        }

        return updated
    }

    private func recentLocationHydrationTargets(
        from workouts: [Workout],
        maxWorkouts: Int
    ) -> [Workout] {
        workouts
            .sorted { $0.date > $1.date }
            .prefix(maxWorkouts)
            .filter { workout in
                guard let cached = healthDataStore[workout.id] else { return true }
                return cached.resolvedWorkoutLocationCoordinate == nil
            }
    }

    private func matchingAppleWorkout(
        for workout: Workout,
        cachedAppleWorkoutUUID: UUID?,
        appleByUUID: [UUID: HKWorkout],
        appleWorkouts: [HKWorkout],
        relaxedTolerance: TimeInterval
    ) -> HKWorkout? {
        if let cachedAppleWorkoutUUID, let exact = appleByUUID[cachedAppleWorkoutUUID] {
            return exact
        }

        return bestMatchingAppleWorkout(
            for: workout,
            candidates: appleWorkouts,
            strictStartDifferenceSeconds: 20 * 60,
            relaxedStartDifferenceSeconds: relaxedTolerance
        )
    }

    private func resolveHydratedLocation(
        for appleWorkout: HKWorkout,
        locationByAppleUUID: inout [UUID: ResolvedWorkoutLocation],
        appleUUIDsWithNoLocation: inout Set<UUID>
    ) async -> ResolvedWorkoutLocation? {
        let appleUUID = appleWorkout.uuid
        if let existing = locationByAppleUUID[appleUUID] {
            return existing
        }
        if appleUUIDsWithNoLocation.contains(appleUUID) {
            return nil
        }

        do {
            let location = try await fetchWorkoutLocation(for: appleWorkout)
            if let location {
                locationByAppleUUID[appleUUID] = location
            } else {
                appleUUIDsWithNoLocation.insert(appleUUID)
            }
            return location
        } catch {
            print("Failed to hydrate workout location for \(appleUUID): \(error)")
            appleUUIDsWithNoLocation.insert(appleUUID)
            return nil
        }
    }

    private func hydratedHealthData(
        for workout: Workout,
        cached: WorkoutHealthData?,
        appleWorkout: HKWorkout,
        resolvedLocation: ResolvedWorkoutLocation
    ) -> WorkoutHealthData {
        var healthData = cached ?? WorkoutHealthData(
            workoutId: workout.id,
            workoutDate: workout.date,
            workoutStartTime: workout.estimatedWindow(defaultMinutes: 60).start,
            workoutEndTime: workout.estimatedWindow(defaultMinutes: 60).end
        )
        healthData.appleWorkoutUUID = appleWorkout.uuid
        healthData.appleWorkoutType = appleWorkout.workoutActivityType.name
        healthData.workoutLocationLatitude = resolvedLocation.location.coordinate.latitude
        healthData.workoutLocationLongitude = resolvedLocation.location.coordinate.longitude
        healthData.workoutLocationSource = resolvedLocation.source
        if resolvedLocation.source == .route {
            healthData.workoutRouteStartLatitude = resolvedLocation.location.coordinate.latitude
            healthData.workoutRouteStartLongitude = resolvedLocation.location.coordinate.longitude
        }
        return healthData
    }

    private func calculateWorkoutWindow(_ workout: Workout) -> (Date, Date) {
        let window = workout.estimatedWindow(defaultMinutes: 60)
        return (window.start, window.end)
    }

    private func sleepSummaryWindow(startTime: Date, workoutDate: Date) -> (start: Date, end: Date) {
        let dayStart = Calendar.current.startOfDay(for: workoutDate)
        let sleepWindowEnd = startTime
        let sleepWindowStart = Calendar.current.date(byAdding: .hour, value: -24, to: sleepWindowEnd) ?? dayStart
        return (sleepWindowStart, sleepWindowEnd)
    }

    // Duration parsing lives on Workout (Models/WorkoutModels.swift).
}
