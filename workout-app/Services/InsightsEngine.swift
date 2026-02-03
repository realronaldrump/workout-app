import SwiftUI
import Combine

/// Intelligent insights engine that analyzes workout data to provide
/// personalized recommendations, detect progress, and surface actionable insights.
@MainActor
class InsightsEngine: ObservableObject {
    @Published var insights: [Insight] = []
    
    private let dataManager: WorkoutDataManager
    
    init(dataManager: WorkoutDataManager) {
        self.dataManager = dataManager
    }
    
    /// Analyzes all workout data and generates prioritized insights
    func generateInsights() async {
        // Capture snapshot of data to pass to background tasks
        let workoutsSnapshot = dataManager.workouts
        let muscleGroupMappings = ExerciseMetadataManager.shared.muscleGroupMappings
        
        // Run analysis in parallel
        let newInsights = await Task.detached(priority: .userInitiated) {
            return await withTaskGroup(of: [Insight]?.self) { group in
                // Personal Records
                group.addTask {
                    return self.detectPersonalRecords(in: workoutsSnapshot)
                }
                
                // Plateau Detection
                group.addTask {
                    return self.detectPlateaus(in: workoutsSnapshot)
                }
                
                // Muscle Balance
                group.addTask {
                    if let balance = self.analyzeMuscleBalance(in: workoutsSnapshot, mappings: muscleGroupMappings) {
                        return [balance]
                    }
                    return []
                }
                
                // Training Frequency
                group.addTask {
                    return self.analyzeTrainingFrequency(in: workoutsSnapshot)
                }
                
                // Volume Trends
                group.addTask {
                    return self.analyzeVolumeTrends(in: workoutsSnapshot)
                }

                // Effort Density
                group.addTask {
                    return self.analyzeEffortDensity(in: workoutsSnapshot)
                }
                
                var results: [Insight] = []
                for await partialResults in group {
                    if let partialResults = partialResults {
                        results.append(contentsOf: partialResults)
                    }
                }
                return results
            }
        }.value
        
        // Update on MainActor
        self.insights = newInsights.sorted { $0.priority > $1.priority }
    }
    
    // MARK: - Personal Records Detection
    
    private nonisolated func detectPersonalRecords(in workouts: [Workout]) -> [Insight] {
        var prInsights: [Insight] = []
        let calendar = Calendar.current
        guard let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else { return [] }
        
        let allExercises = workouts.flatMap { $0.exercises }
        let exerciseGroups = Dictionary(grouping: allExercises) { $0.name }
        
        for (exerciseName, _) in exerciseGroups {
            // Re-implement simplified getExerciseHistory logic here to avoid actor isolation issues or dependency
            // OR ensure getExerciseHistory is nonisolated/safe. 
            // Better to implement local logic using the snapshot.
            
            let history = workouts.compactMap { workout -> (date: Date, sets: [WorkoutSet])? in
                if let exercise = workout.exercises.first(where: { $0.name == exerciseName }) {
                    return (date: workout.date, sets: exercise.sets)
                }
                return nil
            }.sorted { $0.date < $1.date }
            
            guard history.count >= 2 else { continue }
            
            // ... (rest of logic using 'history' local var) ...
            
            // Find all-time max weight
            let allSets = history.flatMap { $0.sets }
            guard let maxWeightSet = allSets.max(by: { $0.weight < $1.weight }) else { continue }
            
            // Check if the PR was set recently
            if let recentSession = history.last,
               recentSession.date >= oneWeekAgo,
               recentSession.sets.contains(where: { $0.weight == maxWeightSet.weight }) {
                
                // Calculate improvement from previous best
                let previousMax = history.dropLast().flatMap { $0.sets }.map { $0.weight }.max() ?? 0
                let improvement = maxWeightSet.weight - previousMax
                
                if improvement > 0 {
                    prInsights.append(Insight(
                        id: UUID(),
                        type: .personalRecord,
                        title: "PR",
                        message: "\(exerciseName) \(Int(maxWeightSet.weight)) lbs | delta +\(Int(improvement))",
                        exerciseName: exerciseName,
                        date: recentSession.date,
                        priority: 10,
                        actionLabel: "Trend",
                        metric: maxWeightSet.weight
                    ))
                }
            }
            
            // Check for estimated 1RM PRs
            let best1RMs = history.map { session -> (date: Date, orm: Double) in
                let bestSet = session.sets.max { 
                    self.calculateOneRepMax(weight: $0.weight, reps: $0.reps) < 
                    self.calculateOneRepMax(weight: $1.weight, reps: $1.reps) 
                }
                let orm = bestSet.map { self.calculateOneRepMax(weight: $0.weight, reps: $0.reps) } ?? 0
                return (date: session.date, orm: orm)
            }
            
            if let latestORM = best1RMs.last,
               latestORM.date >= oneWeekAgo,
               let previousBest = best1RMs.dropLast().max(by: { $0.orm < $1.orm }),
               latestORM.orm > previousBest.orm {
                
                let improvement = latestORM.orm - previousBest.orm
                prInsights.append(Insight(
                    id: UUID(),
                    type: .strengthGain,
                    title: "1RM",
                    message: "\(exerciseName) \(Int(latestORM.orm)) lbs | delta +\(Int(improvement))",
                    exerciseName: exerciseName,
                    date: latestORM.date,
                    priority: 8,
                    actionLabel: "Trend",
                    metric: latestORM.orm
                ))
            }
        }
        
        return prInsights
    }
    
