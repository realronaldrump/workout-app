import Foundation

struct HealthCacheClearResult {
    let removedWorkoutEntries: Int
    let removedDailyEntries: Int
    let removedCoveredDays: Int

    var removedAnything: Bool {
        removedWorkoutEntries > 0 || removedDailyEntries > 0 || removedCoveredDays > 0
    }
}

struct HealthBackupMergeResult {
    let workoutInserted: Int
    let workoutSkipped: Int
    let dailyInserted: Int
    let dailySkipped: Int
    let coverageInserted: Int
}

extension HealthKitManager {
    private var database: AppDatabase { AppDatabase.shared }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    private var workoutDataDirectoryURL: URL {
        getDocumentsDirectory().appendingPathComponent("health_data_store", isDirectory: true)
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

    private func removeLegacyItem(at url: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            print("Failed to remove legacy cache item at \(url.lastPathComponent): \(error)")
        }
    }

    private func removeLegacyWorkoutPersistenceFiles() {
        removeLegacyItem(at: workoutDataDirectoryURL)
        removeLegacyItem(at: dataFileURL)
    }

    private func removeLegacyDailyDataFile() {
        removeLegacyItem(at: dailyDataFileURL)
    }

    private func removeLegacyDailyCoverageFile() {
        removeLegacyItem(at: dailyCoverageFileURL)
    }

    private nonisolated static func shouldPersistRawSamples(for workoutDate: Date, reference: Date = Date()) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .day, value: -180, to: reference)
            ?? reference
        return workoutDate >= cutoff
    }

    private nonisolated static func preparedWorkoutCacheEntry(
        _ entry: WorkoutHealthData,
        reference: Date = Date()
    ) -> WorkoutHealthData {
        guard !shouldPersistRawSamples(for: entry.workoutDate, reference: reference) else {
            var prepared = entry
            prepared.captureRawSampleSummaries()
            return prepared
        }

        var prepared = entry
        prepared.removeRawSamplesPreservingSummaries()
        return prepared
    }

    func persistData(changedWorkoutIDs: [UUID]? = nil, removedWorkoutIDs: [UUID] = []) {
        let snapshot = healthDataStore
        let idsToPersist = changedWorkoutIDs ?? Array(snapshot.keys)
        let idsToRemove = removedWorkoutIDs
        let database = database
        let preparedEntries = idsToPersist.compactMap { workoutID in
            snapshot[workoutID].map { Self.preparedWorkoutCacheEntry($0) }
        }

        // Keep persistence work ordered so older snapshots cannot land after newer ones.
        Task { @MainActor in
            do {
                if !preparedEntries.isEmpty {
                    try database.saveWorkoutHealthData(preparedEntries)
                }
                if !idsToRemove.isEmpty {
                    try database.deleteWorkoutHealthData(ids: idsToRemove)
                }
                removeLegacyWorkoutPersistenceFiles()
            } catch {
                print("Failed to persist health data: \(error)")
            }
        }
    }

    func persistDailyHealthData() {
        let entries = Array(dailyHealthStore.values)
        let database = database
        Task { @MainActor in
            do {
                try database.saveDailyHealthData(entries)
                removeLegacyDailyDataFile()
            } catch {
                print("Failed to persist daily health data: \(error)")
            }
        }
    }

    func persistDailyHealthCoverage() {
        let coveredDays = dailyHealthCoverage
        let database = database
        Task { @MainActor in
            do {
                try database.saveDailyHealthCoverage(coveredDays)
                removeLegacyDailyCoverageFile()
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

                if removedWorkoutEntries > 0 {
                    persistData(changedWorkoutIDs: [], removedWorkoutIDs: workoutIDsToRemove)
                }
            } else {
                let allWorkoutIDs = Array(healthDataStore.keys)
                removedWorkoutEntries = healthDataStore.count
                healthDataStore.removeAll()

                if removedWorkoutEntries > 0 {
                    persistData(changedWorkoutIDs: [], removedWorkoutIDs: allWorkoutIDs)
                }
            }

            if removedWorkoutEntries > 0 {
                lastSyncDate = nil
                syncProgress = 0
                syncedWorkoutsCount = 0
                userDefaults.removeObject(forKey: lastSyncKey)
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
            persistData(changedWorkoutIDs: Array(updatedStore.keys))
        }
    }

    func mergeCachedHealthDataFromBackup(
        workoutEntries: [WorkoutHealthData],
        dailyEntries: [DailyHealthData],
        dailyCoverage: [Date],
        workoutIdMap: [UUID: UUID]
    ) -> HealthBackupMergeResult {
        var workoutInserted = 0
        var workoutSkipped = 0
        var changedWorkoutIDs: [UUID] = []

        for entry in workoutEntries {
            let targetWorkoutId = workoutIdMap[entry.workoutId] ?? entry.workoutId
            guard healthDataStore[targetWorkoutId] == nil else {
                workoutSkipped += 1
                continue
            }

            let remapped = entry.remappingWorkoutId(targetWorkoutId)
            healthDataStore[targetWorkoutId] = remapped
            changedWorkoutIDs.append(targetWorkoutId)
            workoutInserted += 1
        }

        if !changedWorkoutIDs.isEmpty {
            persistData(changedWorkoutIDs: changedWorkoutIDs)
        }

        var dailyInserted = 0
        var dailySkipped = 0
        for entry in dailyEntries {
            guard dailyHealthStore[entry.dayStart] == nil else {
                dailySkipped += 1
                continue
            }
            dailyHealthStore[entry.dayStart] = entry
            dailyInserted += 1
        }

        if dailyInserted > 0 {
            persistDailyHealthData()
        }

        let beforeCoverageCount = dailyHealthCoverage.count
        dailyHealthCoverage.formUnion(dailyCoverage)
        let coverageInserted = dailyHealthCoverage.count - beforeCoverageCount
        if coverageInserted > 0 {
            persistDailyHealthCoverage()
        }

        return HealthBackupMergeResult(
            workoutInserted: workoutInserted,
            workoutSkipped: workoutSkipped,
            dailyInserted: dailyInserted,
            dailySkipped: dailySkipped,
            coverageInserted: coverageInserted
        )
    }

    func loadPersistedData() {
        cleanupLegacyUserDefaults()

        do {
            let stored = try database.loadWorkoutHealthData()
            let preparedEntries = stored.map { Self.preparedWorkoutCacheEntry($0) }
            healthDataStore = Dictionary(uniqueKeysWithValues: preparedEntries.map { ($0.workoutId, $0) })
            removeLegacyWorkoutPersistenceFiles()
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
                try database.clearDailyHealthData()
                try database.clearDailyHealthCoverage()
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
            let stored = try database.loadDailyHealthData()
            dailyHealthStore = Dictionary(uniqueKeysWithValues: stored.map { ($0.dayStart, $0) })
            removeLegacyDailyDataFile()
            print("Loaded \(dailyHealthStore.count) daily health records")
        } catch {
            print("Failed to load persisted daily health data: \(error)")
        }

        do {
            dailyHealthCoverage = try database.loadDailyHealthCoverage()
            removeLegacyDailyCoverageFile()
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
            try database.clearWorkoutHealthData()
            try database.clearDailyHealthData()
            try database.clearDailyHealthCoverage()
            if FileManager.default.fileExists(atPath: workoutDataDirectoryURL.path) {
                try FileManager.default.removeItem(at: workoutDataDirectoryURL)
                print("Deleted health data store directory")
            }
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
