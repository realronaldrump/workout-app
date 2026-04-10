import Foundation

struct WarmupRecommendation: Hashable, Sendable {
    let weight: Double
    let reps: Int
}

struct ExerciseRecommendation: Hashable, Sendable {
    let suggestedWorkingSets: Int
    let repRange: ClosedRange<Int>
    let suggestedWeight: Double?
    let warmup: [WarmupRecommendation]
    let rationale: String
}

enum ExerciseRecommendationEngine {
    private struct RecommendationContext {
        let hasHistory: Bool
        let bestEstimate: Double
        let targetReps: Int
        let workingSets: Int
        let lastMaxWeight: Double
        let repRange: ClosedRange<Int>
    }

    nonisolated static func recommend(
        exerciseName: String,
        history: [(date: Date, sets: [WorkoutSet])],
        weightIncrement: Double
    ) -> ExerciseRecommendation {
        let isAssisted = ExerciseLoad.isAssistedExercise(exerciseName)
        let sorted = history.sorted { $0.date < $1.date }
        let recentSessions = Array(sorted.suffix(12))
        let recentSets = recentSessions
            .flatMap(\.sets)
            .filter { isTrackableSet($0, exerciseName: exerciseName) }

        let repRange = inferredRepRange(from: recentSets)
        let workingSets = inferredWorkingSets(from: recentSessions, exerciseName: exerciseName)
        let targetReps = (repRange.lowerBound + repRange.upperBound) / 2

        let bestSet = OneRepMax.bestSet(in: recentSets, exerciseName: exerciseName)
        let best1RM = bestSet.map {
            OneRepMax.estimate(weight: $0.weight, reps: $0.reps, exerciseName: exerciseName)
        } ?? 0

        let baseWeight: Double? = bestSet.map { _ in
            let repFactor = 1 + 0.0333 * Double(targetReps)
            let projectedWeight = isAssisted
                ? (best1RM * repFactor)
                : (best1RM / repFactor)
            return isAssisted ? (projectedWeight / 0.97) : (projectedWeight * 0.97)
        }
        var suggested = baseWeight.map { roundToIncrement($0, increment: weightIncrement) }

        // Anchor to last session's top load so we don't jump wildly.
        let lastSession = sorted.last
        let lastMaxWeight = lastSession.map { ExerciseLoad.bestWeight(in: $0.sets, exerciseName: exerciseName) } ?? 0
        if let current = suggested, lastMaxWeight > 0, weightIncrement > 0 {
            let clamp = weightIncrement * 2
            let lowerBound = max(0, lastMaxWeight - clamp)
            let upperBound = lastMaxWeight + clamp
            suggested = min(max(current, lowerBound), upperBound)
        }

        // Progression nudge: if last top set was comfortable at target reps, add one increment.
        if let lastSession {
            let topSet = OneRepMax.bestSet(in: lastSession.sets, exerciseName: exerciseName)

            if let topSet, topSet.reps >= targetReps, weightIncrement > 0 {
                let bumped = isAssisted
                    ? max(0, topSet.weight - weightIncrement)
                    : (topSet.weight + weightIncrement)
                if let current = suggested {
                    suggested = ExerciseLoad.isBetter(bumped, than: current, exerciseName: exerciseName) ? bumped : current
                } else {
                    suggested = bumped
                }
            }
        }

        // Warmups
        let warmup: [WarmupRecommendation]
        if let workingWeight = suggested, workingWeight > 0, weightIncrement > 0 {
            let warmupWeights: [Double]
            if isAssisted {
                warmupWeights = [
                    workingWeight * 1.50,
                    workingWeight * 1.25,
                    workingWeight * 1.10
                ]
            } else {
                warmupWeights = [
                    workingWeight * 0.40,
                    workingWeight * 0.60,
                    workingWeight * 0.75
                ]
            }
            let w1 = roundToIncrement(warmupWeights[0], increment: weightIncrement)
            let w2 = roundToIncrement(warmupWeights[1], increment: weightIncrement)
            let w3 = roundToIncrement(warmupWeights[2], increment: weightIncrement)
            warmup = [
                WarmupRecommendation(weight: w1, reps: 8),
                WarmupRecommendation(weight: w2, reps: 5),
                WarmupRecommendation(weight: w3, reps: 3)
            ]
        } else {
            warmup = []
        }

        let rationale = makeRationale(
            exerciseName: exerciseName,
            context: RecommendationContext(
                hasHistory: bestSet != nil,
                bestEstimate: best1RM,
                targetReps: targetReps,
                workingSets: workingSets,
                lastMaxWeight: lastMaxWeight,
                repRange: repRange
            )
        )

        return ExerciseRecommendation(
            suggestedWorkingSets: workingSets,
            repRange: repRange,
            suggestedWeight: suggested,
            warmup: warmup,
            rationale: rationale
        )
    }

    // MARK: - Helpers

    private nonisolated static func inferredRepRange(from sets: [WorkoutSet]) -> ClosedRange<Int> {
        let reps = sets.map(\.reps).filter { $0 > 0 }
        guard !reps.isEmpty else { return 6...10 }

        let median = medianInt(reps)
        let lower = max(3, median - 2)
        let upper = min(15, median + 2)
        return min(lower, upper)...max(lower, upper)
    }

    private nonisolated static func inferredWorkingSets(
        from sessions: [(date: Date, sets: [WorkoutSet])],
        exerciseName: String
    ) -> Int {
        let counts = sessions
            .map { $0.sets.filter { isTrackableSet($0, exerciseName: exerciseName) }.count }
            .filter { $0 > 0 }
        guard !counts.isEmpty else { return 3 }

        let median = medianInt(counts)
        return min(max(median, 2), 6)
    }

    private nonisolated static func isTrackableSet(_ set: WorkoutSet, exerciseName: String) -> Bool {
        set.reps > 0 && ExerciseLoad.isTrackedWeight(set.weight, exerciseName: exerciseName)
    }

    private nonisolated static func roundToIncrement(_ value: Double, increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }

    private nonisolated static func makeRationale(
        exerciseName: String,
        context: RecommendationContext
    ) -> String {
        var parts: [String] = []
        if context.hasHistory {
            let estimateLabel = ExerciseLoad.isAssistedExercise(exerciseName) ? "assist score" : "e1RM"
            parts.append("\(estimateLabel) ~\(Int(context.bestEstimate.rounded()))")
            parts.append("target \(context.targetReps) reps")
            parts.append("\(context.workingSets) sets")
        } else {
            parts.append("No history yet")
        }
        if context.lastMaxWeight > 0 {
            let label = ExerciseLoad.isAssistedExercise(exerciseName) ? "last best assist" : "last max"
            parts.append("\(label) \(Int(context.lastMaxWeight))")
        }
        parts.append("\(context.repRange.lowerBound)-\(context.repRange.upperBound) reps")
        return parts.joined(separator: " | ")
    }

    private nonisolated static func medianInt(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
