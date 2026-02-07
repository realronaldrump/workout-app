import Foundation
import SwiftUI

// swiftlint:disable file_length type_body_length
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
            let parts = trimmed.split(separator: ":").compactMap { Int($0) }
            if parts.count == 3 {
                return Double(parts[0] * 60 + parts[1])
            } else if parts.count == 2 {
                return Double(parts[0])
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
            return Double(hours * 60 + minutes)
        }

        return Double(Int(trimmed) ?? 0)
    }

    nonisolated static func effortDensity(for workout: Workout) -> Double {
        let duration = max(durationMinutes(from: workout.duration), 1)
        return workout.totalVolume / duration
    }

    static func effortDensitySeries(for workouts: [Workout]) -> [EffortDensityPoint] {
        workouts.sorted { $0.date < $1.date }.map { workout in
            EffortDensityPoint(
                workoutId: workout.id,
                date: workout.date,
                value: effortDensity(for: workout),
                durationMinutes: durationMinutes(from: workout.duration),
                volume: workout.totalVolume
            )
        }
    }

    static func repRangeDistribution(for workouts: [Workout]) -> [RepRangeBucket] {
        let allSets = workouts.flatMap { $0.exercises }.flatMap { $0.sets }
        let buckets: [RepRangeDescriptor] = [
            RepRangeDescriptor(label: "1-3", range: 1...3, tint: Theme.Colors.error),
            RepRangeDescriptor(label: "4-6", range: 4...6, tint: Theme.Colors.warning),
            RepRangeDescriptor(label: "7-10", range: 7...10, tint: Theme.Colors.accent),
            RepRangeDescriptor(label: "11-15", range: 11...15, tint: Theme.Colors.accentSecondary),
            RepRangeDescriptor(label: "16-20", range: 16...20, tint: Theme.Colors.success),
            RepRangeDescriptor(label: "21+", range: 21...100, tint: Theme.Colors.textSecondary)
        ]

        let total = max(allSets.count, 1)
        return buckets.map { bucket in
            let count = allSets.filter { bucket.range.contains($0.reps) }.count
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

        let currentDensity = average(current.map { effortDensity(for: $0) })
        let previousDensity = average(previous.map { effortDensity(for: $0) })

        let currentVolume = current.reduce(0) { $0 + $1.totalVolume }
        let previousVolume = previous.reduce(0) { $0 + $1.totalVolume }

        let currentSessions = Double(current.count)
        let previousSessions = Double(previous.count)

        return [
            changeMetric(title: "Sessions", current: currentSessions, previous: previousSessions),
            changeMetric(title: "Total Volume", current: currentVolume, previous: previousVolume),
            changeMetric(title: "Avg Duration", current: currentDuration, previous: previousDuration),
            changeMetric(title: "Effort Density", current: currentDensity, previous: previousDensity)
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

    // swiftlint:disable:next cyclomatic_complexity
    static func consistencyIssues(for workouts: [Workout]) -> [ConsistencyIssue] {
        guard !workouts.isEmpty else { return [] }
        let calendar = Calendar.current

        let sorted = workouts.sorted { $0.date < $1.date }
        let firstDate = sorted.first?.date ?? Date()
        let lastDate = sorted.last?.date ?? firstDate
        let expectedPerWeek = max(1, Int(round(Double(sorted.count) / weeksBetween(firstDate, lastDate))))

        var issues: [ConsistencyIssue] = []

        let recentWeeks = 8
        for weekOffset in 0..<recentWeeks {
            guard let weekStart = calendar.date(byAdding: .day, value: -(weekOffset * 7), to: Date()) else { continue }
            let start = calendar.date(byAdding: .day, value: -6, to: weekStart) ?? weekStart
            let end = weekStart
            let count = workouts.filter { $0.date >= start && $0.date <= end }.count
            if count < expectedPerWeek {
                let missing = expectedPerWeek - count
                issues.append(
                    ConsistencyIssue(
                        type: .missedDay,
                        title: "missed \(missing)",
                        detail: "week \(start.formatted(date: .abbreviated, time: .omitted)) | expected \(expectedPerWeek) | actual \(count)",
                        workoutId: nil,
                        date: start
                    )
                )
            }
        }

        let durationsByName = Dictionary(grouping: workouts, by: { $0.name }).mapValues { items in
            median(items.map { durationMinutes(from: $0.duration) })
        }

        for workout in workouts {
            if let baseline = durationsByName[workout.name], baseline > 0 {
                let duration = durationMinutes(from: workout.duration)
                if duration < baseline * 0.7 {
                    issues.append(
                        ConsistencyIssue(
                            type: .shortenedSession,
                            title: "short \(workout.name)",
                            detail: "duration \(Int(duration))m | baseline \(Int(baseline))m",
                            workoutId: workout.id,
                            date: workout.date
                        )
                    )
                }
            }
        }

        let groupedByName = Dictionary(grouping: workouts, by: { $0.name })
        for (name, sessions) in groupedByName {
            let exerciseCounts = Dictionary(grouping: sessions.flatMap { $0.exercises }) { $0.name }
                .mapValues { $0.count }
            let threshold = max(2, Int(Double(sessions.count) * 0.6))
            let typical = exerciseCounts.filter { $0.value >= threshold }.map { $0.key }

            guard !typical.isEmpty else { continue }

            for session in sessions {
                let present = Set(session.exercises.map { $0.name })
                let missing = typical.filter { !present.contains($0) }
                if !missing.isEmpty {
                    issues.append(
                        ConsistencyIssue(
                            type: .skippedExercises,
                            title: "skipped \(name)",
                            detail: "missing \(missing.prefix(2).joined(separator: ", "))",
                            workoutId: session.id,
                            date: session.date
                        )
                    )
                }
            }
        }

        return issues
    }

    static func fatigueSummary(for workout: Workout, allWorkouts: [Workout]) -> FatigueSummary {
        var entries: [FatigueEntry] = []
        let rpeValues = workout.exercises.flatMap { $0.sets }.compactMap { Double($0.rpe ?? "") }
        let avgRPE = rpeValues.isEmpty ? nil : rpeValues.reduce(0, +) / Double(rpeValues.count)

        for exercise in workout.exercises {
            let sets = exercise.sets.sorted { $0.setOrder < $1.setOrder }
            guard let best = sets.map({ $0.weight * Double($0.reps) }).max(),
                  let last = sets.last.map({ $0.weight * Double($0.reps) }),
                  best > 0 else { continue }

            let drop = max(0, (best - last) / best)
            if drop >= 0.15 {
                let note = String(format: "drop %.0f%%", drop * 100)
                entries.append(
                    FatigueEntry(
                        exerciseName: exercise.name,
                        dropPercent: drop,
                        setCount: sets.count,
                        note: note
                    )
                )
            }
        }

        let duration = durationMinutes(from: workout.duration)
        let restIndex = workout.totalSets > 0 ? duration / Double(workout.totalSets) : nil

        let similar = allWorkouts.filter { $0.name == workout.name }
        let baseline = median(similar.map { durationMinutes(from: $0.duration) / max(Double($0.totalSets), 1) })

        let restTrend: String?
        if let restIndex, baseline > 0 {
            let delta = (restIndex - baseline) / baseline
            restTrend = String(format: "rest idx %+0.f%%", delta * 100)
        } else {
            restTrend = nil
        }

        return FatigueSummary(
            workoutId: workout.id,
            entries: entries.sorted { $0.dropPercent > $1.dropPercent },
            restTimeIndex: restIndex,
            restTimeTrend: restTrend,
            effortDensity: effortDensity(for: workout),
            averageRPE: avgRPE
        )
    }

    static func habitImpactInsights(
        workouts: [Workout],
        annotations: [UUID: WorkoutAnnotation]
    ) -> [HabitImpactInsight] {
        var insights: [HabitImpactInsight] = []

        let densityByStress = groupAverage(workouts: workouts, annotations: annotations) { $0.stress?.label }
        if let (label, value) = topDifference(from: densityByStress) {
            insights.append(
                HabitImpactInsight(
                    kind: .stress,
                    title: "Stress impact",
                    detail: "density \(value) | stress \(label)",
                    value: value,
                    tint: Theme.Colors.warning
                )
            )
        }

        let densityByCaffeine = groupAverage(workouts: workouts, annotations: annotations) { $0.caffeine?.label }
        if let (label, value) = topDifference(from: densityByCaffeine) {
            insights.append(
                HabitImpactInsight(
                    kind: .caffeine,
                    title: "Caffeine impact",
                    detail: "density \(value) | caffeine \(label)",
                    value: value,
                    tint: Theme.Colors.accent
                )
            )
        }

        let densityBySoreness = groupAverage(workouts: workouts, annotations: annotations) { $0.soreness?.label }
        if let (label, value) = topDifference(from: densityBySoreness) {
            insights.append(
                HabitImpactInsight(
                    kind: .soreness,
                    title: "Soreness impact",
                    detail: "density \(value) | soreness \(label)",
                    value: value,
                    tint: Theme.Colors.success
                )
            )
        }

        let densityByMood = groupAverage(workouts: workouts, annotations: annotations) { $0.mood?.label }
        if let (label, value) = topDifference(from: densityByMood) {
            insights.append(
                HabitImpactInsight(
                    kind: .mood,
                    title: "Mood impact",
                    detail: "density \(value) | mood \(label)",
                    value: value,
                    tint: Theme.Colors.accentSecondary
                )
            )
        }

        var timeBuckets: [String: [Double]] = [:]
        for workout in workouts {
            let label = timeOfDayLabel(for: workout.date)
            timeBuckets[label, default: []].append(effortDensity(for: workout))
        }
        let densityByTime = timeBuckets.mapValues { average($0) }
        if let (label, value) = topDifference(from: densityByTime) {
            insights.append(
                HabitImpactInsight(
                    kind: .timeOfDay,
                    title: "Time of day",
                    detail: "density \(value) | \(label)",
                    value: value,
                    tint: Theme.Colors.accentSecondary
                )
            )
        }

        return insights
    }

    static func habitImpactDetail(
        kind: HabitFactorKind,
        workouts: [Workout],
        annotations: [UUID: WorkoutAnnotation]
    ) -> HabitImpactDetailModel {
        var buckets: [String: [Workout]] = [:]

        for workout in workouts {
            let label: String?
            switch kind {
            case .stress:
                label = annotations[workout.id]?.stress?.label
            case .caffeine:
                label = annotations[workout.id]?.caffeine?.label
            case .soreness:
                label = annotations[workout.id]?.soreness?.label
            case .mood:
                label = annotations[workout.id]?.mood?.label
            case .timeOfDay:
                label = timeOfDayLabel(for: workout.date)
            }

            guard let label else { continue }
            buckets[label, default: []].append(workout)
        }

        let models = buckets.map { label, items in
            let densities = items.map { effortDensity(for: $0) }
            let avg = average(densities)
            return HabitImpactBucket(
                label: label.lowercased(),
                averageDensity: avg,
                workoutCount: items.count,
                workouts: items.sorted { $0.date > $1.date }
            )
        }
        .sorted { $0.averageDensity > $1.averageDensity }

        return HabitImpactDetailModel(kind: kind, buckets: models)
    }

    static func correlationInsights(
        workouts: [Workout],
        healthData: [UUID: WorkoutHealthData]
    ) -> [CorrelationInsight] {
        var insights: [CorrelationInsight] = []

        let points = workouts.compactMap { workout -> (sleep: Double, density: Double)? in
            guard let sleep = healthData[workout.id]?.sleepSummary?.totalHours else { return nil }
            return (sleep, effortDensity(for: workout))
        }
        if let correlation = correlation(points.map { $0.sleep }, points.map { $0.density }), points.count >= 4 {
            let title = "Sleep vs output"
            let highSleep = points.filter { $0.sleep >= 7 }.map { $0.density }
            let lowSleep = points.filter { $0.sleep < 7 }.map { $0.density }
            let avgHigh = average(highSleep)
            let avgLow = average(lowSleep)
            let detail = "avg>=7h \(String(format: "%.1f", avgHigh)) | <7h \(String(format: "%.1f", avgLow))"
            insights.append(
                CorrelationInsight(
                    kind: .sleepVsOutput,
                    title: title,
                    detail: detail,
                    correlation: correlation,
                    supportingCount: points.count,
                    exerciseName: nil
                )
            )
        }

        let readinessPoints = workouts.compactMap { workout -> (readiness: Double, density: Double)? in
            guard let readiness = readinessScore(for: healthData[workout.id]) else { return nil }
            return (readiness, effortDensity(for: workout))
        }
        if let correlation = correlation(readinessPoints.map { $0.readiness }, readinessPoints.map { $0.density }), readinessPoints.count >= 4 {
            let title = "Readiness vs output"
            let highReadiness = readinessPoints.filter { $0.readiness >= 70 }.map { $0.density }
            let lowReadiness = readinessPoints.filter { $0.readiness < 70 }.map { $0.density }
            let avgHigh = average(highReadiness)
            let avgLow = average(lowReadiness)
            let detail = "avg>=70 \(String(format: "%.1f", avgHigh)) | <70 \(String(format: "%.1f", avgLow))"
            insights.append(
                CorrelationInsight(
                    kind: .readinessVsOutput,
                    title: title,
                    detail: detail,
                    correlation: correlation,
                    supportingCount: readinessPoints.count,
                    exerciseName: nil
                )
            )
        }

        if let topExercise = topExerciseName(in: workouts) {
            let paired = workouts.compactMap { workout -> (sleep: Double, orm: Double)? in
                guard let sleep = healthData[workout.id]?.sleepSummary?.totalHours else { return nil }
                guard let exercise = workout.exercises.first(where: { $0.name == topExercise }) else { return nil }
                let best = exercise.sets.map { estimateOneRepMax(weight: $0.weight, reps: $0.reps) }.max() ?? 0
                return best > 0 ? (sleep, best) : nil
            }

            let goodSleep = paired.filter { $0.sleep >= 7 }.map { $0.orm }
            let lowSleep = paired.filter { $0.sleep < 7 }.map { $0.orm }
            if goodSleep.count >= 2, lowSleep.count >= 2 {
                let avgGood = average(goodSleep)
                let avgLow = average(lowSleep)
                let delta = avgGood - avgLow
                let sleeps = paired.map { $0.sleep }
                let orms = paired.map { $0.orm }
                if let corr = correlation(sleeps, orms), paired.count >= 4 {
                    let detail = "avg1RM 7h+ \(Int(avgGood)) | <7h \(Int(avgLow)) | delta \(Int(delta))"
                    insights.append(
                        CorrelationInsight(
                            kind: .sleepVsTopExercise,
                            title: "Sleep vs \(topExercise)",
                            detail: detail,
                            correlation: corr,
                            supportingCount: paired.count,
                            exerciseName: topExercise
                        )
                    )
                }
            }
        }

        return insights
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func correlationDetail(
        kind: CorrelationKind,
        workouts: [Workout],
        healthData: [UUID: WorkoutHealthData]
    ) -> CorrelationDetailModel {
        let sortedWorkouts = workouts.sorted { $0.date < $1.date }

        switch kind {
        case .sleepVsOutput:
            let points = sortedWorkouts.compactMap { workout -> CorrelationDetailPoint? in
                guard let sleep = healthData[workout.id]?.sleepSummary?.totalHours else { return nil }
                let density = effortDensity(for: workout)
                guard density > 0 else { return nil }
                return CorrelationDetailPoint(workoutId: workout.id, date: workout.date, x: sleep, y: density)
            }
            let corr = correlation(points.map(\.x), points.map(\.y))
            return CorrelationDetailModel(
                kind: kind,
                points: points,
                correlation: corr,
                supportingCount: points.count,
                title: "Sleep vs output",
                xLabel: "Sleep (h)",
                yLabel: "Output",
                exerciseName: nil
            )
        case .readinessVsOutput:
            let points = sortedWorkouts.compactMap { workout -> CorrelationDetailPoint? in
                guard let readiness = readinessScore(for: healthData[workout.id]) else { return nil }
                let density = effortDensity(for: workout)
                guard density > 0 else { return nil }
                return CorrelationDetailPoint(workoutId: workout.id, date: workout.date, x: readiness, y: density)
            }
            let corr = correlation(points.map(\.x), points.map(\.y))
            return CorrelationDetailModel(
                kind: kind,
                points: points,
                correlation: corr,
                supportingCount: points.count,
                title: "Readiness vs output",
                xLabel: "Readiness",
                yLabel: "Output",
                exerciseName: nil
            )
        case .sleepVsTopExercise:
            let topExercise = topExerciseName(in: workouts)
            let points = sortedWorkouts.compactMap { workout -> CorrelationDetailPoint? in
                guard let sleep = healthData[workout.id]?.sleepSummary?.totalHours else { return nil }
                guard let name = topExercise else { return nil }
                guard let exercise = workout.exercises.first(where: { $0.name == name }) else { return nil }
                let best = exercise.sets.map { estimateOneRepMax(weight: $0.weight, reps: $0.reps) }.max() ?? 0
                guard best > 0 else { return nil }
                return CorrelationDetailPoint(workoutId: workout.id, date: workout.date, x: sleep, y: best)
            }
            let corr = correlation(points.map(\.x), points.map(\.y))
            let title = topExercise.map { "Sleep vs \($0)" } ?? "Sleep vs top exercise"
            return CorrelationDetailModel(
                kind: kind,
                points: points,
                correlation: corr,
                supportingCount: points.count,
                title: title,
                xLabel: "Sleep (h)",
                yLabel: "1RM",
                exerciseName: topExercise
            )
        }
    }

    static func recoveryDebtSnapshot(
        workouts: [Workout],
        healthData: [UUID: WorkoutHealthData]
    ) -> RecoveryDebtSnapshot? {
        guard !workouts.isEmpty else { return nil }

        let calendar = Calendar.current
        let last7Start = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let last28Start = calendar.date(byAdding: .day, value: -28, to: Date()) ?? Date()

        let recentWorkouts = workouts.filter { $0.date >= last7Start }
        let baselineWorkouts = workouts.filter { $0.date >= last28Start && $0.date < last7Start }

        let recentVolume = recentWorkouts.reduce(0) { $0 + $1.totalVolume }
        let baselineVolume = max(baselineWorkouts.reduce(0) { $0 + $1.totalVolume }, 1)
        let loadRatio = recentVolume / baselineVolume

        let sleepHours = average(recentWorkouts.compactMap { healthData[$0.id]?.sleepSummary?.totalHours })
        let readiness = average(recentWorkouts.compactMap { readinessScore(for: healthData[$0.id]) })

        var score = 100.0
        if loadRatio > 1.1 {
            score -= min((loadRatio - 1) * 30, 40)
        }
        if sleepHours > 0 {
            score -= max(0, (7 - sleepHours) * 8)
        }
        if readiness > 0 {
            score -= max(0, (70 - readiness) * 0.6)
        }

        let clamped = Int(max(0, min(100, score)))
        let label: String
        let detail: String
        let tint: Color

        let sleepLabel = sleepHours > 0 ? String(format: "%.1f", sleepHours) : "--"
        let readinessLabel = readiness > 0 ? String(format: "%.0f", readiness) : "--"
        let detailBase = "load \(String(format: "%.2f", loadRatio)) | sleep \(sleepLabel)h | ready \(readinessLabel)"

        switch clamped {
        case 80...100:
            label = "Low debt"
            detail = detailBase
            tint = Theme.Colors.success
        case 60..<80:
            label = "Moderate debt"
            detail = detailBase
            tint = Theme.Colors.warning
        default:
            label = "High debt"
            detail = detailBase
            tint = Theme.Colors.error
        }

        return RecoveryDebtSnapshot(score: clamped, label: label, detail: detail, tint: tint)
    }

    static func readinessScore(for healthData: WorkoutHealthData?) -> Double? {
        guard let hrv = healthData?.avgHRV, let resting = healthData?.restingHeartRate else { return nil }
        return max(0, min(100, (hrv / max(resting, 1)) * 12))
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

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func weeksBetween(_ start: Date, _ end: Date) -> Double {
        let weeks = Calendar.current.dateComponents([.weekOfYear], from: start, to: end).weekOfYear ?? 0
        return max(Double(weeks), 1)
    }

    private static func groupAverage(
        workouts: [Workout],
        annotations: [UUID: WorkoutAnnotation],
        key: (WorkoutAnnotation) -> String?
    ) -> [String: Double] {
        var buckets: [String: [Double]] = [:]
        for workout in workouts {
            guard let annotation = annotations[workout.id], let label = key(annotation) else { continue }
            let density = effortDensity(for: workout)
            buckets[label, default: []].append(density)
        }
        return buckets.mapValues { average($0) }
    }

    private static func topDifference(from map: [String: Double]) -> (String, String)? {
        guard let best = map.max(by: { $0.value < $1.value }) else { return nil }
        let formatted = String(format: "%.1f", best.value)
        return (best.key.lowercased(), formatted)
    }

    private static func timeOfDayLabel(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "morning"
        case 12..<17:
            return "afternoon"
        case 17..<22:
            return "evening"
        default:
            return "late"
        }
    }

    private static func correlation(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        let meanX = average(xs)
        let meanY = average(ys)
        var numerator = 0.0
        var denominatorX = 0.0
        var denominatorY = 0.0

        for (x, y) in zip(xs, ys) {
            let dx = x - meanX
            let dy = y - meanY
            numerator += dx * dy
            denominatorX += dx * dx
            denominatorY += dy * dy
        }

        let denom = sqrt(denominatorX * denominatorY)
        guard denom > 0 else { return nil }
        return numerator / denom
    }

    private static func topExerciseName(in workouts: [Workout]) -> String? {
        let counts = workouts.flatMap { $0.exercises }.reduce(into: [String: Int]()) { counts, exercise in
            counts[exercise.name, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
