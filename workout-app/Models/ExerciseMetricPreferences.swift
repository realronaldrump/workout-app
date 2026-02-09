import Foundation

/// Per-exercise cardio metric preferences.
///
/// Cardio vs strength classification is driven by the exercise's `.cardio` muscle tag
/// (see `ExerciseMetadataManager`). These preferences only control which cardio fields
/// to emphasize and how to label count-based cardio (e.g. "floors" for a stair stepper).
struct ExerciseCardioMetricPreferences: Codable, Hashable, Sendable {
    enum PrimaryMetricSelection: String, Codable, CaseIterable, Sendable {
        case auto
        case distance
        case duration
        case count

        var displayName: String {
            switch self {
            case .auto: return "Auto"
            case .distance: return "Distance"
            case .duration: return "Duration"
            case .count: return "Count"
            }
        }
    }

    /// The preferred primary metric for cardio exercises. `.auto` will infer based on available data.
    var primaryMetric: PrimaryMetricSelection

    /// Label used for count-based cardio (stored in `reps` for compatibility).
    /// Example: "floors", "steps", "cals".
    var countLabel: String

    /// For future migrations.
    var schemaVersion: Int

    static let `default` = ExerciseCardioMetricPreferences(
        primaryMetric: .auto,
        countLabel: "reps",
        schemaVersion: 1
    )
}

/// Concrete cardio metric kinds after resolving `.auto`.
enum CardioMetricKind: String, CaseIterable, Sendable {
    case distance
    case duration
    case count

    var iconName: String {
        switch self {
        case .distance: return "location.fill"
        case .duration: return "clock.fill"
        case .count: return "number"
        }
    }
}

struct ResolvedCardioMetricConfiguration: Hashable, Sendable {
    let primary: CardioMetricKind
    let secondary: CardioMetricKind
    let countLabel: String
}
