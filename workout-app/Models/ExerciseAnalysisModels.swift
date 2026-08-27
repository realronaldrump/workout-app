import Foundation

nonisolated enum MetricDirection: String, Hashable, Sendable {
    case higherIsBetter
    case lowerIsBetter
    case neutral

    func isBetter(_ candidate: Double, than current: Double) -> Bool {
        switch self {
        case .higherIsBetter:
            return candidate > current
        case .lowerIsBetter:
            return candidate < current
        case .neutral:
            return false
        }
    }
}

nonisolated enum MetricSource: Hashable, Sendable {
    case workout(UUID)
    case healthDay(Date)
}

nonisolated enum ExerciseAnalysisMetric: String, Identifiable, Hashable, Sendable {
    case sessions
    case setCount
    case maxLoad
    case averageReps
    case maxReps
    case sessionVolume
    case setVolume
    case estimatedOneRepMax
    case distance
    case duration
    case count

    var id: String { rawValue }
}

nonisolated enum ExerciseMetricFocus: String, Hashable, Sendable {
    case overview
    case total
    case recordHistory
    case topAttempts
}

nonisolated enum ExerciseAnalysisGymScope: Hashable, Sendable {
    case all
    case unassigned
    case gym(UUID)
}

nonisolated struct ExerciseAnalysisScope: Hashable, Sendable {
    let exerciseName: String
    let performanceTrackName: String
    let gym: ExerciseAnalysisGymScope

    init(
        exerciseName: String,
        performanceTrackName: String? = nil,
        gym: ExerciseAnalysisGymScope = .all
    ) {
        self.exerciseName = exerciseName
        self.performanceTrackName = performanceTrackName ?? exerciseName
        self.gym = gym
    }
}

nonisolated struct ExerciseMetricSelection: Identifiable, Hashable, Sendable {
    let scope: ExerciseAnalysisScope
    let metric: ExerciseAnalysisMetric
    let focus: ExerciseMetricFocus

    var id: String {
        "\(scope.performanceTrackName)|\(scope.gym)|\(metric.rawValue)|\(focus.rawValue)"
    }
}

nonisolated struct MetricObservation: Identifiable, Hashable, Sendable {
    let id: String
    let date: Date
    let value: Double
    let source: MetricSource
    let workoutName: String
    let setID: UUID?
    let weight: Double?
    let reps: Int?
    let distance: Double?
    let seconds: Double?

    init(
        id: String,
        date: Date,
        value: Double,
        source: MetricSource,
        workoutName: String,
        setID: UUID? = nil,
        weight: Double? = nil,
        reps: Int? = nil,
        distance: Double? = nil,
        seconds: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.value = value
        self.source = source
        self.workoutName = workoutName
        self.setID = setID
        self.weight = weight
        self.reps = reps
        self.distance = distance
        self.seconds = seconds
    }
}

nonisolated struct MetricRecordEvent: Identifiable, Hashable, Sendable {
    let observation: MetricObservation
    let previousValue: Double?
    let improvement: Double?

    var id: String { observation.id }
    var date: Date { observation.date }
    var value: Double { observation.value }
    var source: MetricSource { observation.source }
}

nonisolated struct MetricRecentComparison: Hashable, Sendable {
    let currentAverage: Double
    let previousAverage: Double
    let improvement: Double
}

nonisolated struct ExerciseMetricAnalysis: Hashable, Sendable {
    let exerciseName: String
    let metric: ExerciseAnalysisMetric
    let direction: MetricDirection
    let observations: [MetricObservation]
    let recordEvents: [MetricRecordEvent]
    let matchedRecords: [MetricObservation]
    let topAttempts: [MetricObservation]
    let headlineValue: Double?
    let bestValue: Double?
    let totalValue: Double
    let averageValue: Double?
    let recentComparison: MetricRecentComparison?

    static func empty(exerciseName: String, metric: ExerciseAnalysisMetric) -> ExerciseMetricAnalysis {
        ExerciseMetricAnalysis(
            exerciseName: exerciseName,
            metric: metric,
            direction: .neutral,
            observations: [],
            recordEvents: [],
            matchedRecords: [],
            topAttempts: [],
            headlineValue: nil,
            bestValue: nil,
            totalValue: 0,
            averageValue: nil,
            recentComparison: nil
        )
    }

    /// Produces the chart/supporting evidence for a selected period while leaving
    /// this analysis's all-time headline and record baseline untouched.
    func slice(in range: DateInterval?, attemptLimit: Int = 10) -> ExerciseMetricAnalysisSlice {
        let visible = observations.filter { observation in
            range?.contains(observation.date) ?? true
        }
        let ranked = visible.sorted { lhs, rhs in
            if abs(lhs.value - rhs.value) <= 0.000_001 {
                return lhs.date > rhs.date
            }
            switch direction {
            case .lowerIsBetter:
                return lhs.value < rhs.value
            case .higherIsBetter, .neutral:
                return lhs.value > rhs.value
            }
        }
        let total = visible.reduce(0) { $0 + $1.value }
        return ExerciseMetricAnalysisSlice(
            observations: visible,
            recordEvents: recordEvents.filter { event in
                range?.contains(event.date) ?? true
            },
            matchedRecords: matchedRecords.filter { observation in
                range?.contains(observation.date) ?? true
            },
            topAttempts: Array(ranked.prefix(max(attemptLimit, 0))),
            bestValue: ranked.first?.value,
            totalValue: total,
            averageValue: visible.isEmpty ? nil : total / Double(visible.count)
        )
    }
}

nonisolated struct ExerciseMetricAnalysisSlice: Hashable, Sendable {
    let observations: [MetricObservation]
    let recordEvents: [MetricRecordEvent]
    let matchedRecords: [MetricObservation]
    let topAttempts: [MetricObservation]
    let bestValue: Double?
    let totalValue: Double
    let averageValue: Double?
}

nonisolated enum ExerciseDirectoryMetricPolicy {
    static func supportsSessionVolume(
        exerciseName: String,
        isCardio: Bool,
        totalVolume: Double
    ) -> Bool {
        totalVolume.isFinite &&
            totalVolume > 0 &&
            !isCardio &&
            !ExerciseLoad.isAssistedExercise(exerciseName)
    }
}

nonisolated enum ExerciseMetricDeltaFormatting {
    static func signPrefix(
        for metric: ExerciseAnalysisMetric,
        value: Double
    ) -> String {
        switch metric {
        case .maxLoad, .estimatedOneRepMax:
            // ExerciseLoad formats these itself because assisted exercises invert
            // the performance meaning of a positive numeric delta.
            return ""
        case .sessions,
             .setCount,
             .averageReps,
             .maxReps,
             .sessionVolume,
             .setVolume,
             .distance,
             .duration,
             .count:
            return value > 0 ? "+" : ""
        }
    }
}
