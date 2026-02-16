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

    nonisolated static func durationMinutes(from duration: String) -> Double {
        let trimmed = duration.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return 0 }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").compactMap { Double($0) }
            if parts.count == 3 {
                return (parts[0] * 60.0) + parts[1] + (parts[2] / 60.0)
            } else if parts.count == 2 {
                return parts[0] + (parts[1] / 60.0)
            }
        }

        var hours = 0
        var minutes = 0
        var seconds = 0
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

        if let secondMatch = trimmed.range(of: "(\\d+)\\s*s", options: .regularExpression) {
            let secondString = String(trimmed[secondMatch]).replacingOccurrences(of: "s", with: "")
            seconds = Int(secondString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            matched = true
        }

        if matched {
            return Double(hours * 60 + minutes) + (Double(seconds) / 60.0)
        }

        return Double(trimmed) ?? 0
    }

    /// Returns streak runs using the same rule as the app's streak calculation:
    /// consecutive workout-days, allowing up to `intentionalRestDays` between sessions.
    /// `workoutDayCount` counts workout days, not total calendar days spanned.
    static func streakRuns(for workouts: [Workout], intentionalRestDays: Int) -> [StreakRun] {
        guard !workouts.isEmpty else { return [] }

        let allowedGapDays = max(0, intentionalRestDays) + 1
        let calendar = Calendar.current
        let uniqueDays = Set(workouts.map { calendar.startOfDay(for: $0.date) })
        let sortedDays = uniqueDays.sorted()
        guard let first = sortedDays.first else { return [] }

        var runs: [StreakRun] = []
        var runStart = first
        var runEnd = first
        var count = 1

        for day in sortedDays.dropFirst() {
            let daysDiff = calendar.dateComponents([.day], from: runEnd, to: day).day ?? 0
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

    static func repRangeDistribution(for workouts: [Workout]) -> [RepRangeBucket] {
        let allSets = workouts.flatMap { $0.exercises }.flatMap { $0.sets }

        // Rep range distribution is a strength metric; exclude cardio-tagged exercises so
        // count-based cardio (e.g. "floors") doesn't pollute the rep histogram.
        let exerciseNames = Set(workouts.flatMap { $0.exercises.map(\.name) })
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
        let allExercises = workouts.flatMap { $0.exercises }
        let best1RMByExercise = Dictionary(grouping: allExercises, by: { $0.name }).compactMapValues { exercises in
            let sets = exercises.flatMap { $0.sets }
            return sets.map { estimateOneRepMax(weight: $0.weight, reps: $0.reps) }.max()
        }

        let allSets = workouts.flatMap { $0.exercises }.flatMap { $0.sets }
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
            let intensity = set.weight / reference
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
        mappings: [String: [MuscleTag]]
    ) -> [ProgressContribution] {
        guard let endDate = workouts.map({ $0.date }).max() else { return [] }
        let calendar = Calendar.current
        let currentStart = calendar.date(byAdding: .day, value: -(weeks * 7), to: endDate) ?? endDate
        let previousStart = calendar.date(byAdding: .day, value: -(weeks * 14), to: endDate) ?? endDate

        let current = workouts.filter { $0.date >= currentStart }
        let previous = workouts.filter { $0.date >= previousStart && $0.date < currentStart }

        let exerciseDeltas = progressDeltaByExercise(current: current, previous: previous)

        let exerciseContributions = exerciseDeltas.map { name, delta in
            let previousValue = previousExerciseValue(previous, exerciseName: name)
            let currentValue = currentExerciseValue(current, exerciseName: name)
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
            let tags = mappings[exerciseName] ?? []
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

        let workoutTypeDeltas = progressDeltaByWorkoutName(current: current, previous: previous)
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

    static func changeMetrics(for workouts: [Workout], windowDays: Int) -> [ChangeMetric] {
        guard let window = rollingChangeWindow(for: workouts, windowDays: windowDays) else { return [] }
        return changeMetrics(for: workouts, window: window)
    }

    static func changeMetrics(for workouts: [Workout], window: ChangeMetricWindow) -> [ChangeMetric] {
        changeMetrics(for: workouts, currentRange: window.current, previousRange: window.previous)
    }

    static func changeMetrics(for workouts: [Workout], currentRange: DateInterval, previousRange: DateInterval) -> [ChangeMetric] {
        let current = workouts.filter { currentRange.contains($0.date) }
        let previous = workouts.filter { previousRange.contains($0.date) }

        let currentDuration = average(current.map { durationMinutes(from: $0.duration) })
        let previousDuration = average(previous.map { durationMinutes(from: $0.duration) })

        let currentVolume = current.reduce(0) { $0 + $1.totalVolume }
        let previousVolume = previous.reduce(0) { $0 + $1.totalVolume }

        let currentSessions = Double(current.count)
        let previousSessions = Double(previous.count)

        return [
            changeMetric(title: "Sessions", current: currentSessions, previous: previousSessions),
            changeMetric(title: "Total Volume", current: currentVolume, previous: previousVolume),
            changeMetric(title: "Avg Duration", current: currentDuration, previous: previousDuration)
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
        if days <= 14 { return "Last 2w" }
        if days <= 28 { return "Last 4w" }
        return "Last \(days)d"
    }

    // MARK: - Helpers

    private static func estimateOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }

    private static func progressDeltaByExercise(current: [Workout], previous: [Workout]) -> [String: Double] {
        let exercises = Set(current.flatMap { $0.exercises.map { $0.name } } + previous.flatMap { $0.exercises.map { $0.name } })
        var deltas: [String: Double] = [:]

        for name in exercises {
            let currentValue = currentExerciseValue(current, exerciseName: name)
            let previousValue = previousExerciseValue(previous, exerciseName: name)
            let delta = currentValue - previousValue
            deltas[name] = delta
        }

        return deltas
    }

    private static func progressDeltaByWorkoutName(current: [Workout], previous: [Workout]) -> [String: Double] {
        let names = Set(current.map { $0.name } + previous.map { $0.name })
        var deltas: [String: Double] = [:]

        for name in names {
            let currentVolume = current.filter { $0.name == name }.reduce(0) { $0 + $1.totalVolume }
            let previousVolume = previous.filter { $0.name == name }.reduce(0) { $0 + $1.totalVolume }
            deltas[name] = currentVolume - previousVolume
        }

        return deltas
    }

    private static func currentExerciseValue(_ workouts: [Workout], exerciseName: String) -> Double {
        let sets = workouts.flatMap { workout in
            workout.exercises.filter { $0.name == exerciseName }.flatMap { $0.sets }
        }
        return sets.map { estimateOneRepMax(weight: $0.weight, reps: $0.reps) }.max() ?? 0
    }

    private static func previousExerciseValue(_ workouts: [Workout], exerciseName: String) -> Double {
        currentExerciseValue(workouts, exerciseName: exerciseName)
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
        guard previous != 0 else { return 0 }
        return (current - previous) / previous * 100
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
