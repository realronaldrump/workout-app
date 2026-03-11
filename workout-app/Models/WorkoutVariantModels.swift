import Foundation

enum WorkoutVariantDimensionKind: String, Hashable {
    case firstExercise
    case durationBand
    case exerciseCountBand
    case timeOfDay
    case gym

    nonisolated var title: String {
        switch self {
        case .firstExercise:
            return "Exercise Order"
        case .durationBand:
            return "Session Length"
        case .exerciseCountBand:
            return "Session Size"
        case .timeOfDay:
            return "Time of Day"
        case .gym:
            return "Location"
        }
    }

    nonisolated var iconName: String {
        switch self {
        case .firstExercise:
            return "arrow.up.forward.app"
        case .durationBand:
            return "clock"
        case .exerciseCountBand:
            return "square.grid.2x2"
        case .timeOfDay:
            return "sun.max"
        case .gym:
            return "mappin.and.ellipse"
        }
    }
}

enum WorkoutVariantMetricKind: String, Hashable {
    case exerciseEstimatedMax
    case totalVolume
    case totalSets
    case durationMinutes

    nonisolated var iconName: String {
        switch self {
        case .exerciseEstimatedMax:
            return "figure.strengthtraining.traditional"
        case .totalVolume:
            return "scalemass"
        case .totalSets:
            return "number.square"
        case .durationMinutes:
            return "clock"
        }
    }
}

enum WorkoutVariantTrend: String, Hashable {
    case higher
    case lower

    nonisolated var directionalWord: String {
        switch self {
        case .higher:
            return "higher"
        case .lower:
            return "lower"
        }
    }
}

struct WorkoutVariantMetricComparison: Identifiable, Hashable {
    let id: String
    let kind: WorkoutVariantMetricKind
    let label: String
    let exerciseName: String?
    let variantAverage: Double
    let baselineAverage: Double
    let variantSampleSize: Int
    let baselineSampleSize: Int
    let deltaAbsolute: Double
    let deltaPercent: Double
    let trend: WorkoutVariantTrend
    let confidence: Double

    nonisolated init(
        id: String,
        kind: WorkoutVariantMetricKind,
        label: String,
        exerciseName: String? = nil,
        variantAverage: Double,
        baselineAverage: Double,
        variantSampleSize: Int,
        baselineSampleSize: Int,
        deltaAbsolute: Double,
        deltaPercent: Double,
        trend: WorkoutVariantTrend,
        confidence: Double
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.exerciseName = exerciseName
        self.variantAverage = variantAverage
        self.baselineAverage = baselineAverage
        self.variantSampleSize = variantSampleSize
        self.baselineSampleSize = baselineSampleSize
        self.deltaAbsolute = deltaAbsolute
        self.deltaPercent = deltaPercent
        self.trend = trend
        self.confidence = confidence
    }

    nonisolated var percentDeltaLabel: String {
        let rounded = Int(deltaPercent.rounded())
        return rounded == 0 ? "0%" : String(format: "%+d%%", rounded)
    }

    nonisolated var summarySnippet: String {
        "\(label) \(percentDeltaLabel)"
    }
}

struct WorkoutVariantDifferenceInsight: Identifiable, Hashable {
    let id: String
    let kind: WorkoutVariantDimensionKind
    let variantLabel: String
    let baselineLabel: String
    let variantSampleSize: Int
    let baselineSampleSize: Int
    let summary: String
    let evidence: [WorkoutVariantMetricComparison]
    let confidence: Double
}

struct WorkoutVariantWorkoutReview: Identifiable, Hashable {
    let id: UUID
    let workout: Workout
    let groupLabel: String
    let variantLabel: String
    let summary: String
    let peerSampleSize: Int
    let exactVariantSampleSize: Int
    let differences: [WorkoutVariantDifferenceInsight]
}

struct WorkoutVariantPattern: Identifiable, Hashable {
    let id: String
    let groupLabel: String
    let representativeWorkout: Workout
    let variantLabel: String
    let baselineLabel: String
    let summary: String
    let sampleSize: Int
    let baselineSampleSize: Int
    let evidence: [WorkoutVariantMetricComparison]
    let confidence: Double
}

struct WorkoutVariantLibrary: Hashable {
    let standoutPatterns: [WorkoutVariantPattern]
    let recentReviews: [WorkoutVariantWorkoutReview]
    let reviewsByWorkoutId: [UUID: WorkoutVariantWorkoutReview]

    static let empty = WorkoutVariantLibrary(
        standoutPatterns: [],
        recentReviews: [],
        reviewsByWorkoutId: [:]
    )
}
