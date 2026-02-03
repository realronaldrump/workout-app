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
    let rpe: String?
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