    // MARK: - Plateau Detection
    
    private nonisolated func detectPlateaus(in workouts: [Workout]) -> [Insight] {
        var plateauInsights: [Insight] = []
        let calendar = Calendar.current
        guard let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date()) else { return [] }
        
        let allExercises = workouts.flatMap { $0.exercises }
        let exerciseGroups = Dictionary(grouping: allExercises) { $0.name }
        
        for (exerciseName, _) in exerciseGroups {
            let history = workouts.compactMap { workout -> (date: Date, sets: [WorkoutSet])? in
                if let exercise = workout.exercises.first(where: { $0.name == exerciseName }) {
                    return (date: workout.date, sets: exercise.sets)
                }
                return nil
            }.sorted { $0.date < $1.date }
            
            // Need at least 4 sessions to detect a plateau
            guard history.count >= 4 else { continue }
            
            // Check recent sessions (last 4)
            let recentSessions = Array(history.suffix(4))
            
            // Check if all sessions are within recent timeframe
            guard let oldestRecent = recentSessions.first?.date,
                  oldestRecent >= fourWeeksAgo else { continue }
            
            // Calculate max weight for each session
            let maxWeights = recentSessions.map { session in
                session.sets.map { $0.weight }.max() ?? 0
            }
            
            // Check if max weight hasn't increased
            guard let firstMax = maxWeights.first else { continue }
            let allSameOrLower = maxWeights.allSatisfy { $0 <= firstMax }
            
            if allSameOrLower {
                plateauInsights.append(Insight(
                    id: UUID(),
                    type: .plateau,
                    title: "Plateau",
                    message: "\(exerciseName) max \(Int(firstMax)) lbs | delta 0 | n=\(recentSessions.count)",
                    exerciseName: exerciseName,
                    date: Date(),
                    priority: 6,
                    actionLabel: "History",
                    metric: firstMax
                ))
            }

            // Estimated 1RM plateau check over 4 weeks
            let recentHistory = history.filter { $0.date >= fourWeeksAgo }
            let recentOrms = recentHistory.map { session -> Double in
                let bestSet = session.sets.max {
                    self.calculateOneRepMax(weight: $0.weight, reps: $0.reps) <
                    self.calculateOneRepMax(weight: $1.weight, reps: $1.reps)
                }
                return bestSet.map { self.calculateOneRepMax(weight: $0.weight, reps: $0.reps) } ?? 0
            }
            if recentOrms.count >= 4, let first = recentOrms.first, let last = recentOrms.last, first > 0 {
                let change = (last - first) / first
                if abs(change) < 0.02 {
                    plateauInsights.append(Insight(
                        id: UUID(),
                        type: .plateau,
                        title: "1RM delta",
                        message: "\(exerciseName) delta \(String(format: "%+.1f", change * 100))% | n=\(recentOrms.count)",
                        exerciseName: exerciseName,
                        date: Date(),
                        priority: 5,
                        actionLabel: "Trend",
                        metric: last
                    ))
                }
            }
        }
        
