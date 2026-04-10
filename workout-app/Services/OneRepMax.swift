import Foundation

enum ExerciseLoad {
    private static let assistedPattern = #"\bassisted\b"#

    static func isAssistedExercise(_ exerciseName: String) -> Bool {
        exerciseName.range(
            of: assistedPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func comparisonValue(for loggedWeight: Double, exerciseName: String) -> Double {
        isAssistedExercise(exerciseName) ? -loggedWeight : loggedWeight
    }

    static func isBetter(_ lhs: Double, than rhs: Double, exerciseName: String) -> Bool {
        comparisonValue(for: lhs, exerciseName: exerciseName) >
        comparisonValue(for: rhs, exerciseName: exerciseName)
    }

    static func bestWeight(in weights: [Double], exerciseName: String) -> Double? {
        guard let first = weights.first else { return nil }
        return weights.dropFirst().reduce(first) { current, candidate in
            isBetter(candidate, than: current, exerciseName: exerciseName) ? candidate : current
        }
    }

    static func bestWeight(in sets: [WorkoutSet], exerciseName: String) -> Double {
        bestWeight(in: sets.map(\.weight), exerciseName: exerciseName) ?? 0
    }

    static func progressDelta(current: Double, previous: Double, exerciseName: String) -> Double {
        comparisonValue(for: current, exerciseName: exerciseName) -
        comparisonValue(for: previous, exerciseName: exerciseName)
    }

    static func isTrackedWeight(_ weight: Double, exerciseName: String) -> Bool {
        isAssistedExercise(exerciseName) ? weight >= 0 : weight > 0
    }

    static func performancePercentChange(current: Double, previous: Double) -> Double {
        guard abs(previous) > 0.0001 else { return 0 }
        return (current - previous) / abs(previous) * 100
    }

    static func relativeIntensity(weight: Double, referenceWeight: Double, exerciseName: String) -> Double {
        guard weight > 0, referenceWeight > 0 else { return 0 }
        if isAssistedExercise(exerciseName) {
            return min(referenceWeight / weight, 1.5)
        }
        return weight / referenceWeight
    }

    static func weightMetricTitle(for exerciseName: String) -> String {
        isAssistedExercise(exerciseName) ? "Least Assistance" : "Max Weight"
    }

    static func weightRecordTitle(for exerciseName: String) -> String {
        isAssistedExercise(exerciseName) ? "Lowest Assistance" : "Heaviest Weight"
    }

    static func oneRepMaxTitle(for exerciseName: String) -> String {
        isAssistedExercise(exerciseName) ? "Assistance Score" : "Est. 1RM"
    }

    static func chartOneRepMaxTitle(for exerciseName: String) -> String {
        isAssistedExercise(exerciseName) ? "Assistance Score" : "1RM"
    }

    static func weightUnitLabel(for exerciseName: String) -> String {
        isAssistedExercise(exerciseName) ? "lbs assist" : "lbs"
    }

    static func formatWeight(_ value: Double, exerciseName: String, includeUnit: Bool = true) -> String {
        let rounded = value.rounded()
        let number: String
        if abs(value - rounded) < 0.0001 {
            number = "\(Int(rounded))"
        } else {
            number = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        }

        guard includeUnit else { return number }
        return "\(number) \(weightUnitLabel(for: exerciseName))"
    }

    static func signedWeightDeltaLabel(_ delta: Double, exerciseName: String) -> String {
        let rounded = Int(delta.rounded())
        if isAssistedExercise(exerciseName) {
            if rounded == 0 { return "0 lbs assist" }
            return rounded > 0 ? "\(rounded) lbs less assist" : "\(abs(rounded)) lbs more assist"
        }

        if rounded == 0 { return "0 lbs" }
        return rounded > 0 ? "+\(rounded) lbs" : "\(rounded) lbs"
    }
}

/// Epley-formula one-rep max estimator used throughout the app.
/// Centralised here so the formula is never duplicated.
enum OneRepMax {
    /// Estimate the one-rep max for a given weight and rep count (Epley formula).
    static func estimate(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }

    /// Assisted exercises store assistance instead of lifted load, so stronger sets
    /// should project to needing less assistance for a one-rep effort.
    static func estimate(weight: Double, reps: Int, exerciseName: String) -> Double {
        guard ExerciseLoad.isAssistedExercise(exerciseName) else {
            return estimate(weight: weight, reps: reps)
        }
        guard reps > 0 else { return weight }
        return weight / (1 + 0.0333 * Double(reps))
    }

    static func comparisonValue(weight: Double, reps: Int, exerciseName: String) -> Double {
        ExerciseLoad.comparisonValue(
            for: estimate(weight: weight, reps: reps, exerciseName: exerciseName),
            exerciseName: exerciseName
        )
    }

    static func bestSet(in sets: [WorkoutSet], exerciseName: String) -> WorkoutSet? {
        sets.max { lhs, rhs in
            comparisonValue(weight: lhs.weight, reps: lhs.reps, exerciseName: exerciseName) <
            comparisonValue(weight: rhs.weight, reps: rhs.reps, exerciseName: exerciseName)
        }
    }

    static func bestEstimate(in sets: [WorkoutSet], exerciseName: String) -> Double {
        guard let bestSet = bestSet(in: sets, exerciseName: exerciseName) else { return 0 }
        return estimate(weight: bestSet.weight, reps: bestSet.reps, exerciseName: exerciseName)
    }
}
