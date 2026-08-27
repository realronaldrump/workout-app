import Foundation

nonisolated enum ExerciseAnalysisEngine {
    private static let equalityTolerance = 0.000_001

    static func analyze(
        exerciseName: String,
        metric: ExerciseAnalysisMetric,
        sessions: [ExerciseHistorySession]
    ) -> ExerciseMetricAnalysis {
        let direction = direction(for: metric, exerciseName: exerciseName)
        let observations = sessions
            .sorted(by: sessionOrder)
            .compactMap { observation(
                for: $0,
                exerciseName: exerciseName,
                metric: metric,
                direction: direction
            ) }
        let recordHistory = recordHistory(in: observations, direction: direction)
        let attempts = observations.sorted { lhs, rhs in
            if approximatelyEqual(lhs.value, rhs.value) {
                return lhs.date > rhs.date
            }
            switch direction {
            case .lowerIsBetter:
                return lhs.value < rhs.value
            case .higherIsBetter, .neutral:
                return lhs.value > rhs.value
            }
        }
        let average = observations.isEmpty
            ? nil
            : observations.reduce(0) { $0 + $1.value } / Double(observations.count)
        let total = observations.reduce(0) { $0 + $1.value }
        let best = attempts.first?.value
        let headline: Double? = {
            switch metric {
            case .sessions:
                return Double(observations.count)
            case .setCount, .distance, .duration, .count:
                return observations.isEmpty ? nil : total
            case .averageReps:
                let reps = sessions.flatMap(\.sets).map(\.reps).filter { $0 > 0 }
                guard !reps.isEmpty else { return nil }
                return Double(reps.reduce(0, +)) / Double(reps.count)
            case .maxLoad, .maxReps, .sessionVolume, .setVolume, .estimatedOneRepMax:
                return best
            }
        }()

        return ExerciseMetricAnalysis(
            exerciseName: exerciseName,
            metric: metric,
            direction: direction,
            observations: observations,
            recordEvents: recordHistory.events,
            matchedRecords: recordHistory.matches,
            topAttempts: Array(attempts.prefix(10)),
            headlineValue: headline,
            bestValue: best,
            totalValue: total,
            averageValue: average,
            recentComparison: recentComparison(in: observations, direction: direction)
        )
    }

    private static func direction(
        for metric: ExerciseAnalysisMetric,
        exerciseName: String
    ) -> MetricDirection {
        switch metric {
        case .sessions, .setCount, .averageReps:
            return .neutral
        case .maxLoad, .estimatedOneRepMax:
            return ExerciseLoad.isAssistedExercise(exerciseName) ? .lowerIsBetter : .higherIsBetter
        case .maxReps, .sessionVolume, .setVolume, .distance, .duration, .count:
            return .higherIsBetter
        }
    }

    private static func observation(
        for session: ExerciseHistorySession,
        exerciseName: String,
        metric: ExerciseAnalysisMetric,
        direction: MetricDirection
    ) -> MetricObservation? {
        switch metric {
        case .sessions:
            guard !session.sets.isEmpty else { return nil }
            return sessionObservation(session: session, value: 1, metric: metric)
        case .setCount:
            guard !session.sets.isEmpty else { return nil }
            return sessionObservation(
                session: session,
                value: Double(session.sets.count),
                metric: metric
            )
        case .maxLoad:
            return maxLoadObservation(
                for: session,
                exerciseName: exerciseName,
                metric: metric,
                direction: direction
            )
        case .averageReps:
            return averageRepsObservation(for: session, metric: metric)
        case .maxReps:
            return maxRepsObservation(
                for: session,
                metric: metric,
                direction: direction
            )
        case .sessionVolume:
            return sessionVolumeObservation(
                for: session,
                exerciseName: exerciseName,
                metric: metric
            )
        case .setVolume:
            return setVolumeObservation(
                for: session,
                exerciseName: exerciseName,
                metric: metric,
                direction: direction
            )
        case .estimatedOneRepMax:
            return oneRepMaxObservation(
                for: session,
                exerciseName: exerciseName,
                metric: metric,
                direction: direction
            )
        case .distance:
            return distanceObservation(
                for: session,
                metric: metric
            )
        case .duration:
            return durationObservation(
                for: session,
                metric: metric
            )
        case .count:
            return countObservation(
                for: session,
                metric: metric
            )
        }
    }

    private static func maxLoadObservation(
        for session: ExerciseHistorySession,
        exerciseName: String,
        metric: ExerciseAnalysisMetric,
        direction: MetricDirection
    ) -> MetricObservation? {
        let candidates = session.sets.filter {
            $0.weight.isFinite &&
                ExerciseLoad.isTrackedWeight($0.weight, exerciseName: exerciseName)
        }
        guard let set = bestSet(in: candidates, direction: direction, value: { $0.weight }) else {
            return nil
        }
        return setObservation(session: session, set: set, value: set.weight, metric: metric)
    }

    private static func averageRepsObservation(
        for session: ExerciseHistorySession,
        metric: ExerciseAnalysisMetric
    ) -> MetricObservation? {
        let reps = session.sets.map(\.reps).filter { $0 > 0 }
        guard !reps.isEmpty else { return nil }
        return sessionObservation(
            session: session,
            value: Double(reps.reduce(0, +)) / Double(reps.count),
            metric: metric
        )
    }

    private static func maxRepsObservation(
        for session: ExerciseHistorySession,
        metric: ExerciseAnalysisMetric,
        direction: MetricDirection
    ) -> MetricObservation? {
        let candidates = session.sets.filter { $0.reps > 0 }
        guard let set = bestSet(in: candidates, direction: direction, value: { Double($0.reps) }) else {
            return nil
        }
        return setObservation(
            session: session,
            set: set,
            value: Double(set.reps),
            metric: metric
        )
    }

    private static func sessionVolumeObservation(
        for session: ExerciseHistorySession,
        exerciseName: String,
        metric: ExerciseAnalysisMetric
    ) -> MetricObservation? {
        guard !ExerciseLoad.isAssistedExercise(exerciseName) else { return nil }
        let value = session.sets.reduce(0) { partial, set in
            guard set.weight.isFinite, set.weight > 0, set.reps > 0 else { return partial }
            return partial + set.weight * Double(set.reps)
        }
        guard value.isFinite, value > 0 else { return nil }
        return sessionObservation(session: session, value: value, metric: metric)
    }

    private static func setVolumeObservation(
        for session: ExerciseHistorySession,
        exerciseName: String,
        metric: ExerciseAnalysisMetric,
        direction: MetricDirection
    ) -> MetricObservation? {
        guard !ExerciseLoad.isAssistedExercise(exerciseName) else { return nil }
        let candidates = session.sets.filter {
            $0.weight.isFinite && $0.weight > 0 && $0.reps > 0
        }
        guard let set = bestSet(
            in: candidates,
            direction: direction,
            value: { $0.weight * Double($0.reps) }
        ) else {
            return nil
        }
        return setObservation(
            session: session,
            set: set,
            value: set.weight * Double(set.reps),
            metric: metric
        )
    }

    private static func oneRepMaxObservation(
        for session: ExerciseHistorySession,
        exerciseName: String,
        metric: ExerciseAnalysisMetric,
        direction: MetricDirection
    ) -> MetricObservation? {
        let candidates = session.sets.filter {
            $0.weight.isFinite &&
                $0.reps > 0 &&
                ExerciseLoad.isTrackedWeight($0.weight, exerciseName: exerciseName) &&
                OneRepMax.estimate(
                    weight: $0.weight,
                    reps: $0.reps,
                    exerciseName: exerciseName
                ).isFinite
        }
        guard let set = bestSet(
            in: candidates,
            direction: direction,
            value: {
                OneRepMax.estimate(
                    weight: $0.weight,
                    reps: $0.reps,
                    exerciseName: exerciseName
                )
            }
        ) else {
            return nil
        }
        return setObservation(
            session: session,
            set: set,
            value: OneRepMax.estimate(
                weight: set.weight,
                reps: set.reps,
                exerciseName: exerciseName
            ),
            metric: metric
        )
    }

    private static func distanceObservation(
        for session: ExerciseHistorySession,
        metric: ExerciseAnalysisMetric
    ) -> MetricObservation? {
        let distance = session.sets.reduce(0) { partial, set in
            guard set.distance.isFinite, set.distance > 0 else { return partial }
            return partial + set.distance
        }
        guard distance > 0 else { return nil }
        return sessionObservation(
            session: session,
            value: distance,
            metric: metric,
            distance: distance,
            seconds: positiveTotalSeconds(in: session),
            reps: positiveTotalCount(in: session)
        )
    }

    private static func durationObservation(
        for session: ExerciseHistorySession,
        metric: ExerciseAnalysisMetric
    ) -> MetricObservation? {
        guard let seconds = positiveTotalSeconds(in: session) else { return nil }
        return sessionObservation(
            session: session,
            value: seconds,
            metric: metric,
            distance: positiveTotalDistance(in: session),
            seconds: seconds,
            reps: positiveTotalCount(in: session)
        )
    }

    private static func countObservation(
        for session: ExerciseHistorySession,
        metric: ExerciseAnalysisMetric
    ) -> MetricObservation? {
        guard let count = positiveTotalCount(in: session) else { return nil }
        return sessionObservation(
            session: session,
            value: Double(count),
            metric: metric,
            distance: positiveTotalDistance(in: session),
            seconds: positiveTotalSeconds(in: session),
            reps: count
        )
    }

    private static func bestSet(
        in sets: [WorkoutSet],
        direction: MetricDirection,
        value: (WorkoutSet) -> Double
    ) -> WorkoutSet? {
        guard var best = sets.first else { return nil }
        for set in sets.dropFirst() where direction.isBetter(value(set), than: value(best)) {
            best = set
        }
        return best
    }

    private static func setObservation(
        session: ExerciseHistorySession,
        set: WorkoutSet,
        value: Double,
        metric: ExerciseAnalysisMetric
    ) -> MetricObservation {
        MetricObservation(
            id: "\(metric.rawValue)|\(session.workoutId.uuidString)|\(set.id.uuidString)",
            date: session.date,
            value: value,
            source: .workout(session.workoutId),
            workoutName: set.workoutName,
            setID: set.id,
            weight: set.weight,
            reps: set.reps,
            distance: set.distance > 0 ? set.distance : nil,
            seconds: set.seconds > 0 ? set.seconds : nil
        )
    }

    private static func sessionObservation(
        session: ExerciseHistorySession,
        value: Double,
        metric: ExerciseAnalysisMetric,
        distance: Double? = nil,
        seconds: Double? = nil,
        reps: Int? = nil
    ) -> MetricObservation {
        MetricObservation(
            id: "\(metric.rawValue)|\(session.workoutId.uuidString)",
            date: session.date,
            value: value,
            source: .workout(session.workoutId),
            workoutName: session.sets.first?.workoutName ?? "Workout",
            reps: reps,
            distance: distance,
            seconds: seconds
        )
    }

    private static func positiveTotalDistance(in session: ExerciseHistorySession) -> Double? {
        let distance = session.sets.reduce(0) { partial, set in
            guard set.distance.isFinite, set.distance > 0 else { return partial }
            return partial + set.distance
        }
        return distance > 0 ? distance : nil
    }

    private static func positiveTotalSeconds(in session: ExerciseHistorySession) -> Double? {
        let seconds = session.sets.reduce(0) { partial, set in
            guard set.seconds.isFinite, set.seconds > 0 else { return partial }
            return partial + set.seconds
        }
        return seconds > 0 ? seconds : nil
    }

    private static func positiveTotalCount(in session: ExerciseHistorySession) -> Int? {
        let count = session.sets.reduce(0) { $0 + max($1.reps, 0) }
        return count > 0 ? count : nil
    }

    private static func recordHistory(
        in observations: [MetricObservation],
        direction: MetricDirection
    ) -> (events: [MetricRecordEvent], matches: [MetricObservation]) {
        guard direction != .neutral else { return ([], []) }
        var events: [MetricRecordEvent] = []
        var matches: [MetricObservation] = []
        var bestValue: Double?

        for observation in observations {
            guard let currentBest = bestValue else {
                events.append(MetricRecordEvent(
                    observation: observation,
                    previousValue: nil,
                    improvement: nil
                ))
                bestValue = observation.value
                continue
            }

            if direction.isBetter(observation.value, than: currentBest) {
                let improvement = direction == .lowerIsBetter
                    ? currentBest - observation.value
                    : observation.value - currentBest
                events.append(MetricRecordEvent(
                    observation: observation,
                    previousValue: currentBest,
                    improvement: improvement
                ))
                bestValue = observation.value
            } else if approximatelyEqual(observation.value, currentBest) {
                matches.append(observation)
            }
        }
        return (events, matches)
    }

    private static func recentComparison(
        in observations: [MetricObservation],
        direction: MetricDirection
    ) -> MetricRecentComparison? {
        guard observations.count >= 10 else { return nil }
        let recent = observations.suffix(5).map(\.value)
        let previous = observations.dropLast(5).suffix(5).map(\.value)
        let currentAverage = recent.reduce(0, +) / Double(recent.count)
        let previousAverage = previous.reduce(0, +) / Double(previous.count)
        let improvement: Double
        switch direction {
        case .higherIsBetter:
            improvement = currentAverage - previousAverage
        case .lowerIsBetter:
            improvement = previousAverage - currentAverage
        case .neutral:
            improvement = currentAverage - previousAverage
        }
        return MetricRecentComparison(
            currentAverage: currentAverage,
            previousAverage: previousAverage,
            improvement: improvement
        )
    }

    private static func sessionOrder(_ lhs: ExerciseHistorySession, _ rhs: ExerciseHistorySession) -> Bool {
        if lhs.date == rhs.date {
            return lhs.workoutId.uuidString < rhs.workoutId.uuidString
        }
        return lhs.date < rhs.date
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= equalityTolerance
    }
}

