import Foundation

struct ExerciseSelection: Identifiable, Hashable {
    let id: String
}

enum MetricDrilldown: String, Identifiable {
    case sessions
    case streak
    case volume
    case readiness

    var id: String { rawValue }
}
