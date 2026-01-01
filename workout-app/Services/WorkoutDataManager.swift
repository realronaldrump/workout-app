import Foundation
import SwiftUI
import Combine

@MainActor
class WorkoutDataManager: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var isLoading = false
    @Published var error: String?
    
    nonisolated func processWorkoutSets(_ sets: [WorkoutSet]) async {
        // Run heavy grouping logic on a background thread
        let processedWorkouts = await Task.detached(priority: .userInitiated) {
            // Group sets by date (year-month-day-hour) using Calendar components
            // This is significantly faster than DateFormatter
            let calendar = Calendar.current
            
            let groupedByWorkout = Dictionary(grouping: sets) { set -> String in
                let components = calendar.dateComponents([.year, .month, .day, .hour], from: set.date)
                // Unique key: YYYY-MM-DD-HH-WorkoutName
                return "\(components.year!)-\(components.month!)-\(components.day!)-\(components.hour!)-\(set.workoutName)"
            }
            
            var workouts: [Workout] = []
            
            for (_, workoutSets) in groupedByWorkout {
                guard let firstSet = workoutSets.first else { continue }
                
                // Group by exercise within workout
                let groupedByExercise = Dictionary(grouping: workoutSets) { $0.exerciseName }
                
                var exercises: [Exercise] = []
                for (exerciseName, exerciseSets) in groupedByExercise {
                    let sortedSets = exerciseSets.sorted { $0.setOrder < $1.setOrder }
                    exercises.append(Exercise(name: exerciseName, sets: sortedSets))
                }
                
                let workout = Workout(
                    date: workoutSets.map { $0.date }.min() ?? firstSet.date,
                    name: firstSet.workoutName,
                    duration: firstSet.duration,
                    exercises: exercises
                )
                workouts.append(workout)
            }
            
            return workouts.sorted { $0.date > $1.date }
        }.value
        
        // Update UI on MainActor
        await MainActor.run {
            self.workouts = processedWorkouts
            self.isLoading = false
        }
    }
    
    func getExerciseHistory(for exerciseName: String) -> [(date: Date, sets: [WorkoutSet])] {
        var history: [(date: Date, sets: [WorkoutSet])] = []
        
        for workout in workouts {
            if let exercise = workout.exercises.first(where: { $0.name == exerciseName }) {
                history.append((date: workout.date, sets: exercise.sets))
            }
        }
        
        return history.sorted { $0.date < $1.date }
    }
    
    func calculateStats() -> WorkoutStats {
        return calculateStats(for: workouts)
    }
    
    func calculateStats(for filteredWorkouts: [Workout]) -> WorkoutStats {
        let allExercises = filteredWorkouts.flatMap { $0.exercises }
        let exerciseGroups = Dictionary(grouping: allExercises) { $0.name }
        
        // Calculate favorite exercise (most performed)
        let favoriteExercise = exerciseGroups
            .map { (name: $0.key, count: $0.value.count) }
            .max { $0.count < $1.count }?.name
        
        // Calculate strongest exercise
        let strongestExercise = exerciseGroups
            .map { (name: $0.key, maxWeight: $0.value.map { $0.maxWeight }.max() ?? 0) }
            .max { $0.maxWeight < $1.maxWeight }
            .map { (name: $0.name, weight: $0.maxWeight) }
        
        // Calculate improvement
        var mostImprovedExercise: (name: String, improvement: Double)?
        for (exerciseName, exercises) in exerciseGroups {
            let sortedByDate = exercises.sorted { exercise1, exercise2 in
                let date1 = filteredWorkouts.first { $0.exercises.contains { $0.id == exercise1.id } }?.date ?? Date()
                let date2 = filteredWorkouts.first { $0.exercises.contains { $0.id == exercise2.id } }?.date ?? Date()
                return date1 < date2
            }
            
            if let first = sortedByDate.first?.oneRepMax,
               let last = sortedByDate.last?.oneRepMax,
               first > 0 {
                let improvement = ((last - first) / first) * 100
                if mostImprovedExercise == nil || improvement > mostImprovedExercise!.improvement {
                    mostImprovedExercise = (name: exerciseName, improvement: improvement)
                }
            }
        }
        
        // Calculate streaks and consistency (use all workouts for streaks, filtered for other stats)
        let (currentStreak, longestStreak) = calculateStreaks()
        let workoutsPerWeek = calculateWorkoutsPerWeek(for: filteredWorkouts)
        
        // Calculate average duration
        let avgDuration = calculateAverageDuration(for: filteredWorkouts)
        
        return WorkoutStats(
            totalWorkouts: filteredWorkouts.count,
            totalExercises: allExercises.count,
            totalVolume: filteredWorkouts.reduce(0) { $0 + $1.totalVolume },
            totalSets: filteredWorkouts.reduce(0) { $0 + $1.totalSets },
            avgWorkoutDuration: avgDuration,
            favoriteExercise: favoriteExercise,
            strongestExercise: strongestExercise,
            mostImprovedExercise: mostImprovedExercise,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            workoutsPerWeek: workoutsPerWeek,
            lastWorkoutDate: filteredWorkouts.first?.date
        )
    }
    
    private func calculateStreaks() -> (current: Int, longest: Int) {
        guard !workouts.isEmpty else { return (0, 0) }
        
        let sortedWorkouts = workouts.sorted { $0.date < $1.date }
        var currentStreak = 0
        var longestStreak = 0
        var tempStreak = 1
        var lastDate = sortedWorkouts[0].date
        
        for i in 1..<sortedWorkouts.count {
            let daysDiff = Calendar.current.dateComponents([.day], from: lastDate, to: sortedWorkouts[i].date).day ?? 0
            
            if daysDiff <= 2 { // Allow 1 rest day
                tempStreak += 1
            } else {
                longestStreak = max(longestStreak, tempStreak)
                tempStreak = 1
            }
            lastDate = sortedWorkouts[i].date
        }
        
        longestStreak = max(longestStreak, tempStreak)
        
        // Calculate current streak
        if let lastWorkout = sortedWorkouts.last {
            let daysSinceLastWorkout = Calendar.current.dateComponents([.day], from: lastWorkout.date, to: Date()).day ?? 0
            if daysSinceLastWorkout <= 2 {
                currentStreak = tempStreak
            }
        }
        
        return (currentStreak, longestStreak)
    }
    
    private func calculateWorkoutsPerWeek(for filteredWorkouts: [Workout]) -> Double {
        guard !filteredWorkouts.isEmpty else { return 0 }
        
        let sortedWorkouts = filteredWorkouts.sorted { $0.date < $1.date }
        guard let firstDate = sortedWorkouts.first?.date,
              let lastDate = sortedWorkouts.last?.date else { return 0 }
        
        let weeksBetween = Calendar.current.dateComponents([.weekOfYear], from: firstDate, to: lastDate).weekOfYear ?? 1
        let totalWeeks = max(Double(weeksBetween), 1)
        
        return Double(filteredWorkouts.count) / totalWeeks
    }
    
    private func calculateAverageDuration(for filteredWorkouts: [Workout]) -> String {
        let durations = filteredWorkouts.compactMap { workout -> Int? in
            let components = workout.duration.replacingOccurrences(of: "m", with: "").split(separator: "h")
            if components.count == 2,
               let hours = Int(components[0]),
               let minutes = Int(components[1]) {
                return hours * 60 + minutes
            } else if let minutes = Int(workout.duration.replacingOccurrences(of: "m", with: "")) {
                return minutes
            }
            return nil
        }
        
        guard !durations.isEmpty else { return "0m" }
        
        let avgMinutes = durations.reduce(0, +) / durations.count
        if avgMinutes >= 60 {
            return "\(avgMinutes / 60)h \(avgMinutes % 60)m"
        }
        return "\(avgMinutes)m"
    }
    func clearAllData() {
        self.workouts = []
        self.isLoading = false
        self.error = nil
    }
}
