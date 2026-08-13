import Combine
import Foundation

class ExerciseMetadataManager: ObservableObject {
    static let shared = ExerciseMetadataManager()

    /// A curated list of built-in exercises that should appear in pickers even before any workouts exist.
    /// CSV entries lead the list; still-valid legacy entries remain available without duplicating renamed rows.
    static let defaultExerciseNames: [String] = {
        let hiddenLegacyNames: Set<String> = [
            "Single Arm Tricep Extension (dumbell)",
            "Single Leg Leg Curl (Left)",
            "Single Leg Leg Curl (Right)"
        ]
        var seen = Set<String>()
        return (DefaultExerciseCatalog.entries.map(\.name) + defaultExerciseCatalog.map(\.name))
            .filter { !hiddenLegacyNames.contains($0) }
            .filter { seen.insert(ExerciseIdentityResolver.normalizedName($0)).inserted }
    }()

    /// Parent/side relationships that ship with the built-in exercise catalog.
    static let defaultExerciseRelationships: [ExerciseRelationship] = DefaultExerciseCatalog.relationships

    /// User overrides. If a key is present with an empty array, that exercise is explicitly untagged.
    @Published private(set) var muscleAssignmentOverrides: [String: [ExerciseMuscleAssignment]] = [:] {
        didSet { revision &+= 1 }
    }

    /// Compatibility view for code and older backup formats that only understand flat tags.
    var muscleTagOverrides: [String: [MuscleTag]] {
        muscleAssignmentOverrides.mapValues { $0.map(\.tag) }
    }

    private(set) var revision: UInt64 = 0

    private let userDefaults: UserDefaults
    static let assignmentMetadataKey = "ExerciseMuscleAssignments"
    static let legacyMetadataKey = "ExerciseMetadata"

    private struct CatalogEntry {
        let name: String
        let groups: [MuscleGroup]

        var assignments: [ExerciseMuscleAssignment] {
            let primaryCount = name == "Deadlift (Barbell)" ? 2 : 1
            return groups.enumerated().map { index, group in
                ExerciseMuscleAssignment(
                    tag: .builtIn(group),
                    role: index < primaryCount ? .primary : .secondary
                )
            }
        }
    }

