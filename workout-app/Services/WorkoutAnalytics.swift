import Foundation
import SwiftUI

struct WorkoutAnalytics {
    private struct RepRangeDescriptor {
        let label: String
        let range: ClosedRange<Int>
        let tint: Color
    }

    private struct IntensityZoneDescriptor {
        let label: String
        let range: ClosedRange<Double>
        let tint: Color
    }

    /// Returns streak runs using the same rule as the app's streak calculation:
    /// consecutive workout-days, allowing up to `intentionalRestDays` between sessions.
    /// `workoutDayCount` counts workout days, not total calendar days spanned.
    static func streakRuns(
        for workouts: [Workout],
        intentionalRestDays: Int,
        intentionalBreakRanges: [IntentionalBreakRange]? = nil
    ) -> [StreakRun] {
        guard !workouts.isEmpty else { return [] }

        let allowedGapDays = max(0, intentionalRestDays) + 1
        let calendar = Calendar.current
        let uniqueDays = Set(workouts.map { calendar.startOfDay(for: $0.date) })
        let breakDays = IntentionalBreaksAnalytics.breakDaySet(
            from: intentionalBreakRanges ?? IntentionalBreaksStore.load(
                key: IntentionalBreaksStore.savedBreaksKey
            ),
            excluding: uniqueDays,
            calendar: calendar
        )
        let sortedDays = uniqueDays.sorted()
        guard let first = sortedDays.first else { return [] }

        var runs: [StreakRun] = []
        var runStart = first
        var runEnd = first
        var count = 1

        for day in sortedDays.dropFirst() {
            let daysDiff = IntentionalBreaksAnalytics.effectiveGapDays(
                from: runEnd,
                to: day,
                breakDays: breakDays,
                calendar: calendar
            )
            let continues = daysDiff >= 1 && daysDiff <= allowedGapDays
            if continues {
                runEnd = day
                count += 1
            } else {
                runs.append(StreakRun(start: runStart, end: runEnd, workoutDayCount: count))
                runStart = day
                runEnd = day
                count = 1
            }
        }

        runs.append(StreakRun(start: runStart, end: runEnd, workoutDayCount: count))
        return runs
    }

