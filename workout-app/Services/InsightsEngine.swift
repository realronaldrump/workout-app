import Combine
import Foundation

/// Intelligent insights engine that analyzes workout data to provide
/// lightweight, objective signals (e.g. PRs) without subjective coaching.
@MainActor
class InsightsEngine: ObservableObject {
    @Published var insights: [Insight] = []
    private var generation = 0
    private var backgroundAnalysisTask: Task<[Insight], Never>?

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
        generation += 1
        let currentGeneration = generation
        backgroundAnalysisTask?.cancel()

        // Capture snapshot of data to pass to background tasks
        let workoutsSnapshot = dataManager.workouts
        let annotationsSnapshot = annotationsProvider()
        let gymNameSnapshot = gymNameProvider()
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()

        // Run analysis in parallel
        let analysisTask = Task.detached(priority: .userInitiated) {
            let index = WorkoutInsightsIndex(workouts: workoutsSnapshot, resolver: resolver)
            guard !Task.isCancelled else { return [Insight]() }
            return await withTaskGroup(of: [Insight].self) { group in
                // Personal Records
                group.addTask {
                    return self.detectPersonalRecords(index: index)
                }

                // New Equipment Baseline
                group.addTask {
                    return self.detectNewEquipmentBaseline(
                        index: index,
                        annotations: annotationsSnapshot,
                        gymNames: gymNameSnapshot
                    )
                }

                // Progressive Overload Detection
                group.addTask {
                    return self.detectProgressiveOverload(index: index)
                }

                // Volume Milestones
                group.addTask {
                    return self.detectVolumeMilestones(workoutCount: workoutsSnapshot.count, totalVolume: index.totalVolume)
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
        }
        backgroundAnalysisTask = analysisTask
        let newInsights = await withTaskCancellationHandler {
            await analysisTask.value
        } onCancel: {
            analysisTask.cancel()
        }

        // Update on MainActor
        guard currentGeneration == generation else { return }
        backgroundAnalysisTask = nil
        guard !Task.isCancelled else { return }
        self.insights = newInsights.sorted { $0.priority > $1.priority }
    }

    // MARK: - Personal Records Detection

    private nonisolated func detectPersonalRecords(index: WorkoutInsightsIndex) -> [Insight] {
        var prInsights: [Insight] = []
        let calendar = Calendar.current
        guard let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else { return [] }

        for exerciseName in index.performanceTrackNames {
            guard !Task.isCancelled else { return [] }
            let isAssisted = ExerciseLoad.isAssistedExercise(exerciseName)
            let history = index.historyByPerformanceTrack[exerciseName] ?? []

            guard history.count >= 2 else { continue }

            // Find all-time max weight
            let allSets = history.flatMap { $0.sets }
            guard let maxWeightSet = ExerciseLoad.bestWeight(in: allSets.map(\.weight), exerciseName: exerciseName) else {
                continue
            }

            // Check if the PR was set recently
            if let recentSession = history.last,
               recentSession.date >= oneWeekAgo,
               recentSession.sets.contains(where: { $0.weight == maxWeightSet }) {

                // Calculate improvement from previous best
                let previousBest = ExerciseLoad.bestWeight(
                    in: history.dropLast().flatMap { $0.sets }.map(\.weight),
                    exerciseName: exerciseName
                ) ?? 0
                let improvement = ExerciseLoad.progressDelta(
                    current: maxWeightSet,
                    previous: previousBest,
                    exerciseName: exerciseName
                )

                if improvement > 0 {
                    let weightLabel = ExerciseLoad.formatWeight(maxWeightSet, exerciseName: exerciseName)
                    prInsights.append(Insight(
                        id: UUID(),
                        type: .personalRecord,
                        title: "PR",
                        message: """
                        \(exerciseName): \(weightLabel) \
                        (\(ExerciseLoad.signedWeightDeltaLabel(improvement, exerciseName: exerciseName)))
                        """,
                        exerciseName: exerciseName,
                        date: recentSession.date,
                        priority: 10,
                        actionLabel: "Trend",
                        metric: ExerciseLoad.comparisonValue(for: maxWeightSet, exerciseName: exerciseName)
                    ))
                }
            }

            // Check for estimated 1RM PRs
            let best1RMs = history.map { session -> (date: Date, orm: Double) in
                let orm = OneRepMax.bestEstimate(in: session.sets, exerciseName: exerciseName)
                return (date: session.date, orm: orm)
            }

            if let latestORM = best1RMs.last,
               latestORM.date >= oneWeekAgo,
               let previousBest = best1RMs.dropLast().max(by: { lhs, rhs in
                   ExerciseLoad.comparisonValue(for: lhs.orm, exerciseName: exerciseName) <
                   ExerciseLoad.comparisonValue(for: rhs.orm, exerciseName: exerciseName)
               }) {

                let improvement = ExerciseLoad.progressDelta(
                    current: latestORM.orm,
                    previous: previousBest.orm,
                    exerciseName: exerciseName
                )
                guard improvement > 0 else { continue }
                prInsights.append(Insight(
                    id: UUID(),
                    type: .strengthGain,
                    title: isAssisted ? "Assistance estimate" : "Estimated max",
                    message: """
                    \(exerciseName): \(ExerciseLoad.formatWeight(latestORM.orm, exerciseName: exerciseName)) \
                    (\(ExerciseLoad.signedWeightDeltaLabel(improvement, exerciseName: exerciseName)))
                    """,
                    exerciseName: exerciseName,
                    date: latestORM.date,
                    priority: 8,
                    actionLabel: "Trend",
                    metric: ExerciseLoad.comparisonValue(for: latestORM.orm, exerciseName: exerciseName)
                ))
            }
        }

        return prInsights
    }

    // MARK: - New Equipment Baseline

    private nonisolated func detectNewEquipmentBaseline(
        index: WorkoutInsightsIndex,
        annotations: [UUID: WorkoutAnnotation],
        gymNames: [UUID: String]
    ) -> [Insight] {
        var baselineInsights: [Insight] = []

        for (exerciseName, sessions) in index.aggregateSessionsByName {
            guard !Task.isCancelled else { return [] }
            guard sessions.count >= 2 else { continue }

            var seenGymKeys: Set<UUID?> = []
            for session in sessions {
                let gymKey = annotations[session.workoutID]?.gymProfileId
                if !seenGymKeys.contains(gymKey) {
                    if let gymId = gymKey,
                       !seenGymKeys.isEmpty {
                        let gymLabel = gymNames[gymId] ?? "Deleted gym"
                        baselineInsights.append(Insight(
                            id: UUID(),
                            type: .baseline,
                            title: "New gym",
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

    // MARK: - Progressive Overload Detection

    private nonisolated func detectProgressiveOverload(index: WorkoutInsightsIndex) -> [Insight] {
        var insights: [Insight] = []
        let calendar = Calendar.current
        guard let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date()) else { return [] }

        for (name, sorted) in index.aggregateSessionsByName {
            guard !Task.isCancelled else { return [] }
            guard !ExerciseLoad.isAssistedExercise(name) else { continue }
            guard sorted.count >= 4 else { continue }

            // Get weekly volume over last 4 weeks
            let recentSessions = sorted.filter { $0.date >= fourWeeksAgo }
            guard recentSessions.count >= 2 else { continue }

            let recentVolumes = recentSessions.map(\.volume)
            let olderSessions = sorted.filter { $0.date < fourWeeksAgo }.suffix(4)
            let olderVolumes = olderSessions.map(\.volume)

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
                    date: recentSessions.last?.date ?? Date(),
                    priority: 7,
                    actionLabel: "Trend",
                    metric: change
                ))
            }
        }

        return Array(insights.prefix(5))
    }

    // MARK: - Volume Milestones

    private nonisolated func detectVolumeMilestones(
        workoutCount: Int,
        totalVolume: Double
    ) -> [Insight] {
        guard !Task.isCancelled else { return [] }
        var insights: [Insight] = []

        // Total lifetime volume milestones
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
        let count = workoutCount
        let countMilestones = [1000, 500, 250, 100, 50, 25]
        if let cm = countMilestones.first(where: { count >= $0 }) {
            insights.append(Insight(
                id: UUID(),
                type: .milestone,
                title: "\(cm) Workouts",
                message: "\(count) sessions logged",
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
        guard !Task.isCancelled else { return [] }
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
                title: "12-week streak",
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
    case traps
    case shoulders
    case biceps
    case triceps
    case forearms
    case quads
    case hamstrings
    case glutes
    case hipFlexors
    case adductors
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
        case .traps: return "Traps"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .hipFlexors: return "Hip Flexors"
        case .adductors: return "Adductors"
        case .calves: return "Calves"
        case .core: return "Core"
        case .cardio: return "Cardio"
        }
    }
}
