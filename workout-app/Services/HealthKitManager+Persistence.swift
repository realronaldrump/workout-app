import Foundation

struct HealthCacheClearResult {
    let removedWorkoutEntries: Int
    let removedDailyEntries: Int
    let removedCoveredDays: Int

    var removedAnything: Bool {
        removedWorkoutEntries > 0 || removedDailyEntries > 0 || removedCoveredDays > 0
    }
}

extension HealthKitManager {
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    private var dataFileURL: URL {
        getDocumentsDirectory().appendingPathComponent("health_data_store.json")
    }

    private var dailyDataFileURL: URL {
        getDocumentsDirectory().appendingPathComponent("daily_health_store.json")
    }

    private var dailyCoverageFileURL: URL {
        getDocumentsDirectory().appendingPathComponent("daily_health_coverage.json")
    }

    func persistData() {
        let entries = Array(healthDataStore.values)
        let url = dataFileURL
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(entries)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                print("Failed to persist health data: \(error)")
            }
        }
    }

    func persistDailyHealthData() {
        let entries = Array(dailyHealthStore.values)
        let url = dailyDataFileURL
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(entries)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                print("Failed to persist daily health data: \(error)")
            }
        }
    }

    func persistDailyHealthCoverage() {
        let coveredDays = Array(dailyHealthCoverage).sorted()
        let url = dailyCoverageFileURL
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(coveredDays)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                print("Failed to persist daily health coverage: \(error)")
            }
        }
    }

    func clearCachedHealthData(
        in range: DateInterval? = nil,
        includeWorkoutData: Bool = true,
        includeDailyData: Bool = true
    ) -> HealthCacheClearResult {
        var removedWorkoutEntries = 0
        var removedDailyEntries = 0
        var removedCoveredDays = 0

        if includeWorkoutData {
            if let range {
                let workoutIDsToRemove = healthDataStore.compactMap { workoutID, healthData in
                    range.contains(healthData.workoutDate) ? workoutID : nil
                }
                removedWorkoutEntries = workoutIDsToRemove.count
                workoutIDsToRemove.forEach { healthDataStore.removeValue(forKey: $0) }
            } else {
                removedWorkoutEntries = healthDataStore.count
                healthDataStore.removeAll()
            }

            if removedWorkoutEntries > 0 {
                lastSyncDate = nil
                syncProgress = 0
                syncedWorkoutsCount = 0
                userDefaults.removeObject(forKey: lastSyncKey)
                persistData()
            }
        }

        if includeDailyData {
            var didMutateDailyCache = false

            if let range {
                let matchingDailyKeys = dailyHealthStore.keys.filter { range.contains($0) }
                removedDailyEntries = matchingDailyKeys.count
                matchingDailyKeys.forEach { dailyHealthStore.removeValue(forKey: $0) }

                let coveredDaysToRemove = dailyHealthCoverage.filter { range.contains($0) }
                removedCoveredDays = coveredDaysToRemove.count
                coveredDaysToRemove.forEach { dailyHealthCoverage.remove($0) }

                didMutateDailyCache = !matchingDailyKeys.isEmpty || !coveredDaysToRemove.isEmpty
            } else {
                removedDailyEntries = dailyHealthStore.count
                removedCoveredDays = dailyHealthCoverage.count
                dailyHealthStore.removeAll()
                dailyHealthCoverage.removeAll()
                didMutateDailyCache = removedDailyEntries > 0 || removedCoveredDays > 0
            }

            if didMutateDailyCache {
                lastDailySyncDate = nil
                dailySyncProgress = 0
                userDefaults.removeObject(forKey: lastDailySyncKey)
                persistDailyHealthData()
                persistDailyHealthCoverage()
            }
        }

        return HealthCacheClearResult(
            removedWorkoutEntries: removedWorkoutEntries,
            removedDailyEntries: removedDailyEntries,
            removedCoveredDays: removedCoveredDays
        )
    }

    func invalidateDailyHealthCache() {
        dailyHealthStore.removeAll()
        dailyHealthCoverage.removeAll()
        lastDailySyncDate = nil
        dailySyncProgress = 0
        userDefaults.removeObject(forKey: lastDailySyncKey)
        persistDailyHealthData()
        persistDailyHealthCoverage()
    }

    func clearCachedWorkoutSleepSummaries(persist: Bool = true) {
        var updatedStore: [UUID: WorkoutHealthData] = [:]

        for (workoutID, var healthData) in healthDataStore {
            healthData.sleepSummary = nil
            updatedStore[workoutID] = healthData
        }

        healthDataStore = updatedStore
        if persist {
            persistData()
        }
    }

    func loadPersistedData() {
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

    func loadPersistedDailyHealthData() {
        cleanupLegacyUserDefaults()
        earliestAvailableDailyHealthDate = userDefaults.object(forKey: earliestAvailableDailyHealthDateKey) as? Date
        let storedVersion = userDefaults.integer(forKey: dailyHealthStoreVersionKey)
        if storedVersion < currentDailyHealthStoreVersion {
            // Daily sleep aggregation logic changed; discard old cached daily store to avoid showing inflated sleep.
            dailyHealthStore.removeAll()
            dailyHealthCoverage.removeAll()
            lastDailySyncDate = nil
            userDefaults.removeObject(forKey: lastDailySyncKey)

            do {
                if FileManager.default.fileExists(atPath: dailyDataFileURL.path) {
                    try FileManager.default.removeItem(at: dailyDataFileURL)
                    print("Deleted daily health data store file (version bump)")
                }
                if FileManager.default.fileExists(atPath: dailyCoverageFileURL.path) {
                    try FileManager.default.removeItem(at: dailyCoverageFileURL)
                    print("Deleted daily health coverage file (version bump)")
                }
            } catch {
                print("Failed to delete daily health data file during version bump: \(error)")
            }

            userDefaults.set(currentDailyHealthStoreVersion, forKey: dailyHealthStoreVersionKey)
            return
        }

        do {
            guard FileManager.default.fileExists(atPath: dailyDataFileURL.path) else { return }
            let data = try Data(contentsOf: dailyDataFileURL)
            let dailyArray = try JSONDecoder().decode([DailyHealthData].self, from: data)
            dailyHealthStore = Dictionary(uniqueKeysWithValues: dailyArray.map { ($0.dayStart, $0) })
            print("Loaded \(dailyHealthStore.count) daily health records")
        } catch {
            print("Failed to load persisted daily health data: \(error)")
        }

        do {
            guard FileManager.default.fileExists(atPath: dailyCoverageFileURL.path) else {
                dailyHealthCoverage = []
                lastDailySyncDate = userDefaults.object(forKey: lastDailySyncKey) as? Date
                return
            }
            let data = try Data(contentsOf: dailyCoverageFileURL)
            let coverageArray = try JSONDecoder().decode([Date].self, from: data)
            dailyHealthCoverage = Set(coverageArray)
            print("Loaded \(dailyHealthCoverage.count) covered daily health days")
        } catch {
            dailyHealthCoverage = []
            print("Failed to load persisted daily health coverage: \(error)")
        }

        lastDailySyncDate = userDefaults.object(forKey: lastDailySyncKey) as? Date
    }

    /// Clears all health data from memory and disk
    func clearAllData() {
        // Clear memory
        healthDataStore.removeAll()
        lastSyncDate = nil
        syncProgress = 0
        syncedWorkoutsCount = 0
        syncError = nil
        dailyHealthStore.removeAll()
        dailyHealthCoverage.removeAll()
        lastDailySyncDate = nil
        dailySyncProgress = 0
        isDailySyncing = false
        earliestAvailableDailyHealthDate = nil

        // Clear persistence
        cleanupLegacyUserDefaults()
        userDefaults.removeObject(forKey: lastSyncKey)
        userDefaults.removeObject(forKey: lastDailySyncKey)
        userDefaults.removeObject(forKey: earliestAvailableDailyHealthDateKey)
        userDefaults.removeObject(forKey: pendingWorkoutSleepSummaryRefreshKey)

        do {
            if FileManager.default.fileExists(atPath: dataFileURL.path) {
                try FileManager.default.removeItem(at: dataFileURL)
                print("Deleted health data store file")
            }
            if FileManager.default.fileExists(atPath: dailyDataFileURL.path) {
                try FileManager.default.removeItem(at: dailyDataFileURL)
                print("Deleted daily health data store file")
            }
            if FileManager.default.fileExists(atPath: dailyCoverageFileURL.path) {
                try FileManager.default.removeItem(at: dailyCoverageFileURL)
                print("Deleted daily health coverage file")
            }
        } catch {
            print("Failed to delete health data file: \(error)")
        }
    }

    func cleanupLegacyUserDefaults() {
        if userDefaults.data(forKey: healthDataKey) != nil {
            userDefaults.removeObject(forKey: healthDataKey)
        }
        if userDefaults.data(forKey: dailyHealthDataKey) != nil {
            userDefaults.removeObject(forKey: dailyHealthDataKey)
        }
    }
}
