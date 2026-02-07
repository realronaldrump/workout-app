import Foundation
import Combine

class ExerciseMetadataManager: ObservableObject {
    static let shared = ExerciseMetadataManager()
    
    /// User overrides. If a key is present with an empty array, that exercise is explicitly untagged.
    @Published private(set) var muscleTagOverrides: [String: [MuscleTag]] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let metadataKey = "ExerciseMetadata"
    
    private let defaultMappings: [String: [MuscleTag]] = [
        // Chest
        "Chest Press (Machine)": [.builtIn(.chest)],
        "Bench Press (Barbell)": [.builtIn(.chest)],
        "Incline Bench Press (Barbell)": [.builtIn(.chest)],
        "Dumbbell Press": [.builtIn(.chest)],
        "Chest Fly": [.builtIn(.chest)],
        "Push Ups": [.builtIn(.chest)],
        
        // Back
        "Lat Pulldown (Machine)": [.builtIn(.back)],
        "Seated Row (Machine)": [.builtIn(.back)],
        "MTS Row": [.builtIn(.back)],
        "Pull Up": [.builtIn(.back)],
        "Chin Up": [.builtIn(.back)],
        "Barbell Row": [.builtIn(.back)],
        "Deadlift (Barbell)": [.builtIn(.back)],
        "Reverse Fly (Machine)": [.builtIn(.back)],
        
        // Shoulders
        "Shoulder Press (Machine)": [.builtIn(.shoulders)],
        "Overhead Press (Barbell)": [.builtIn(.shoulders)],
        "Lateral Raise (Machine)": [.builtIn(.shoulders)],
        
        // Biceps
        "Bicep Curl (Machine)": [.builtIn(.biceps)],
        "Preacher Curl (Machine)": [.builtIn(.biceps)],
        
        // Triceps
        "Triceps Press Machine": [.builtIn(.triceps)],
        "Triceps Extension (Machine)": [.builtIn(.triceps)],
        
        // Quads
        "Leg Extension (Machine)": [.builtIn(.quads)],
        "Seated Leg Press (Machine)": [.builtIn(.quads)],
        "Squat (Barbell)": [.builtIn(.quads)],
        "Leg Press": [.builtIn(.quads)],
        "Lunges": [.builtIn(.quads)],
        
        // Hamstrings
        "Seated Leg Curl (Machine)": [.builtIn(.hamstrings)],
        "Lying Leg Curl (Machine)": [.builtIn(.hamstrings)],
        
        // Glutes
        "Hip Adductor (Machine)": [.builtIn(.glutes)],
        "Hip Abductor (Machine)": [.builtIn(.glutes)],
        "Glute Kickback (Machine)": [.builtIn(.glutes)],
        
        // Calves
        "Calf Extension Machine": [.builtIn(.calves)],
        
        // Cardio
        "Running (Treadmill)": [.builtIn(.cardio)],
        "Stair stepper": [.builtIn(.cardio)],
        "Cycling": [.builtIn(.cardio)],
        "Elliptical": [.builtIn(.cardio)]
    ]
    
    init() {
        loadMappings()
    }
    
    func resolvedTags(for exerciseName: String) -> [MuscleTag] {
        if let override = muscleTagOverrides[exerciseName] {
            return override
        }
        return defaultMappings[exerciseName] ?? []
    }

    /// Returns resolved (defaults + user overrides) tags for all provided exercise names.
    /// By default, untagged exercises are omitted.
    func resolvedMappings(
        for exerciseNames: Set<String>,
        includeUntagged: Bool = false
    ) -> [String: [MuscleTag]] {
        exerciseNames.reduce(into: [String: [MuscleTag]]()) { result, name in
            let tags = resolvedTags(for: name)
            if includeUntagged || !tags.isEmpty {
                result[name] = tags
            }
        }
    }

    func defaultTags(for exerciseName: String) -> [MuscleTag] {
        defaultMappings[exerciseName] ?? []
    }

