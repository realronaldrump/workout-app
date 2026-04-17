import Foundation

nonisolated struct HomeDashboardSnapshot {
    let recentWorkouts: [Workout]
    let stats: WorkoutStats
    let exerciseSummaries: [ExerciseSummary]
    let allExerciseNames: [String]
    let datasetRevision: Int
}

nonisolated struct WorkoutHistoryFilter {
    var searchText: String = ""
    var dateRange: DateInterval?
    var exerciseNames: Set<String> = []
    var gymProfileIds: Set<UUID?> = []

    init(
        searchText: String = "",
        dateRange: DateInterval? = nil,
        exerciseNames: Set<String> = [],
        gymProfileIds: Set<UUID?> = []
    ) {
        self.searchText = searchText
        self.dateRange = dateRange
        self.exerciseNames = exerciseNames
        self.gymProfileIds = gymProfileIds
    }
}

nonisolated struct WorkoutHistoryCursor: Hashable {
    let offset: Int

    init(offset: Int = 0) {
        self.offset = max(0, offset)
    }
}

nonisolated struct WorkoutHistoryPage {
    let workouts: [Workout]
    let totalCount: Int
    let nextCursor: WorkoutHistoryCursor?
}

nonisolated struct WorkoutDetailSnapshot {
    let workout: Workout
    let healthData: WorkoutHealthData?
    let annotation: WorkoutAnnotation?
}

nonisolated enum ExerciseSortOrder: Hashable {
    case alphabetical
    case volume
    case frequency
    case recent
}

nonisolated struct ExerciseCursor: Hashable {
    let offset: Int

    init(offset: Int = 0) {
        self.offset = max(0, offset)
    }
}

nonisolated struct ExerciseDirectoryPage {
    let exercises: [ExerciseSummary]
    let totalCount: Int
    let nextCursor: ExerciseCursor?
}

nonisolated enum ExerciseScope: Hashable {
    case all
    case unassigned
    case gym(UUID)
}

nonisolated struct ExerciseDetailSnapshot {
    let exerciseName: String
    let history: [ExerciseHistorySession]
    let workouts: [Workout]
}

nonisolated struct PerformanceSnapshot {
    let workouts: [Workout]
    let stats: WorkoutStats
    let exerciseSummaries: [ExerciseSummary]
}

nonisolated struct HealthSnapshot {
    let workoutHealthData: [WorkoutHealthData]
    let dailyHealthData: [DailyHealthData]
    let dailyCoverage: Set<Date>
}

nonisolated struct WorkoutRepositoryImportSummary {
    let importedWorkoutCount: Int
    let loggedWorkoutCount: Int
    let workoutHealthCount: Int
    let dailyHealthCount: Int
    let dailyCoverageCount: Int
}

