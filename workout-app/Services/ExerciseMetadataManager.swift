import Foundation
import Combine

class ExerciseMetadataManager: ObservableObject {
    static let shared = ExerciseMetadataManager()

    /// A curated list of built-in exercises that should appear in pickers even before any workouts exist.
    static let defaultExerciseNames: [String] = defaultExerciseCatalog.map(\.name)

    /// User overrides. If a key is present with an empty array, that exercise is explicitly untagged.
    @Published private(set) var muscleTagOverrides: [String: [MuscleTag]] = [:]

    private let userDefaults = UserDefaults.standard
    private let metadataKey = "ExerciseMetadata"

    private struct CatalogEntry {
        let name: String
        let groups: [MuscleGroup]
    }

    /// This is the default exercise list requested by the user (names + built-in muscle-group tags).
    /// This list is also used to populate the exercise picker when there are no logged workouts yet.
    private static let defaultExerciseCatalog: [CatalogEntry] = [
        .init(name: "45\u{00B0} Donkey Calf", groups: [.calves]),
        .init(name: "Arnold Press (Dumbbell)", groups: [.shoulders, .triceps]),
        .init(name: "Back Extension (Machine)", groups: [.back, .glutes, .hamstrings]),
        .init(name: "Bench Press - Close Grip (Barbell)", groups: [.triceps, .chest, .shoulders]),
        .init(name: "Bench Press (Barbell)", groups: [.chest, .triceps, .shoulders]),
        .init(name: "Bent Over Row (Dumbbell)", groups: [.back, .biceps]),
        .init(name: "Bicep Curl (Barbell)", groups: [.biceps]),
        .init(name: "Bicep Curl (Cable)", groups: [.biceps]),
        .init(name: "Bicep Curl (Dumbbell)", groups: [.biceps]),
        .init(name: "Bicep Curl (Machine)", groups: [.biceps]),
        .init(name: "Bicep Curl (Machine) (Bands)", groups: [.biceps]),
        .init(name: "Bulgarian Split Squat", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Calf Extension Machine", groups: [.calves]),
        .init(name: "Chest Fly", groups: [.chest]),
        .init(name: "Chest Fly (Dumbbell)", groups: [.chest]),
        .init(name: "Chest Press (Machine)", groups: [.chest, .triceps, .shoulders]),
        .init(name: "Crunch", groups: [.core]),
        .init(name: "Crunch (Machine)", groups: [.core]),
        .init(name: "Cycling (Indoor)", groups: [.cardio]),
        .init(name: "Deadlift (Smith Machine)", groups: [.hamstrings, .glutes, .back]),
        .init(name: "Elliptical Machine", groups: [.cardio]),
        .init(name: "EZ Bar Curl", groups: [.biceps]),
        .init(name: "Face Pull (Cable)", groups: [.shoulders, .back]),
        .init(name: "Front Raise (Dumbbell)", groups: [.shoulders]),
        .init(name: "Glute Bridge (Dumbbell) - 20lb", groups: [.glutes, .hamstrings]),
        .init(name: "Glute Kickback (Machine)", groups: [.glutes]),
        .init(name: "Hack Squat", groups: [.quads, .glutes]),
        .init(name: "Hammer Curl (Cable)", groups: [.biceps]),
        .init(name: "Hammer Curl (Dumbbell)", groups: [.biceps]),
        .init(name: "Hip Abductor (Machine)", groups: [.glutes]),
        .init(name: "Hip Adductor (Machine)", groups: [.quads]),
        .init(name: "Hip Thrust (Bodyweight)", groups: [.glutes, .hamstrings]),
        .init(name: "Hip Thrust Machine", groups: [.glutes, .hamstrings]),
        .init(name: "Incline Bench Press (Smith Machine)", groups: [.chest, .shoulders, .triceps]),
        .init(name: "Incline Curl (Dumbbell)", groups: [.biceps]),
        .init(name: "Lat Pulldown (Cable)", groups: [.back, .biceps]),
        .init(name: "Lat Pulldown (Machine)", groups: [.back, .biceps]),
        .init(name: "Lateral Raise (Cable)", groups: [.shoulders]),
        .init(name: "Lateral Raise (Dumbbell)", groups: [.shoulders]),
        .init(name: "Lateral Raise (Machine)", groups: [.shoulders]),
        .init(name: "Leg Extension (Machine)", groups: [.quads]),
        .init(name: "Leg Press", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Lying Leg Curl (Machine)", groups: [.hamstrings]),
        .init(name: "MTS Abdominal Crunch", groups: [.core]),
        .init(name: "MTS Row", groups: [.back, .biceps]),
        .init(name: "Overhead Press (Dumbbell)", groups: [.shoulders, .triceps]),
        .init(name: "Overhead Press (Machine)", groups: [.shoulders, .triceps]),
        .init(name: "Overhead Tricep Extensions with Cable (low to high)", groups: [.triceps]),
        .init(name: "Plank", groups: [.core]),
        .init(name: "Preacher Curl (Barbell)", groups: [.biceps]),
        .init(name: "Preacher Curl (Machine)", groups: [.biceps]),
        .init(name: "Pull Up (Assisted)", groups: [.back, .biceps]),
        .init(name: "Push Up", groups: [.chest, .triceps, .shoulders]),
        .init(name: "Reverse Crunch", groups: [.core]),
        .init(name: "Reverse Curl (Barbell)", groups: [.biceps]),
        .init(name: "Reverse Fly (Machine)", groups: [.shoulders, .back]),
        .init(name: "Reverse Plank", groups: [.core, .glutes, .hamstrings]),
        .init(name: "Romanian Deadlift (Dumbbell)", groups: [.hamstrings, .glutes, .back]),
        .init(name: "Rotary Torso Machine", groups: [.core]),
        .init(name: "Running (Treadmill)", groups: [.cardio]),
        .init(name: "Seated Calf Raise (Plate Loaded)", groups: [.calves]),
        .init(name: "Seated Leg Curl (Machine)", groups: [.hamstrings]),
        .init(name: "Seated Leg Press (Machine)", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Seated Overhead Press (Dumbbell)", groups: [.shoulders, .triceps]),
        .init(name: "Seated Palms Down Wrist Curl (Dumbbell)", groups: [.biceps]),
        .init(name: "Seated Palms Up Wrist Curl (Dumbbell)", groups: [.biceps]),
        .init(name: "Seated Row (Cable)", groups: [.back, .biceps]),
        .init(name: "Seated Row (Machine)", groups: [.back, .biceps]),
        .init(name: "Shoulder Press (Machine)", groups: [.shoulders, .triceps]),
        .init(name: "Shrug (Barbell)", groups: [.back]),
        .init(name: "Shrug (Dumbbell)", groups: [.back]),
        .init(name: "Shrug (Smith Machine)", groups: [.back]),
        .init(name: "Side Leg Raises", groups: [.glutes]),
        .init(name: "Single Arm Tricep Extension (dumbell)", groups: [.triceps]),
        .init(name: "Single-Leg RDL", groups: [.hamstrings, .glutes, .core]),
        .init(name: "Skullcrusher (Barbell)", groups: [.triceps]),
        .init(name: "Squat (Dumbbell)", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Squat (Smith Machine)", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Stair Stepper", groups: [.cardio, .glutes, .quads]),
        .init(name: "Standing Calf Raise (Bodyweight)", groups: [.calves]),
        .init(name: "Standing Calf Raise (Dumbbell)", groups: [.calves]),
        .init(name: "Standing Calf Raise (Machine)", groups: [.calves]),
        .init(name: "Standing Calf Raise (Smith Machine)", groups: [.calves]),
        .init(name: "Superman", groups: [.back, .glutes, .hamstrings]),
        .init(name: "Tricep Overhead Extension With Rope", groups: [.triceps]),
        .init(name: "Triceps Dip (Assisted)", groups: [.triceps, .chest, .shoulders]),
        .init(name: "Triceps Extension (Dumbbell)", groups: [.triceps]),
        .init(name: "Triceps Extension (Machine)", groups: [.triceps]),
        .init(name: "Triceps Kickback (dumbbell)", groups: [.triceps]),
        .init(name: "Triceps Press Machine", groups: [.triceps]),
        .init(name: "Triceps Pushdown (Cable - Straight Bar)", groups: [.triceps]),
        .init(name: "Upright Row (Dumbbell)", groups: [.shoulders, .back]),
        .init(name: "V-bar Pulldown", groups: [.back, .biceps])
    ]

    private static func builtInTags(_ groups: [MuscleGroup]) -> [MuscleTag] {
        groups.map { MuscleTag.builtIn($0) }
    }

    /// Default mappings are derived from the curated catalog above.
    /// Additional keys below act as aliases for common naming variants found in imports.
    private static let defaultMappings: [String: [MuscleTag]] = {
        var mappings: [String: [MuscleTag]] = Dictionary(
            uniqueKeysWithValues: defaultExerciseCatalog.map { entry in
                (entry.name, builtInTags(entry.groups))
            }
        )

        // Alias/legacy names (not shown in the picker).
        let aliases: [String: [MuscleTag]] = [
            "Push Ups": builtInTags([.chest, .triceps, .shoulders]),
            "Pull Up": builtInTags([.back, .biceps]),
            "Chin Up": builtInTags([.back, .biceps]),
            "Barbell Row": builtInTags([.back, .biceps]),
            "Deadlift (Barbell)": builtInTags([.hamstrings, .glutes, .back]),
            "Overhead Press (Barbell)": builtInTags([.shoulders, .triceps]),
            "Squat (Barbell)": builtInTags([.quads, .glutes, .hamstrings]),
            "Lunges": builtInTags([.quads, .glutes, .hamstrings]),
            "Incline Bench Press (Barbell)": builtInTags([.chest, .shoulders, .triceps]),
            "Dumbbell Press": builtInTags([.chest, .triceps, .shoulders]),
            "Stair stepper": builtInTags([.cardio, .glutes, .quads]),
            "Cycling": builtInTags([.cardio]),
            "Elliptical": builtInTags([.cardio])
        ]

        mappings.merge(aliases) { current, _ in current }
        return mappings
    }()

    init() {
        loadMappings()
    }

    func resolvedTags(for exerciseName: String) -> [MuscleTag] {
        if let override = muscleTagOverrides[exerciseName] {
            return override
        }
        return Self.defaultMappings[exerciseName] ?? []
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
        Self.defaultMappings[exerciseName] ?? []
    }

    func hasDefaultTags(for exerciseName: String) -> Bool {
        Self.defaultMappings[exerciseName] != nil
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
            variants.min { lhs, rhs in
                let insensitive = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if insensitive != .orderedSame { return insensitive == .orderedAscending }
                let sensitive = lhs.displayName.localizedCompare(rhs.displayName)
                if sensitive != .orderedSame { return sensitive == .orderedAscending }
                return lhs.value.count < rhs.value.count
            }
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
                guard tag.builtInGroup != nil else { return nil }
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
            case let (left?, right?):
                return (builtInOrder[left] ?? 0) < (builtInOrder[right] ?? 0)
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