        return plateauInsights
    }
    
    // MARK: - Muscle Balance Analysis
    
    private nonisolated func analyzeMuscleBalance(in workouts: [Workout], mappings: [String: MuscleGroup]) -> Insight? {
        let muscleGroups = mappings
        
        guard !muscleGroups.isEmpty else { return nil }
        
        // Count sets per muscle group in past 4 weeks
        let calendar = Calendar.current
        guard let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date()) else { return nil }
        
        let recentWorkouts = workouts.filter { $0.date >= fourWeeksAgo }
        var muscleGroupSets: [MuscleGroup: Int] = [:]
        
        for workout in recentWorkouts {
            for exercise in workout.exercises {
                if let group = muscleGroups[exercise.name] {
                    muscleGroupSets[group, default: 0] += exercise.sets.count
                }
            }
        }
        
        guard !muscleGroupSets.isEmpty else { return nil }
        
        // Check push/pull balance
        let pushSets = muscleGroupSets[.push, default: 0]
        let pullSets = muscleGroupSets[.pull, default: 0]
        
        if pushSets > 0 && pullSets > 0 {
            let ratio = Double(pushSets) / Double(pullSets)
            
            if ratio > 1.5 {
                return Insight(
                    id: UUID(),
                    type: .muscleBalance,
                    title: "Push/Pull",
                    message: "push \(pushSets) | pull \(pullSets) | r \(String(format: "%.2f", ratio))",
                    exerciseName: nil,
                    date: Date(),
                    priority: 5,
                    actionLabel: "Breakdown",
                    metric: ratio
                )
            } else if ratio < 0.67 {
                return Insight(
                    id: UUID(),
                    type: .muscleBalance,
                    title: "Push/Pull",
                    message: "push \(pushSets) | pull \(pullSets) | r \(String(format: "%.2f", ratio))",
                    exerciseName: nil,
                    date: Date(),
                    priority: 5,
                    actionLabel: "Breakdown",
                    metric: ratio
                )
            }
        }
        
        // Check for neglected muscle groups
        let averageSets = muscleGroupSets.values.reduce(0, +) / max(muscleGroupSets.count, 1)
        for (group, sets) in muscleGroupSets {
            if sets < averageSets / 2 && sets > 0 {
                return Insight(
                    id: UUID(),
                    type: .recommendation,
                    title: "Low Volume",
                    message: "\(group.displayName) sets \(sets) | avg \(Int(averageSets))",
                    exerciseName: nil,
                    date: Date(),
                    priority: 4,
                    actionLabel: nil,
                    metric: Double(sets)
                )
            }
        }
        
        return nil
    }
    
    // MARK: - Training Frequency Analysis
    
    private nonisolated func analyzeTrainingFrequency(in workouts: [Workout]) -> [Insight] {
        var insights: [Insight] = []
        let calendar = Calendar.current
        
        // Check days since last workout
        if let lastWorkout = workouts.first {
            let daysSince = calendar.dateComponents([.day], from: lastWorkout.date, to: Date()).day ?? 0
            
            if daysSince >= 4 && daysSince < 7 {
                insights.append(Insight(
                    id: UUID(),
                    type: .reminder,
                    title: "Gap",
                    message: "days \(daysSince)",
                    exerciseName: nil,
                    date: Date(),
                    priority: 7,
                    actionLabel: "Log",
                    metric: Double(daysSince)
                ))
            } else if daysSince >= 7 {
                insights.append(Insight(
                    id: UUID(),
                    type: .warning,
                    title: "Gap",
                    message: "days \(daysSince)",
                    exerciseName: nil,
                    date: Date(),
                    priority: 7,
                    actionLabel: nil,
                    metric: Double(daysSince)
                ))
            }
        }
        
        // Weekly volume trend
        guard let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: Date()),
              let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else { return insights }
        
        let lastWeekWorkouts = workouts.filter { $0.date >= oneWeekAgo }
        let previousWeekWorkouts = workouts.filter { $0.date >= twoWeeksAgo && $0.date < oneWeekAgo }
        
        if lastWeekWorkouts.count >= 3 && previousWeekWorkouts.count >= 2 {
            if lastWeekWorkouts.count >= previousWeekWorkouts.count + 2 {
                insights.append(Insight(
                    id: UUID(),
                    type: .recommendation,
                    title: "Sessions",
                    message: "this \(lastWeekWorkouts.count) | prev \(previousWeekWorkouts.count)",
                    exerciseName: nil,
                    date: Date(),
                    priority: 6,
                    actionLabel: nil,
                    metric: Double(lastWeekWorkouts.count)
                ))
            }
        }
        
        return insights
    }
    
    // MARK: - Volume Trends
    
    private nonisolated func analyzeVolumeTrends(in workouts: [Workout]) -> [Insight] {
        var insights: [Insight] = []
        let calendar = Calendar.current
        
        // Compare this month vs last month total volume
        guard let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: Date()),
              let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: Date()) else { return [] }
        
        let thisMonthVolume = workouts
            .filter { $0.date >= oneMonthAgo }
            .reduce(0.0) { $0 + $1.totalVolume }
        
        let lastMonthVolume = workouts
            .filter { $0.date >= twoMonthsAgo && $0.date < oneMonthAgo }
            .reduce(0.0) { $0 + $1.totalVolume }
        
        if lastMonthVolume > 0 && thisMonthVolume > 0 {
            let percentChange = ((thisMonthVolume - lastMonthVolume) / lastMonthVolume) * 100
            
            if percentChange >= 10 {
                insights.append(Insight(
                    id: UUID(),
                    type: .strengthGain,
                    title: "Volume delta",
                    message: "delta \(String(format: "%+.0f", percentChange))% | total \(Int(thisMonthVolume))",
                    exerciseName: nil,
                    date: Date(),
                    priority: 5,
                    actionLabel: "Stats",
                    metric: thisMonthVolume
                ))
            } else if percentChange <= -15 {
                insights.append(Insight(
                    id: UUID(),
                    type: .warning,
                    title: "Volume delta",
                    message: "delta \(String(format: "%+.0f", percentChange))% | total \(Int(thisMonthVolume))",
                    exerciseName: nil,
                    date: Date(),
                    priority: 4,
                    actionLabel: nil,
                    metric: thisMonthVolume
                ))
            }
        }
        
        return insights
    }

    // MARK: - Effort Density Trends

    private nonisolated func analyzeEffortDensity(in workouts: [Workout]) -> [Insight] {
        var insights: [Insight] = []
        let calendar = Calendar.current

        guard let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: Date()),
              let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else { return [] }

        let lastWeek = workouts.filter { $0.date >= oneWeekAgo }
        let previousWeek = workouts.filter { $0.date >= twoWeeksAgo && $0.date < oneWeekAgo }

        let lastDensity = average(lastWeek.map { WorkoutAnalytics.effortDensity(for: $0) })
        let previousDensity = average(previousWeek.map { WorkoutAnalytics.effortDensity(for: $0) })

        guard lastDensity > 0, previousDensity > 0 else { return [] }

        let change = (lastDensity - previousDensity) / previousDensity
        if change >= 0.12 {
            insights.append(Insight(
                id: UUID(),
                type: .strengthGain,
                title: "Density delta",
                message: "delta \(String(format: "%+.0f", change * 100))% | avg \(String(format: "%.1f", lastDensity))",
                exerciseName: nil,
                date: Date(),
                priority: 5,
                actionLabel: "Breakdown",
                metric: lastDensity
            ))
        } else if change <= -0.12 {
            insights.append(Insight(
                id: UUID(),
                type: .warning,
                title: "Density delta",
                message: "delta \(String(format: "%+.0f", change * 100))% | avg \(String(format: "%.1f", lastDensity))",
                exerciseName: nil,
                date: Date(),
                priority: 4,
                actionLabel: "Sessions",
                metric: lastDensity
            ))
        }

        return insights
    }

    private nonisolated func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
    
    // MARK: - Helper Methods
    
    private nonisolated func calculateOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }
}

