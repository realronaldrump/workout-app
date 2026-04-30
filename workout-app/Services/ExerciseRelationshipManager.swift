import Combine
import Foundation

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

nonisolated struct ExerciseIdentityResolver: Hashable, Sendable {
    private let relationshipsByNormalizedName: [String: ExerciseRelationship]

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

        let candidates: [(prefix: String, suffix: String, laterality: ExerciseLaterality)] = [
            ("Left ", "", .left),
            ("Right ", "", .right),
            ("L ", "", .left),
            ("R ", "", .right),
            ("", " - Left", .left),
            ("", " - Right", .right),
            ("", " (Left)", .left),
            ("", " (Right)", .right),
            ("", " Left", .left),
            ("", " Right", .right)
        ]

        let knownByNormalized = knownExerciseNames.reduce(into: [String: String]()) { result, name in
            let trimmedKnownName = trimmedName(name)
            guard !trimmedKnownName.isEmpty else { return }
            result[normalizedName(trimmedKnownName)] = trimmedKnownName
        }

        for candidate in candidates {
            if !candidate.prefix.isEmpty,
               trimmed.localizedCaseInsensitiveContains(candidate.prefix),
               normalizedName(trimmed).hasPrefix(normalizedName(candidate.prefix)) {
                let parent = String(trimmed.dropFirst(candidate.prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let resolvedParent = knownByNormalized[normalizedName(parent)], !resolvedParent.isEmpty {
                    return ExerciseRelationshipSuggestion(
                        exerciseName: trimmed,
                        parentName: resolvedParent,
                        laterality: candidate.laterality
                    )
                }
            }

            if !candidate.suffix.isEmpty,
               normalizedName(trimmed).hasSuffix(normalizedName(candidate.suffix)) {
                let parent = String(trimmed.dropLast(candidate.suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let resolvedParent = knownByNormalized[normalizedName(parent)], !resolvedParent.isEmpty {
                    return ExerciseRelationshipSuggestion(
                        exerciseName: trimmed,
                        parentName: resolvedParent,
                        laterality: candidate.laterality
                    )
                }
            }
        }

        return nil
    }
}

nonisolated enum ExerciseAggregation {
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
        aggregateExercises(in: workout, resolver: resolver).reduce(0) { $0 + $1.totalVolume }
    }

    static func totalSets(for workout: Workout, resolver: ExerciseIdentityResolver) -> Int {
        aggregateExercises(in: workout, resolver: resolver).reduce(0) { $0 + $1.sets.count }
    }

    static func exerciseCount(for workout: Workout, resolver: ExerciseIdentityResolver) -> Int {
        aggregateExercises(in: workout, resolver: resolver).count
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

    @Published private(set) var relationships: [String: ExerciseRelationship] = [:]

    private let userDefaults: UserDefaults
    private let storageKey = "ExerciseRelationships"

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
        }
        relationships[relationship.id] = relationship
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
        relationships.removeValue(forKey: ExerciseIdentityResolver.normalizedName(exerciseName))
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
            guard isValidRelationship(
                child: canonical.exerciseName,
                parent: canonical.parentName,
                laterality: canonical.laterality,
                replacingChild: nil
            ) else {
                skipped += 1
                continue
            }
            guard relationships[canonical.id] == nil else {
                skipped += 1
                continue
            }
            relationships[canonical.id] = canonical
            inserted += 1
        }

        if inserted > 0 {
            save()
        }
        return (inserted, skipped)
    }

    func clearRelationships() {
        relationships = [:]
        userDefaults.removeObject(forKey: storageKey)
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

    private func load() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([ExerciseRelationship].self, from: data) {
            let keyed = decoded.reduce(into: [String: ExerciseRelationship]()) { result, relationship in
                result[relationship.id] = relationship
            }
            relationships = ExerciseIdentityResolver(relationships: keyed).relationships
            return
        }
        if let decoded = try? JSONDecoder().decode([String: ExerciseRelationship].self, from: data) {
            relationships = ExerciseIdentityResolver(relationships: decoded).relationships
        }
    }

    private func save() {
        let values = relationships.values.sorted {
            $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending
        }
        if let data = try? JSONEncoder().encode(values) {
            userDefaults.set(data, forKey: storageKey)
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
