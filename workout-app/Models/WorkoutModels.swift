import Foundation

struct WorkoutSet: Identifiable, Codable, Hashable {
    var id = UUID()
    let date: Date
    let workoutName: String
    let duration: String
    let exerciseName: String
    let setOrder: Int
    let weight: Double
    let reps: Int
    let distance: Double
    let seconds: Double
}

struct Exercise: Identifiable, Hashable {
    let id: UUID
    let name: String
    var sets: [WorkoutSet]

    nonisolated init(id: UUID = UUID(), name: String, sets: [WorkoutSet]) {
        self.id = id
        self.name = name
        self.sets = sets
    }

    var maxWeight: Double {
        sets.map { $0.weight }.max() ?? 0
    }

    nonisolated var totalVolume: Double {
        sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    var averageReps: Double {
        guard !sets.isEmpty else { return 0 }
        return Double(sets.reduce(0) { $0 + $1.reps }) / Double(sets.count)
    }

    var oneRepMax: Double {
        guard let bestSet = sets.max(by: {
            calculateOneRepMax(weight: $0.weight, reps: $0.reps) < calculateOneRepMax(weight: $1.weight, reps: $1.reps)
        }) else { return 0 }
        return calculateOneRepMax(weight: bestSet.weight, reps: bestSet.reps)
    }

    private func calculateOneRepMax(weight: Double, reps: Int) -> Double {
        // Epley formula
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }
}

struct Workout: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let name: String
    let duration: String
    var exercises: [Exercise]

    nonisolated init(
        id: UUID = UUID(),
        date: Date,
        name: String,
        duration: String,
        exercises: [Exercise]
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.duration = duration
        self.exercises = exercises
    }

    nonisolated var totalVolume: Double {
        exercises.reduce(0) { $0 + $1.totalVolume }
    }

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }
}

extension Workout {
    /// Attempts to parse the user-facing duration string into minutes.
    /// Falls back to `defaultMinutes` when the string is empty or unparseable.
    func estimatedDurationMinutes(defaultMinutes: Int = 60) -> Int {
        let trimmed = duration.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return defaultMinutes }

        // Handle HH:mm:ss or H:mm:ss format (e.g., "01:15:00" or "1:15:00")
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").compactMap { Int($0) }
            if parts.count == 3 {
                // HH:mm:ss
                return (parts[0] * 60) + parts[1]
            } else if parts.count == 2 {
                // mm:ss
                return parts[0]
            }
        }

        var hours = 0
        var minutes = 0
        var matched = false

        if let hourMatch = trimmed.range(of: "(\\d+)\\s*h", options: .regularExpression) {
            let hourString = String(trimmed[hourMatch]).replacingOccurrences(of: "h", with: "")
            hours = Int(hourString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            matched = true
        }

        if let minuteMatch = trimmed.range(of: "(\\d+)\\s*m", options: .regularExpression) {
            let minuteString = String(trimmed[minuteMatch]).replacingOccurrences(of: "m", with: "")
            minutes = Int(minuteString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            matched = true
        }

        if matched {
            return (hours * 60) + minutes
        }

        return Int(trimmed) ?? defaultMinutes
    }

    func estimatedWindow(defaultMinutes: Int = 60) -> DateInterval {
        let minutes = max(1, estimatedDurationMinutes(defaultMinutes: defaultMinutes))
        let end = date.addingTimeInterval(TimeInterval(minutes * 60))
        return DateInterval(start: date, end: end)
    }
}

struct WorkoutStats {
    let totalWorkouts: Int
    let totalExercises: Int
    let totalVolume: Double
    let totalSets: Int
    let avgWorkoutDuration: String
    let favoriteExercise: String?
    let strongestExercise: (name: String, weight: Double)?
    let mostImprovedExercise: (name: String, improvement: Double)?
    let currentStreak: Int
    let longestStreak: Int
    let workoutsPerWeek: Double
    let lastWorkoutDate: Date?
}