    /// Returns the current Sunday-start calendar-week streak.
    /// A week counts once if it contains at least one workout. Fully excused
    /// weeks are skipped so saved breaks pause the streak instead of breaking it.
    static func currentWeeklyStreak(
        for workouts: [Workout],
        intentionalBreakRanges: [IntentionalBreakRange]? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard !workouts.isEmpty else { return 0 }

        var calendar = calendar
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1

        let normalizedReferenceDate = calendar.startOfDay(for: referenceDate)
        let workoutDays = IntentionalBreaksAnalytics.normalizedWorkoutDays(
            for: workouts,
            calendar: calendar
        )
        guard let earliestWorkoutDay = workoutDays.min() else { return 0 }

        let boundsStart = calendar.startOfDay(for: earliestWorkoutDay)
        let currentWeekStart = startOfWeek(for: normalizedReferenceDate, calendar: calendar)
        let earliestWeekStart = startOfWeek(for: earliestWorkoutDay, calendar: calendar)
        let workoutWeekStarts = Set(workoutDays.map { startOfWeek(for: $0, calendar: calendar) })
        let breakDays = IntentionalBreaksAnalytics.breakDaySet(
            from: intentionalBreakRanges ?? IntentionalBreaksStore.load(
                key: IntentionalBreaksStore.savedBreaksKey
            ),
            excluding: workoutDays,
            within: boundsStart...normalizedReferenceDate,
            calendar: calendar
        )

        var streak = 0
        var cursor = currentWeekStart

        while cursor >= earliestWeekStart {
            let naturalWeekEnd = calendar.date(byAdding: .day, value: 6, to: cursor) ?? cursor
            let trackedStart = max(cursor, boundsStart)
            let trackedEnd = min(naturalWeekEnd, normalizedReferenceDate)

            if trackedStart <= trackedEnd {
                let trackedDays = max(
                    (calendar.dateComponents([.day], from: trackedStart, to: trackedEnd).day ?? 0) + 1,
                    0
                )
                let excludedDays = IntentionalBreaksAnalytics.dayCount(
                    from: trackedStart,
                    to: trackedEnd,
                    breakDays: breakDays,
                    includeStart: true,
                    includeEnd: true,
                    calendar: calendar
                )
                let eligibleDays = max(trackedDays - excludedDays, 0)

                if eligibleDays == 0 {
                    guard let previousWeek = calendar.date(
                        byAdding: .weekOfYear,
                        value: -1,
                        to: cursor
                    ) else {
                        break
                    }
                    cursor = previousWeek
                    continue
                }

                if workoutWeekStarts.contains(cursor) {
                    streak += 1
                } else {
                    break
                }
            }

            guard let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else {
                break
            }
            cursor = previousWeek
        }

        return streak
    }

    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func repRangeDistribution(for workouts: [Workout]) -> [RepRangeBucket] {
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()
        let allExercises = workouts.flatMap {
            ExerciseAggregation.aggregateExercises(in: $0, resolver: resolver)
        }
        let allSets = allExercises.flatMap { $0.sets }

        // Rep range distribution is a strength metric; exclude cardio-tagged exercises so
        // count-based cardio (e.g. "floors") doesn't pollute the rep histogram.
        let exerciseNames = Set(allExercises.map(\.name))
        let cardioNames: Set<String> = Set(
            exerciseNames.filter { name in
                ExerciseMetadataManager.shared
                    .resolvedTags(for: name)
                    .contains(where: { $0.builtInGroup == .cardio })
            }
        )
        let strengthSets = allSets.filter { !cardioNames.contains($0.exerciseName) }
        let buckets: [RepRangeDescriptor] = [
            RepRangeDescriptor(label: "1-3", range: 1...3, tint: Theme.Colors.error),
            RepRangeDescriptor(label: "4-6", range: 4...6, tint: Theme.Colors.warning),
            RepRangeDescriptor(label: "7-10", range: 7...10, tint: Theme.Colors.accent),
            RepRangeDescriptor(label: "11-15", range: 11...15, tint: Theme.Colors.accentSecondary),
            RepRangeDescriptor(label: "16-20", range: 16...20, tint: Theme.Colors.success),
            RepRangeDescriptor(label: "21+", range: 21...100, tint: Theme.Colors.textSecondary)
        ]

        let total = max(strengthSets.count, 1)
        return buckets.map { bucket in
            let count = strengthSets.filter { bucket.range.contains($0.reps) }.count
            return RepRangeBucket(
                label: bucket.label,
                range: bucket.range,
                count: count,
                percent: Double(count) / Double(total),
                tint: bucket.tint
            )
        }
    }

    static func intensityZones(for workouts: [Workout]) -> [IntensityZoneBucket] {
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()
        let allExercises = workouts.flatMap {
            ExerciseAggregation.aggregateExercises(in: $0, resolver: resolver)
        }
        let best1RMByExercise = Dictionary(grouping: allExercises, by: { $0.name }).compactMapValues { exercises in
            let sets = exercises.flatMap { $0.sets }
            let exerciseName = exercises.first?.name ?? ""
            let best = OneRepMax.bestEstimate(in: sets, exerciseName: exerciseName)
            return best > 0 ? best : nil
        }

        let allSets = allExercises.flatMap { $0.sets }
        let zones: [IntensityZoneDescriptor] = [
            IntensityZoneDescriptor(label: "<50%", range: 0.0...0.49, tint: Theme.Colors.textSecondary),
            IntensityZoneDescriptor(label: "50-65%", range: 0.50...0.65, tint: Theme.Colors.accentSecondary),
            IntensityZoneDescriptor(label: "65-75%", range: 0.66...0.75, tint: Theme.Colors.accent),
            IntensityZoneDescriptor(label: "75-85%", range: 0.76...0.85, tint: Theme.Colors.warning),
            IntensityZoneDescriptor(label: "85%+", range: 0.86...1.5, tint: Theme.Colors.error)
        ]

        var zoneCounts = Array(repeating: 0, count: zones.count)
        var total = 0

        for set in allSets {
            guard let reference = best1RMByExercise[set.exerciseName], reference > 0 else { continue }
            let intensity = ExerciseLoad.relativeIntensity(
                weight: set.weight,
                referenceWeight: reference,
                exerciseName: set.exerciseName
            )
            if let index = zones.firstIndex(where: { $0.range.contains(intensity) }) {
                zoneCounts[index] += 1
                total += 1
            }
        }

        let totalCount = max(total, 1)
        return zones.enumerated().map { index, zone in
            IntensityZoneBucket(
                label: zone.label,
                range: zone.range,
                count: zoneCounts[index],
                percent: Double(zoneCounts[index]) / Double(totalCount),
                tint: zone.tint
            )
        }
    }

