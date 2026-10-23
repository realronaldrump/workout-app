import Foundation

nonisolated struct LoggedWorkout: Codable, Identifiable, Hashable, Sendable {
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

nonisolated struct LoggedExercise: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var sets: [LoggedSet]

    init(id: UUID = UUID(), name: String, sets: [LoggedSet]) {
        self.id = id
        self.name = name
        self.sets = sets
    }
}

nonisolated struct LoggedSet: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var order: Int
    var weight: Double
    var reps: Int
    var distance: Double?
    var seconds: Double?

    init(
        id: UUID = UUID(),
        order: Int,
        weight: Double,
        reps: Int,
        distance: Double? = nil,
        seconds: Double? = nil
    ) {
        self.id = id
        self.order = order
        self.weight = weight
        self.reps = reps
        self.distance = distance
        self.seconds = seconds
    }
}

// Keep history, analytics, and every export on the persisted identity of the session.
// Rebuilding this projection must never create new exercise or set IDs.
extension LoggedWorkout {
    nonisolated var analyticsWorkout: Workout {
        let duration = durationText
        return Workout(
            id: id,
            date: startedAt,
            name: name,
            duration: duration,
            exercises: exercises.map { exercise in
                Exercise(
                    id: exercise.id,
                    name: exercise.name,
                    sets: exercise.sets.sorted { $0.order < $1.order }.map { set in
                        var result = WorkoutSet(
                            date: startedAt,
                            workoutName: name,
                            duration: duration,
                            exerciseName: exercise.name,
                            setOrder: set.order,
                            weight: set.weight,
                            reps: set.reps,
                            distance: set.distance ?? 0,
                            seconds: set.seconds ?? 0
                        )
                        result.id = set.id
                        return result
                    }
                )
            }
        )
    }

    /// Retain seconds in the history projection instead of rounding every workout up
    /// to the next minute. The original start/end timestamps remain in native backups.
    nonisolated var durationText: String {
        let interval = endedAt.timeIntervalSince(startedAt)
        guard interval.isFinite, interval >= 0, interval < Double(Int.max) else { return "0s" }
        let total = Int(interval)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds)s") }
        return parts.joined(separator: " ")
    }
}