actor WorkoutRepository {
    static let shared = WorkoutRepository()

    private let database: AppDatabase
    private var datasetRevision: Int = 0

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func homeSnapshot() async throws -> HomeDashboardSnapshot {
        let workouts = try loadAllWorkouts()
        return HomeDashboardSnapshot(
            recentWorkouts: Array(workouts.prefix(5)),
            stats: Self.stats(for: workouts),
            exerciseSummaries: Self.exerciseSummaries(for: workouts),
            allExerciseNames: Self.allExerciseNames(for: workouts),
            datasetRevision: datasetRevision
        )
    }

    func workoutHistoryPage(
        filter: WorkoutHistoryFilter,
        cursor: WorkoutHistoryCursor? = nil,
        limit: Int
    ) async throws -> WorkoutHistoryPage {
        let annotations = Dictionary(uniqueKeysWithValues: try database.loadAnnotations().map { ($0.workoutId, $0) })
        let filtered = try loadAllWorkouts().filter { workout in
            Self.matchesHistoryFilter(workout, filter: filter, annotations: annotations)
        }
        let offset = cursor?.offset ?? 0
        let resolvedLimit = max(1, limit)
        let page = Array(filtered.dropFirst(offset).prefix(resolvedLimit))
        let nextOffset = offset + page.count
        return WorkoutHistoryPage(
            workouts: page,
            totalCount: filtered.count,
            nextCursor: nextOffset < filtered.count ? WorkoutHistoryCursor(offset: nextOffset) : nil
        )
    }

    func workoutDetail(id: UUID) async throws -> WorkoutDetailSnapshot {
        let workouts = try loadAllWorkouts()
        guard let workout = workouts.first(where: { $0.id == id }) else {
            throw WorkoutRepositoryError.workoutNotFound
        }
        let healthData = try database.loadWorkoutHealthData().first { $0.workoutId == id }
        let annotation = try database.loadAnnotations().first { $0.workoutId == id }
        return WorkoutDetailSnapshot(workout: workout, healthData: healthData, annotation: annotation)
    }

    func exerciseDirectory(
        query: String,
        sort: ExerciseSortOrder,
        cursor: ExerciseCursor? = nil,
        limit: Int
    ) async throws -> ExerciseDirectoryPage {
        let summaries = Self.sortedExerciseSummaries(
            Self.exerciseSummaries(for: try loadAllWorkouts()).filter { summary in
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty || summary.name.localizedCaseInsensitiveContains(trimmed)
            },
            sort: sort
        )
        let offset = cursor?.offset ?? 0
        let resolvedLimit = max(1, limit)
        let page = Array(summaries.dropFirst(offset).prefix(resolvedLimit))
        let nextOffset = offset + page.count
        return ExerciseDirectoryPage(
            exercises: page,
            totalCount: summaries.count,
            nextCursor: nextOffset < summaries.count ? ExerciseCursor(offset: nextOffset) : nil
        )
    }

    func exerciseDetail(
        name: String,
        scope: ExerciseScope,
        range: DateInterval? = nil
    ) async throws -> ExerciseDetailSnapshot {
        let annotations = Dictionary(uniqueKeysWithValues: try database.loadAnnotations().map { ($0.workoutId, $0) })
        let workouts = try loadAllWorkouts().filter { workout in
            guard workout.exercises.contains(where: { $0.name == name }) else { return false }
            if let range, !range.contains(workout.date) { return false }
            return Self.matchesScope(workoutId: workout.id, scope: scope, annotations: annotations)
        }
        let history = workouts.compactMap { workout -> ExerciseHistorySession? in
            guard let exercise = workout.exercises.first(where: { $0.name == name }) else { return nil }
            return ExerciseHistorySession(workoutId: workout.id, date: workout.date, sets: exercise.sets)
        }
        .sorted { $0.date < $1.date }

        return ExerciseDetailSnapshot(exerciseName: name, history: history, workouts: workouts)
    }

    func performanceSnapshot(range: DateInterval) async throws -> PerformanceSnapshot {
        let workouts = try loadAllWorkouts().filter { range.contains($0.date) }
        return PerformanceSnapshot(
            workouts: workouts,
            stats: Self.stats(for: workouts),
            exerciseSummaries: Self.exerciseSummaries(for: workouts)
        )
    }

    func healthSnapshot(range: DateInterval) async throws -> HealthSnapshot {
        HealthSnapshot(
            workoutHealthData: try database.loadWorkoutHealthData().filter { range.contains($0.workoutDate) },
            dailyHealthData: try database.loadDailyHealthData().filter { range.contains($0.dayStart) },
            dailyCoverage: try database.loadDailyHealthCoverage().filter { range.contains($0) }
        )
    }

    func importStrongCSV(_ data: Data, sourceSignature: String?) async throws {
        let sets = try CSVParser.parseStrongWorkoutsCSV(from: data)
        let existingImported = try database.loadImportedWorkouts()
        let identitySnapshot = try database.loadWorkoutIdentities()
        let healthIdentitySnapshot = try database.loadWorkoutHealthData().map {
            WorkoutHealthIdentitySnapshot(workoutId: $0.workoutId, workoutDate: $0.workoutDate)
        }
        let (workouts, identityEntries) = WorkoutDataManager.processImportedWorkoutSetsSnapshot(
            sets: sets,
            existingImported: existingImported,
            identitySnapshot: identitySnapshot,
            healthIdentitySnapshot: healthIdentitySnapshot
        )
        try database.saveImportedWorkouts(workouts)
        try database.mergeWorkoutIdentities(identityEntries)
        incrementRevision()
    }

    @discardableResult
    func importBigBeautifulBackup(_ backup: BigBeautifulWorkoutBackup) async throws -> WorkoutRepositoryImportSummary {
        let payload = backup.payload
        try database.saveImportedWorkouts(payload.importedWorkouts)
        try database.replaceLoggedWorkouts(payload.loggedWorkouts)
        try database.mergeWorkoutIdentities(payload.workoutIdentities)
        try database.replaceAnnotations(payload.workoutAnnotations)
        try database.saveGymProfiles(payload.gymProfiles)
        try database.saveWorkoutHealthData(payload.workoutHealthData)
        try database.saveDailyHealthData(payload.dailyHealthData)
        try database.saveDailyHealthCoverage(Set(payload.dailyHealthCoverage))
        incrementRevision()
        return WorkoutRepositoryImportSummary(
            importedWorkoutCount: payload.importedWorkouts.count,
            loggedWorkoutCount: payload.loggedWorkouts.count,
            workoutHealthCount: payload.workoutHealthData.count,
            dailyHealthCount: payload.dailyHealthData.count,
            dailyCoverageCount: payload.dailyHealthCoverage.count
        )
    }

    func upsertLoggedWorkout(_ workout: LoggedWorkout) async throws {
        try database.saveLoggedWorkout(workout)
        incrementRevision()
    }

    func deleteLoggedWorkout(id: UUID) async throws {
        try database.deleteLoggedWorkout(id: id)
        incrementRevision()
    }

    func replaceWorkoutHealthData(_ entries: [WorkoutHealthData]) async throws {
        try database.saveWorkoutHealthData(entries)
        incrementRevision()
    }

    func replaceDailyHealthData(_ entries: [DailyHealthData], coverage: Set<Date>) async throws {
        try database.saveDailyHealthData(entries)
        try database.saveDailyHealthCoverage(coverage)
        incrementRevision()
    }

    func resetLocalStore() async throws {
        try database.resetLocalStore()
        incrementRevision()
    }

    private func loadAllWorkouts() throws -> [Workout] {
        (try database.loadImportedWorkouts() + database.loadLoggedWorkouts().map(Self.mapLoggedWorkoutToAnalyticsWorkout))
            .sorted { $0.date > $1.date }
    }

    private func incrementRevision() {
        datasetRevision &+= 1
    }
}

