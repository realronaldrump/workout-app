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
    func generateInsights() {
        var newInsights: [Insight] = []
        
        // Personal Records
        newInsights.append(contentsOf: detectPersonalRecords())
        
        // Plateau Detection
        newInsights.append(contentsOf: detectPlateaus())
        
        // Muscle Balance Analysis
        if let balanceInsight = analyzeMuscleBalance() {
            newInsights.append(balanceInsight)
        }
        
        // Training Frequency Insights
        newInsights.append(contentsOf: analyzeTrainingFrequency())
        
        // Volume Trends
        newInsights.append(contentsOf: analyzeVolumeTrends())
        
        // Sort by priority and recency
        insights = newInsights.sorted { $0.priority > $1.priority }
    }
    
    // MARK: - Personal Records Detection
    
    private func detectPersonalRecords() -> [Insight] {
        var prInsights: [Insight] = []
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        
        let allExercises = dataManager.workouts.flatMap { $0.exercises }
        let exerciseGroups = Dictionary(grouping: allExercises) { $0.name }
        
        for (exerciseName, _) in exerciseGroups {
            let history = dataManager.getExerciseHistory(for: exerciseName)
            guard history.count >= 2 else { continue }
            
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
                        title: "New PR! 🎉",
                        message: "\(exerciseName): \(Int(maxWeightSet.weight)) lbs (+\(Int(improvement)) lbs)",
                        exerciseName: exerciseName,
                        date: recentSession.date,
                        priority: 10,
                        actionLabel: "View Progress",
                        metric: maxWeightSet.weight
                    ))
                }
            }
            
            // Check for estimated 1RM PRs
            let best1RMs = history.map { session -> (date: Date, orm: Double) in
                let bestSet = session.sets.max { 
                    calculateOneRepMax(weight: $0.weight, reps: $0.reps) < 
                    calculateOneRepMax(weight: $1.weight, reps: $1.reps) 
                }
                let orm = bestSet.map { calculateOneRepMax(weight: $0.weight, reps: $0.reps) } ?? 0
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
                    title: "Estimated 1RM Up! 💪",
                    message: "\(exerciseName): \(Int(latestORM.orm)) lbs (+\(Int(improvement)) lbs estimated)",
                    exerciseName: exerciseName,
                    date: latestORM.date,
                    priority: 8,
                    actionLabel: "View Trend",
                    metric: latestORM.orm
                ))
            }
        }
        
        return prInsights
    }
    
    // MARK: - Plateau Detection
    
    private func detectPlateaus() -> [Insight] {
        var plateauInsights: [Insight] = []
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: Date())!
        
        let allExercises = dataManager.workouts.flatMap { $0.exercises }
        let exerciseGroups = Dictionary(grouping: allExercises) { $0.name }
        
        for (exerciseName, _) in exerciseGroups {
            let history = dataManager.getExerciseHistory(for: exerciseName)
            
            // Need at least 4 sessions to detect a plateau
            guard history.count >= 4 else { continue }
            
            // Check recent sessions (last 4)
            let recentSessions = Array(history.suffix(4))
            
            // Check if all sessions are within recent timeframe
            guard let oldestRecent = recentSessions.first?.date,
                  oldestRecent >= twoWeeksAgo else { continue }
            
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
                    title: "Plateau Detected",
                    message: "\(exerciseName) hasn't progressed in \(recentSessions.count) sessions. Consider varying rep ranges or adding volume.",
                    exerciseName: exerciseName,
                    date: Date(),
                    priority: 6,
                    actionLabel: "View History",
                    metric: firstMax
                ))
            }
        }
        
        return plateauInsights
    }
    
    // MARK: - Muscle Balance Analysis
    
    private func analyzeMuscleBalance() -> Insight? {
        let muscleGroups = categorizeMuscleGroups()
        
        guard !muscleGroups.isEmpty else { return nil }
        
        // Count sets per muscle group in past 4 weeks
        let calendar = Calendar.current
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date())!
        
        let recentWorkouts = dataManager.workouts.filter { $0.date >= fourWeeksAgo }
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
                    title: "Push/Pull Imbalance ⚖️",
                    message: "You're doing \(Int(ratio * 100 - 100))% more pushing than pulling. Consider adding more rows and pulldowns.",
                    exerciseName: nil,
                    date: Date(),
                    priority: 5,
                    actionLabel: "See Breakdown",
                    metric: ratio
                )
            } else if ratio < 0.67 {
                return Insight(
                    id: UUID(),
                    type: .muscleBalance,
                    title: "Push/Pull Imbalance ⚖️",
                    message: "You're doing more pulling than pushing. Consider adding more chest and shoulder work.",
                    exerciseName: nil,
                    date: Date(),
                    priority: 5,
                    actionLabel: "See Breakdown",
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
                    title: "Undertrained: \(group.displayName)",
                    message: "Only \(sets) sets in the past 4 weeks. Consider adding more \(group.displayName.lowercased()) exercises.",
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
    
    private func analyzeTrainingFrequency() -> [Insight] {
        var insights: [Insight] = []
        let calendar = Calendar.current
        
        // Check days since last workout
        if let lastWorkout = dataManager.workouts.first {
            let daysSince = calendar.dateComponents([.day], from: lastWorkout.date, to: Date()).day ?? 0
            
            if daysSince >= 4 && daysSince < 7 {
                insights.append(Insight(
                    id: UUID(),
                    type: .reminder,
                    title: "Time to Train! 🏋️",
                    message: "It's been \(daysSince) days since your last workout. Ready to get back at it?",
                    exerciseName: nil,
                    date: Date(),
                    priority: 7,
                    actionLabel: "Log Workout",
                    metric: Double(daysSince)
                ))
            } else if daysSince >= 7 {
                insights.append(Insight(
                    id: UUID(),
                    type: .warning,
                    title: "Extended Break",
                    message: "It's been \(daysSince) days. Consider a lighter session to ease back in.",
                    exerciseName: nil,
                    date: Date(),
                    priority: 7,
                    actionLabel: nil,
                    metric: Double(daysSince)
                ))
            }
        }
        
        // Weekly volume trend
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: Date())!
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        
        let lastWeekWorkouts = dataManager.workouts.filter { $0.date >= oneWeekAgo }
        let previousWeekWorkouts = dataManager.workouts.filter { $0.date >= twoWeeksAgo && $0.date < oneWeekAgo }
        
        if lastWeekWorkouts.count >= 3 && previousWeekWorkouts.count >= 2 {
            if lastWeekWorkouts.count >= previousWeekWorkouts.count + 2 {
                insights.append(Insight(
                    id: UUID(),
                    type: .recommendation,
                    title: "Great Consistency! 🔥",
                    message: "\(lastWeekWorkouts.count) workouts this week vs \(previousWeekWorkouts.count) last week. Keep it up!",
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
    
    private func analyzeVolumeTrends() -> [Insight] {
        var insights: [Insight] = []
        let calendar = Calendar.current
        
        // Compare this month vs last month total volume
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: Date())!
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: Date())!
        
        let thisMonthVolume = dataManager.workouts
            .filter { $0.date >= oneMonthAgo }
            .reduce(0.0) { $0 + $1.totalVolume }
        
        let lastMonthVolume = dataManager.workouts
            .filter { $0.date >= twoMonthsAgo && $0.date < oneMonthAgo }
            .reduce(0.0) { $0 + $1.totalVolume }
        
        if lastMonthVolume > 0 && thisMonthVolume > 0 {
            let percentChange = ((thisMonthVolume - lastMonthVolume) / lastMonthVolume) * 100
            
            if percentChange >= 10 {
                insights.append(Insight(
                    id: UUID(),
                    type: .strengthGain,
                    title: "Volume Increasing! 📈",
                    message: "Total volume up \(Int(percentChange))% this month. You're building capacity!",
                    exerciseName: nil,
                    date: Date(),
                    priority: 5,
                    actionLabel: "View Stats",
                    metric: thisMonthVolume
                ))
            } else if percentChange <= -15 {
                insights.append(Insight(
                    id: UUID(),
                    type: .warning,
                    title: "Volume Dropping",
                    message: "Total volume down \(Int(abs(percentChange)))% this month. Consider adding more sets if recovery allows.",
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
    
    // MARK: - Helper Methods
    
    private func calculateOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }
    
    private func categorizeMuscleGroups() -> [String: MuscleGroup] {
        return ExerciseMetadataManager.shared.muscleGroupMappings
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
    
    var displayName: String {
        switch self {
        case .push: return "Push (Chest/Shoulders/Triceps)"
        case .pull: return "Pull (Back/Biceps)"
        case .legs: return "Legs"
        case .core: return "Core"
        case .cardio: return "Cardio"
        }
    }
}