    static func progressContributions(
        workouts: [Workout],
        weeks: Int,
        mappings: [String: [MuscleTag]],
        resolver: ExerciseIdentityResolver = .empty
    ) -> [ProgressContribution] {
        guard let endDate = workouts.map({ $0.date }).max() else { return [] }
        let calendar = Calendar.current
        let currentStart = calendar.date(byAdding: .day, value: -(weeks * 7), to: endDate) ?? endDate
        let previousStart = calendar.date(byAdding: .day, value: -(weeks * 14), to: endDate) ?? endDate

        let current = workouts.filter { $0.date >= currentStart }
        let previous = workouts.filter { $0.date >= previousStart && $0.date < currentStart }

        let exerciseDeltas = progressDeltaByExercise(current: current, previous: previous, resolver: resolver)

        let exerciseContributions = exerciseDeltas.map { name, delta in
            let previousValue = previousExerciseValue(previous, exerciseName: name, resolver: resolver)
            let currentValue = currentExerciseValue(current, exerciseName: name, resolver: resolver)
            let percent = percentChange(current: currentValue, previous: previousValue)
            return ProgressContribution(
                name: name,
                delta: delta,
                current: currentValue,
                previous: previousValue,
                percentChange: percent,
                category: .exercise,
                tint: Theme.Colors.accent
            )
        }

        var muscleTotals: [MuscleTag: Double] = [:]
        for (exerciseName, delta) in exerciseDeltas {
            let tags = mappings[exerciseName] ?? ExerciseMetadataManager.shared.resolvedTags(for: exerciseName)
            for tag in tags {
                muscleTotals[tag, default: 0] += delta
            }
        }

        let muscleContributions = muscleTotals.map { tag, delta in
            ProgressContribution(
                name: tag.shortName,
                delta: delta,
                current: delta,
                previous: 0,
                percentChange: 0,
                category: .muscleGroup,
                tint: tag.tint
            )
        }

        let workoutTypeDeltas = progressDeltaByWorkoutName(current: current, previous: previous, resolver: resolver)
        let workoutContributions = workoutTypeDeltas.map { name, delta in
            ProgressContribution(
                name: name,
                delta: delta,
                current: max(delta, 0),
                previous: 0,
                percentChange: 0,
                category: .workoutType,
                tint: Theme.Colors.accentSecondary
            )
        }

        return (exerciseContributions + muscleContributions + workoutContributions)
            .sorted { abs($0.delta) > abs($1.delta) }
    }

    static func exerciseConsistencySummaries(workouts: [Workout], weeks: Int) -> [ExerciseConsistencySummary] {
        guard let endDate = workouts.map({ $0.date }).max() else { return [] }
        let calendar = Calendar.current
        let currentStart = calendar.date(byAdding: .day, value: -(weeks * 7), to: endDate) ?? endDate
        let current = workouts.filter { $0.date >= currentStart && $0.date <= endDate }
        return exerciseConsistencySummaries(for: current, calendar: calendar)
    }