nonisolated enum WorkoutRepositoryError: Error {
    case workoutNotFound
}

private extension WorkoutRepository {
    nonisolated static func matchesHistoryFilter(
        _ workout: Workout,
        filter: WorkoutHistoryFilter,
        annotations: [UUID: WorkoutAnnotation]
    ) -> Bool {
        let query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty,
           !workout.name.localizedCaseInsensitiveContains(query),
           !workout.exercises.contains(where: { $0.name.localizedCaseInsensitiveContains(query) }) {
            return false
        }

        if let dateRange = filter.dateRange, !dateRange.contains(workout.date) {
            return false
        }

        if !filter.exerciseNames.isEmpty {
            let names = Set(workout.exercises.map(\.name))
            if filter.exerciseNames.isDisjoint(with: names) {
                return false
            }
        }

        if !filter.gymProfileIds.isEmpty {
            let gymId = annotations[workout.id]?.gymProfileId
            if !filter.gymProfileIds.contains(gymId) {
                return false
            }
        }

        return true
    }

    nonisolated static func matchesScope(
        workoutId: UUID,
        scope: ExerciseScope,
        annotations: [UUID: WorkoutAnnotation]
    ) -> Bool {
        let gymId = annotations[workoutId]?.gymProfileId
        switch scope {
        case .all:
            return true
        case .unassigned:
            return gymId == nil
        case .gym(let targetId):
            return gymId == targetId
        }
    }

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
        return Workout(id: logged.id, date: logged.startedAt, name: logged.name, duration: duration, exercises: exercises)
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

