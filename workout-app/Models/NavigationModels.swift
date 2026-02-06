import Foundation

struct ExerciseSelection: Identifiable, Hashable {
    let id: String
}

enum ExerciseStatKind: String, Identifiable, CaseIterable {
    case totalSets
    case maxWeight
    case maxVolume
    case avgReps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .totalSets:
            return "Total Sets"
        case .maxWeight:
            return "Max Weight"
        case .maxVolume:
            return "Max Volume"
        case .avgReps:
            return "Avg Reps"
        }
    }
}

enum WorkoutMetricDetailKind: String, Identifiable, CaseIterable {
    case sessions
    case streak
    case totalVolume
    case avgDuration
    case effortDensity
    case readiness

    var id: String { rawValue }
}

enum MetricDetailScrollTarget: String, Hashable {
    case topExercisesByVolume
}

struct WorkoutMetricDetailSelection: Identifiable, Hashable {
    let kind: WorkoutMetricDetailKind
    let scrollTarget: MetricDetailScrollTarget?

    var id: String {
        "\(kind.rawValue)-\(scrollTarget?.rawValue ?? "none")"
    }
}
