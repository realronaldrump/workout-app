import Foundation
import HealthKit
import CoreLocation

extension HealthKitManager {
    /// Sync health data for a single workout
    func syncHealthDataForWorkout(_ workout: Workout, persist: Bool = true) async throws -> WorkoutHealthData {
        guard healthStore != nil else {
            throw HealthKitError.notAvailable
        }
        guard authorizationStatus == .authorized else {
            throw HealthKitError.authorizationFailed("Health access is not authorized.")
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

        // Fetch sleep summary (night before workout)
        let sleepWindowEnd = startTime
        let sleepWindowStart = Calendar.current.date(byAdding: .hour, value: -24, to: sleepWindowEnd) ?? dayStart
        healthData.sleepSummary = try await fetchSleepSummary(from: sleepWindowStart, to: sleepWindowEnd)

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

        // Fetch the best-matching Apple workout (with a relaxed fallback for timestamp drift).
        if let appleWorkout = try await fetchBestMatchingAppleWorkout(for: workout) {
            healthData.appleWorkoutType = appleWorkout.workoutActivityType.name
            healthData.appleWorkoutDuration = appleWorkout.duration
            healthData.appleWorkoutUUID = appleWorkout.uuid

            // Get additional metrics from Apple workout
            if let avgSpeed = appleWorkout.statistics(for: HKQuantityType(.runningSpeed))?.averageQuantity() {
                healthData.avgSpeed = avgSpeed.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))
            }
            if let avgPower = appleWorkout.statistics(for: HKQuantityType(.runningPower))?.averageQuantity() {
                healthData.avgPower = avgPower.doubleValue(for: .watt())
            }

            // Try to capture the start location (if Health has a route sample for this workout).
            do {
                if let startLocation = try await fetchWorkoutRouteStartLocation(for: appleWorkout) {
                    healthData.workoutRouteStartLatitude = startLocation.coordinate.latitude
                    healthData.workoutRouteStartLongitude = startLocation.coordinate.longitude
                }
            } catch {
                // Route data is optional; don't fail the overall health sync.
            }
        }

        // Store in local cache
        healthDataStore[workout.id] = healthData
        if persist {
            persistData()
            lastSyncDate = Date()
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
        }

        return healthData
    }

    /// Lightweight background sync for the most recent workouts that are missing data.
    func syncRecentWorkoutsIfNeeded(_ workouts: [Workout]) async {
        guard authorizationStatus == .authorized else { return }
        guard isHealthKitAvailable() else { return }
        guard !isAutoSyncing else { return }

        let missing = workouts.filter { healthDataStore[$0.id] == nil }
        let recentMissing = Array(missing.prefix(3))
        guard !recentMissing.isEmpty else { return }

        isAutoSyncing = true
        defer { isAutoSyncing = false }
        syncProgress = 0
        syncedWorkoutsCount = 0

        for (index, workout) in recentMissing.enumerated() {
            do {
                _ = try await syncHealthDataForWorkout(workout, persist: false)
            } catch {
                print("Auto sync failed for workout \(workout.id): \(error)")
            }

            syncedWorkoutsCount = index + 1
            syncProgress = Double(index + 1) / Double(recentMissing.count)
        }

        lastSyncDate = Date()
        userDefaults.set(lastSyncDate, forKey: lastSyncKey)
        persistData()
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
            persistData()
            return []
        }

        let total = Double(workouts.count)

        for (index, workout) in workouts.enumerated() {
            do {
                let healthData = try await syncHealthDataForWorkout(workout, persist: false)
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
        persistData()

        return results
    }

    /// Best-effort route-location hydration for recent workouts.
    /// Used by Gym discovery so it can work even when route points weren't previously cached.
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

        try await requestWorkoutRouteAuthorization()

        let sorted = workouts.sorted { $0.date > $1.date }
        let targets = sorted
            .prefix(maxWorkouts)
            .filter { workout in
                guard let cached = healthDataStore[workout.id] else { return true }
                return cached.workoutRouteStartLatitude == nil || cached.workoutRouteStartLongitude == nil
            }

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
        var routeStartByAppleUUID: [UUID: CLLocation] = [:]
        var appleUUIDsWithNoRoute: Set<UUID> = []
        var updated = 0

        for workout in targets {
            let cached = healthDataStore[workout.id]

            let appleWorkout: HKWorkout?
            if let appleUUID = cached?.appleWorkoutUUID, let exact = appleByUUID[appleUUID] {
                appleWorkout = exact
            } else {
                appleWorkout = bestMatchingAppleWorkout(
                    for: workout,
                    candidates: appleWorkouts,
                    strictStartDifferenceSeconds: 20 * 60,
                    relaxedStartDifferenceSeconds: relaxedTolerance
                )
            }

            guard let appleWorkout else { continue }

            let appleUUID = appleWorkout.uuid
            let startLocation: CLLocation?
            if let existing = routeStartByAppleUUID[appleUUID] {
                startLocation = existing
            } else if appleUUIDsWithNoRoute.contains(appleUUID) {
                startLocation = nil
            } else {
                let fetched = try await fetchWorkoutRouteStartLocation(for: appleWorkout)
                if let fetched {
                    routeStartByAppleUUID[appleUUID] = fetched
                } else {
                    appleUUIDsWithNoRoute.insert(appleUUID)
                }
                startLocation = fetched
            }

            guard let startLocation else { continue }

            var healthData = cached ?? WorkoutHealthData(
                workoutId: workout.id,
                workoutDate: workout.date,
                workoutStartTime: workout.estimatedWindow(defaultMinutes: 60).start,
                workoutEndTime: workout.estimatedWindow(defaultMinutes: 60).end
            )
            healthData.appleWorkoutUUID = appleWorkout.uuid
            healthData.workoutRouteStartLatitude = startLocation.coordinate.latitude
            healthData.workoutRouteStartLongitude = startLocation.coordinate.longitude
            healthDataStore[workout.id] = healthData
            updated += 1
        }

        if updated > 0 {
            persistData()
        }

        return updated
    }

    private func calculateWorkoutWindow(_ workout: Workout) -> (Date, Date) {
        let window = workout.estimatedWindow(defaultMinutes: 60)
        return (window.start, window.end)
    }

    // Duration parsing lives on Workout (Models/WorkoutModels.swift).
}
