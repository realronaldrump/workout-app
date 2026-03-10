import Foundation

enum WorkoutSimilarityMatchKind: String, Hashable {
    case exactOrdered
    case exactExercisesReordered
    case partial

    nonisolated var title: String {
        switch self {
        case .exactOrdered:
            return "Exact Same Order"
        case .exactExercisesReordered:
            return "Same Exercises, Different Order"
        case .partial:
            return "Closest Partial Match"
        }
    }

    nonisolated var iconName: String {
        switch self {
        case .exactOrdered:
            return "checklist"
        case .exactExercisesReordered:
            return "arrow.triangle.swap"
        case .partial:
            return "square.stack.3d.up"
        }
    }
}

struct WorkoutSimilarityMatch: Identifiable, Hashable {
    let selectedWorkoutId: UUID
    let priorWorkoutId: UUID
    let priorWorkoutName: String
    let priorWorkoutDate: Date
    let priorExerciseCount: Int
    let kind: WorkoutSimilarityMatchKind
    let score: Double
    let sharedExerciseCount: Int
    let samePositionCount: Int

    var id: UUID { priorWorkoutId }
}

struct WorkoutSimilarityReview: Identifiable, Hashable {
    let id: UUID
    let workoutId: UUID
    let bestMatch: WorkoutSimilarityMatch?
    let exactOrderMatches: [WorkoutSimilarityMatch]
    let reorderedExerciseMatches: [WorkoutSimilarityMatch]

    nonisolated var hasAnyMatch: Bool {
        bestMatch != nil
    }
}

enum WorkoutSimilarityComparisonRowKind: Hashable {
    case samePosition
    case moved
    case onlyInSelected
    case onlyInPrior

    nonisolated var title: String {
        switch self {
        case .samePosition:
            return "Same position"
        case .moved:
            return "Moved"
        case .onlyInSelected:
            return "Only in selected"
        case .onlyInPrior:
            return "Only in prior"
        }
    }
}

struct WorkoutSimilarityComparisonRow: Identifiable, Hashable {
    let id: String
    let selectedExerciseName: String?
    let priorExerciseName: String?
    let selectedPosition: Int?
    let priorPosition: Int?
    let kind: WorkoutSimilarityComparisonRowKind
}

struct WorkoutSimilarityComparison: Hashable {
    let selectedWorkoutId: UUID
    let priorWorkoutId: UUID
    let kind: WorkoutSimilarityMatchKind
    let score: Double
    let sharedExerciseCount: Int
    let samePositionCount: Int
    let rows: [WorkoutSimilarityComparisonRow]
}

struct WorkoutSimilarityLibrary: Hashable {
    let reviewsByWorkoutId: [UUID: WorkoutSimilarityReview]
    let comparisonsByKey: [String: WorkoutSimilarityComparison]

    static let empty = WorkoutSimilarityLibrary(
        reviewsByWorkoutId: [:],
        comparisonsByKey: [:]
    )
}