    func hasDefaultTags(for exerciseName: String) -> Bool {
        defaultMappings[exerciseName] != nil
    }

    func isOverridden(for exerciseName: String) -> Bool {
        muscleTagOverrides[exerciseName] != nil
    }

    func resetToDefault(for exerciseName: String) {
        muscleTagOverrides.removeValue(forKey: exerciseName)
        saveMappings()
    }

    func clearTags(for exerciseName: String) {
        setTags(for: exerciseName, to: [])
    }

    func setTags(for exerciseName: String, to tags: [MuscleTag]) {
        let canonical = canonicalize(tags)
        let defaultCanonical = canonicalize(defaultTags(for: exerciseName))

        if canonical == defaultCanonical {
            // No override needed: fall back to defaults.
            muscleTagOverrides.removeValue(forKey: exerciseName)
        } else {
            muscleTagOverrides[exerciseName] = canonical
        }
        saveMappings()
    }

    func toggleTag(for exerciseName: String, tag: MuscleTag) {
        var current = resolvedTags(for: exerciseName)
        let canonicalTagId = tag.id

        if let index = current.firstIndex(where: { $0.id == canonicalTagId }) {
            current.remove(at: index)
        } else {
            current.append(tag)
        }

        setTags(for: exerciseName, to: current)
    }

    func addCustomTag(for exerciseName: String, name: String) {
        guard let tag = MuscleTag.custom(name) else { return }
        var current = resolvedTags(for: exerciseName)
        if current.contains(where: { $0.id == tag.id }) { return }
        current.append(tag)
        setTags(for: exerciseName, to: current)
    }

    var knownCustomTags: [MuscleTag] {
        let all = muscleTagOverrides.values.flatMap { $0 }.filter { $0.kind == .custom }
        let grouped = Dictionary(grouping: all, by: { $0.id })

        let representatives = grouped.values.compactMap { variants -> MuscleTag? in
            variants.sorted { lhs, rhs in
                let insensitive = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if insensitive != .orderedSame { return insensitive == .orderedAscending }
                let sensitive = lhs.displayName.localizedCompare(rhs.displayName)
                if sensitive != .orderedSame { return sensitive == .orderedAscending }
                return lhs.value.count < rhs.value.count
            }.first
        }

        return representatives.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
    
    // MARK: - Persistence
    
    private func loadMappings() {
        guard let data = userDefaults.data(forKey: metadataKey) else { return }

        if let saved = try? JSONDecoder().decode([String: [MuscleTag]].self, from: data) {
            self.muscleTagOverrides = saved
            return
        }

        // Legacy: [String: MuscleGroup]
        if let saved = try? JSONDecoder().decode([String: MuscleGroup].self, from: data) {
            self.muscleTagOverrides = saved.mapValues { [MuscleTag.builtIn($0)] }
            saveMappings()
            return
        }
    }
    
    private func saveMappings() {
        if let data = try? JSONEncoder().encode(muscleTagOverrides) {
            userDefaults.set(data, forKey: metadataKey)
        }
    }

    private func canonicalize(_ tags: [MuscleTag]) -> [MuscleTag] {
        var seen = Set<String>()
        let cleaned: [MuscleTag] = tags.compactMap { tag in
            switch tag.kind {
            case .builtIn:
                guard let _ = tag.builtInGroup else { return nil }
                return tag
            case .custom:
                guard !tag.displayName.isEmpty else { return nil }
                return tag
            }
        }
        .filter { seen.insert($0.id).inserted }

        let builtInOrder: [MuscleGroup: Int] = Dictionary(
            uniqueKeysWithValues: MuscleGroup.allCases.enumerated().map { ($1, $0) }
        )

        return cleaned.sorted { lhs, rhs in
            switch (lhs.builtInGroup, rhs.builtInGroup) {
            case let (l?, r?):
                return (builtInOrder[l] ?? 0) < (builtInOrder[r] ?? 0)
            case (nil, nil):
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }
}
