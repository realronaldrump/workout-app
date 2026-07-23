import Combine
import Foundation

// Relationship resolution, aggregation, and persisted editing intentionally share this domain file.
// swiftlint:disable file_length

nonisolated enum ExerciseLaterality: String, Codable, CaseIterable, Hashable, Sendable {
    case left
    case right
    case unilateral

    var displayName: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .unilateral:
            return "Unilateral"
        }
    }

    var shortLabel: String {
        switch self {
        case .left:
            return "L"
        case .right:
            return "R"
        case .unilateral:
            return "1S"
        }
    }
}

nonisolated struct ExerciseRelationship: Codable, Hashable, Identifiable, Sendable {
    var exerciseName: String
    var parentName: String
    var laterality: ExerciseLaterality
    var schemaVersion: Int

    var id: String { ExerciseIdentityResolver.normalizedName(exerciseName) }

    init(
        exerciseName: String,
        parentName: String,
        laterality: ExerciseLaterality,
        schemaVersion: Int = 1
    ) {
        self.exerciseName = ExerciseIdentityResolver.trimmedName(exerciseName)
        self.parentName = ExerciseIdentityResolver.trimmedName(parentName)
        self.laterality = laterality
        self.schemaVersion = schemaVersion
    }
}

nonisolated struct ExerciseDisplayIdentity: Hashable, Sendable {
    let rawName: String
    let aggregateName: String
    let laterality: ExerciseLaterality?

    var isVariant: Bool { laterality != nil }
    var sideLabel: String? { laterality?.displayName }
}

nonisolated struct ExerciseRelationshipSuggestion: Hashable, Sendable {
    let exerciseName: String
    let parentName: String
    let laterality: ExerciseLaterality
}

nonisolated struct ExerciseRelationshipAutoLinkResult: Hashable, Sendable {
    let created: [ExerciseRelationship]
    let skipped: Int

    static let empty = ExerciseRelationshipAutoLinkResult(created: [], skipped: 0)
}

