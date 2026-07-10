import Foundation

/// Narrow persistence surface used by the Health cache coordinator.
///
/// Keeping this protocol nonisolated lets the coordinator own the blocking Core Data
/// adapter without accidentally inheriting the app's default `MainActor` isolation.
nonisolated protocol HealthCacheDatabase: Sendable {
    func loadWorkoutHealthData() throws -> [WorkoutHealthData]
    func saveWorkoutHealthData(_ entries: [WorkoutHealthData]) throws
    func deleteWorkoutHealthData(ids: [UUID]) throws
    func clearWorkoutHealthData() throws

    func loadDailyHealthData() throws -> [DailyHealthData]
    func saveDailyHealthData(_ entries: [DailyHealthData]) throws
    func clearDailyHealthData() throws

    func loadDailyHealthCoverage() throws -> Set<Date>
    func saveDailyHealthCoverage(_ coveredDays: Set<Date>) throws
    func clearDailyHealthCoverage() throws
}

extension AppDatabase: HealthCacheDatabase {}

/// Immutable transfer values are safe to move from the persistence actor to MainActor.
/// The wrapped model graph consists only of value types and is discarded by the actor
/// after it returns, so no mutable reference is shared across isolation domains.
nonisolated struct HealthCacheBootstrapSnapshot: @unchecked Sendable {
    let workoutData: [UUID: WorkoutHealthData]
    let dailyData: [Date: DailyHealthData]
    let dailyCoverage: Set<Date>
    let didLoadWorkoutData: Bool
    let didLoadDailyData: Bool
    let didLoadDailyCoverage: Bool
    let didResetDailyStore: Bool
    let prunedWorkoutCount: Int
    let errors: [String]
}

nonisolated struct WorkoutHealthPersistencePayload: @unchecked Sendable {
    let entries: [WorkoutHealthData]
    let removedIDs: [UUID]
    let referenceDate: Date
}

nonisolated struct DailyHealthPersistencePayload: @unchecked Sendable {
    let entries: [DailyHealthData]
}

nonisolated struct DailyHealthCoveragePersistencePayload: @unchecked Sendable {
    let coveredDays: Set<Date>
}

