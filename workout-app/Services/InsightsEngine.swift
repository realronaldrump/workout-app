import Foundation
import Combine

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

    var iconName: String {
        switch self {
        case .personalRecord: return "trophy.fill"
        case .strengthGain: return "arrow.up.right.circle.fill"
        case .baseline: return "flag.fill"
        }
    }

    var color: String {
        switch self {
        case .personalRecord: return "yellow"
        case .strengthGain: return "green"
        case .baseline: return "cyan"
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
