import Foundation
import Combine

@MainActor
final class ExerciseMetricManager: ObservableObject {
    static let shared = ExerciseMetricManager()

    /// User overrides. If a key is present, it overrides the defaults for that exercise.
    @Published private(set) var cardioOverrides: [String: ExerciseCardioMetricPreferences] = [:]

    private let userDefaults = UserDefaults.standard
    private let storageKey = "ExerciseMetricPreferences"

    init() {
        load()
    }

    func preferences(for exerciseName: String) -> ExerciseCardioMetricPreferences {
        cardioOverrides[exerciseName] ?? .default
    }

    func setPrimaryMetric(for exerciseName: String, to selection: ExerciseCardioMetricPreferences.PrimaryMetricSelection) {
        var prefs = preferences(for: exerciseName)
        prefs.primaryMetric = selection
        setPreferences(for: exerciseName, to: prefs)
    }

    func setCountLabel(for exerciseName: String, to label: String) {
        var prefs = preferences(for: exerciseName)
        prefs.countLabel = sanitizeCountLabel(label)
        setPreferences(for: exerciseName, to: prefs)
    }

    func resolvedCardioConfiguration(for exerciseName: String, historySets: [WorkoutSet]) -> ResolvedCardioMetricConfiguration {
        let prefs = preferences(for: exerciseName)
        let effective = resolveEffectivePrimaryMetric(selection: prefs.primaryMetric, sets: historySets)

        let secondary: CardioMetricKind = {
            switch effective {
            case .distance: return .duration
            case .duration: return .distance
            case .count: return .duration
            }
        }()

        return ResolvedCardioMetricConfiguration(
            primary: effective,
            secondary: secondary,
            countLabel: sanitizeCountLabel(prefs.countLabel)
        )
    }

    // MARK: - Persistence

    private func setPreferences(for exerciseName: String, to prefs: ExerciseCardioMetricPreferences) {
        let canonical = canonicalize(prefs)
        if canonical == .default {
            cardioOverrides.removeValue(forKey: exerciseName)
        } else {
            cardioOverrides[exerciseName] = canonical
        }
        save()
    }

    private func load() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }
        if let saved = try? JSONDecoder().decode([String: ExerciseCardioMetricPreferences].self, from: data) {
            cardioOverrides = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cardioOverrides) {
            userDefaults.set(data, forKey: storageKey)
        }
    }

    // MARK: - Helpers

    private func canonicalize(_ prefs: ExerciseCardioMetricPreferences) -> ExerciseCardioMetricPreferences {
        var copy = prefs
        copy.countLabel = sanitizeCountLabel(copy.countLabel)
        copy.schemaVersion = ExerciseCardioMetricPreferences.default.schemaVersion
        return copy
    }

    private func sanitizeCountLabel(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ExerciseCardioMetricPreferences.default.countLabel }

        // Collapse repeated whitespace so "Floor   Count" normalizes the same.
        let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed
    }

    private func resolveEffectivePrimaryMetric(
        selection: ExerciseCardioMetricPreferences.PrimaryMetricSelection,
        sets: [WorkoutSet]
    ) -> CardioMetricKind {
        switch selection {
        case .distance:
            return .distance
        case .duration:
            return .duration
        case .count:
            return .count
        case .auto:
            if sets.contains(where: { $0.distance > 0 }) { return .distance }
            if sets.contains(where: { $0.seconds > 0 }) { return .duration }
            if sets.contains(where: { $0.reps > 0 }) { return .count }
            // Fallback: time is the most universal cardio metric to start with.
            return .duration
        }
    }
}