/// Serializes all Health cache access away from MainActor.
///
/// `AppDatabase` internally uses `performAndWait`. Calling it from this actor means that
/// wait can no longer freeze SwiftUI, while the manager's task chain preserves invocation
/// order before operations reach this actor.
actor HealthCachePersistenceCoordinator {
    private let databaseProvider: @Sendable () -> any HealthCacheDatabase
    private var resolvedDatabase: (any HealthCacheDatabase)?

    init(
        databaseProvider: @escaping @Sendable () -> any HealthCacheDatabase = { AppDatabase.shared }
    ) {
        self.databaseProvider = databaseProvider
    }

    func loadSnapshot(
        resetDailyStore: Bool,
        referenceDate: Date = Date()
    ) -> HealthCacheBootstrapSnapshot {
        let database = database()
        var errors: [String] = []
        var workoutData: [UUID: WorkoutHealthData] = [:]
        var dailyData: [Date: DailyHealthData] = [:]
        var dailyCoverage: Set<Date> = []
        var didLoadWorkoutData = false
        var didLoadDailyData = false
        var didLoadDailyCoverage = false
        var didResetDailyStore = false
        var prunedEntries: [WorkoutHealthData] = []

        do {
            let stored = try database.loadWorkoutHealthData()
            workoutData.reserveCapacity(stored.count)

            for entry in stored {
                let shouldPrune = entry.hasRawSamples &&
                    !HealthKitManager.shouldPersistRawSamples(
                        for: entry.workoutDate,
                        reference: referenceDate
                    )
                let prepared = HealthKitManager.preparedWorkoutCacheEntry(
                    entry,
                    reference: referenceDate
                )
                workoutData[prepared.workoutId] = prepared
                if shouldPrune {
                    prunedEntries.append(prepared)
                }
            }
            didLoadWorkoutData = true

            if !prunedEntries.isEmpty {
                do {
                    // Persist the retention policy so old raw payloads are not decoded again
                    // on every launch.
                    try database.saveWorkoutHealthData(prunedEntries)
                } catch {
                    errors.append("Failed to persist pruned workout health data: \(error)")
                }
            }
        } catch {
            errors.append("Failed to load persisted workout health data: \(error)")
        }

        if resetDailyStore {
            do {
                try database.clearDailyHealthData()
                try database.clearDailyHealthCoverage()
                didResetDailyStore = true
            } catch {
                errors.append("Failed to reset the versioned daily health cache: \(error)")
            }
        } else {
            do {
                let stored = try database.loadDailyHealthData()
                dailyData.reserveCapacity(stored.count)
                for entry in stored {
                    dailyData[entry.dayStart] = entry
                }
                didLoadDailyData = true
            } catch {
                errors.append("Failed to load persisted daily health data: \(error)")
            }

            do {
                dailyCoverage = try database.loadDailyHealthCoverage()
                didLoadDailyCoverage = true
            } catch {
                errors.append("Failed to load persisted daily health coverage: \(error)")
            }
        }

        return HealthCacheBootstrapSnapshot(
            workoutData: workoutData,
            dailyData: dailyData,
            dailyCoverage: dailyCoverage,
            didLoadWorkoutData: didLoadWorkoutData,
            didLoadDailyData: didLoadDailyData,
            didLoadDailyCoverage: didLoadDailyCoverage,
            didResetDailyStore: didResetDailyStore,
            prunedWorkoutCount: prunedEntries.count,
            errors: errors
        )
    }

    func persistWorkoutData(_ payload: WorkoutHealthPersistencePayload) throws {
        let database = database()
        let preparedEntries = payload.entries.map {
            HealthKitManager.preparedWorkoutCacheEntry($0, reference: payload.referenceDate)
        }

        if !preparedEntries.isEmpty {
            try database.saveWorkoutHealthData(preparedEntries)
        }
        if !payload.removedIDs.isEmpty {
            try database.deleteWorkoutHealthData(ids: payload.removedIDs)
        }
    }

    func persistDailyData(_ payload: DailyHealthPersistencePayload) throws {
        try database().saveDailyHealthData(payload.entries)
    }

    func persistDailyCoverage(_ payload: DailyHealthCoveragePersistencePayload) throws {
        try database().saveDailyHealthCoverage(payload.coveredDays)
    }

    func clearAllHealthData() throws {
        let database = database()
        try database.clearWorkoutHealthData()
        try database.clearDailyHealthData()
        try database.clearDailyHealthCoverage()
    }

    func clearWorkoutHealthData() throws {
        try database().clearWorkoutHealthData()
    }

    private func database() -> any HealthCacheDatabase {
        if let resolvedDatabase {
            return resolvedDatabase
        }
        let database = databaseProvider()
        resolvedDatabase = database
        return database
    }
}

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

    fileprivate nonisolated static func shouldPersistRawSamples(for workoutDate: Date, reference: Date = Date()) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .day, value: -180, to: reference)
            ?? reference
        return workoutDate >= cutoff
    }

    fileprivate nonisolated static func preparedWorkoutCacheEntry(
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

    /// Enqueues a workout-cache write and returns a handle callers can await when their
    /// success UI depends on the data being durable.
    @discardableResult
    func persistData(
        changedWorkoutIDs: [UUID]? = nil,
        removedWorkoutIDs: [UUID] = []
    ) -> Task<Void, Error> {
        let bootstrap = startPersistedCacheBootstrapIfNeeded()
        let previous = latestCachePersistenceOperation
        let coordinator = cachePersistenceCoordinator

        let operation = Task<Void, Error> { @MainActor in
            await bootstrap.value
            if let previous {
                _ = try? await previous.value
            }

            // Take the snapshot only after earlier writes and cache bootstrap complete. That
            // prevents a delayed old snapshot from landing after a newer in-memory mutation.
            let idsToPersist = changedWorkoutIDs ?? Array(self.healthDataStore.keys)
            let entries = idsToPersist.compactMap { self.healthDataStore[$0] }
            let payload = WorkoutHealthPersistencePayload(
                entries: entries,
                removedIDs: removedWorkoutIDs,
                referenceDate: Date()
            )
            do {
                try await coordinator.persistWorkoutData(payload)
            } catch {
                self.recordCachePersistenceFailure(error)
                throw error
            }
            self.removeLegacyWorkoutPersistenceFiles()
        }

        trackPersistenceOperation(operation, label: "workout health data")
        return operation
    }

    /// Enqueues a daily-cache write in the same total order as workout and coverage writes.
    @discardableResult
    func persistDailyHealthData() -> Task<Void, Error> {
        let bootstrap = startPersistedCacheBootstrapIfNeeded()
        let previous = latestCachePersistenceOperation
        let coordinator = cachePersistenceCoordinator

        let operation = Task<Void, Error> { @MainActor in
            await bootstrap.value
            if let previous {
                _ = try? await previous.value
            }

            let payload = DailyHealthPersistencePayload(
                entries: Array(self.dailyHealthStore.values)
            )
            do {
                try await coordinator.persistDailyData(payload)
            } catch {
                self.recordCachePersistenceFailure(error)
                throw error
            }
            self.removeLegacyDailyDataFile()
        }

        trackPersistenceOperation(operation, label: "daily health data")
        return operation
    }

    /// Enqueues a coverage write in the same total order as every other Health cache write.
    @discardableResult
    func persistDailyHealthCoverage() -> Task<Void, Error> {
        let bootstrap = startPersistedCacheBootstrapIfNeeded()
        let previous = latestCachePersistenceOperation
        let coordinator = cachePersistenceCoordinator

        let operation = Task<Void, Error> { @MainActor in
            await bootstrap.value
            if let previous {
                _ = try? await previous.value
            }

            let payload = DailyHealthCoveragePersistencePayload(
                coveredDays: self.dailyHealthCoverage
            )
            do {
                try await coordinator.persistDailyCoverage(payload)
            } catch {
                self.recordCachePersistenceFailure(error)
                throw error
            }
            self.removeLegacyDailyCoverageFile()
        }

        trackPersistenceOperation(operation, label: "daily health coverage")
        return operation
    }

    /// Waits for the most recently enqueued cache write. New writes always wait for their
    /// predecessor, so awaiting this handle drains the current ordered queue.
    func waitForPendingCachePersistence() async throws {
        var latestFailure: Error?
        if let latestCachePersistenceOperation {
            do {
                try await latestCachePersistenceOperation.value
            } catch {
                latestFailure = error
            }
        }

        let failure = pendingCachePersistenceFailure ?? latestFailure
        pendingCachePersistenceFailure = nil
        if let failure {
            throw failure
        }
    }

    private func recordCachePersistenceFailure(_ error: Error) {
        if pendingCachePersistenceFailure == nil {
            pendingCachePersistenceFailure = error
        }
    }

    private func trackPersistenceOperation(
        _ operation: Task<Void, Error>,
        label: String
    ) {
        latestCachePersistenceOperation = operation
        Task { @MainActor in
            do {
                try await operation.value
            } catch {
                print("Failed to persist \(label): \(error)")
            }
        }
    }

    func clearCachedHealthData(
        in range: DateInterval? = nil,
        includeWorkoutData: Bool = true,
        includeDailyData: Bool = true
    ) -> HealthCacheClearResult {
        if range == nil, includeWorkoutData, includeDailyData {
            let result = HealthCacheClearResult(
                removedWorkoutEntries: healthDataStore.count,
                removedDailyEntries: dailyHealthStore.count,
                removedCoveredDays: dailyHealthCoverage.count
            )
            // The database can contain records that an in-flight bootstrap has not published
            // yet, so an all-cache clear must issue a real database clear even when memory is empty.
            clearAllData()
            return result
        }

        if !hasBootstrappedPersistedCache, range == nil {
            if includeWorkoutData { discardWorkoutBootstrapSnapshot = true }
            if includeDailyData { discardDailyBootstrapSnapshot = true }
        }

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
                removedWorkoutEntries = healthDataStore.count
                clearAllWorkoutHealthData()
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
                // Persist an empty snapshot even if memory was empty: persisted records may
                // still be waiting in an in-flight bootstrap.
                didMutateDailyCache = true
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

    /// Clears every cached workout-health record and exposes persistence failures to callers.
    /// This is used when workout history is deleted while daily Health history is retained.
    @discardableResult
    func clearAllWorkoutHealthData() -> Task<Void, Error> {
        if !hasBootstrappedPersistedCache {
            discardWorkoutBootstrapSnapshot = true
        }

        healthDataStore.removeAll()
        lastSyncDate = nil
        syncProgress = 0
        syncedWorkoutsCount = 0
        syncError = nil
        userDefaults.removeObject(forKey: lastSyncKey)
        userDefaults.removeObject(forKey: pendingWorkoutSleepSummaryRefreshKey)

        let bootstrap = startPersistedCacheBootstrapIfNeeded()
        let previous = latestCachePersistenceOperation
        let coordinator = cachePersistenceCoordinator
        let operation = Task<Void, Error> { @MainActor in
            await bootstrap.value
            if let previous {
                _ = try? await previous.value
            }
            try await coordinator.clearWorkoutHealthData()
            self.removeLegacyWorkoutPersistenceFiles()
        }
        trackPersistenceOperation(operation, label: "cleared workout health data")
        return operation
    }

    func invalidateDailyHealthCache() {
        if !hasBootstrappedPersistedCache {
            discardDailyBootstrapSnapshot = true
        }
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

    /// Loads every persisted Health cache in one off-main operation and applies the result
    /// without an intervening suspension on MainActor.
    func bootstrapPersistedDataIfNeeded() async {
        await startPersistedCacheBootstrapIfNeeded().value
    }

    /// Compatibility entry point for callers being migrated to
    /// `await bootstrapPersistedDataIfNeeded()`.
    func loadPersistedData() {
        startPersistedCacheBootstrapIfNeeded()
    }

    /// Compatibility entry point for callers being migrated to
    /// `await bootstrapPersistedDataIfNeeded()`.
    func loadPersistedDailyHealthData() {
        startPersistedCacheBootstrapIfNeeded()
    }

    @discardableResult
    func startPersistedCacheBootstrapIfNeeded() -> Task<Void, Never> {
        if hasBootstrappedPersistedCache {
            return Task<Void, Never> {}
        }
        if let persistedCacheBootstrapTask {
            return persistedCacheBootstrapTask
        }

        cleanupLegacyUserDefaults()
        let resetDailyStore = userDefaults.integer(forKey: dailyHealthStoreVersionKey) <
            currentDailyHealthStoreVersion
        let coordinator = cachePersistenceCoordinator
        let referenceDate = Date()

        let task = Task<Void, Never> { @MainActor in
            let snapshot = await coordinator.loadSnapshot(
                resetDailyStore: resetDailyStore,
                referenceDate: referenceDate
            )
            self.applyPersistedCacheBootstrapSnapshot(
                snapshot,
                resetDailyStore: resetDailyStore
            )
        }
        persistedCacheBootstrapTask = task
        return task
    }

    private func applyPersistedCacheBootstrapSnapshot(
        _ snapshot: HealthCacheBootstrapSnapshot,
        resetDailyStore: Bool
    ) {
        // A sync may have produced a value while the disk snapshot was loading. Merge that
        // newer in-memory value over the loaded cache rather than overwriting it.
        var mergedWorkoutData = snapshot.workoutData
        if discardWorkoutBootstrapSnapshot {
            mergedWorkoutData = healthDataStore
        } else {
            mergedWorkoutData.merge(healthDataStore) { _, current in current }
        }

        var mergedDailyData = snapshot.dailyData
        var mergedCoverage = snapshot.dailyCoverage
        if discardDailyBootstrapSnapshot {
            mergedDailyData = dailyHealthStore
            mergedCoverage = dailyHealthCoverage
        } else {
            mergedDailyData.merge(dailyHealthStore) { _, current in current }
            mergedCoverage.formUnion(dailyHealthCoverage)
        }

        // Apply the complete value graph synchronously. There is no await between these
        // assignments, so consumers never render a partially loaded cache on another turn.
        healthDataStore = mergedWorkoutData
        dailyHealthStore = mergedDailyData
        dailyHealthCoverage = mergedCoverage
        lastSyncDate = userDefaults.object(forKey: lastSyncKey) as? Date
        earliestAvailableDailyHealthDate = userDefaults.object(
            forKey: earliestAvailableDailyHealthDateKey
        ) as? Date

        if resetDailyStore {
            lastDailySyncDate = nil
            userDefaults.removeObject(forKey: lastDailySyncKey)
            if snapshot.didResetDailyStore {
                userDefaults.set(currentDailyHealthStoreVersion, forKey: dailyHealthStoreVersionKey)
                removeLegacyDailyDataFile()
                removeLegacyDailyCoverageFile()
            }
        } else {
            lastDailySyncDate = userDefaults.object(forKey: lastDailySyncKey) as? Date
        }

        if snapshot.didLoadWorkoutData {
            removeLegacyWorkoutPersistenceFiles()
        }
        if snapshot.didLoadDailyData {
            removeLegacyDailyDataFile()
        }
        if snapshot.didLoadDailyCoverage {
            removeLegacyDailyCoverageFile()
        }

        print("Loaded \(healthDataStore.count) health records")
        print("Loaded \(dailyHealthStore.count) daily health records")
        print("Loaded \(dailyHealthCoverage.count) covered daily health days")
        if snapshot.prunedWorkoutCount > 0 {
            print("Pruned raw samples from \(snapshot.prunedWorkoutCount) persisted health records")
        }
        snapshot.errors.forEach { print($0) }

        discardWorkoutBootstrapSnapshot = false
        discardDailyBootstrapSnapshot = false
        hasBootstrappedPersistedCache = true
        persistedCacheBootstrapTask = nil
    }

    /// Clears all health data from memory and enqueues an ordered off-main disk clear.
    @discardableResult
    func clearAllData() -> Task<Void, Error> {
        if !hasBootstrappedPersistedCache {
            // Prevent an in-flight bootstrap from repopulating memory after the user clears it.
            discardWorkoutBootstrapSnapshot = true
            discardDailyBootstrapSnapshot = true
        }

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

        let bootstrap = startPersistedCacheBootstrapIfNeeded()
        let previous = latestCachePersistenceOperation
        let coordinator = cachePersistenceCoordinator
        let operation = Task<Void, Error> { @MainActor in
            await bootstrap.value
            if let previous {
                _ = try? await previous.value
            }
            try await coordinator.clearAllHealthData()

            self.removeLegacyWorkoutPersistenceFiles()
            self.removeLegacyDailyDataFile()
            self.removeLegacyDailyCoverageFile()
        }
        trackPersistenceOperation(operation, label: "cleared health data")
        return operation
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
