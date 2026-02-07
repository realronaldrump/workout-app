import Foundation

struct LoggedWorkout: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var name: String
    var gymProfileId: UUID?
    var exercises: [LoggedExercise]
    var createdAt: Date
    var updatedAt: Date
    var schemaVersion: Int

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        name: String,
        gymProfileId: UUID? = nil,
        exercises: [LoggedExercise],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        schemaVersion: Int = 2
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.name = name
        self.gymProfileId = gymProfileId
        self.exercises = exercises
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }
}

struct LoggedExercise: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var sets: [LoggedSet]

    init(id: UUID = UUID(), name: String, sets: [LoggedSet]) {
        self.id = id
        self.name = name
        self.sets = sets
    }
}

struct LoggedSet: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var order: Int
    var weight: Double
    var reps: Int
    var rpe: Double?

    init(id: UUID = UUID(), order: Int, weight: Double, reps: Int, rpe: Double? = nil) {
        self.id = id
        self.order = order
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
    }
}
