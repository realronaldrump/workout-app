import Combine
import Foundation

/// Intelligent insights engine that analyzes workout data to provide
/// lightweight, objective signals (e.g. PRs) without subjective coaching.
@MainActor
class InsightsEngine: ObservableObject {
    @Published var insights: [Insight] = []

    private let dataManager: WorkoutDataManager
    private let annotationsProvider: () -> [UUID: WorkoutAnnotation]
    private let gymNameProvider: () -> [UUID: String]

    init(
        dataManager: WorkoutDataManager,
        annotationsProvider: @escaping () -> [UUID: WorkoutAnnotation],
        gymNameProvider: @escaping () -> [UUID: String]
    ) {
        self.dataManager = dataManager
        self.annotationsProvider = annotationsProvider
        self.gymNameProvider = gymNameProvider
    }

    /// Analyzes all workout data and generates prioritized insights
    func generateInsights() async {
        // Capture snapshot of data to pass to background tasks
        let workoutsSnapshot = dataManager.workouts
        let annotationsSnapshot = annotationsProvider()
        let gymNameSnapshot = gymNameProvider()

        // Run analysis in parallel
        let newInsights = await Task.detached(priority: .userInitiated) {
            return await withTaskGroup(of: [Insight].self) { group in
                // Personal Records
                group.addTask {
                    return self.detectPersonalRecords(in: workoutsSnapshot)
                }

                // New Equipment Baseline
                group.addTask {
                    return self.detectNewEquipmentBaseline(
                        in: workoutsSnapshot,
                        annotations: annotationsSnapshot,
                        gymNames: gymNameSnapshot
                    )
                }

                // Progressive Overload Detection
                group.addTask {
                    return self.detectProgressiveOverload(in: workoutsSnapshot)
                }

                // Volume Milestones
                group.addTask {
                    return self.detectVolumeMilestones(in: workoutsSnapshot)
                }

                // Consistency Streaks
                group.addTask {
                    return self.detectConsistencyMilestones(in: workoutsSnapshot)
                }

                var results: [Insight] = []
                for await partialResults in group {
                    results.append(contentsOf: partialResults)
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

    // MARK: - New Equipment Baseline

    private nonisolated func detectNewEquipmentBaseline(
        in workouts: [Workout],
        annotations: [UUID: WorkoutAnnotation],
        gymNames: [UUID: String]
    ) -> [Insight] {
        var baselineInsights: [Insight] = []

        let allExercises = workouts.flatMap { $0.exercises }
        let exerciseGroups = Dictionary(grouping: allExercises) { $0.name }

        for (exerciseName, _) in exerciseGroups {
            let sessions = workouts.compactMap { workout -> (date: Date, gymId: UUID?)? in
                if workout.exercises.contains(where: { $0.name == exerciseName }) {
                    let gymId = annotations[workout.id]?.gymProfileId
                    return (date: workout.date, gymId: gymId)
                }
                return nil
            }.sorted { $0.date < $1.date }

            guard sessions.count >= 2 else { continue }

            var seenGymKeys: Set<UUID?> = []
            for session in sessions {
                let gymKey = session.gymId
                if !seenGymKeys.contains(gymKey) {
                    if let gymId = gymKey,
                       !seenGymKeys.isEmpty {
                        let gymLabel = gymNames[gymId] ?? "Deleted gym"
                        baselineInsights.append(Insight(
                            id: UUID(),
                            type: .baseline,
                            title: "New Equipment Baseline",
                            message: "\(exerciseName) | \(gymLabel)",
                            exerciseName: exerciseName,
                            date: session.date,
                            priority: 4,
                            actionLabel: "History",
                            metric: nil
                        ))
                    }
                    seenGymKeys.insert(gymKey)
                }
            }
        }

        return baselineInsights
    }

    // MARK: - Helper Methods

    private nonisolated func calculateOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }

    // MARK: - Progressive Overload Detection

    private nonisolated func detectProgressiveOverload(in workouts: [Workout]) -> [Insight] {
        var insights: [Insight] = []
        let calendar = Calendar.current
        guard let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date()) else { return [] }

        let exerciseGroups = Dictionary(
            grouping: workouts.flatMap { workout in workout.exercises.map { (workout.date, $0) } },
            by: { $0.1.name }
        )

        for (name, dateExercises) in exerciseGroups {
            let sorted = dateExercises.sorted { $0.0 < $1.0 }
            guard sorted.count >= 4 else { continue }

            // Get weekly volume over last 4 weeks
            let recentSessions = sorted.filter { $0.0 >= fourWeeksAgo }
            guard recentSessions.count >= 2 else { continue }

            let recentVolumes = recentSessions.map { $0.1.totalVolume }
            let olderSessions = sorted.filter { $0.0 < fourWeeksAgo }.suffix(4)
            let olderVolumes = olderSessions.map { $0.1.totalVolume }

            guard !olderVolumes.isEmpty else { continue }

            let recentAvg = recentVolumes.reduce(0, +) / Double(recentVolumes.count)
            let olderAvg = olderVolumes.reduce(0, +) / Double(olderVolumes.count)

            guard olderAvg > 0 else { continue }
            let change = ((recentAvg - olderAvg) / olderAvg) * 100

            // Meaningful volume increase (>10%)
            if change > 10 {
                insights.append(Insight(
                    id: UUID(),
                    type: .progressiveOverload,
                    title: "Volume Up",
                    message: "\(name) +\(Int(change))% volume over 4 weeks",
                    exerciseName: name,
                    date: recentSessions.last?.0 ?? Date(),
                    priority: 7,
                    actionLabel: "Trend",
                    metric: change
                ))
            }
        }

        return Array(insights.prefix(5))
    }

    // MARK: - Volume Milestones

    private nonisolated func detectVolumeMilestones(in workouts: [Workout]) -> [Insight] {
        var insights: [Insight] = []

        // Total lifetime volume milestones
        let totalVolume = workouts.reduce(0.0) { $0 + $1.totalVolume }
        let milestones: [(threshold: Double, label: String)] = [
            (10_000_000, "10M lbs"),
            (5_000_000, "5M lbs"),
            (2_500_000, "2.5M lbs"),
            (1_000_000, "1M lbs"),
            (500_000, "500k lbs"),
            (250_000, "250k lbs"),
            (100_000, "100k lbs")
        ]

        if let milestone = milestones.first(where: { totalVolume >= $0.threshold }) {
            insights.append(Insight(
                id: UUID(),
                type: .milestone,
                title: "Milestone",
                message: "Lifetime volume: \(milestone.label) lifted",
                exerciseName: nil,
                date: Date(),
                priority: 6,
                actionLabel: nil,
                metric: totalVolume
            ))
        }

        // Total workout count milestones
        let count = workouts.count
        let countMilestones = [1000, 500, 250, 100, 50, 25]
        if let cm = countMilestones.first(where: { count >= $0 }) {
            insights.append(Insight(
                id: UUID(),
                type: .milestone,
                title: "\(cm) Workouts",
                message: "You've logged \(count) total sessions",
                exerciseName: nil,
                date: Date(),
                priority: 5,
                actionLabel: nil,
                metric: Double(count)
            ))
        }

        return insights
    }

    // MARK: - Consistency Milestones

    private nonisolated func detectConsistencyMilestones(in workouts: [Workout]) -> [Insight] {
        var insights: [Insight] = []
        let calendar = Calendar.current

        // Current weekly consistency
        guard let twelveWeeksAgo = calendar.date(byAdding: .day, value: -84, to: Date()) else { return [] }
        let recentWorkouts = workouts.filter { $0.date >= twelveWeeksAgo }

        // Count unique weeks with workouts
        let weekKeys = Set(recentWorkouts.map { workout -> Int in
            let week = calendar.component(.weekOfYear, from: workout.date)
            let year = calendar.component(.year, from: workout.date)
            return year * 100 + week
        })

        let weeksWithWorkouts = weekKeys.count

        // Perfect consistency = 12/12 weeks
        if weeksWithWorkouts >= 12 {
            insights.append(Insight(
                id: UUID(),
                type: .consistency,
                title: "Perfect Streak",
                message: "Trained every week for 12 straight weeks",
                exerciseName: nil,
                date: Date(),
                priority: 9,
                actionLabel: nil,
                metric: 12
            ))
        } else if weeksWithWorkouts >= 8 {
            insights.append(Insight(
                id: UUID(),
                type: .consistency,
                title: "Consistent",
                message: "\(weeksWithWorkouts)/12 weeks trained in the last 3 months",
                exerciseName: nil,
                date: Date(),
                priority: 6,
                actionLabel: nil,
                metric: Double(weeksWithWorkouts)
            ))
        }

        return insights
    }
}

// MARK: - Supporting Types

struct Insight: Identifiable, Sendable {
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

enum InsightType: Sendable {
    case personalRecord
    case strengthGain
    case baseline
    case progressiveOverload
    case milestone
    case consistency

    var iconName: String {
        switch self {
        case .personalRecord: return "trophy.fill"
        case .strengthGain: return "arrow.up.right.circle.fill"
        case .baseline: return "flag.fill"
        case .progressiveOverload: return "chart.line.uptrend.xyaxis"
        case .milestone: return "star.fill"
        case .consistency: return "flame.fill"
        }
    }

    var color: String {
        switch self {
        case .personalRecord: return "yellow"
        case .strengthGain: return "green"
        case .baseline: return "cyan"
        case .progressiveOverload: return "blue"
        case .milestone: return "orange"
        case .consistency: return "red"
        }
    }
}

enum MuscleGroup: String, CaseIterable, Codable, Sendable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case quads
    case hamstrings
    case glutes
    case calves
    case core
    case cardio

    // Legacy cases for backward compatibility (not in allCases)
    private static let legacyMappings: [String: MuscleGroup] = [
        "push": .chest,
        "pull": .back,
        "legs": .quads
    ]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if let group = MuscleGroup(rawValue: rawValue) {
            self = group
        } else if let mapped = MuscleGroup.legacyMappings[rawValue] {
            self = mapped
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown muscle group: \(rawValue)")
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .core: return "Core"
        case .cardio: return "Cardio"
        }
    }
}
