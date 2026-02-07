import Foundation
import HealthKit

extension HealthKitManager {
    /// Sync health data for a single workout
    func syncHealthDataForWorkout(_ workout: Workout, persist: Bool = true) async throws -> WorkoutHealthData {
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

        isSyncing = true
        defer { isSyncing = false }
        syncProgress = 0
        syncedWorkoutsCount = 0
        syncError = nil

        var results: [WorkoutHealthData] = []
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
}