    nonisolated static func allExerciseNames(for workouts: [Workout]) -> [String] {
        Array(Set(workouts.flatMap { $0.exercises.map(\.name) }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    nonisolated static func exerciseSummaries(for workouts: [Workout]) -> [ExerciseSummary] {
        var accumulators: [String: ExerciseAccumulator] = [:]
        for workout in workouts {
            for exercise in workout.exercises {
                var accumulator = accumulators[exercise.name] ?? ExerciseAccumulator()
                accumulator.totalVolume += exercise.totalVolume
                accumulator.frequency += 1
                accumulator.lastPerformed = max(accumulator.lastPerformed ?? workout.date, workout.date)
                if accumulator.maxWeight == nil ||
                    ExerciseLoad.isBetter(
                        exercise.maxWeight,
                        than: accumulator.maxWeight ?? exercise.maxWeight,
                        exerciseName: exercise.name
                    ) {
                    accumulator.maxWeight = exercise.maxWeight
                }
                if accumulator.oneRepMax == nil ||
                    ExerciseLoad.isBetter(
                        exercise.oneRepMax,
                        than: accumulator.oneRepMax ?? exercise.oneRepMax,
                        exerciseName: exercise.name
                    ) {
                    accumulator.oneRepMax = exercise.oneRepMax
                }
                accumulators[exercise.name] = accumulator
            }
        }

        return accumulators.map { name, accumulator in
            ExerciseSummary(
                name: name,
                stats: ExerciseStats(
                    totalVolume: accumulator.totalVolume,
                    maxWeight: accumulator.maxWeight ?? 0,
                    frequency: accumulator.frequency,
                    lastPerformed: accumulator.lastPerformed,
                    oneRepMax: accumulator.oneRepMax ?? 0
                )
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated static func sortedExerciseSummaries(
        _ summaries: [ExerciseSummary],
        sort: ExerciseSortOrder
    ) -> [ExerciseSummary] {
        switch sort {
        case .alphabetical:
            return summaries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .volume:
            return summaries.sorted { $0.stats.totalVolume > $1.stats.totalVolume }
        case .frequency:
            return summaries.sorted { $0.stats.frequency > $1.stats.frequency }
        case .recent:
            return summaries.sorted { ($0.stats.lastPerformed ?? .distantPast) > ($1.stats.lastPerformed ?? .distantPast) }
        }
    }

    nonisolated static func stats(for workouts: [Workout]) -> WorkoutStats {
        let allExercises = workouts.flatMap(\.exercises)
        let exerciseGroups = Dictionary(grouping: allExercises, by: \.name)
        let favoriteExercise = exerciseGroups.max { $0.value.count < $1.value.count }?.key
        let strongestExercise = exerciseGroups.compactMap { name, exercises -> (name: String, weight: Double, score: Double)? in
            guard let bestWeight = ExerciseLoad.bestWeight(in: exercises.flatMap { $0.sets.map(\.weight) }, exerciseName: name) else {
                return nil
            }
            return (name, bestWeight, ExerciseLoad.comparisonValue(for: bestWeight, exerciseName: name))
        }
        .max { $0.score < $1.score }
        .map { (name: $0.name, weight: $0.weight) }

        let calendar = Calendar.current
        let uniqueDays = Set(workouts.map { calendar.startOfDay(for: $0.date) }).sorted()
        let currentStreak = currentDayStreak(days: uniqueDays, calendar: calendar)
        let longestStreak = longestDayStreak(days: uniqueDays, calendar: calendar)

        return WorkoutStats(
            totalWorkouts: workouts.count,
            totalExercises: exerciseGroups.count,
            totalVolume: workouts.reduce(0) { $0 + $1.totalVolume },
            totalSets: workouts.reduce(0) { $0 + $1.totalSets },
            favoriteExercise: favoriteExercise,
            strongestExercise: strongestExercise,
            mostImprovedExercise: nil,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            workoutsPerWeek: workoutsPerWeek(for: workouts, calendar: calendar),
            lastWorkoutDate: workouts.map(\.date).max()
        )
    }

    nonisolated static func currentDayStreak(days: [Date], calendar: Calendar) -> Int {
        guard let last = days.last else { return 0 }
        let today = calendar.startOfDay(for: Date())
        guard (calendar.dateComponents([.day], from: last, to: today).day ?? Int.max) <= 1 else { return 0 }
        var streak = 1
        var previous = last
        for day in days.dropLast().reversed() {
            let gap = calendar.dateComponents([.day], from: day, to: previous).day ?? Int.max
            guard gap == 1 else { break }
            streak += 1
            previous = day
        }
        return streak
    }

    nonisolated static func longestDayStreak(days: [Date], calendar: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for (previous, next) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previous, to: next).day ?? Int.max
            if gap == 1 {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    nonisolated static func workoutsPerWeek(for workouts: [Workout], calendar: Calendar) -> Double {
        guard let first = workouts.map(\.date).min(), let last = workouts.map(\.date).max() else { return 0 }
        let days = max((calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1, 1)
        return Double(workouts.count) / max(Double(days) / 7.0, 1)
    }

    struct ExerciseAccumulator {
        var totalVolume: Double = 0
        var maxWeight: Double?
        var frequency: Int = 0
        var lastPerformed: Date?
        var oneRepMax: Double?
    }
}