/// On-device cache for the pure exercise analysis result. The key carries the workout
/// dataset revision plus the exact track, gym scope, metric, range, and session digest,
/// so edits, deletions, and scope changes cannot reuse stale evidence.
actor ExerciseAnalysisCache {
    static let shared = ExerciseAnalysisCache()

    private struct Key: Hashable {
        let datasetRevision: UInt64
        let scope: ExerciseAnalysisScope
        let metric: ExerciseAnalysisMetric
        let range: String
        let sessionDigest: Int
    }

    private var values: [Key: ExerciseMetricAnalysis] = [:]
    private let capacity = 96

    func analysis(
        datasetRevision: UInt64,
        scope: ExerciseAnalysisScope,
        metric: ExerciseAnalysisMetric,
        range: String = "allTime",
        sessions: [ExerciseHistorySession]
    ) -> ExerciseMetricAnalysis {
        let key = Key(
            datasetRevision: datasetRevision,
            scope: scope,
            metric: metric,
            range: range,
            sessionDigest: Self.digest(sessions)
        )
        if let cached = values[key] {
            return cached
        }

        let result = ExerciseAnalysisEngine.analyze(
            exerciseName: scope.performanceTrackName,
            metric: metric,
            sessions: sessions
        )
        if values.count >= capacity {
            values.removeAll(keepingCapacity: true)
        }
        values[key] = result
        return result
    }

    private static func digest(_ sessions: [ExerciseHistorySession]) -> Int {
        var hasher = Hasher()
        for session in sessions {
            hasher.combine(session)
        }
        return hasher.finalize()
    }
}
