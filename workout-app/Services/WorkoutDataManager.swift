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

    private let identityStore = WorkoutIdentityStore()
    private var exerciseHistoryCache: [String: [ExerciseHistorySession]] = [:]
    private var exerciseSummariesCache: [ExerciseSummary] = []
    private var allExerciseNamesCache: [String] = []
    private var recentExerciseNamesCache: [String] = []

    nonisolated func processImportedWorkoutSets(
        _ sets: [WorkoutSet],
        healthDataSnapshot: [WorkoutHealthData] = []
    ) async {
        let snapshots: (existingImported: [Workout], identitySnapshot: [String: UUID]) = await MainActor.run {
            self.isLoading = true
            self.error = nil
            return (existingImported: self.importedWorkouts, identitySnapshot: self.identityStore.snapshot())
        }

        // Run heavy grouping logic on a background thread
        let task = Task.detached(priority: .userInitiated) {
            Self.processImportedWorkoutSetsSnapshot(
                sets: sets,
                existingImported: snapshots.existingImported,
                identitySnapshot: snapshots.identitySnapshot,
                healthDataSnapshot: healthDataSnapshot
            )
        }
        let (processedWorkouts, newIdentityEntries) = await task.value

        // Update UI on MainActor
        await MainActor.run {
            self.importedWorkouts = processedWorkouts
            self.mergeSources()
            self.isLoading = false
            self.identityStore.merge(newIdentityEntries)
        }
    }

    func setLoggedWorkouts(_ logged: [LoggedWorkout]) {
        let mapped = logged.map(Self.mapLoggedWorkoutToAnalyticsWorkout)
        loggedWorkouts = mapped.sorted { $0.date > $1.date }
        loggedWorkoutIds = Set(logged.map(\.id))
        mergeSources()
    }

    /// Centralized method for loading workout data from iCloud storage.
    /// Previously duplicated in both HomeView and DashboardView.
    /// Sets `isLoading` / `error` so views can show loading and error states.
    func loadLatestWorkoutData(
        iCloudManager: iCloudDocumentManager,
        healthDataSnapshot: [WorkoutHealthData]
    ) async {
        let directoryURL = iCloudManager.storageSnapshot().url
        isLoading = true
        error = nil

        let setsResult = await Task.detached(priority: .userInitiated) { [directoryURL] in
            do {
                guard let directoryURL else { return Result<[WorkoutSet], Error>.success([]) }

                let importFiles = iCloudDocumentManager.listStrongImportFiles(in: directoryURL)
                let files = (importFiles.isEmpty
                    ? iCloudDocumentManager.listWorkoutFiles(in: directoryURL)
                    : importFiles)
                    .sorted { url1, url2 in
                        let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                        let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                        return date1 > date2
                    }

                guard let latestFile = files.first else { return Result<[WorkoutSet], Error>.success([]) }
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
                isLoading = false
                return
            }
            await processImportedWorkoutSets(sets, healthDataSnapshot: healthDataSnapshot)
        case .failure(let loadError):
            isLoading = false
            error = loadError.localizedDescription
        }
    }

    private func mergeSources() {
        workouts = (importedWorkouts + loggedWorkouts).sorted { $0.date > $1.date }
        rebuildDerivedCaches()
    }

    func getExerciseHistory(for exerciseName: String) -> [(date: Date, sets: [WorkoutSet])] {
        (exerciseHistoryCache[exerciseName] ?? []).map { (date: $0.date, sets: $0.sets) }
    }

    func exerciseHistorySessions(for exerciseName: String) -> [ExerciseHistorySession] {
        exerciseHistoryCache[exerciseName] ?? []
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
        let allExercises = filteredWorkouts.flatMap { $0.exercises }
        let exerciseGroups = Dictionary(grouping: allExercises) { $0.name }

        // Calculate favorite exercise (most performed)
        let favoriteExercise = exerciseGroups
            .map { (name: $0.key, count: $0.value.count) }
            .max { $0.count < $1.count }?.name

        // Calculate strongest exercise
        let strongestExercise = exerciseGroups
            .map { (name: $0.key, maxWeight: $0.value.map { $0.maxWeight }.max() ?? 0) }
            .max { $0.maxWeight < $1.maxWeight }
            .map { (name: $0.name, weight: $0.maxWeight) }

        // Calculate improvement
        var mostImprovedExercise: (name: String, improvement: Double)?
        for (exerciseName, exercises) in exerciseGroups {
            let sortedByDate = exercises.sorted { exercise1, exercise2 in
                let date1 = exercise1.sets.map(\.date).min() ?? Date.distantPast
                let date2 = exercise2.sets.map(\.date).min() ?? Date.distantPast
                return date1 < date2
            }

            if let first = sortedByDate.first?.oneRepMax,
               let last = sortedByDate.last?.oneRepMax,
               first > 0 {
                let improvement = ((last - first) / first) * 100
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
            totalExercises: exerciseGroups.keys.count,
            totalVolume: filteredWorkouts.reduce(0) { $0 + $1.totalVolume },
            totalSets: filteredWorkouts.reduce(0) { $0 + $1.totalSets },
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

    func clearAllData() {
        self.workouts = []
        self.importedWorkouts = []
        self.loggedWorkouts = []
        self.loggedWorkoutIds = []
        self.isLoading = false
        self.error = nil
        self.exerciseHistoryCache = [:]
        self.exerciseSummariesCache = []
        self.allExerciseNamesCache = []
        self.recentExerciseNamesCache = []
        self.identityStore.clear()
    }

    private func rebuildDerivedCaches() {
        var historyByExercise: [String: [ExerciseHistorySession]] = [:]
        var summaryByExercise: [String: ExerciseStatsAccumulator] = [:]
        var allExerciseNames = Set<String>()
        var seenRecentExerciseKeys = Set<String>()
        var recentExerciseNames: [String] = []

        recentExerciseNames.reserveCapacity(16)

        for workout in workouts {
            for exercise in workout.exercises {
                historyByExercise[exercise.name, default: []].append(
                    ExerciseHistorySession(workoutId: workout.id, date: workout.date, sets: exercise.sets)
                )

                var accumulator = summaryByExercise[exercise.name] ?? ExerciseStatsAccumulator()
                accumulator.totalVolume += exercise.totalVolume
                accumulator.maxWeight = max(accumulator.maxWeight, exercise.maxWeight)
                accumulator.frequency += 1
                accumulator.lastPerformed = max(accumulator.lastPerformed ?? workout.date, workout.date)
                accumulator.oneRepMax = max(accumulator.oneRepMax, exercise.oneRepMax)
                summaryByExercise[exercise.name] = accumulator

                let trimmedName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { continue }

                allExerciseNames.insert(trimmedName)

                let recentKey = trimmedName.lowercased()
                if seenRecentExerciseKeys.insert(recentKey).inserted {
                    recentExerciseNames.append(trimmedName)
                }
            }
        }

        for name in historyByExercise.keys {
            historyByExercise[name]?.sort { $0.date < $1.date }
        }

        exerciseHistoryCache = historyByExercise
        exerciseSummariesCache = summaryByExercise.map { name, accumulator in
            ExerciseSummary(
                name: name,
                stats: ExerciseStats(
                    totalVolume: accumulator.totalVolume,
                    maxWeight: accumulator.maxWeight,
                    frequency: accumulator.frequency,
                    lastPerformed: accumulator.lastPerformed,
                    oneRepMax: accumulator.oneRepMax
                )
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        allExerciseNamesCache = Array(allExerciseNames)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        recentExerciseNamesCache = recentExerciseNames
    }
}

private extension WorkoutDataManager {
    struct ExerciseStatsAccumulator {
        var totalVolume: Double = 0
        var maxWeight: Double = 0
        var frequency: Int = 0
        var lastPerformed: Date?
        var oneRepMax: Double = 0
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
        healthDataSnapshot: [WorkoutHealthData]
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
        var legacyCandidatesByHour = makeLegacyCandidatesByHour(from: healthDataSnapshot, calendar: calendar)

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
        from healthDataSnapshot: [WorkoutHealthData],
        calendar: Calendar
    ) -> [String: [LegacyWorkoutCandidate]] {
        var candidatesByHour: [String: [LegacyWorkoutCandidate]] = [:]
        for health in healthDataSnapshot {
            let bucket = WorkoutIdentity.hourBucket(for: health.workoutDate, calendar: calendar)
            candidatesByHour[bucket, default: []].append(
                LegacyWorkoutCandidate(id: health.workoutId, date: health.workoutDate)
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
