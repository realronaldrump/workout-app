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
    nonisolated static func recommend(
        exerciseName: String,
        history: [(date: Date, sets: [WorkoutSet])],
        weightIncrement: Double
    ) -> ExerciseRecommendation {
        let sorted = history.sorted { $0.date < $1.date }
        let recentSessions = Array(sorted.suffix(12))
        let recentSets = recentSessions.flatMap(\.sets).filter { $0.weight > 0 && $0.reps > 0 }

        let repRange = inferredRepRange(from: recentSets)
        let workingSets = inferredWorkingSets(from: recentSessions)
        let targetReps = (repRange.lowerBound + repRange.upperBound) / 2

        let best1RM = recentSets.map { estimateOneRepMax(weight: $0.weight, reps: $0.reps) }.max() ?? 0

        let baseWeight: Double? = best1RM > 0
            ? (best1RM / (1 + 0.0333 * Double(targetReps))) * 0.97
            : nil
        var suggested = baseWeight.map { roundToIncrement($0, increment: weightIncrement) }

        // Anchor to last session's top load so we don't jump wildly.
        let lastSession = sorted.last
        let lastMaxWeight = lastSession?.sets.map(\.weight).max() ?? 0
        if let current = suggested, lastMaxWeight > 0, weightIncrement > 0 {
            let clamp = weightIncrement * 2
            if current > lastMaxWeight + clamp { suggested = lastMaxWeight + clamp }
            if current < max(0, lastMaxWeight - clamp) { suggested = max(0, lastMaxWeight - clamp) }
        }

        // Progression nudge: if last top set was comfortable at target reps, add one increment.
        if let lastSession {
            let topSet = lastSession.sets.max { lhs, rhs in
                estimateOneRepMax(weight: lhs.weight, reps: lhs.reps) < estimateOneRepMax(weight: rhs.weight, reps: rhs.reps)
            }

            if let topSet, topSet.reps >= targetReps, weightIncrement > 0 {
                let bumped = topSet.weight + weightIncrement
                suggested = max(suggested ?? 0, bumped)
            }
        }

        // Warmups
        let warmup: [WarmupRecommendation]
        if let workingWeight = suggested, workingWeight > 0, weightIncrement > 0 {
            let w1 = roundToIncrement(workingWeight * 0.40, increment: weightIncrement)
            let w2 = roundToIncrement(workingWeight * 0.60, increment: weightIncrement)
            let w3 = roundToIncrement(workingWeight * 0.75, increment: weightIncrement)
            warmup = [
                WarmupRecommendation(weight: w1, reps: 8),
                WarmupRecommendation(weight: w2, reps: 5),
                WarmupRecommendation(weight: w3, reps: 3)
            ]
        } else {
            warmup = []
        }

        let rationale = makeRationale(
            best1RM: best1RM,
            targetReps: targetReps,
            workingSets: workingSets,
            lastMaxWeight: lastMaxWeight,
            repRange: repRange
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

    private nonisolated static func inferredWorkingSets(from sessions: [(date: Date, sets: [WorkoutSet])]) -> Int {
        let counts = sessions
            .map { $0.sets.filter { $0.weight > 0 && $0.reps > 0 }.count }
            .filter { $0 > 0 }
        guard !counts.isEmpty else { return 3 }

        let median = medianInt(counts)
        return min(max(median, 2), 6)
    }

    private nonisolated static func estimateOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }

    private nonisolated static func roundToIncrement(_ value: Double, increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }

    private nonisolated static func makeRationale(
        best1RM: Double,
        targetReps: Int,
        workingSets: Int,
        lastMaxWeight: Double,
        repRange: ClosedRange<Int>
    ) -> String {
        var parts: [String] = []
        if best1RM > 0 {
            parts.append("e1RM ~\(Int(best1RM))")
            parts.append("target \(targetReps) reps")
            parts.append("\(workingSets) sets")
        } else {
            parts.append("No history yet")
        }
        if lastMaxWeight > 0 {
            parts.append("last max \(Int(lastMaxWeight))")
        }
        parts.append("\(repRange.lowerBound)-\(repRange.upperBound) reps")
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
