import Foundation

struct ActiveWorkoutSession: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var startedAt: Date
    var name: String
    var gymProfileId: UUID?
    var exercises: [ActiveExercise]
    var dismissedMuscleGroupSuggestions: [String]
    var lastModifiedAt: Date
    var schemaVersion: Int

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        name: String,
        gymProfileId: UUID? = nil,
        exercises: [ActiveExercise] = [],
        dismissedMuscleGroupSuggestions: [String] = [],
        lastModifiedAt: Date = Date(),
        schemaVersion: Int = 4
    ) {
        self.id = id
        self.startedAt = startedAt
        self.name = name
        self.gymProfileId = gymProfileId
        self.exercises = exercises
        self.dismissedMuscleGroupSuggestions = dismissedMuscleGroupSuggestions
        self.lastModifiedAt = lastModifiedAt
        self.schemaVersion = schemaVersion
    }
}

struct ActiveExercise: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var sets: [ActiveSet]

    init(id: UUID = UUID(), name: String, sets: [ActiveSet] = []) {
        self.id = id
        self.name = name
        self.sets = sets
    }
}

struct ActiveSet: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var order: Int
    var weight: Double?
    var reps: Int?
    var distance: Double?
    var seconds: Double?
    var isCompleted: Bool
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        order: Int,
        weight: Double? = nil,
        reps: Int? = nil,
        distance: Double? = nil,
        seconds: Double? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.order = order
        self.weight = weight
        self.reps = reps
        self.distance = distance
        self.seconds = seconds
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}

// Tolerant decoding so a draft written by an older app version (missing newer fields)
// still restores instead of silently losing the in-progress workout.
extension ActiveWorkoutSession {
    private enum CodingKeys: String, CodingKey {
        case id, startedAt, name, gymProfileId, exercises
        case dismissedMuscleGroupSuggestions, lastModifiedAt, schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let startedAt = try container.decode(Date.self, forKey: .startedAt)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            startedAt: startedAt,
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "Workout",
            gymProfileId: try container.decodeIfPresent(UUID.self, forKey: .gymProfileId),
            exercises: try container.decodeIfPresent([ActiveExercise].self, forKey: .exercises) ?? [],
            dismissedMuscleGroupSuggestions: try container.decodeIfPresent(
                [String].self,
                forKey: .dismissedMuscleGroupSuggestions
            ) ?? [],
            lastModifiedAt: try container.decodeIfPresent(Date.self, forKey: .lastModifiedAt) ?? startedAt,
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 4
        )
    }
}

extension ActiveSet {
    private enum CodingKeys: String, CodingKey {
        case id, order, weight, reps, distance, seconds, isCompleted, completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            order: try container.decodeIfPresent(Int.self, forKey: .order) ?? 1,
            weight: try container.decodeIfPresent(Double.self, forKey: .weight),
            reps: try container.decodeIfPresent(Int.self, forKey: .reps),
            distance: try container.decodeIfPresent(Double.self, forKey: .distance),
            seconds: try container.decodeIfPresent(Double.self, forKey: .seconds),
            isCompleted: try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false,
            completedAt: try container.decodeIfPresent(Date.self, forKey: .completedAt)
        )
    }
}
