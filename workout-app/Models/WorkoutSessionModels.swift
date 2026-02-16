import Foundation

struct ActiveWorkoutSession: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var startedAt: Date
    var name: String
    var gymProfileId: UUID?
    var plannedProgramId: UUID?
    var plannedDayId: UUID?
    var plannedDayDate: Date?
    var plannedTargetsSnapshot: [PlannedExerciseTarget]?
    var exercises: [ActiveExercise]
    var dismissedMuscleGroupSuggestions: [String]
    var lastModifiedAt: Date
    var schemaVersion: Int

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        name: String,
        gymProfileId: UUID? = nil,
        plannedProgramId: UUID? = nil,
        plannedDayId: UUID? = nil,
        plannedDayDate: Date? = nil,
        plannedTargetsSnapshot: [PlannedExerciseTarget]? = nil,
        exercises: [ActiveExercise] = [],
        dismissedMuscleGroupSuggestions: [String] = [],
        lastModifiedAt: Date = Date(),
        schemaVersion: Int = 4
    ) {
        self.id = id
        self.startedAt = startedAt
        self.name = name
        self.gymProfileId = gymProfileId
        self.plannedProgramId = plannedProgramId
        self.plannedDayId = plannedDayId
        self.plannedDayDate = plannedDayDate
        self.plannedTargetsSnapshot = plannedTargetsSnapshot
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