    /// Legacy built-ins retained for compatibility and for valid exercises omitted from the latest CSV.
    private static let defaultExerciseCatalog: [CatalogEntry] = [
        .init(name: "45\u{00B0} Donkey Calf", groups: [.calves]),
        .init(name: "Arnold Press (Dumbbell)", groups: [.shoulders, .triceps]),
        .init(name: "Back Extension", groups: [.back, .glutes, .hamstrings]),
        .init(name: "Back Extension (Machine)", groups: [.back, .glutes, .hamstrings]),
        .init(name: "Barbell Row", groups: [.back, .biceps]),
        .init(name: "Bayesian Curl", groups: [.biceps]),
        .init(name: "Bench Press - Close Grip (Barbell)", groups: [.triceps, .chest, .shoulders]),
        .init(name: "Bench Press (Barbell)", groups: [.chest, .triceps, .shoulders]),
        .init(name: "Bent Over One Arm Row (Dumbbell)", groups: [.back, .biceps]),
        .init(name: "Bent Over Row (Dumbbell)", groups: [.back, .biceps]),
        .init(name: "Bicep Curl (Barbell)", groups: [.biceps]),
        .init(name: "Bicep Curl (Cable)", groups: [.biceps]),
        .init(name: "Bicep Curl (Dumbbell)", groups: [.biceps]),
        .init(name: "Bicep Curl (Machine)", groups: [.biceps]),
        .init(name: "Bicep Curl (Machine) (Bands)", groups: [.biceps]),
        .init(name: "Bulgarian Split Squat", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Calf Extension Machine", groups: [.calves]),
        .init(name: "Calf Press on Seated Leg Press", groups: [.calves]),
        .init(name: "Chest Fly", groups: [.chest]),
        .init(name: "Chest Fly (Dumbbell)", groups: [.chest]),
        .init(name: "Chest Press (Machine)", groups: [.chest, .triceps, .shoulders]),
        .init(name: "Chin Up", groups: [.back, .biceps]),
        .init(name: "Crunch", groups: [.core]),
        .init(name: "Crunch (Machine)", groups: [.core]),
        .init(name: "Cycling", groups: [.cardio]),
        .init(name: "Cycling (Indoor)", groups: [.cardio]),
        .init(name: "Deadlift (Barbell)", groups: [.hamstrings, .glutes, .back]),
        .init(name: "Deadlift (Smith Machine)", groups: [.hamstrings, .glutes, .back]),
        .init(name: "Dumbbell Press", groups: [.chest, .triceps, .shoulders]),
        .init(name: "Elliptical", groups: [.cardio]),
        .init(name: "Elliptical Machine", groups: [.cardio]),
        .init(name: "EZ Bar Curl", groups: [.biceps]),
        .init(name: "Face Pull (Cable)", groups: [.back, .shoulders, .traps]),
        .init(name: "Front Raise (Dumbbell)", groups: [.shoulders]),
        .init(name: "Glute Bridge (Dumbbell) - 20lb", groups: [.glutes, .hamstrings]),
        .init(name: "Glute Kickback (Machine)", groups: [.glutes]),
        .init(name: "Goblet Squat (Kettlebell)", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Hack Squat", groups: [.quads, .glutes]),
        .init(name: "Hammer Curl (Cable)", groups: [.biceps, .forearms]),
        .init(name: "Hammer Curl (Dumbbell)", groups: [.biceps, .forearms]),
        .init(name: "Hip Abductor (Cable)", groups: [.glutes]),
        .init(name: "Hip Abductor (Machine)", groups: [.glutes]),
        .init(name: "Hip Adductor (Cable)", groups: [.adductors]),
        .init(name: "Hip Adductor (Machine)", groups: [.adductors]),
        .init(name: "Hip Thrust (Bodyweight)", groups: [.glutes, .hamstrings]),
        .init(name: "Hip Thrust Machine", groups: [.glutes, .hamstrings]),
        .init(name: "Incline Bench Press (Dumbbell)", groups: [.chest, .shoulders, .triceps]),
        .init(name: "Incline Bench Press (Smith Machine)", groups: [.chest, .shoulders, .triceps]),
        .init(name: "Incline Bench Press (Barbell)", groups: [.chest, .shoulders, .triceps]),
        .init(name: "Incline Chest Press (Machine)", groups: [.chest, .shoulders, .triceps]),
        .init(name: "Incline Curl (Dumbbell)", groups: [.biceps]),
        .init(name: "Iso-Lateral Row (Machine)", groups: [.back, .biceps]),
        .init(name: "Knee Raise (Captain's Chair)", groups: [.core]),
        .init(name: "Lat Pulldown (Cable)", groups: [.back, .biceps]),
        .init(name: "Lat Pulldown (Machine)", groups: [.back, .biceps]),
        .init(name: "Lateral Raise (Cable)", groups: [.shoulders]),
        .init(name: "Lateral Raise (Dumbbell)", groups: [.shoulders]),
        .init(name: "Lateral Raise (Machine)", groups: [.shoulders]),
        .init(name: "Leg Extension (Machine)", groups: [.quads]),
        .init(name: "Leg Press", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Lunge (Dumbbell)", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Lunges", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Lying Leg Curl (Machine)", groups: [.hamstrings]),
        .init(name: "MTS Abdominal Crunch", groups: [.core]),
        .init(name: "MTS Row", groups: [.back, .biceps]),
        .init(name: "Overhead Press (Barbell)", groups: [.shoulders, .triceps]),
        .init(name: "Overhead Press (Dumbbell)", groups: [.shoulders, .triceps]),
        .init(name: "Overhead Press (Machine)", groups: [.shoulders, .triceps]),
        .init(name: "Overhead Tricep Extensions (single arm, no attachment)", groups: [.triceps]),
        .init(name: "Overhead Tricep Extensions with Cable (low to high)", groups: [.triceps]),
        .init(name: "Plank", groups: [.core]),
        .init(name: "Preacher Curl (Barbell)", groups: [.biceps]),
        .init(name: "Preacher Curl (Machine)", groups: [.biceps]),
        .init(name: "Pull Up", groups: [.back, .biceps]),
        .init(name: "Pull Up (Assisted)", groups: [.back, .biceps]),
        .init(name: "Push Up", groups: [.chest, .triceps, .shoulders]),
        .init(name: "RDL (Kettlebell)", groups: [.hamstrings, .glutes]),
        .init(name: "Reverse Crunch", groups: [.core]),
        .init(name: "Reverse Curl (Barbell)", groups: [.biceps, .forearms]),
        .init(name: "Reverse Curl (EZ Bar)", groups: [.biceps, .forearms]),
        .init(name: "Reverse Fly (Dumbbell)", groups: [.back, .shoulders, .traps]),
        .init(name: "Reverse Fly (Machine)", groups: [.back, .shoulders, .traps]),
        .init(name: "Reverse Plank", groups: [.core, .glutes, .hamstrings]),
        .init(name: "Romanian Deadlift (Dumbbell)", groups: [.hamstrings, .glutes]),
        .init(name: "Romanian Deadlift (Smith Machine)", groups: [.hamstrings, .glutes]),
        .init(name: "Rotary Torso Machine", groups: [.core]),
        .init(name: "Running (Treadmill)", groups: [.cardio]),
        .init(name: "Seated Calf Raise (Plate Loaded)", groups: [.calves]),
        .init(name: "Seated Leg Curl (Machine)", groups: [.hamstrings]),
        .init(name: "Seated Leg Press (Machine)", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Seated Overhead Press (Dumbbell)", groups: [.shoulders, .triceps]),
        .init(name: "Seated Palms Down Wrist Curl (Dumbbell)", groups: [.forearms]),
        .init(name: "Seated Palms Up Wrist Curl (Dumbbell)", groups: [.forearms]),
        .init(name: "Seated Row (Cable)", groups: [.back, .biceps]),
        .init(name: "Seated Row (Machine)", groups: [.back, .biceps]),
        .init(name: "Shoulder Press (Machine)", groups: [.shoulders, .triceps]),
        .init(name: "Shrug (Barbell)", groups: [.back, .traps]),
        .init(name: "Shrug (Dumbbell)", groups: [.back, .traps]),
        .init(name: "Shrug (Smith Machine)", groups: [.back, .traps]),
        .init(name: "Side Leg Raises", groups: [.glutes]),
        .init(name: "Single Arm Tricep Extension (dumbell)", groups: [.triceps]),
        .init(name: "Single Leg Leg Curl (Left)", groups: [.hamstrings]),
        .init(name: "Single Leg Leg Curl (Right)", groups: [.hamstrings]),
        .init(name: "Single Leg Leg Extension (Left)", groups: [.quads]),
        .init(name: "Single Leg Leg Extension (Right)", groups: [.quads]),
        .init(name: "Single-Arm Overhead Cable Extension", groups: [.triceps]),
        .init(name: "Single-Leg RDL", groups: [.hamstrings, .glutes, .core]),
        .init(name: "Skullcrusher (Barbell)", groups: [.triceps]),
        .init(name: "Squat (Band)", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Squat (Barbell)", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Squat (Dumbbell)", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Squat (Smith Machine)", groups: [.quads, .glutes, .hamstrings]),
        .init(name: "Stair Stepper", groups: [.cardio]),
        .init(name: "Straight Arm Pulldown", groups: [.back]),
        .init(name: "Standing Calf Raise (Bodyweight)", groups: [.calves]),
        .init(name: "Standing Calf Raise (Dumbbell)", groups: [.calves]),
        .init(name: "Standing Calf Raise (Machine)", groups: [.calves]),
        .init(name: "Standing Calf Raise (Smith Machine)", groups: [.calves]),
        .init(name: "Superman", groups: [.back, .glutes, .hamstrings]),
        .init(name: "T Bar Row", groups: [.back, .biceps]),
        .init(name: "Tricep Overhead Extension With Rope", groups: [.triceps]),
        .init(name: "Triceps Dip", groups: [.chest, .shoulders, .triceps]),
        .init(name: "Triceps Dip (Assisted)", groups: [.triceps, .chest, .shoulders]),
        .init(name: "Triceps Extension (Dumbbell)", groups: [.triceps]),
        .init(name: "Triceps Extension (Machine)", groups: [.triceps]),
        .init(name: "Triceps Kickback (dumbbell)", groups: [.triceps]),
        .init(name: "Triceps Press Machine", groups: [.triceps]),
        .init(name: "Triceps Pushdown (Cable - Straight Bar)", groups: [.triceps]),
        .init(name: "Upright Row (Dumbbell)", groups: [.back, .shoulders, .traps]),
        .init(name: "V-bar Pulldown", groups: [.back, .biceps]),
        .init(name: "Walking (Treadmill)", groups: [.cardio])
    ]

    private static func builtInAssignments(_ groups: [MuscleGroup]) -> [ExerciseMuscleAssignment] {
        groups.enumerated().map { index, group in
            ExerciseMuscleAssignment(
                tag: .builtIn(group),
                role: index == 0 ? .primary : .secondary
            )
        }
    }

    /// Default mappings merge the legacy catalog with the latest CSV. CSV values win when a row was revised.
    /// Additional keys below preserve common import/name variants without creating duplicate picker entries.
    private static let defaultMappings: [String: [ExerciseMuscleAssignment]] = {
        var mappings: [String: [ExerciseMuscleAssignment]] = Dictionary(
            uniqueKeysWithValues: defaultExerciseCatalog.map { entry in
                (entry.name, entry.assignments)
            }
        )

        for entry in DefaultExerciseCatalog.entries {
            mappings[entry.name] = entry.assignments
        }

        let compatibilityMappings: [String: [ExerciseMuscleAssignment]] = [
            // Strong exports contain these historical spelling variants. Keep the picker
            // canonical while still tagging imported workouts under their original names.
            "Hallow Hold": builtInAssignments([.core]),
            "Kneeling Bilateral Lat Pulldown - Kinesis Machind": builtInAssignments([.back, .biceps]),
            "Push Ups": builtInAssignments([.chest, .triceps, .shoulders]),
            "Stair stepper": builtInAssignments([.cardio])
        ]

        mappings.merge(compatibilityMappings) { current, _ in current }
        return mappings
    }()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadMappings()
    }

    func resolvedAssignments(for exerciseName: String) -> [ExerciseMuscleAssignment] {
        if let override = muscleAssignmentOverrides[exerciseName] {
            return override
        }
        if let relationship = ExerciseRelationshipManager.shared.relationship(for: exerciseName) {
            if let parentOverride = muscleAssignmentOverrides[relationship.parentName] {
                return parentOverride
            }
            return Self.defaultMappings[relationship.parentName] ?? []
        }
        return Self.defaultMappings[exerciseName] ?? []
    }

    func resolvedTags(for exerciseName: String) -> [MuscleTag] {
        resolvedAssignments(for: exerciseName).map(\.tag)
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

    /// Returns resolved role-aware assignments for all provided exercise names.
    func resolvedAssignmentMappings(
        for exerciseNames: Set<String>,
        includeUntagged: Bool = false,
        resolver: ExerciseIdentityResolver? = nil
    ) -> [String: [ExerciseMuscleAssignment]] {
        var result = exerciseNames.reduce(into: [String: [ExerciseMuscleAssignment]]()) { result, name in
            let assignments = resolvedAssignments(for: name)
            if includeUntagged || !assignments.isEmpty {
                result[name] = assignments
            }
        }

        // Muscle analytics operate on relationship-aggregated exercise names. Include
        // those parent identities even when the input only contains left/right children.
        if let resolver {
            let aggregateNames = Set(exerciseNames.map { resolver.aggregateName(for: $0) })
            for aggregateName in aggregateNames {
                let assignments = resolvedAssignments(for: aggregateName)
                if includeUntagged || !assignments.isEmpty {
                    result[aggregateName] = assignments
                } else {
                    result.removeValue(forKey: aggregateName)
                }
            }
        }

        return result
    }

    func defaultAssignments(for exerciseName: String) -> [ExerciseMuscleAssignment] {
        if let direct = Self.defaultMappings[exerciseName] {
            return direct
        }
        if let relationship = ExerciseRelationshipManager.shared.relationship(for: exerciseName) {
            return Self.defaultMappings[relationship.parentName] ?? []
        }
        return []
    }

    func defaultTags(for exerciseName: String) -> [MuscleTag] {
        defaultAssignments(for: exerciseName).map(\.tag)
    }

    func hasDefaultTags(for exerciseName: String) -> Bool {
        !defaultTags(for: exerciseName).isEmpty
    }

    func isOverridden(for exerciseName: String) -> Bool {
        muscleAssignmentOverrides[exerciseName] != nil
    }

    func resetToDefault(for exerciseName: String) {
        muscleAssignmentOverrides.removeValue(forKey: exerciseName)
        saveMappings()
    }

    func clearTags(for exerciseName: String) {
        setTags(for: exerciseName, to: [])
    }

    func setTags(for exerciseName: String, to tags: [MuscleTag]) {
        // Flat callers predate roles, so preserve their former full-credit semantics.
        setAssignments(for: exerciseName, to: tags.map { .primary($0) })
    }

    func setAssignments(
        for exerciseName: String,
        to assignments: [ExerciseMuscleAssignment]
    ) {
        let canonical = canonicalize(assignments)
        let defaultCanonical = canonicalize(defaultAssignments(for: exerciseName))

        if canonical == defaultCanonical {
            // No override needed: fall back to defaults.
            muscleAssignmentOverrides.removeValue(forKey: exerciseName)
        } else {
            muscleAssignmentOverrides[exerciseName] = canonical
        }
        saveMappings()
    }

    func role(for exerciseName: String, tag: MuscleTag) -> ExerciseMuscleRole? {
        resolvedAssignments(for: exerciseName)
            .first(where: { $0.tag.id == tag.id })?
            .role
    }

    func setRole(
        for exerciseName: String,
        tag: MuscleTag,
        role: ExerciseMuscleRole?
    ) {
        var current = resolvedAssignments(for: exerciseName)
        current.removeAll { $0.tag.id == tag.id }
        if let role {
            current.append(ExerciseMuscleAssignment(tag: tag, role: role))
        }
        setAssignments(for: exerciseName, to: current)
    }

    func toggleTag(for exerciseName: String, tag: MuscleTag) {
        var current = resolvedAssignments(for: exerciseName)
        let canonicalTagId = tag.id

        if let index = current.firstIndex(where: { $0.tag.id == canonicalTagId }) {
            current.remove(at: index)
        } else {
            let role: ExerciseMuscleRole = current.contains(where: { $0.role == .primary })
                ? .secondary
                : .primary
            current.append(ExerciseMuscleAssignment(tag: tag, role: role))
        }

        setAssignments(for: exerciseName, to: current)
    }

    func addCustomTag(for exerciseName: String, name: String) {
        guard let tag = MuscleTag.custom(name) else { return }
        var current = resolvedAssignments(for: exerciseName)
        if current.contains(where: { $0.tag.id == tag.id }) { return }
        let role: ExerciseMuscleRole = current.contains(where: { $0.role == .primary })
            ? .secondary
            : .primary
        current.append(ExerciseMuscleAssignment(tag: tag, role: role))
        setAssignments(for: exerciseName, to: current)
    }

    var knownCustomTags: [MuscleTag] {
        let all = muscleAssignmentOverrides.values
            .flatMap { $0 }
            .map(\.tag)
            .filter { $0.kind == .custom }
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

    @discardableResult
    func mergeOverridesFromBackup(_ overrides: [String: [MuscleTag]]) -> (inserted: Int, skipped: Int) {
        mergeAssignmentOverridesFromBackup(
            overrides.mapValues { tags in tags.map { .primary($0) } }
        )
    }

    @discardableResult
    func mergeAssignmentOverridesFromBackup(
        _ overrides: [String: [ExerciseMuscleAssignment]],
        legacyTagOverrides: [String: [MuscleTag]] = [:]
    ) -> (inserted: Int, skipped: Int) {
        var mergedOverrides = overrides
        for (exerciseName, tags) in legacyTagOverrides where mergedOverrides[exerciseName] == nil {
            mergedOverrides[exerciseName] = tags.map { .primary($0) }
        }

        guard !mergedOverrides.isEmpty else { return (0, 0) }

        var inserted = 0
        var skipped = 0
        for (exerciseName, assignments) in mergedOverrides {
            guard muscleAssignmentOverrides[exerciseName] == nil else {
                skipped += 1
                continue
            }

            muscleAssignmentOverrides[exerciseName] = canonicalize(assignments)
            inserted += 1
        }

        if inserted > 0 {
            saveMappings()
        }

        return (inserted, skipped)
    }

    func clearOverrides() {
        muscleAssignmentOverrides = [:]
        userDefaults.removeObject(forKey: Self.assignmentMetadataKey)
        userDefaults.removeObject(forKey: Self.legacyMetadataKey)
    }

    // MARK: - Persistence

    private func loadMappings() {
        if let data = userDefaults.data(forKey: Self.assignmentMetadataKey),
           let saved = try? JSONDecoder().decode(
               [String: [ExerciseMuscleAssignment]].self,
               from: data
           ) {
            muscleAssignmentOverrides = saved.mapValues(canonicalize)
            return
        }

        guard let data = userDefaults.data(forKey: Self.legacyMetadataKey) else { return }

        if let saved = try? JSONDecoder().decode([String: [MuscleTag]].self, from: data) {
            muscleAssignmentOverrides = saved.mapValues { tags in
                canonicalize(tags.map { .primary($0) })
            }
            saveMappings()
            return
        }

        // Legacy: [String: MuscleGroup]
        if let saved = try? JSONDecoder().decode([String: MuscleGroup].self, from: data) {
            muscleAssignmentOverrides = saved.mapValues { [.primary(.builtIn($0))] }
            saveMappings()
            return
        }
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(muscleAssignmentOverrides) {
            userDefaults.set(data, forKey: Self.assignmentMetadataKey)
        }
    }

    private func canonicalize(
        _ assignments: [ExerciseMuscleAssignment]
    ) -> [ExerciseMuscleAssignment] {
        var byTagID: [String: ExerciseMuscleAssignment] = [:]
        for assignment in assignments {
            let tag = assignment.tag
            let validTag: MuscleTag?
            switch tag.kind {
            case .builtIn:
                validTag = tag.builtInGroup == nil ? nil : tag
            case .custom:
                validTag = tag.displayName.isEmpty ? nil : tag
            }
            guard let validTag else { continue }

            let normalizedRole: ExerciseMuscleRole = validTag.builtInGroup == .cardio
                ? .primary
                : assignment.role
            let candidate = ExerciseMuscleAssignment(tag: validTag, role: normalizedRole)
            if let existing = byTagID[validTag.id], existing.role == .primary {
                continue
            }
            byTagID[validTag.id] = candidate
        }

        var cleaned = Array(byTagID.values)
        if !cleaned.isEmpty, !cleaned.contains(where: { $0.role == .primary }),
           let promoted = cleaned.indices.min(by: { assignmentSortKey(cleaned[$0]) < assignmentSortKey(cleaned[$1]) }) {
            cleaned[promoted] = .primary(cleaned[promoted].tag)
        }

        return cleaned.sorted { assignmentSortKey($0) < assignmentSortKey($1) }
    }

    private func assignmentSortKey(
        _ assignment: ExerciseMuscleAssignment
    ) -> String {
        let roleOrder = assignment.role == .primary ? "0" : "1"
        if let group = assignment.tag.builtInGroup,
           let groupIndex = MuscleGroup.allCases.firstIndex(of: group) {
            return "\(roleOrder)|0|\(String(format: "%03d", groupIndex))"
        }
        return "\(roleOrder)|1|\(assignment.tag.displayName.lowercased())"
    }
}