    static func consistentExerciseNames(
        workouts: [Workout],
        weeks: Int,
        minimumSessions: Int = 3,
        minimumWeeks: Int = 3,
        minimumWeeklyCoverage: Double = 0.5
    ) -> Set<String> {
        Set(
            exerciseConsistencySummaries(workouts: workouts, weeks: weeks)
                .filter { summary in
                    summary.sessions >= minimumSessions &&
                    summary.weeksPerformed >= minimumWeeks &&
                    summary.weeklyCoverage >= minimumWeeklyCoverage
                }
                .map(\.exerciseName)
        )
    }

    static func changeMetrics(
        for workouts: [Workout],
        windowDays: Int,
        resolver: ExerciseIdentityResolver = .empty
    ) -> [ChangeMetric] {
        guard let window = rollingChangeWindow(for: workouts, windowDays: windowDays) else { return [] }
        return changeMetrics(for: workouts, window: window, resolver: resolver)
    }

    static func changeMetrics(
        for workouts: [Workout],
        window: ChangeMetricWindow,
        resolver: ExerciseIdentityResolver = .empty
    ) -> [ChangeMetric] {
        changeMetrics(for: workouts, currentRange: window.current, previousRange: window.previous, resolver: resolver)
    }

    static func changeMetrics(
        for workouts: [Workout],
        currentRange: DateInterval,
        previousRange: DateInterval,
        resolver: ExerciseIdentityResolver = .empty
    ) -> [ChangeMetric] {
        let current = workouts.filter { currentRange.contains($0.date) }
        let previous = workouts.filter { previousRange.contains($0.date) }

        let currentVolume = ExerciseAggregation.totalVolume(for: current, resolver: resolver)
        let previousVolume = ExerciseAggregation.totalVolume(for: previous, resolver: resolver)

        let currentSessions = Double(current.count)
        let previousSessions = Double(previous.count)

        return [
            changeMetric(title: "Sessions", current: currentSessions, previous: previousSessions),
            changeMetric(title: "Total Volume", current: currentVolume, previous: previousVolume)
        ]
    }

    static func rollingChangeWindow(for workouts: [Workout], windowDays: Int) -> ChangeMetricWindow? {
        guard let endDate = workouts.map({ $0.date }).max() else { return nil }
        let calendar = Calendar.current
        let currentStart = calendar.date(byAdding: .day, value: -windowDays, to: endDate) ?? endDate
        let previousStart = calendar.date(byAdding: .day, value: -(windowDays * 2), to: endDate) ?? endDate
        // DateInterval.contains(...) is inclusive; shift the previous end slightly to avoid double-counting
        // workouts that happen exactly at currentStart.
        let previousEnd = currentStart.addingTimeInterval(-0.001)

        return ChangeMetricWindow(
            label: rollingWindowLabel(days: windowDays),
            current: DateInterval(start: currentStart, end: endDate),
            previous: DateInterval(start: previousStart, end: previousEnd)
        )
    }

    private static func rollingWindowLabel(days: Int) -> String {
        if days % 7 == 0 {
            return "Last \(days / 7)w"
        }
        if days % 30 == 0 {
            return "Last \(days / 30)mo"
        }
        return "Last \(days)d"
    }

    // MARK: - Helpers

    private static func progressDeltaByExercise(
        current: [Workout],
        previous: [Workout],
        resolver: ExerciseIdentityResolver
    ) -> [String: Double] {
        let currentExercises = current.flatMap {
            ExerciseAggregation.aggregateExercises(in: $0, resolver: resolver).map(\.name)
        }
        let previousExercises = previous.flatMap {
            ExerciseAggregation.aggregateExercises(in: $0, resolver: resolver).map(\.name)
        }
        let exercises = Set(currentExercises + previousExercises)
        var deltas: [String: Double] = [:]

        for name in exercises {
            let currentValue = currentExerciseValue(current, exerciseName: name, resolver: resolver)
            let previousValue = previousExerciseValue(previous, exerciseName: name, resolver: resolver)
            let delta = currentValue - previousValue
            deltas[name] = delta
        }

        return deltas
    }

