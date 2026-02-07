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
        schemaVersion: Int = 2
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
    var isCompleted: Bool
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        order: Int,
        weight: Double? = nil,
        reps: Int? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.order = order
        self.weight = weight
        self.reps = reps
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}
