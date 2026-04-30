import Combine
import Foundation

struct ExerciseHistorySession {
    let workoutId: UUID
    let date: Date
    let sets: [WorkoutSet]
}

struct ExerciseSummary {
    let name: String
    let stats: ExerciseStats
}

struct WorkoutHealthIdentitySnapshot {
    let workoutId: UUID
    let workoutDate: Date
}

@MainActor
class WorkoutDataManager: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published private(set) var importedWorkouts: [Workout] = []
    @Published private(set) var loggedWorkouts: [Workout] = []
    @Published private(set) var loggedWorkoutIds: Set<UUID> = []
    @Published var isLoading = false
    @Published var error: String?

    private static let intentionalRestDaysKey = "intentionalRestDays"
    private static let defaultIntentionalRestDays = 1
    private static let importedWorkoutsSourcePathKey = "importedWorkoutsSourcePath"
    private static let importedWorkoutsSourceTimestampKey = "importedWorkoutsSourceTimestamp"

    private let database = AppDatabase.shared
    private let identityStore = WorkoutIdentityStore.shared
    private let userDefaults = UserDefaults.standard
    private var aggregateExerciseHistoryCache: [String: [ExerciseHistorySession]] = [:]
    private var exactExerciseHistoryCache: [String: [ExerciseHistorySession]] = [:]
    private var exerciseSummariesCache: [ExerciseSummary] = []
    private var allExerciseNamesCache: [String] = []
    private var recentExerciseNamesCache: [String] = []
    private var importedWorkoutRequestID: UInt64 = 0

    nonisolated deinit {}

    private struct DerivedWorkoutState {
        let workouts: [Workout]
        let importedWorkouts: [Workout]
        let loggedWorkouts: [Workout]
        let aggregateExerciseHistory: [String: [ExerciseHistorySession]]
        let exactExerciseHistory: [String: [ExerciseHistorySession]]
        let exerciseSummaries: [ExerciseSummary]
        let allExerciseNames: [String]
        let recentExerciseNames: [String]
    }

    func processImportedWorkoutSets(
        _ sets: [WorkoutSet],
        healthIdentitySnapshot: [WorkoutHealthIdentitySnapshot] = [],
        requestID: UInt64? = nil
    ) async {
        isLoading = true
        error = nil
        let snapshots = (existingImported: importedWorkouts, identitySnapshot: identityStore.snapshot())

        // Run heavy grouping logic on a background thread
        let task = Task.detached(priority: .userInitiated) {
            Self.processImportedWorkoutSetsSnapshot(
                sets: sets,
                existingImported: snapshots.existingImported,
                identitySnapshot: snapshots.identitySnapshot,
                healthIdentitySnapshot: healthIdentitySnapshot
            )
        }
        let (processedWorkouts, newIdentityEntries) = await task.value

        guard requestID.map(isCurrentImportedWorkoutRequest) ?? true else { return }

        await applyImportedWorkouts(processedWorkouts)
        isLoading = false
        identityStore.merge(newIdentityEntries)

        do {
            try database.saveImportedWorkouts(processedWorkouts)
        } catch {
            print("Failed to persist imported workouts: \(error)")
        }
    }

    func setLoggedWorkouts(_ logged: [LoggedWorkout]) {
        let mapped = logged.map(Self.mapLoggedWorkoutToAnalyticsWorkout)
        loggedWorkouts = mapped.sorted { $0.date > $1.date }
        loggedWorkoutIds = Set(logged.map(\.id))
        mergeSources()
    }

    func setLoggedWorkoutsOffMain(_ logged: [LoggedWorkout]) async {
        let importedSnapshot = importedWorkouts
        let loggedIds = Set(logged.map(\.id))
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()
        let state = await Task.detached(priority: .userInitiated) {
            let mapped = logged.map(Self.mapLoggedWorkoutToAnalyticsWorkout)
            return Self.makeDerivedWorkoutState(
                importedWorkouts: importedSnapshot,
                loggedWorkouts: mapped,
                resolver: resolver
            )
        }.value
        loggedWorkoutIds = loggedIds
        applyDerivedState(state)
    }

    /// Centralized method for loading workout data from iCloud storage.
    /// Centralized so views share one loading path.
    /// Sets `isLoading` / `error` so views can show loading and error states.
    func loadLatestWorkoutData(
        iCloudManager: iCloudDocumentManager,
        healthIdentitySnapshot: [WorkoutHealthIdentitySnapshot]
    ) async {
        let requestID = beginImportedWorkoutRequest()
        let searchDirectories = await iCloudManager.storageSearchDirectories()
        isLoading = true
        error = nil

        do {
            let persistedWorkouts = try await Task.detached(priority: .userInitiated) { [database] in
                try database.loadImportedWorkouts()
            }.value

            if iCloudDocumentManager.latestBackupFile(in: searchDirectories) != nil {
                guard isCurrentImportedWorkoutRequest(requestID) else { return }
                await applyImportedWorkouts(persistedWorkouts)
                isLoading = false
                return
            }

            let latestFile = Self.latestWorkoutFile(in: searchDirectories)
            let latestSignature = Self.importSourceSignature(for: latestFile)
            let cachedSignature = cachedImportSourceSignature()

            if !persistedWorkouts.isEmpty, latestSignature == cachedSignature || cachedSignature == nil {
                guard isCurrentImportedWorkoutRequest(requestID) else { return }
                await applyImportedWorkouts(persistedWorkouts)
                isLoading = false
                if cachedSignature == nil {
                    persistImportSourceSignature(latestSignature)
                }
                return
            }

            if latestFile == nil {
                guard isCurrentImportedWorkoutRequest(requestID) else { return }
                await applyImportedWorkouts(persistedWorkouts)
                isLoading = false
                return
            }
        } catch {
            print("Failed to load cached imported workouts: \(error)")
        }

        let setsResult = await Task.detached(priority: .userInitiated) { [searchDirectories] in
            do {
                guard let latestFile = Self.latestWorkoutFile(in: searchDirectories) else {
                    return Result<[WorkoutSet], Error>.success([])
                }
                let data = try Data(contentsOf: latestFile)
                let sets = try CSVParser.parseStrongWorkoutsCSV(from: data)
                return Result<[WorkoutSet], Error>.success(sets)
            } catch {
                return Result<[WorkoutSet], Error>.failure(error)
            }
        }.value

        switch setsResult {
        case .success(let sets):
            guard !sets.isEmpty else {
                guard isCurrentImportedWorkoutRequest(requestID) else { return }
                await applyImportedWorkouts([])
                isLoading = false
                clearImportSourceSignature()
                do {
                    try database.clearImportedWorkouts()
                } catch {
                    print("Failed to clear imported workouts: \(error)")
                }
                return
            }
            await processImportedWorkoutSets(
                sets,
                healthIdentitySnapshot: healthIdentitySnapshot,
                requestID: requestID
            )
            guard isCurrentImportedWorkoutRequest(requestID) else { return }
            if let latestFile = Self.latestWorkoutFile(in: searchDirectories) {
                persistImportSourceSignature(Self.importSourceSignature(for: latestFile))
            }
        case .failure(let loadError):
            guard isCurrentImportedWorkoutRequest(requestID) else { return }
            isLoading = false
            error = loadError.localizedDescription
        }
    }

    func loadPersistedImportedWorkouts() async {
        let requestID = importedWorkoutRequestID
        do {
            let persisted = try await Task.detached(priority: .userInitiated) { [database] in
                try database.loadImportedWorkouts()
            }.value
            guard requestID == importedWorkoutRequestID else { return }
            await applyImportedWorkouts(persisted)
        } catch {
            print("Failed to load persisted imported workouts: \(error)")
        }
    }

    func reloadPersistedMigrationState() async {
        identityStore.reload()
        await loadPersistedImportedWorkouts()
    }

    nonisolated static func latestWorkoutFile(in directories: [URL]) -> URL? {
        for directory in directories {
            let files = listNewestFirst(iCloudDocumentManager.listStrongImportFiles(in: directory))
            if let latest = files.first {
                return latest
            }
        }

        for directory in directories {
            let files = listNewestFirst(iCloudDocumentManager.listWorkoutFiles(in: directory))
            if let latest = files.first {
                return latest
            }
        }

        return nil
    }

    nonisolated static func importSourceSignature(for fileURL: URL?) -> String? {
        guard let fileURL else { return nil }
        let creationDate = (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
        return "\(fileURL.standardizedFileURL.path)|\(creationDate.timeIntervalSince1970)"
    }

    nonisolated private static func listNewestFirst(_ files: [URL]) -> [URL] {
        files.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 > date2
        }
    }

    private func mergeSources() {
        applyDerivedState(
            Self.makeDerivedWorkoutState(
                importedWorkouts: importedWorkouts,
                loggedWorkouts: loggedWorkouts,
                resolver: ExerciseRelationshipManager.shared.resolverSnapshot()
            )
        )
    }

    private func applyImportedWorkouts(_ imported: [Workout]) async {
        let loggedSnapshot = loggedWorkouts
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()
        let state = await Task.detached(priority: .userInitiated) {
            Self.makeDerivedWorkoutState(
                importedWorkouts: imported,
                loggedWorkouts: loggedSnapshot,
                resolver: resolver
            )
        }.value
        applyDerivedState(state)
    }

    private func applyDerivedState(_ state: DerivedWorkoutState) {
        workouts = state.workouts
        importedWorkouts = state.importedWorkouts
        loggedWorkouts = state.loggedWorkouts
        aggregateExerciseHistoryCache = state.aggregateExerciseHistory
        exactExerciseHistoryCache = state.exactExerciseHistory
        exerciseSummariesCache = state.exerciseSummaries
        allExerciseNamesCache = state.allExerciseNames
        recentExerciseNamesCache = state.recentExerciseNames
    }

    func getExerciseHistory(for exerciseName: String) -> [(date: Date, sets: [WorkoutSet])] {
        (exactExerciseHistoryCache[ExerciseIdentityResolver.trimmedName(exerciseName)] ?? [])
            .map { (date: $0.date, sets: $0.sets) }
    }

    func exerciseHistorySessions(for exerciseName: String, includingVariants: Bool = true) -> [ExerciseHistorySession] {
        let key = ExerciseIdentityResolver.trimmedName(exerciseName)
        if includingVariants {
            return aggregateExerciseHistoryCache[key] ?? exactExerciseHistoryCache[key] ?? []
        }
        return exactExerciseHistoryCache[key] ?? []
    }

    func exerciseSummaries() -> [ExerciseSummary] {
        exerciseSummariesCache
    }

    func allExerciseNames() -> [String] {
        allExerciseNamesCache
    }

    func recentExerciseNames(limit: Int? = nil) -> [String] {
        guard let limit else { return recentExerciseNamesCache }
        return Array(recentExerciseNamesCache.prefix(limit))
    }

    func refreshExerciseIdentityDerivedState() {
        mergeSources()
    }

    func calculateStats() -> WorkoutStats {
        return calculateStats(for: workouts)
    }

    func calculateStats(
        for filteredWorkouts: [Workout],
        intentionalBreakRanges: [IntentionalBreakRange]? = nil
    ) -> WorkoutStats {
        let breakRanges = intentionalBreakRanges ?? IntentionalBreaksStore.load(
            key: IntentionalBreaksStore.savedBreaksKey
        )
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()
        let allExercises = filteredWorkouts.flatMap { $0.exercises }
        let exerciseGroups = Dictionary(grouping: allExercises) { $0.name }
        let aggregateExercises = filteredWorkouts.flatMap {
            ExerciseAggregation.aggregateExercises(in: $0, resolver: resolver)
        }
        let aggregateExerciseGroups = Dictionary(grouping: aggregateExercises) { $0.name }

        // Calculate favorite exercise (most performed)
        let favoriteExercise = aggregateExerciseGroups
            .map { (name: $0.key, count: $0.value.count) }
            .max { $0.count < $1.count }?.name

        // Calculate strongest exercise
        let strongestExercise = exerciseGroups
            .compactMap { name, exercises -> (name: String, weight: Double, score: Double)? in
                let allWeights = exercises.flatMap { $0.sets.map(\.weight) }
                guard let bestWeight = ExerciseLoad.bestWeight(in: allWeights, exerciseName: name) else {
                    return nil
                }
                let score = ExerciseLoad.comparisonValue(for: bestWeight, exerciseName: name)
                return (name: name, weight: bestWeight, score: score)
            }
            .max { $0.score < $1.score }
            .map { (name: $0.name, weight: $0.weight) }

        // Calculate improvement
        var mostImprovedExercise: (name: String, improvement: Double)?
        for (exerciseName, exercises) in exerciseGroups {
            let sortedByDate = exercises.sorted { exercise1, exercise2 in
                let date1 = exercise1.sets.map(\.date).min() ?? Date.distantPast
                let date2 = exercise2.sets.map(\.date).min() ?? Date.distantPast
                return date1 < date2
            }

            if let first = sortedByDate.first?.oneRepMax,
               let last = sortedByDate.last?.oneRepMax {
                let firstScore = ExerciseLoad.comparisonValue(for: first, exerciseName: exerciseName)
                let lastScore = ExerciseLoad.comparisonValue(for: last, exerciseName: exerciseName)
                let improvement = ExerciseLoad.performancePercentChange(current: lastScore, previous: firstScore)
                if let current = mostImprovedExercise {
                    if improvement > current.improvement {
                        mostImprovedExercise = (name: exerciseName, improvement: improvement)
                    }
                } else {
                    mostImprovedExercise = (name: exerciseName, improvement: improvement)
                }
            }
        }

        // Calculate streaks and consistency (use all workouts for streaks, filtered for other stats)
        let (currentStreak, longestStreak) = calculateStreaks(intentionalBreakRanges: breakRanges)
        let workoutsPerWeek = calculateWorkoutsPerWeek(
            for: filteredWorkouts,
            intentionalBreakRanges: breakRanges
        )

        return WorkoutStats(
            totalWorkouts: filteredWorkouts.count,
            totalExercises: aggregateExerciseGroups.keys.count,
            totalVolume: ExerciseAggregation.totalVolume(for: filteredWorkouts, resolver: resolver),
            totalSets: ExerciseAggregation.totalSets(for: filteredWorkouts, resolver: resolver),
            favoriteExercise: favoriteExercise,
            strongestExercise: strongestExercise,
            mostImprovedExercise: mostImprovedExercise,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            workoutsPerWeek: workoutsPerWeek,
            lastWorkoutDate: filteredWorkouts.map(\.date).max()
        )
    }

    private func calculateStreaks(
        intentionalBreakRanges: [IntentionalBreakRange]
    ) -> (current: Int, longest: Int) {
        guard !workouts.isEmpty else { return (0, 0) }

        let intentionalRestDays = configuredIntentionalRestDays()
        let allowedGapDays = intentionalRestDays + 1 // e.g. 1 rest day => allow workout days 2 days apart

        // 1. Normalize all workout dates to start of day
        let calendar = Calendar.current
        let uniqueDays = Set(workouts.map { calendar.startOfDay(for: $0.date) })
        let breakDays = IntentionalBreaksAnalytics.breakDaySet(
            from: intentionalBreakRanges,
            excluding: uniqueDays,
            calendar: calendar
        )

        // 2. Sort unique days
        let sortedDays = uniqueDays.sorted()

        guard !sortedDays.isEmpty else { return (0, 0) }

        var currentStreak = 0
        var longestStreak = 0
        var tempStreak = 1
        var lastDay = sortedDays[0]

        // 3. Calculate consecutive workout-days, allowing a configurable rest window.
        for index in 1..<sortedDays.count {
            let currentDay = sortedDays[index]
            let daysDiff = IntentionalBreaksAnalytics.effectiveGapDays(
                from: lastDay,
                to: currentDay,
                breakDays: breakDays,
                calendar: calendar
            )

            if daysDiff >= 1 && daysDiff <= allowedGapDays {
                // Within the allowed rest window, streak continues (streak counts workout days, not calendar span).
                tempStreak += 1
            } else {
                // Broken streak
                longestStreak = max(longestStreak, tempStreak)
                tempStreak = 1
            }
            lastDay = currentDay
        }

        longestStreak = max(longestStreak, tempStreak)

        // 4. Calculate current streak
        // Check if the streak is still active (last workout was today or yesterday or day before yesterday?)
        if let lastWorkoutDay = sortedDays.last {
            let today = calendar.startOfDay(for: Date())
            let daysSinceLast = IntentionalBreaksAnalytics.effectiveGapDays(
                from: lastWorkoutDay,
                to: today,
                breakDays: breakDays,
                includeEnd: true,
                calendar: calendar
            )

            // If last workout was within the rest window, streak is still active.
            if daysSinceLast <= allowedGapDays {
                currentStreak = tempStreak
            }
        }

        return (currentStreak, longestStreak)
    }

    private func calculateWorkoutsPerWeek(
        for filteredWorkouts: [Workout],
        intentionalBreakRanges: [IntentionalBreakRange]
    ) -> Double {
        guard !filteredWorkouts.isEmpty else { return 0 }

        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1

        let sortedWorkouts = filteredWorkouts.sorted { $0.date < $1.date }
        guard let firstWorkoutDate = sortedWorkouts.first?.date,
              let lastWorkoutDate = sortedWorkouts.last?.date else {
            return 0
        }

        let interval = DateInterval(start: firstWorkoutDate, end: lastWorkoutDate)
        let workoutDays = Set(sortedWorkouts.map { calendar.startOfDay(for: $0.date) })
        let breakDays = IntentionalBreaksAnalytics.breakDaySet(
            from: intentionalBreakRanges,
            excluding: workoutDays,
            within: calendar.startOfDay(for: firstWorkoutDate)...calendar.startOfDay(for: lastWorkoutDate),
            calendar: calendar
        )
        let effectiveWeeks = max(
            IntentionalBreaksAnalytics.effectiveWeekUnits(in: interval, breakDays: breakDays, calendar: calendar),
            1
        )

        return Double(filteredWorkouts.count) / effectiveWeeks
    }

    private func configuredIntentionalRestDays() -> Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.intentionalRestDaysKey) != nil else {
            return Self.defaultIntentionalRestDays
        }
        return max(0, defaults.integer(forKey: Self.intentionalRestDaysKey))
    }

    func clearWorkoutHistory() {
        workouts = []
        importedWorkouts = []
        loggedWorkouts = []
        loggedWorkoutIds = []
        isLoading = false
        error = nil
        aggregateExerciseHistoryCache = [:]
        exactExerciseHistoryCache = [:]
        exerciseSummariesCache = []
        allExerciseNamesCache = []
        recentExerciseNamesCache = []
        identityStore.clear()
        clearImportSourceSignature()
        try? database.clearImportedWorkouts()
    }

    func clearAllData() {
        clearWorkoutHistory()
    }

    func mergeImportedWorkoutsFromBackup(_ backupWorkouts: [Workout]) -> (
        idMap: [UUID: UUID],
        inserted: Int,
        skipped: Int
    ) {
        guard !backupWorkouts.isEmpty else {
            return ([:], 0, 0)
        }

        let calendar = Calendar.current
        var idMap: [UUID: UUID] = [:]
        var inserted = 0
        var skipped = 0
        var mergedImported = importedWorkouts
        var existingIds = Set(workouts.map(\.id))
        var existingIdsByKey = Self.makeExistingIdsByKey(from: workouts, calendar: calendar)
        var identityEntries: [String: UUID] = [:]

        for backupWorkout in backupWorkouts {
            let workoutKey = WorkoutIdentity.workoutKey(
                date: backupWorkout.date,
                workoutName: backupWorkout.name,
                calendar: calendar
            )

            if existingIds.contains(backupWorkout.id) {
                idMap[backupWorkout.id] = backupWorkout.id
                identityEntries[workoutKey] = backupWorkout.id
                skipped += 1
                continue
            }

            if let existingId = existingIdsByKey[workoutKey] {
                idMap[backupWorkout.id] = existingId
                identityEntries[workoutKey] = existingId
                skipped += 1
                continue
            }

            mergedImported.append(backupWorkout)
            existingIds.insert(backupWorkout.id)
            existingIdsByKey[workoutKey] = backupWorkout.id
            idMap[backupWorkout.id] = backupWorkout.id
            identityEntries[workoutKey] = backupWorkout.id
            inserted += 1
        }

        if inserted > 0 {
            importedWorkouts = mergedImported.sorted { $0.date > $1.date }
            mergeSources()
            do {
                try database.saveImportedWorkouts(importedWorkouts)
            } catch {
                print("Failed to persist imported backup workouts: \(error)")
            }
        }

        identityStore.mergeMissing(identityEntries)
        return (idMap, inserted, skipped)
    }

    func mergeWorkoutIdentitiesFromBackup(
        _ entries: [String: UUID],
        workoutIdMap: [UUID: UUID]
    ) -> Int {
        let remapped = entries.mapValues { workoutIdMap[$0] ?? $0 }
        return identityStore.mergeMissing(remapped)
    }

    private func cachedImportSourceSignature() -> String? {
        let path = userDefaults.string(forKey: Self.importedWorkoutsSourcePathKey)
        let timestamp = userDefaults.object(forKey: Self.importedWorkoutsSourceTimestampKey) as? Double
        guard let path, let timestamp else { return nil }
        return "\(path)|\(timestamp)"
    }

    private func persistImportSourceSignature(_ signature: String?) {
        guard let signature else {
            clearImportSourceSignature()
            return
        }

        let parts = signature.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let timestamp = Double(parts[1]) else {
            clearImportSourceSignature()
            return
        }

        userDefaults.set(parts[0], forKey: Self.importedWorkoutsSourcePathKey)
        userDefaults.set(timestamp, forKey: Self.importedWorkoutsSourceTimestampKey)
    }

    private func clearImportSourceSignature() {
        userDefaults.removeObject(forKey: Self.importedWorkoutsSourcePathKey)
        userDefaults.removeObject(forKey: Self.importedWorkoutsSourceTimestampKey)
    }

    func beginImportedWorkoutRequest() -> UInt64 {
        importedWorkoutRequestID &+= 1
        return importedWorkoutRequestID
    }

    private func isCurrentImportedWorkoutRequest(_ requestID: UInt64) -> Bool {
        requestID == importedWorkoutRequestID
    }

    private nonisolated static func makeDerivedWorkoutState(
        importedWorkouts: [Workout],
        loggedWorkouts: [Workout],
        resolver: ExerciseIdentityResolver
    ) -> DerivedWorkoutState {
        let sortedImported = importedWorkouts.sorted { $0.date > $1.date }
        let sortedLogged = loggedWorkouts.sorted { $0.date > $1.date }
        let workouts = (sortedImported + sortedLogged).sorted { $0.date > $1.date }
        var aggregateHistoryByExercise: [String: [ExerciseHistorySession]] = [:]
        var exactHistoryByExercise: [String: [ExerciseHistorySession]] = [:]
        var summaryByExercise: [String: ExerciseStatsAccumulator] = [:]
        var allExerciseNames = Set<String>()
        var seenRecentExerciseKeys = Set<String>()
        var recentExerciseNames: [String] = []

        recentExerciseNames.reserveCapacity(16)

        for workout in workouts {
            for exercise in workout.exercises {
                let exactName = resolver.performanceTrackName(for: exercise.name)
                exactHistoryByExercise[exactName, default: []].append(
                    ExerciseHistorySession(workoutId: workout.id, date: workout.date, sets: exercise.sets)
                )

                let trimmedName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { continue }

                allExerciseNames.insert(trimmedName)
                let aggregateName = resolver.aggregateName(for: trimmedName)
                let recentKey = ExerciseIdentityResolver.normalizedName(aggregateName)
                if seenRecentExerciseKeys.insert(recentKey).inserted {
                    recentExerciseNames.append(aggregateName)
                }
            }

            for (rank, aggregateExercise) in ExerciseAggregation.aggregateExercises(in: workout, resolver: resolver).enumerated() {
                let aggregateName = aggregateExercise.name
                let sortedSets = aggregateExercise.sets
                aggregateHistoryByExercise[aggregateName, default: []].append(
                    ExerciseHistorySession(workoutId: workout.id, date: workout.date, sets: sortedSets)
                )

                var accumulator = summaryByExercise[aggregateName] ?? ExerciseStatsAccumulator()
                accumulator.totalVolume += aggregateExercise.totalVolume
                if let currentBest = accumulator.maxWeight {
                    if ExerciseLoad.isBetter(aggregateExercise.maxWeight, than: currentBest, exerciseName: aggregateName) {
                        accumulator.maxWeight = aggregateExercise.maxWeight
                    }
                } else {
                    accumulator.maxWeight = aggregateExercise.maxWeight
                }
                accumulator.frequency += 1
                accumulator.lastPerformed = max(accumulator.lastPerformed ?? workout.date, workout.date)
                if let currentBest = accumulator.oneRepMax {
                    if ExerciseLoad.isBetter(aggregateExercise.oneRepMax, than: currentBest, exerciseName: aggregateName) {
                        accumulator.oneRepMax = aggregateExercise.oneRepMax
                    }
                } else {
                    accumulator.oneRepMax = aggregateExercise.oneRepMax
                }
                accumulator.hasRelationshipVariants = accumulator.hasRelationshipVariants ||
                    resolver.containsRelationship(for: aggregateName) ||
                    !resolver.children(of: aggregateName).isEmpty
                accumulator.firstSeenRank = min(accumulator.firstSeenRank ?? Int.max, rank)
                summaryByExercise[aggregateName] = accumulator
            }
        }

        for name in aggregateHistoryByExercise.keys {
            aggregateHistoryByExercise[name]?.sort { $0.date < $1.date }
        }
        for name in exactHistoryByExercise.keys {
            exactHistoryByExercise[name]?.sort { $0.date < $1.date }
        }

        return DerivedWorkoutState(
            workouts: workouts,
            importedWorkouts: sortedImported,
            loggedWorkouts: sortedLogged,
            aggregateExerciseHistory: aggregateHistoryByExercise,
            exactExerciseHistory: exactHistoryByExercise,
            exerciseSummaries: summaryByExercise.map { name, accumulator in
                ExerciseSummary(
                    name: name,
                    stats: ExerciseStats(
                        totalVolume: accumulator.totalVolume,
                        maxWeight: accumulator.hasRelationshipVariants ? 0 : accumulator.maxWeight ?? 0,
                        frequency: accumulator.frequency,
                        lastPerformed: accumulator.lastPerformed,
                        oneRepMax: accumulator.hasRelationshipVariants ? 0 : accumulator.oneRepMax ?? 0
                    )
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            allExerciseNames: Array(allExerciseNames)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
            recentExerciseNames: recentExerciseNames
        )
    }
}

extension WorkoutDataManager {
    nonisolated struct ExerciseStatsAccumulator {
        var totalVolume: Double = 0
        var maxWeight: Double?
        var frequency: Int = 0
        var lastPerformed: Date?
        var oneRepMax: Double?
        var firstSeenRank: Int?
        var hasRelationshipVariants = false
    }

    struct ImportedWorkoutBuildResult {
        let workout: Workout
        let resolvedId: UUID
    }

    struct LegacyWorkoutCandidate {
        let id: UUID
        let date: Date
    }

    struct ImportedWorkoutProcessingContext {
        let existingIdsByKey: [String: UUID]
        let identitySnapshot: [String: UUID]
        let calendar: Calendar
    }

    nonisolated static func processImportedWorkoutSetsSnapshot(
        sets: [WorkoutSet],
        existingImported: [Workout],
        identitySnapshot: [String: UUID],
        healthIdentitySnapshot: [WorkoutHealthIdentitySnapshot]
    ) -> ([Workout], [String: UUID]) {
        let calendar = Calendar.current
        let groupedByWorkout = Dictionary(grouping: sets) { set in
            WorkoutIdentity.workoutKey(date: set.date, workoutName: set.workoutName, calendar: calendar)
        }
        let existingIdsByKey = makeExistingIdsByKey(from: existingImported, calendar: calendar)
        let context = ImportedWorkoutProcessingContext(
            existingIdsByKey: existingIdsByKey,
            identitySnapshot: identitySnapshot,
            calendar: calendar
        )
        var legacyCandidatesByHour = makeLegacyCandidatesByHour(from: healthIdentitySnapshot, calendar: calendar)

        var workouts: [Workout] = []
        workouts.reserveCapacity(groupedByWorkout.count)
        var newIdentityEntries: [String: UUID] = [:]
        newIdentityEntries.reserveCapacity(groupedByWorkout.count)

        for (workoutKey, workoutSets) in groupedByWorkout {
            guard let result = buildImportedWorkout(
                workoutKey: workoutKey,
                workoutSets: workoutSets,
                context: context,
                legacyCandidatesByHour: &legacyCandidatesByHour
            ) else {
                continue
            }
            workouts.append(result.workout)
            if context.identitySnapshot[workoutKey] != result.resolvedId {
                newIdentityEntries[workoutKey] = result.resolvedId
            }
        }

        return (workouts.sorted { $0.date > $1.date }, newIdentityEntries)
    }

    nonisolated static func makeExistingIdsByKey(
        from workouts: [Workout],
        calendar: Calendar
    ) -> [String: UUID] {
        var idsByKey: [String: UUID] = [:]
        idsByKey.reserveCapacity(workouts.count)
        for workout in workouts {
            let key = WorkoutIdentity.workoutKey(date: workout.date, workoutName: workout.name, calendar: calendar)
            idsByKey[key] = workout.id
        }
        return idsByKey
    }

    nonisolated static func makeLegacyCandidatesByHour(
        from healthIdentitySnapshot: [WorkoutHealthIdentitySnapshot],
        calendar: Calendar
    ) -> [String: [LegacyWorkoutCandidate]] {
        var candidatesByHour: [String: [LegacyWorkoutCandidate]] = [:]
        for snapshot in healthIdentitySnapshot {
            let bucket = WorkoutIdentity.hourBucket(for: snapshot.workoutDate, calendar: calendar)
            candidatesByHour[bucket, default: []].append(
                LegacyWorkoutCandidate(id: snapshot.workoutId, date: snapshot.workoutDate)
            )
        }
        return candidatesByHour
    }

    nonisolated static func buildImportedWorkout(
        workoutKey: String,
        workoutSets: [WorkoutSet],
        context: ImportedWorkoutProcessingContext,
        legacyCandidatesByHour: inout [String: [LegacyWorkoutCandidate]]
    ) -> ImportedWorkoutBuildResult? {
        guard let firstSet = workoutSets.first else { return nil }
        let workoutDate = workoutSets.map(\.date).min() ?? firstSet.date
        let resolvedId = resolveImportedWorkoutId(
            workoutKey: workoutKey,
            workoutDate: workoutDate,
            context: context,
            legacyCandidatesByHour: &legacyCandidatesByHour
        )
        let workout = Workout(
            id: resolvedId,
            date: workoutDate,
            name: firstSet.workoutName.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: firstSet.duration,
            exercises: makeExercises(from: workoutSets)
        )
        return ImportedWorkoutBuildResult(workout: workout, resolvedId: resolvedId)
    }

    nonisolated static func makeExercises(from workoutSets: [WorkoutSet]) -> [Exercise] {
        let groupedByExercise = Dictionary(grouping: workoutSets) { $0.exerciseName }
        var firstSeenRankByExerciseName: [String: Int] = [:]
        firstSeenRankByExerciseName.reserveCapacity(groupedByExercise.count)
        var nextRank = 0

        let orderedSets = workoutSets.enumerated().sorted { lhs, rhs in
            if lhs.element.date != rhs.element.date { return lhs.element.date < rhs.element.date }
            return lhs.offset < rhs.offset
        }
        for item in orderedSets where firstSeenRankByExerciseName[item.element.exerciseName] == nil {
            firstSeenRankByExerciseName[item.element.exerciseName] = nextRank
            nextRank += 1
        }

        let orderedExerciseNames = groupedByExercise.keys.sorted { lhs, rhs in
            let lhsRank = firstSeenRankByExerciseName[lhs] ?? Int.max
            let rhsRank = firstSeenRankByExerciseName[rhs] ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        var exercises: [Exercise] = []
        exercises.reserveCapacity(orderedExerciseNames.count)
        for exerciseName in orderedExerciseNames {
            guard let exerciseSets = groupedByExercise[exerciseName] else { continue }
            let sortedSets = exerciseSets.sorted { lhs, rhs in
                if lhs.setOrder != rhs.setOrder { return lhs.setOrder < rhs.setOrder }
                return lhs.date < rhs.date
            }
            exercises.append(Exercise(name: exerciseName, sets: sortedSets))
        }

        return exercises
    }

    nonisolated static func resolveImportedWorkoutId(
        workoutKey: String,
        workoutDate: Date,
        context: ImportedWorkoutProcessingContext,
        legacyCandidatesByHour: inout [String: [LegacyWorkoutCandidate]]
    ) -> UUID {
        if let existingId = context.existingIdsByKey[workoutKey] {
            return existingId
        }
        if let mappedId = context.identitySnapshot[workoutKey] {
            return mappedId
        }
        let hourBucket = WorkoutIdentity.hourBucket(for: workoutDate, calendar: context.calendar)
        return consumeClosestLegacyCandidateId(
            for: workoutDate,
            hourBucket: hourBucket,
            legacyCandidatesByHour: &legacyCandidatesByHour
        ) ?? UUID()
    }

    nonisolated static func consumeClosestLegacyCandidateId(
        for workoutDate: Date,
        hourBucket: String,
        legacyCandidatesByHour: inout [String: [LegacyWorkoutCandidate]]
    ) -> UUID? {
        guard var candidates = legacyCandidatesByHour[hourBucket], !candidates.isEmpty else { return nil }
        let bestIndex = closestLegacyCandidateIndex(for: workoutDate, in: candidates)
        let chosen = candidates.remove(at: bestIndex)
        if candidates.isEmpty {
            legacyCandidatesByHour.removeValue(forKey: hourBucket)
        } else {
            legacyCandidatesByHour[hourBucket] = candidates
        }
        return chosen.id
    }

    nonisolated static func closestLegacyCandidateIndex(
        for workoutDate: Date,
        in candidates: [LegacyWorkoutCandidate]
    ) -> Int {
        var bestIndex = 0
        var bestDistance = abs(candidates[0].date.timeIntervalSince(workoutDate))
        for index in 1..<candidates.count {
            let distance = abs(candidates[index].date.timeIntervalSince(workoutDate))
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}

// MARK: - LoggedWorkout mapping

private extension WorkoutDataManager {
    nonisolated static func mapLoggedWorkoutToAnalyticsWorkout(_ logged: LoggedWorkout) -> Workout {
        let duration = formatDuration(start: logged.startedAt, end: logged.endedAt)

        let exercises: [Exercise] = logged.exercises.map { loggedExercise in
            let sets: [WorkoutSet] = loggedExercise.sets.map { loggedSet in
                WorkoutSet(
                    date: logged.startedAt,
                    workoutName: logged.name,
                    duration: duration,
                    exerciseName: loggedExercise.name,
                    setOrder: loggedSet.order,
                    weight: loggedSet.weight,
                    reps: loggedSet.reps,
                    distance: loggedSet.distance ?? 0,
                    seconds: loggedSet.seconds ?? 0
                )
            }
            return Exercise(id: loggedExercise.id, name: loggedExercise.name, sets: sets.sorted { $0.setOrder < $1.setOrder })
        }

        return Workout(
            id: logged.id,
            date: logged.startedAt,
            name: logged.name,
            duration: duration,
            exercises: exercises
        )
    }

    nonisolated static func formatDuration(start: Date, end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        let minutes = Int(ceil(seconds / 60.0))
        if minutes >= 60 {
            let hours = minutes / 60
            let minutesRemainder = minutes % 60
            return minutesRemainder == 0 ? "\(hours)h" : "\(hours)h \(minutesRemainder)m"
        }
        return "\(minutes)m"
    }

}