    private static func exerciseConsistencySummaries(
        for workouts: [Workout],
        calendar: Calendar
    ) -> [ExerciseConsistencySummary] {
        guard !workouts.isEmpty else { return [] }

        let activeWeeks = Set(workouts.compactMap { weekStart(for: $0.date, calendar: calendar) })
        guard !activeWeeks.isEmpty else { return [] }

        var sessionsByExercise: [String: Int] = [:]
        var weeksByExercise: [String: Set<Date>] = [:]
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()

        for workout in workouts {
            guard let weekStart = weekStart(for: workout.date, calendar: calendar) else { continue }
            let exerciseNames = Set(
                ExerciseAggregation.aggregateExercises(
                    in: workout,
                    resolver: resolver
                ).map(\.name)
            )
            for name in exerciseNames {
                sessionsByExercise[name, default: 0] += 1
                weeksByExercise[name, default: []].insert(weekStart)
            }
        }

        let activeWeekCount = activeWeeks.count
        return sessionsByExercise.map { name, sessions in
            ExerciseConsistencySummary(
                exerciseName: name,
                sessions: sessions,
                weeksPerformed: weeksByExercise[name]?.count ?? 0,
                activeWeeks: activeWeekCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.sessions != rhs.sessions { return lhs.sessions > rhs.sessions }
            if lhs.weeksPerformed != rhs.weeksPerformed { return lhs.weeksPerformed > rhs.weeksPerformed }
            return lhs.exerciseName < rhs.exerciseName
        }
    }

    private static func weekStart(for date: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components)
    }

    private static func progressDeltaByWorkoutName(
        current: [Workout],
        previous: [Workout],
        resolver: ExerciseIdentityResolver
    ) -> [String: Double] {
        let names = Set(current.map { $0.name } + previous.map { $0.name })
        var deltas: [String: Double] = [:]

        for name in names {
            let currentVolume = ExerciseAggregation.totalVolume(
                for: current.filter { $0.name == name },
                resolver: resolver
            )
            let previousVolume = ExerciseAggregation.totalVolume(
                for: previous.filter { $0.name == name },
                resolver: resolver
            )
            deltas[name] = currentVolume - previousVolume
        }

        return deltas
    }

    private static func currentExerciseValue(
        _ workouts: [Workout],
        exerciseName: String,
        resolver: ExerciseIdentityResolver
    ) -> Double {
        let sets = workouts.flatMap { workout in
            ExerciseAggregation.aggregateExercises(in: workout, resolver: resolver)
                .filter { $0.name == exerciseName }
                .flatMap { $0.sets }
        }
        guard let bestWeight = ExerciseLoad.bestWeight(in: sets.map(\.weight), exerciseName: exerciseName) else {
            return 0
        }
        // Return a comparison-space value so assisted lifts improve when assistance decreases.
        return ExerciseLoad.comparisonValue(for: bestWeight, exerciseName: exerciseName)
    }

    private static func previousExerciseValue(
        _ workouts: [Workout],
        exerciseName: String,
        resolver: ExerciseIdentityResolver
    ) -> Double {
        currentExerciseValue(workouts, exerciseName: exerciseName, resolver: resolver)
    }

    private static func changeMetric(title: String, current: Double, previous: Double) -> ChangeMetric {
        let delta = current - previous
        let percent = percentChange(current: current, previous: previous)
        return ChangeMetric(
            title: title,
            current: current,
            previous: previous,
            delta: delta,
            percentChange: percent,
            isPositive: delta >= 0
        )
    }

    private static func percentChange(current: Double, previous: Double) -> Double {
        ExerciseLoad.performancePercentChange(current: current, previous: previous)
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