nonisolated struct ExerciseIdentityResolver: Hashable, Sendable {
    private let relationshipsByNormalizedName: [String: ExerciseRelationship]

    private struct SideNamePattern {
        let prefix: String
        let suffix: String
        let laterality: ExerciseLaterality
    }

    private struct SideNameComponents {
        let baseName: String
        let laterality: ExerciseLaterality
    }

    init(relationships: [String: ExerciseRelationship] = [:]) {
        var canonical: [String: ExerciseRelationship] = [:]
        canonical.reserveCapacity(relationships.count)
        for relationship in relationships.values {
            let child = Self.trimmedName(relationship.exerciseName)
            let parent = Self.trimmedName(relationship.parentName)
            guard !child.isEmpty, !parent.isEmpty else { continue }
            guard Self.normalizedName(child) != Self.normalizedName(parent) else { continue }
            canonical[Self.normalizedName(child)] = ExerciseRelationship(
                exerciseName: child,
                parentName: parent,
                laterality: relationship.laterality,
                schemaVersion: relationship.schemaVersion
            )
        }
        relationshipsByNormalizedName = canonical
    }

    static var empty: ExerciseIdentityResolver {
        ExerciseIdentityResolver()
    }

    @MainActor static var current: ExerciseIdentityResolver {
        ExerciseRelationshipManager.shared.resolverSnapshot()
    }

    var relationships: [String: ExerciseRelationship] {
        relationshipsByNormalizedName
    }

    func relationship(for exerciseName: String) -> ExerciseRelationship? {
        relationshipsByNormalizedName[Self.normalizedName(exerciseName)]
    }

    func aggregateName(for exerciseName: String) -> String {
        let trimmed = Self.trimmedName(exerciseName)
        guard !trimmed.isEmpty else { return exerciseName }

        var current = trimmed
        var seen: Set<String> = []
        while let relationship = relationship(for: current) {
            let key = Self.normalizedName(current)
            guard seen.insert(key).inserted else { break }
            let parent = Self.trimmedName(relationship.parentName)
            guard !parent.isEmpty else { break }
            current = parent
        }

        return current
    }

    func performanceTrackName(for exerciseName: String) -> String {
        let trimmed = Self.trimmedName(exerciseName)
        return trimmed.isEmpty ? exerciseName : trimmed
    }

    func children(of parentName: String) -> [ExerciseRelationship] {
        let parentKey = Self.normalizedName(parentName)
        return relationshipsByNormalizedName.values
            .filter { Self.normalizedName($0.parentName) == parentKey }
            .sorted { lhs, rhs in
                let sideOrder: [ExerciseLaterality: Int] = [.left: 0, .right: 1, .unilateral: 2]
                let lhsOrder = sideOrder[lhs.laterality] ?? Int.max
                let rhsOrder = sideOrder[rhs.laterality] ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.exerciseName.localizedCaseInsensitiveCompare(rhs.exerciseName) == .orderedAscending
            }
    }

    func displayIdentity(for exerciseName: String) -> ExerciseDisplayIdentity {
        let rawName = performanceTrackName(for: exerciseName)
        let relationship = relationship(for: rawName)
        return ExerciseDisplayIdentity(
            rawName: rawName,
            aggregateName: aggregateName(for: rawName),
            laterality: relationship?.laterality
        )
    }

    func containsRelationship(for exerciseName: String) -> Bool {
        relationship(for: exerciseName) != nil
    }

    static func trimmedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedName(_ name: String) -> String {
        trimmedName(name).lowercased()
    }

    static func inferredSuggestion(
        for exerciseName: String,
        knownExerciseNames: Set<String>
    ) -> ExerciseRelationshipSuggestion? {
        let trimmed = trimmedName(exerciseName)
        guard !trimmed.isEmpty else { return nil }

        guard let components = sideNameComponents(for: trimmed),
              let parent = uniqueParentName(
                forBaseName: components.baseName,
                knownExerciseNames: knownExerciseNames,
                excludingExerciseName: trimmed
              ) else { return nil }

        return ExerciseRelationshipSuggestion(
            exerciseName: trimmed,
            parentName: parent,
            laterality: components.laterality
        )
    }

    static func inferredSuggestions(
        forParent parentName: String,
        knownExerciseNames: Set<String>
    ) -> [ExerciseRelationshipSuggestion] {
        let parent = trimmedName(parentName)
        let parentKey = normalizedName(parent)
        guard !parentKey.isEmpty else { return [] }

        return knownExerciseNames
            .compactMap { name -> ExerciseRelationshipSuggestion? in
                guard normalizedName(name) != parentKey else { return nil }
                guard let suggestion = inferredSuggestion(
                    for: name,
                    knownExerciseNames: knownExerciseNames
                ) else { return nil }
                return normalizedName(suggestion.parentName) == parentKey ? suggestion : nil
            }
            .sorted { lhs, rhs in
                let sideOrder: [ExerciseLaterality: Int] = [.left: 0, .right: 1, .unilateral: 2]
                let lhsOrder = sideOrder[lhs.laterality] ?? Int.max
                let rhsOrder = sideOrder[rhs.laterality] ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.exerciseName.localizedCaseInsensitiveCompare(rhs.exerciseName) == .orderedAscending
            }
    }

    private static var sideNamePatterns: [SideNamePattern] {
        [
            SideNamePattern(prefix: "Left ", suffix: "", laterality: .left),
            SideNamePattern(prefix: "Right ", suffix: "", laterality: .right),
            SideNamePattern(prefix: "L ", suffix: "", laterality: .left),
            SideNamePattern(prefix: "R ", suffix: "", laterality: .right),
            SideNamePattern(prefix: "", suffix: " - Left", laterality: .left),
            SideNamePattern(prefix: "", suffix: " - Right", laterality: .right),
            SideNamePattern(prefix: "", suffix: " (Left)", laterality: .left),
            SideNamePattern(prefix: "", suffix: " (Right)", laterality: .right),
            SideNamePattern(prefix: "", suffix: " Left", laterality: .left),
            SideNamePattern(prefix: "", suffix: " Right", laterality: .right)
        ]
    }

    private static func sideNameComponents(for exerciseName: String) -> SideNameComponents? {
        let trimmed = trimmedName(exerciseName)
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()

        for pattern in sideNamePatterns {
            if !pattern.prefix.isEmpty,
               lowercased.hasPrefix(pattern.prefix.lowercased()) {
                let base = String(trimmed.dropFirst(pattern.prefix.count))
                let canonicalBase = canonicalSideBaseName(base)
                guard !canonicalBase.isEmpty else { return nil }
                return SideNameComponents(baseName: canonicalBase, laterality: pattern.laterality)
            }

            if !pattern.suffix.isEmpty,
               lowercased.hasSuffix(pattern.suffix.lowercased()) {
                let base = String(trimmed.dropLast(pattern.suffix.count))
                let canonicalBase = canonicalSideBaseName(base)
                guard !canonicalBase.isEmpty else { return nil }
                return SideNameComponents(baseName: canonicalBase, laterality: pattern.laterality)
            }
        }

        return nil
    }

    private static func uniqueParentName(
        forBaseName baseName: String,
        knownExerciseNames: Set<String>,
        excludingExerciseName exerciseName: String
    ) -> String? {
        let childKey = normalizedName(exerciseName)
        let childBaseKeys = comparisonKeys(forBaseName: baseName)
        guard !childBaseKeys.isEmpty else { return nil }

        let matches = knownExerciseNames.reduce(into: [String: String]()) { result, candidate in
            let trimmedCandidate = trimmedName(candidate)
            let candidateKey = normalizedName(trimmedCandidate)
            guard !trimmedCandidate.isEmpty, candidateKey != childKey else { return }
            guard sideNameComponents(for: trimmedCandidate) == nil else { return }

            let parentKeys = comparisonKeys(forParentName: trimmedCandidate)
            guard !childBaseKeys.isDisjoint(with: parentKeys) else { return }
            result[candidateKey] = trimmedCandidate
        }

        guard matches.count == 1 else { return nil }
        return matches.values.first
    }

    private static func canonicalSideBaseName(_ name: String) -> String {
        let stripped = stripLeadingPhrases(
            from: stripParentheticalEquipment(from: name),
            phrases: unilateralLeadingPhrases
        )
        return collapsedWhitespace(stripped)
    }

    private static func comparisonKeys(forBaseName baseName: String) -> Set<String> {
        comparisonKeys(for: baseName, stripsPositionPhrases: false)
    }

    private static func comparisonKeys(forParentName parentName: String) -> Set<String> {
        comparisonKeys(for: parentName, stripsPositionPhrases: true)
    }

    private static func comparisonKeys(for name: String, stripsPositionPhrases: Bool) -> Set<String> {
        var keys: Set<String> = []
        let withoutEquipment = stripParentheticalEquipment(from: name)
        let withoutUnilateral = stripLeadingPhrases(from: withoutEquipment, phrases: unilateralLeadingPhrases)
        let collapsed = collapsedWhitespace(withoutUnilateral)
        let primary = normalizedComparisonName(collapsed)
        if !primary.isEmpty {
            keys.insert(primary)
        }

        if stripsPositionPhrases {
            let withoutPosition = stripLeadingPhrases(from: collapsed, phrases: positionalLeadingPhrases)
            let positionKey = normalizedComparisonName(withoutPosition)
            if !positionKey.isEmpty {
                keys.insert(positionKey)
            }
        }

        return keys
    }

    private static var unilateralLeadingPhrases: [String] {
        [
            "Single Leg ",
            "Single-Leg ",
            "Single Arm ",
            "Single-Arm ",
            "Single Side ",
            "Single-Side ",
            "One Leg ",
            "One-Leg ",
            "One Arm ",
            "One-Arm ",
            "Unilateral "
        ]
    }

    private static var positionalLeadingPhrases: [String] {
        [
            "Seated ",
            "Lying ",
            "Standing ",
            "Kneeling ",
            "Prone ",
            "Supine "
        ]
    }

    private static func stripLeadingPhrases(from name: String, phrases: [String]) -> String {
        var result = collapsedWhitespace(name)
        var didStrip = true
        while didStrip {
            didStrip = false
            for phrase in phrases where normalizedName(result).hasPrefix(normalizedName(phrase)) {
                result = String(result.dropFirst(phrase.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
                break
            }
        }
        return result
    }

    private static func stripParentheticalEquipment(from name: String) -> String {
        name.replacingOccurrences(
            of: #"\s*\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func collapsedWhitespace(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func normalizedComparisonName(_ name: String) -> String {
        collapsedWhitespace(name)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

nonisolated enum ExerciseAggregation {
    struct Summary: Hashable, Sendable {
        let volume: Double
        let exerciseCount: Int
        let setCount: Int
    }

    private struct Bucket {
        var entries: [(exercise: Exercise, relationship: ExerciseRelationship?)] = []
        var firstRank: Int = Int.max
    }

    static func aggregateExercises(in workout: Workout, resolver: ExerciseIdentityResolver) -> [Exercise] {
        var buckets: [String: Bucket] = [:]

        for (index, exercise) in workout.exercises.enumerated() {
            let aggregateName = resolver.aggregateName(for: exercise.name)
            let relationship = resolver.relationship(for: exercise.name)
            var bucket = buckets[aggregateName] ?? Bucket()
            bucket.entries.append((exercise, relationship))
            bucket.firstRank = min(bucket.firstRank, index)
            buckets[aggregateName] = bucket
        }

        return buckets
            .map { aggregateName, bucket in
                (
                    rank: bucket.firstRank,
                    exercise: Exercise(
                        name: aggregateName,
                        sets: creditedSets(
                            from: bucket.entries,
                            aggregateName: aggregateName
                        )
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.exercise.name.localizedCaseInsensitiveCompare(rhs.exercise.name) == .orderedAscending
            }
            .map(\.exercise)
    }

    static func totalVolume(for workouts: [Workout], resolver: ExerciseIdentityResolver) -> Double {
        workouts.reduce(0) { partial, workout in
            partial + totalVolume(for: workout, resolver: resolver)
        }
    }

    static func totalSets(for workouts: [Workout], resolver: ExerciseIdentityResolver) -> Int {
        workouts.reduce(0) { partial, workout in
            partial + totalSets(for: workout, resolver: resolver)
        }
    }

    static func totalVolume(for workout: Workout, resolver: ExerciseIdentityResolver) -> Double {
        summary(for: workout, resolver: resolver).volume
    }

    static func totalSets(for workout: Workout, resolver: ExerciseIdentityResolver) -> Int {
        summary(for: workout, resolver: resolver).setCount
    }

    static func exerciseCount(for workout: Workout, resolver: ExerciseIdentityResolver) -> Int {
        summary(for: workout, resolver: resolver).exerciseCount
    }

    static func summary(for workout: Workout, resolver: ExerciseIdentityResolver) -> Summary {
        let exercises = aggregateExercises(in: workout, resolver: resolver)
        return Summary(
            volume: exercises.reduce(0) { $0 + $1.totalVolume },
            exerciseCount: exercises.count,
            setCount: exercises.reduce(0) { $0 + $1.sets.count }
        )
    }

    static func historySessions(
        in workouts: [Workout],
        for exerciseName: String,
        includingVariants: Bool,
        resolver: ExerciseIdentityResolver
    ) -> [ExerciseHistorySession] {
        let targetName = ExerciseIdentityResolver.trimmedName(exerciseName)
        guard !targetName.isEmpty else { return [] }

        return workouts
            .compactMap { workout -> ExerciseHistorySession? in
                let matchingExercises: [Exercise]
                if includingVariants {
                    matchingExercises = aggregateExercises(in: workout, resolver: resolver).filter {
                        namesMatch($0.name, targetName)
                    }
                } else {
                    matchingExercises = workout.exercises.filter {
                        namesMatch(resolver.performanceTrackName(for: $0.name), targetName)
                    }
                }

                guard !matchingExercises.isEmpty else { return nil }
                return ExerciseHistorySession(
                    workoutId: workout.id,
                    date: workout.date,
                    sets: sorted(matchingExercises.flatMap(\.sets))
                )
            }
            .sorted { $0.date < $1.date }
    }

    private static func creditedSets(
        from entries: [(exercise: Exercise, relationship: ExerciseRelationship?)],
        aggregateName: String
    ) -> [WorkoutSet] {
        var directSets: [WorkoutSet] = []
        var leftSets: [WorkoutSet] = []
        var rightSets: [WorkoutSet] = []
        var unilateralSets: [WorkoutSet] = []

        for entry in entries {
            switch entry.relationship?.laterality {
            case .left:
                leftSets.append(contentsOf: entry.exercise.sets)
            case .right:
                rightSets.append(contentsOf: entry.exercise.sets)
            case .unilateral:
                unilateralSets.append(contentsOf: entry.exercise.sets)
            case nil:
                directSets.append(contentsOf: entry.exercise.sets)
            }
        }

        let credited = directSets.map { remap($0, exerciseName: aggregateName) } +
            pairedSideSets(left: leftSets, right: rightSets, aggregateName: aggregateName) +
            unilateralSets.map { remap($0, exerciseName: aggregateName) }

        return credited.sorted { lhs, rhs in
            if lhs.setOrder != rhs.setOrder { return lhs.setOrder < rhs.setOrder }
            return lhs.date < rhs.date
        }
    }

    private static func pairedSideSets(
        left: [WorkoutSet],
        right: [WorkoutSet],
        aggregateName: String
    ) -> [WorkoutSet] {
        let left = sorted(left)
        let right = sorted(right)
        let count = max(left.count, right.count)
        guard count > 0 else { return [] }

        return (0..<count).compactMap { index in
            let lhs = index < left.count ? left[index] : nil
            let rhs = index < right.count ? right[index] : nil
            switch (lhs, rhs) {
            case let (.some(lhs), .some(rhs)):
                return averagedSet(lhs, rhs, exerciseName: aggregateName)
            case let (.some(set), nil), let (nil, .some(set)):
                return remap(set, exerciseName: aggregateName)
            case (nil, nil):
                return nil
            }
        }
    }

    private static func averagedSet(_ lhs: WorkoutSet, _ rhs: WorkoutSet, exerciseName: String) -> WorkoutSet {
        let lhsVolume = lhs.weight * Double(lhs.reps)
        let rhsVolume = rhs.weight * Double(rhs.reps)
        let reps = max(0, Int((Double(lhs.reps + rhs.reps) / 2.0).rounded()))
        let volume = (lhsVolume + rhsVolume) / 2.0
        let weight = reps > 0 ? volume / Double(reps) : (lhs.weight + rhs.weight) / 2.0

        return WorkoutSet(
            date: max(lhs.date, rhs.date),
            workoutName: lhs.workoutName,
            duration: lhs.duration,
            exerciseName: exerciseName,
            setOrder: min(lhs.setOrder, rhs.setOrder),
            weight: weight,
            reps: reps,
            distance: (lhs.distance + rhs.distance) / 2.0,
            seconds: (lhs.seconds + rhs.seconds) / 2.0
        )
    }

    private static func remap(_ set: WorkoutSet, exerciseName: String) -> WorkoutSet {
        WorkoutSet(
            date: set.date,
            workoutName: set.workoutName,
            duration: set.duration,
            exerciseName: exerciseName,
            setOrder: set.setOrder,
            weight: set.weight,
            reps: set.reps,
            distance: set.distance,
            seconds: set.seconds
        )
    }

    private static func sorted(_ sets: [WorkoutSet]) -> [WorkoutSet] {
        sets.sorted { lhs, rhs in
            if lhs.setOrder != rhs.setOrder { return lhs.setOrder < rhs.setOrder }
            return lhs.date < rhs.date
        }
    }

    private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        ExerciseIdentityResolver.trimmedName(lhs)
            .localizedCaseInsensitiveCompare(ExerciseIdentityResolver.trimmedName(rhs)) == .orderedSame
    }
}

final class ExerciseRelationshipManager: ObservableObject {
    static let shared = ExerciseRelationshipManager()

    @Published private(set) var relationships: [String: ExerciseRelationship] = [:] {
        didSet { revision &+= 1 }
    }
    private(set) var revision: UInt64 = 0

    private let userDefaults: UserDefaults
    private let storageKey = "ExerciseRelationships"
    private let suppressedDefaultsKey = "ExerciseRelationshipSuppressedDefaults"
    private var suppressedDefaultIDs: Set<String> = []

    private static let defaultRelationships = ExerciseMetadataManager.defaultExerciseRelationships
    private static let defaultRelationshipIDs = Set(defaultRelationships.map(\.id))
    private static let defaultRelationshipsByID = Dictionary(
        uniqueKeysWithValues: defaultRelationships.map { ($0.id, $0) }
    )

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    func resolverSnapshot() -> ExerciseIdentityResolver {
        ExerciseIdentityResolver(relationships: relationships)
    }

    func relationship(for exerciseName: String) -> ExerciseRelationship? {
        relationships[ExerciseIdentityResolver.normalizedName(exerciseName)]
    }

    func children(of parentName: String) -> [ExerciseRelationship] {
        resolverSnapshot().children(of: parentName)
    }

    var suppressedDefaultExerciseNames: [String] {
        Self.defaultRelationships
            .filter { suppressedDefaultIDs.contains($0.id) }
            .map(\.exerciseName)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func suggestedRelationship(
        for exerciseName: String,
        knownExerciseNames: Set<String>
    ) -> ExerciseRelationshipSuggestion? {
        guard relationship(for: exerciseName) == nil else { return nil }
        return ExerciseIdentityResolver.inferredSuggestion(
            for: exerciseName,
            knownExerciseNames: knownExerciseNames
        )
    }

    func suggestedRelationships(
        forParent parentName: String,
        knownExerciseNames: Set<String>
    ) -> [ExerciseRelationshipSuggestion] {
        ExerciseIdentityResolver.inferredSuggestions(
            forParent: parentName,
            knownExerciseNames: knownExerciseNames
        )
        .filter { relationship(for: $0.exerciseName) == nil }
    }

    @discardableResult
    func autoLinkSideRelationships(
        observedExerciseNames: Set<String>
    ) -> ExerciseRelationshipAutoLinkResult {
        let observed = Set(
            observedExerciseNames
                .map(ExerciseIdentityResolver.trimmedName)
                .filter { !$0.isEmpty }
        )
        guard !observed.isEmpty else { return .empty }

        var created: [ExerciseRelationship] = []
        var skipped = 0

        for exerciseName in observed.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            guard relationship(for: exerciseName) == nil,
                  let suggestion = ExerciseIdentityResolver.inferredSuggestion(
                    for: exerciseName,
                    knownExerciseNames: observed
                  ) else {
                continue
            }

            let replaceableDefault = unmodifiedDefaultRelationship(
                parentName: suggestion.parentName,
                laterality: suggestion.laterality
            ).flatMap { relationship in
                observed.contains(where: {
                    ExerciseIdentityResolver.normalizedName($0) == relationship.id
                }) ? nil : relationship
            }
            let didSave = setRelationship(
                exerciseName: suggestion.exerciseName,
                parentName: suggestion.parentName,
                laterality: suggestion.laterality,
                replacingExerciseName: replaceableDefault?.exerciseName
            )
            if didSave, let relationship = relationship(for: suggestion.exerciseName) {
                created.append(relationship)
            } else {
                skipped += 1
            }
        }

        return ExerciseRelationshipAutoLinkResult(created: created, skipped: skipped)
    }

    @discardableResult
    func setRelationship(
        exerciseName: String,
        parentName: String,
        laterality: ExerciseLaterality,
        replacingExerciseName: String? = nil
    ) -> Bool {
        let child = ExerciseIdentityResolver.trimmedName(exerciseName)
        let requestedParent = ExerciseIdentityResolver.trimmedName(parentName)
        guard !child.isEmpty, !requestedParent.isEmpty else { return false }

        let replacedName = replacingExerciseName ?? child
        let parent = canonicalParentName(for: requestedParent, replacingChild: replacedName)
        guard isValidRelationship(
            child: child,
            parent: parent,
            laterality: laterality,
            replacingChild: replacedName
        ) else { return false }

        let relationship = ExerciseRelationship(
            exerciseName: child,
            parentName: parent,
            laterality: laterality
        )
        let replacedKey = ExerciseIdentityResolver.normalizedName(replacedName)
        if replacedKey != relationship.id {
            relationships.removeValue(forKey: replacedKey)
            suppressDefaultIfNeeded(exerciseName: replacedName)
        }
        relationships[relationship.id] = relationship
        suppressedDefaultIDs.remove(relationship.id)
        save()
        return true
    }

    @discardableResult
    func createStandardSideVariants(
        parentName: String,
        sides: [ExerciseLaterality] = [.left, .right]
    ) -> (created: [ExerciseRelationship], skipped: [ExerciseLaterality]) {
        let requestedParent = ExerciseIdentityResolver.trimmedName(parentName)
        let parent = canonicalParentName(for: requestedParent, replacingChild: nil)
        guard !parent.isEmpty else { return ([], sides) }

        var created: [ExerciseRelationship] = []
        var skipped: [ExerciseLaterality] = []
        var seenSides: Set<ExerciseLaterality> = []
        var existingSides = Set(
            relationships.values
                .filter {
                    ExerciseIdentityResolver.normalizedName($0.parentName) ==
                        ExerciseIdentityResolver.normalizedName(parent)
                }
                .map(\.laterality)
        )

        for side in sides where seenSides.insert(side).inserted {
            guard !existingSides.contains(side) else {
                skipped.append(side)
                continue
            }

            let child = Self.standardVariantName(parentName: parent, laterality: side)
            guard isValidRelationship(
                child: child,
                parent: parent,
                laterality: side,
                replacingChild: nil
            ) else {
                skipped.append(side)
                continue
            }
            guard relationship(for: child) == nil else {
                skipped.append(side)
                continue
            }

            let relationship = ExerciseRelationship(
                exerciseName: child,
                parentName: parent,
                laterality: side
            )
            relationships[relationship.id] = relationship
            existingSides.insert(side)
            created.append(relationship)
        }

        if !created.isEmpty {
            save()
        }

        return (created, skipped)
    }

    func removeRelationship(for exerciseName: String) {
        let relationshipID = ExerciseIdentityResolver.normalizedName(exerciseName)
        relationships.removeValue(forKey: relationshipID)
        if Self.defaultRelationshipIDs.contains(relationshipID) {
            suppressedDefaultIDs.insert(relationshipID)
        }
        save()
    }

    @discardableResult
    func mergeRelationshipsFromBackup(_ incoming: [ExerciseRelationship]) -> (inserted: Int, skipped: Int) {
        guard !incoming.isEmpty else { return (0, 0) }

        var inserted = 0
        var skipped = 0
        for relationship in incoming {
            let canonical = ExerciseRelationship(
                exerciseName: relationship.exerciseName,
                parentName: canonicalParentName(for: relationship.parentName, replacingChild: relationship.exerciseName),
                laterality: relationship.laterality,
                schemaVersion: relationship.schemaVersion
            )
            guard relationships[canonical.id] == nil else {
                skipped += 1
                continue
            }

            let replaceableDefault = unmodifiedDefaultRelationship(
                parentName: canonical.parentName,
                laterality: canonical.laterality
            )
            if let replaceableDefault {
                relationships.removeValue(forKey: replaceableDefault.id)
            }
            guard isValidRelationship(
                child: canonical.exerciseName,
                parent: canonical.parentName,
                laterality: canonical.laterality,
                replacingChild: nil
            ) else {
                if let replaceableDefault {
                    relationships[replaceableDefault.id] = replaceableDefault
                }
                skipped += 1
                continue
            }
            if let replaceableDefault {
                suppressedDefaultIDs.insert(replaceableDefault.id)
            }
            relationships[canonical.id] = canonical
            suppressedDefaultIDs.remove(canonical.id)
            inserted += 1
        }

        if inserted > 0 {
            save()
        }
        return (inserted, skipped)
    }

    @discardableResult
    func mergeSuppressedDefaultsFromBackup(_ exerciseNames: [String]) -> Int {
        var changed = 0
        for exerciseName in exerciseNames {
            let relationshipID = ExerciseIdentityResolver.normalizedName(exerciseName)
            guard let defaultRelationship = Self.defaultRelationshipsByID[relationshipID] else { continue }

            if suppressedDefaultIDs.insert(relationshipID).inserted {
                changed += 1
            }
            if relationships[relationshipID] == defaultRelationship {
                relationships.removeValue(forKey: relationshipID)
                changed += 1
            }
        }

        if changed > 0 {
            save()
        }
        return changed
    }

    func clearRelationships() {
        relationships = [:]
        suppressedDefaultIDs = Self.defaultRelationshipIDs
        userDefaults.removeObject(forKey: storageKey)
        saveSuppressedDefaults()
    }

    /// Clears user customization while restoring the parent/side relationships shipped with the app.
    func resetToDefaults() {
        suppressedDefaultIDs = []
        relationships = ExerciseIdentityResolver(
            relationships: Dictionary(uniqueKeysWithValues: Self.defaultRelationships.map { ($0.id, $0) })
        ).relationships
        save()
    }

    static func standardVariantName(parentName: String, laterality: ExerciseLaterality) -> String {
        switch laterality {
        case .left:
            return "\(ExerciseIdentityResolver.trimmedName(parentName)) - Left"
        case .right:
            return "\(ExerciseIdentityResolver.trimmedName(parentName)) - Right"
        case .unilateral:
            return "\(ExerciseIdentityResolver.trimmedName(parentName)) - Unilateral"
        }
    }

    static func replacementCandidateForSideAssignment(
        parentName: String,
        laterality: ExerciseLaterality,
        children: [ExerciseRelationship],
        hasExactHistory: (String) -> Bool
    ) -> ExerciseRelationship? {
        let parentKey = ExerciseIdentityResolver.normalizedName(parentName)
        let standardName = standardVariantName(parentName: parentName, laterality: laterality)
        let sideChildren = children.filter {
            ExerciseIdentityResolver.normalizedName($0.parentName) == parentKey &&
                $0.laterality == laterality
        }

        return sideChildren.first {
            ExerciseIdentityResolver.normalizedName($0.exerciseName) ==
                ExerciseIdentityResolver.normalizedName(standardName) &&
                !hasExactHistory($0.exerciseName)
        } ?? sideChildren.first {
            !hasExactHistory($0.exerciseName)
        }
    }

    private func load() {
        suppressedDefaultIDs = Set(userDefaults.stringArray(forKey: suppressedDefaultsKey) ?? [])

        if let data = userDefaults.data(forKey: storageKey) {
            if let decoded = try? JSONDecoder().decode([ExerciseRelationship].self, from: data) {
                let keyed = decoded.reduce(into: [String: ExerciseRelationship]()) { result, relationship in
                    result[relationship.id] = relationship
                }
                relationships = ExerciseIdentityResolver(relationships: keyed).relationships
            } else if let decoded = try? JSONDecoder().decode([String: ExerciseRelationship].self, from: data) {
                relationships = ExerciseIdentityResolver(relationships: decoded).relationships
            }
        }

        installMissingDefaultRelationships()
    }

    private func installMissingDefaultRelationships() {
        for relationship in Self.defaultRelationships where !suppressedDefaultIDs.contains(relationship.id) {
            guard relationships[relationship.id] == nil else { continue }
            guard isValidRelationship(
                child: relationship.exerciseName,
                parent: relationship.parentName,
                laterality: relationship.laterality,
                replacingChild: nil
            ) else { continue }
            relationships[relationship.id] = relationship
        }
    }

    private func save() {
        let values = relationships.values.sorted {
            $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending
        }
        if let data = try? JSONEncoder().encode(values) {
            userDefaults.set(data, forKey: storageKey)
        }
        saveSuppressedDefaults()
    }

    private func saveSuppressedDefaults() {
        if suppressedDefaultIDs.isEmpty {
            userDefaults.removeObject(forKey: suppressedDefaultsKey)
        } else {
            userDefaults.set(suppressedDefaultIDs.sorted(), forKey: suppressedDefaultsKey)
        }
    }

    private func suppressDefaultIfNeeded(exerciseName: String) {
        let relationshipID = ExerciseIdentityResolver.normalizedName(exerciseName)
        if Self.defaultRelationshipIDs.contains(relationshipID) {
            suppressedDefaultIDs.insert(relationshipID)
        }
    }

    private func unmodifiedDefaultRelationship(
        parentName: String,
        laterality: ExerciseLaterality
    ) -> ExerciseRelationship? {
        let parentID = ExerciseIdentityResolver.normalizedName(parentName)
        return relationships.values.first { relationship in
            ExerciseIdentityResolver.normalizedName(relationship.parentName) == parentID &&
                relationship.laterality == laterality &&
                Self.defaultRelationshipsByID[relationship.id] == relationship
        }
    }

    private func canonicalParentName(for parentName: String, replacingChild childName: String?) -> String {
        var snapshot = relationships
        if let childName {
            snapshot.removeValue(forKey: ExerciseIdentityResolver.normalizedName(childName))
        }
        return ExerciseIdentityResolver(relationships: snapshot).aggregateName(for: parentName)
    }

    private func isValidRelationship(
        child: String,
        parent: String,
        laterality: ExerciseLaterality,
        replacingChild: String?
    ) -> Bool {
        let childKey = ExerciseIdentityResolver.normalizedName(child)
        let parentKey = ExerciseIdentityResolver.normalizedName(parent)
        let replacementKey = replacingChild.map(ExerciseIdentityResolver.normalizedName)
        guard !childKey.isEmpty, !parentKey.isEmpty, childKey != parentKey else {
            return false
        }

        let duplicateSide = relationships.values.contains { relationship in
            let existingChildKey = ExerciseIdentityResolver.normalizedName(relationship.exerciseName)
            if existingChildKey == childKey { return false }
            if let replacementKey, existingChildKey == replacementKey { return false }
            return existingChildKey != childKey &&
                ExerciseIdentityResolver.normalizedName(relationship.parentName) == parentKey &&
                relationship.laterality == laterality
        }
        guard !duplicateSide else { return false }

        var validationRelationships = relationships
        if let replacementKey {
            validationRelationships.removeValue(forKey: replacementKey)
        }
        var current = parent
        var seen = Set<String>()
        while let relationship = validationRelationships[ExerciseIdentityResolver.normalizedName(current)] {
            let key = ExerciseIdentityResolver.normalizedName(relationship.exerciseName)
            guard seen.insert(key).inserted else { break }
            if ExerciseIdentityResolver.normalizedName(relationship.parentName) == childKey {
                return false
            }
            current = relationship.parentName
        }

        return true
    }
}