// MARK: - Supporting Types

struct Insight: Identifiable {
    let id: UUID
    let type: InsightType
    let title: String
    let message: String
    let exerciseName: String?
    let date: Date
    let priority: Int
    let actionLabel: String?
    let metric: Double?
}

enum InsightType {
    case personalRecord
    case strengthGain
    case plateau
    case muscleBalance
    case recommendation
    case reminder
    case warning
    
    var iconName: String {
        switch self {
        case .personalRecord: return "trophy.fill"
        case .strengthGain: return "arrow.up.right.circle.fill"
        case .plateau: return "equal.circle.fill"
        case .muscleBalance: return "scalemass.fill"
        case .recommendation: return "lightbulb.fill"
        case .reminder: return "bell.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .personalRecord: return "yellow"
        case .strengthGain: return "green"
        case .plateau: return "orange"
        case .muscleBalance: return "purple"
        case .recommendation: return "blue"
        case .reminder: return "cyan"
        case .warning: return "red"
        }
    }
}

enum MuscleGroup: String, CaseIterable, Codable {
    case push
    case pull
    case legs
    case core
    case cardio
    
    nonisolated var displayName: String {
        switch self {
        case .push: return "Push (Chest/Shoulders/Triceps)"
        case .pull: return "Pull (Back/Biceps)"
        case .legs: return "Legs"
        case .core: return "Core"
        case .cardio: return "Cardio"
        }
    }
}
