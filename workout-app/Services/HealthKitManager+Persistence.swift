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
    private static let persistedRawSampleRetentionDays = 180

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

    private func workoutDataFileURL(for workoutID: UUID) -> URL {
        workoutDataDirectoryURL.appendingPathComponent("\(workoutID.uuidString).json")
    }

    private func shouldPersistRawSamples(for workoutDate: Date, reference: Date = Date()) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.persistedRawSampleRetentionDays, to: reference)
            ?? reference
        return workoutDate >= cutoff
    }

    private func preparedWorkoutCacheEntry(_ entry: WorkoutHealthData, reference: Date = Date()) -> WorkoutHealthData {
        guard !shouldPersistRawSamples(for: entry.workoutDate, reference: reference) else {
            var prepared = entry
            prepared.captureRawSampleSummaries()
            return prepared
        }

        var prepared = entry
        prepared.removeRawSamplesPreservingSummaries()
        return prepared
    }

    private func writeWorkoutEntriesToDirectory(_ entries: [WorkoutHealthData]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: workoutDataDirectoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        let preparedEntries = entries.map(preparedWorkoutCacheEntry)
        let validFileNames = Set(preparedEntries.map { "\($0.workoutId.uuidString).json" })

        for entry in preparedEntries {
            let fileURL = workoutDataFileURL(for: entry.workoutId)
            let data = try encoder.encode(entry)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        }

        let directoryContents = try fileManager.contentsOfDirectory(
            at: workoutDataDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for fileURL in directoryContents where !validFileNames.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    func persistData(changedWorkoutIDs: [UUID]? = nil, removedWorkoutIDs: [UUID] = []) {
        let snapshot = healthDataStore
        let directoryURL = workoutDataDirectoryURL
        let idsToPersist = changedWorkoutIDs ?? Array(snapshot.keys)
        let idsToRemove = removedWorkoutIDs

        Task.detached(priority: .utility) {
            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

                let encoder = JSONEncoder()

                for workoutID in idsToPersist {
                    let fileURL = directoryURL.appendingPathComponent("\(workoutID.uuidString).json")
                    guard let entry = snapshot[workoutID] else {
                        if fileManager.fileExists(atPath: fileURL.path) {
                            try? fileManager.removeItem(at: fileURL)
                        }
                        continue
                    }

                    let preparedEntry = preparedWorkoutCacheEntry(entry)
                    let data = try encoder.encode(preparedEntry)
                    try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
                }

                for workoutID in idsToRemove {
                    let fileURL = directoryURL.appendingPathComponent("\(workoutID.uuidString).json")
                    if fileManager.fileExists(atPath: fileURL.path) {
                        try? fileManager.removeItem(at: fileURL)
                    }
                }

                if changedWorkoutIDs == nil {
                    let validFileNames = Set(snapshot.keys.map { "\($0.uuidString).json" })
                    let directoryContents = try fileManager.contentsOfDirectory(
                        at: directoryURL,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )

                    for fileURL in directoryContents where !validFileNames.contains(fileURL.lastPathComponent) {
                        try? fileManager.removeItem(at: fileURL)
                    }
                }
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

    func loadPersistedData() {
        cleanupLegacyUserDefaults()

        do {
            let fileManager = FileManager.default

            if fileManager.fileExists(atPath: workoutDataDirectoryURL.path) {
                let fileURLs = try fileManager.contentsOfDirectory(
                    at: workoutDataDirectoryURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                    .filter { $0.pathExtension == "json" }

                if !fileURLs.isEmpty {
                    let decoder = JSONDecoder()
                    let healthDataArray = try fileURLs.map { fileURL in
                        let data = try Data(contentsOf: fileURL)
                        let decoded = try decoder.decode(WorkoutHealthData.self, from: data)
                        return preparedWorkoutCacheEntry(decoded)
                    }
                    healthDataStore = Dictionary(uniqueKeysWithValues: healthDataArray.map { ($0.workoutId, $0) })
                    print("Loaded \(healthDataStore.count) health records")
                    lastSyncDate = userDefaults.object(forKey: lastSyncKey) as? Date
                    return
                }
            }
        } catch {
            print("Failed to load persisted health data directory: \(error)")
        }

        do {
            guard FileManager.default.fileExists(atPath: dataFileURL.path) else { return }
            let data = try Data(contentsOf: dataFileURL)
            let healthDataArray = try JSONDecoder().decode([WorkoutHealthData].self, from: data)
            let preparedEntries = healthDataArray.map(preparedWorkoutCacheEntry)
            healthDataStore = Dictionary(uniqueKeysWithValues: preparedEntries.map { ($0.workoutId, $0) })
            try writeWorkoutEntriesToDirectory(preparedEntries)
            try? FileManager.default.removeItem(at: dataFileURL)
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
