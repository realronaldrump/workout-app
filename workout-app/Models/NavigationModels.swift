struct ExerciseSelection: Identifiable, Hashable {
    let id: String
}

enum WorkoutMetricDetailKind: String, Identifiable {
    case sessions
    case streak
    case totalVolume
    case totalSets
    case averageDuration
    case averageFrequency

    var id: String { rawValue }
}

struct WorkoutMetricDetailSelection: Identifiable, Hashable {
    let kind: WorkoutMetricDetailKind

    var id: String {
        kind.rawValue
    }
}
