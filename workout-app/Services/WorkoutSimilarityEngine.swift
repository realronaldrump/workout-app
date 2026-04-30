import Combine
import Foundation

@MainActor
final class WorkoutSimilarityEngine: ObservableObject {
    @Published private(set) var library: WorkoutSimilarityLibrary = .empty
    @Published private(set) var isAnalyzing = false

    private var generation = 0

    func analyze(workouts: [Workout]) async {
        generation += 1
        let currentGeneration = generation

        guard !workouts.isEmpty else {
            library = .empty
            isAnalyzing = false
            return
        }

        isAnalyzing = true
        let workoutsSnapshot = workouts
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()

        let result = await Task.detached(priority: .userInitiated) {
            WorkoutSimilarityAnalyzer.buildLibrary(workouts: workoutsSnapshot, resolver: resolver)
        }.value

        guard currentGeneration == generation else { return }
        library = result
        isAnalyzing = false
    }

    func review(for workoutId: UUID) -> WorkoutSimilarityReview? {
        library.reviewsByWorkoutId[workoutId]
    }

    func comparison(
        selectedWorkoutId: UUID,
        priorWorkoutId: UUID
    ) -> WorkoutSimilarityComparison? {
        library.comparisonsByKey[Self.comparisonKey(selectedWorkoutId: selectedWorkoutId, priorWorkoutId: priorWorkoutId)]
    }

    nonisolated static func comparisonKey(selectedWorkoutId: UUID, priorWorkoutId: UUID) -> String {
        "\(selectedWorkoutId.uuidString)|\(priorWorkoutId.uuidString)"
    }
}

private enum WorkoutSimilarityAnalyzer {
    private struct CanonicalExercise: Hashable {
        let displayName: String
        let normalizedName: String
    }

    private struct Snapshot: Hashable {
        let workout: Workout
        let exercises: [CanonicalExercise]
        let normalizedOrderedExerciseNames: [String]
        let normalizedExerciseSet: Set<String>
        let orderedSignature: String
        let unorderedSignature: String
        let positionsByName: [String: Int]
    }

    nonisolated static func buildLibrary(
        workouts: [Workout],
        resolver: ExerciseIdentityResolver = .empty
    ) -> WorkoutSimilarityLibrary {
        let snapshots = workouts
            .map { snapshot(for: $0, resolver: resolver) }
            .sorted(by: snapshotSort)

        var reviewsByWorkoutId: [UUID: WorkoutSimilarityReview] = [:]
        var comparisonsByKey: [String: WorkoutSimilarityComparison] = [:]

        var exactOrderIndex: [String: [Snapshot]] = [:]
        var exactExercisesIndex: [String: [Snapshot]] = [:]
        var snapshotsById: [UUID: Snapshot] = [:]
        var candidateIdsByExercise: [String: Set<UUID>] = [:]

        for snapshot in snapshots {
            let exactOrderMatches = buildExactMatches(
                selected: snapshot,
                priorSnapshots: exactOrderIndex[snapshot.orderedSignature] ?? [],
                kind: .exactOrdered,
                comparisonsByKey: &comparisonsByKey
            )

            let reorderedMatches = buildExactMatches(
                selected: snapshot,
                priorSnapshots: (exactExercisesIndex[snapshot.unorderedSignature] ?? []).filter {
                    $0.orderedSignature != snapshot.orderedSignature
                },
                kind: .exactExercisesReordered,
                comparisonsByKey: &comparisonsByKey
            )

            let exactPriorIds = Set(exactOrderMatches.map(\.priorWorkoutId) + reorderedMatches.map(\.priorWorkoutId))
            let partialMatches = buildPartialMatches(
                selected: snapshot,
                candidateIdsByExercise: candidateIdsByExercise,
                snapshotsById: snapshotsById,
                excludedIds: exactPriorIds,
                comparisonsByKey: &comparisonsByKey
            )

            let bestMatch = (exactOrderMatches + reorderedMatches + partialMatches)
                .sorted(by: matchSort)
                .first

            reviewsByWorkoutId[snapshot.workout.id] = WorkoutSimilarityReview(
                id: snapshot.workout.id,
                workoutId: snapshot.workout.id,
                bestMatch: bestMatch,
                exactOrderMatches: exactOrderMatches.sorted(by: matchSort),
                reorderedExerciseMatches: reorderedMatches.sorted(by: matchSort)
            )

            exactOrderIndex[snapshot.orderedSignature, default: []].append(snapshot)
            exactExercisesIndex[snapshot.unorderedSignature, default: []].append(snapshot)
            snapshotsById[snapshot.workout.id] = snapshot

            for exercise in snapshot.normalizedExerciseSet {
                candidateIdsByExercise[exercise, default: []].insert(snapshot.workout.id)
            }
        }

        return WorkoutSimilarityLibrary(
            reviewsByWorkoutId: reviewsByWorkoutId,
            comparisonsByKey: comparisonsByKey
        )
    }

    private nonisolated static func snapshot(
        for workout: Workout,
        resolver: ExerciseIdentityResolver
    ) -> Snapshot {
        var seen = Set<String>()
        var exercises: [CanonicalExercise] = []
        exercises.reserveCapacity(workout.exercises.count)

        for exercise in workout.exercises {
            let aggregateName = resolver.aggregateName(for: exercise.name)
            let trimmed = aggregateName.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = normalizedExerciseName(trimmed)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            exercises.append(
                CanonicalExercise(
                    displayName: trimmed.isEmpty ? aggregateName : trimmed,
                    normalizedName: normalized
                )
            )
        }

        let normalizedOrderedExerciseNames = exercises.map(\.normalizedName)
        let normalizedExerciseSet = Set(normalizedOrderedExerciseNames)
        let orderedSignature = normalizedOrderedExerciseNames.joined(separator: "|")
        let unorderedSignature = normalizedExerciseSet.sorted().joined(separator: "|")
        let positionsByName = Dictionary(uniqueKeysWithValues: normalizedOrderedExerciseNames.enumerated().map { offset, name in
            (name, offset)
        })

        return Snapshot(
            workout: workout,
            exercises: exercises,
            normalizedOrderedExerciseNames: normalizedOrderedExerciseNames,
            normalizedExerciseSet: normalizedExerciseSet,
            orderedSignature: orderedSignature,
            unorderedSignature: unorderedSignature,
            positionsByName: positionsByName
        )
    }

    private nonisolated static func buildExactMatches(
        selected: Snapshot,
        priorSnapshots: [Snapshot],
        kind: WorkoutSimilarityMatchKind,
        comparisonsByKey: inout [String: WorkoutSimilarityComparison]
    ) -> [WorkoutSimilarityMatch] {
        priorSnapshots.map { prior in
            let comparison = comparison(selected: selected, prior: prior, kind: kind, score: 1.0)
            comparisonsByKey[comparisonKey(selectedWorkoutId: selected.workout.id, priorWorkoutId: prior.workout.id)] = comparison
            return match(from: comparison, prior: prior)
        }
    }

    private nonisolated static func buildPartialMatches(
        selected: Snapshot,
        candidateIdsByExercise: [String: Set<UUID>],
        snapshotsById: [UUID: Snapshot],
        excludedIds: Set<UUID>,
        comparisonsByKey: inout [String: WorkoutSimilarityComparison]
    ) -> [WorkoutSimilarityMatch] {
        var candidateIds = Set<UUID>()
        for exerciseName in selected.normalizedExerciseSet {
            candidateIds.formUnion(candidateIdsByExercise[exerciseName] ?? [])
        }

        return candidateIds
            .subtracting(excludedIds)
            .compactMap { snapshotsById[$0] }
            .compactMap { prior in
                let sharedExerciseCount = selected.normalizedExerciseSet.intersection(prior.normalizedExerciseSet).count
                guard sharedExerciseCount > 0 else { return nil }
                let score = partialScore(selected: selected, prior: prior)
                let comparison = comparison(selected: selected, prior: prior, kind: .partial, score: score)
                comparisonsByKey[comparisonKey(selectedWorkoutId: selected.workout.id, priorWorkoutId: prior.workout.id)] = comparison
                return match(from: comparison, prior: prior)
            }
            .sorted(by: matchSort)
    }

    private nonisolated static func comparison(
        selected: Snapshot,
        prior: Snapshot,
        kind: WorkoutSimilarityMatchKind,
        score: Double
    ) -> WorkoutSimilarityComparison {
        let rows = buildComparisonRows(selected: selected, prior: prior)
        let samePositionCount = rows.filter { isSamePosition($0.kind) }.count
        let sharedExerciseCount = rows.filter { isSharedRow($0.kind) }.count

        return WorkoutSimilarityComparison(
            selectedWorkoutId: selected.workout.id,
            priorWorkoutId: prior.workout.id,
            kind: kind,
            score: score,
            sharedExerciseCount: sharedExerciseCount,
            samePositionCount: samePositionCount,
            rows: rows
        )
    }

    private nonisolated static func buildComparisonRows(
        selected: Snapshot,
        prior: Snapshot
    ) -> [WorkoutSimilarityComparisonRow] {
        var rows: [WorkoutSimilarityComparisonRow] = []
        let priorExercisesByName = Dictionary(uniqueKeysWithValues: prior.exercises.map { ($0.normalizedName, $0) })
        let selectedExercisesByName = Dictionary(uniqueKeysWithValues: selected.exercises.map { ($0.normalizedName, $0) })

        for (offset, exercise) in selected.exercises.enumerated() {
            if let priorOffset = prior.positionsByName[exercise.normalizedName],
               let priorExercise = priorExercisesByName[exercise.normalizedName] {
                let kind: WorkoutSimilarityComparisonRowKind = priorOffset == offset ? .samePosition : .moved
                rows.append(
                    WorkoutSimilarityComparisonRow(
                        id: "shared-\(exercise.normalizedName)",
                        selectedExerciseName: exercise.displayName,
                        priorExerciseName: priorExercise.displayName,
                        selectedPosition: offset + 1,
                        priorPosition: priorOffset + 1,
                        kind: kind
                    )
                )
            } else {
                rows.append(
                    WorkoutSimilarityComparisonRow(
                        id: "selected-\(exercise.normalizedName)",
                        selectedExerciseName: exercise.displayName,
                        priorExerciseName: nil,
                        selectedPosition: offset + 1,
                        priorPosition: nil,
                        kind: .onlyInSelected
                    )
                )
            }
        }

        for (offset, exercise) in prior.exercises.enumerated() where selectedExercisesByName[exercise.normalizedName] == nil {
            rows.append(
                WorkoutSimilarityComparisonRow(
                    id: "prior-\(exercise.normalizedName)",
                    selectedExerciseName: nil,
                    priorExerciseName: exercise.displayName,
                    selectedPosition: nil,
                    priorPosition: offset + 1,
                    kind: .onlyInPrior
                )
            )
        }

        return rows
    }

    private nonisolated static func partialScore(selected: Snapshot, prior: Snapshot) -> Double {
        let sharedCount = Double(selected.normalizedExerciseSet.intersection(prior.normalizedExerciseSet).count)
        let unionCount = Double(selected.normalizedExerciseSet.union(prior.normalizedExerciseSet).count)
        let jaccard = unionCount > 0 ? sharedCount / unionCount : 0

        let maxExerciseCount = Double(max(selected.normalizedOrderedExerciseNames.count, prior.normalizedOrderedExerciseNames.count))
        let lcsNormalized = maxExerciseCount > 0
            ? Double(longestCommonSubsequenceLength(selected.normalizedOrderedExerciseNames, prior.normalizedOrderedExerciseNames)) / maxExerciseCount
            : 0

        return (0.75 * jaccard) + (0.25 * lcsNormalized)
    }

    private nonisolated static func longestCommonSubsequenceLength(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        var table = Array(repeating: Array(repeating: 0, count: rhs.count + 1), count: lhs.count + 1)

        for lhsIndex in 1...lhs.count {
            for rhsIndex in 1...rhs.count {
                if lhs[lhsIndex - 1] == rhs[rhsIndex - 1] {
                    table[lhsIndex][rhsIndex] = table[lhsIndex - 1][rhsIndex - 1] + 1
                } else {
                    table[lhsIndex][rhsIndex] = max(table[lhsIndex - 1][rhsIndex], table[lhsIndex][rhsIndex - 1])
                }
            }
        }

        return table[lhs.count][rhs.count]
    }

    private nonisolated static func match(
        from comparison: WorkoutSimilarityComparison,
        prior: Snapshot
    ) -> WorkoutSimilarityMatch {
        WorkoutSimilarityMatch(
            selectedWorkoutId: comparison.selectedWorkoutId,
            priorWorkoutId: prior.workout.id,
            priorWorkoutName: prior.workout.name,
            priorWorkoutDate: prior.workout.date,
            priorExerciseCount: prior.exercises.count,
            kind: comparison.kind,
            score: comparison.score,
            sharedExerciseCount: comparison.sharedExerciseCount,
            samePositionCount: comparison.samePositionCount
        )
    }

    private nonisolated static func normalizedExerciseName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private nonisolated static func isSamePosition(_ kind: WorkoutSimilarityComparisonRowKind) -> Bool {
        switch kind {
        case .samePosition:
            return true
        case .moved, .onlyInSelected, .onlyInPrior:
            return false
        }
    }

    private nonisolated static func isSharedRow(_ kind: WorkoutSimilarityComparisonRowKind) -> Bool {
        switch kind {
        case .samePosition, .moved:
            return true
        case .onlyInSelected, .onlyInPrior:
            return false
        }
    }

    private nonisolated static func comparisonKey(selectedWorkoutId: UUID, priorWorkoutId: UUID) -> String {
        WorkoutSimilarityEngine.comparisonKey(selectedWorkoutId: selectedWorkoutId, priorWorkoutId: priorWorkoutId)
    }

    private nonisolated static func snapshotSort(lhs: Snapshot, rhs: Snapshot) -> Bool {
        if lhs.workout.date != rhs.workout.date {
            return lhs.workout.date < rhs.workout.date
        }
        return lhs.workout.id.uuidString < rhs.workout.id.uuidString
    }

    private nonisolated static func matchSort(lhs: WorkoutSimilarityMatch, rhs: WorkoutSimilarityMatch) -> Bool {
        let lhsRank = rank(for: lhs.kind)
        let rhsRank = rank(for: rhs.kind)

        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.sharedExerciseCount != rhs.sharedExerciseCount {
            return lhs.sharedExerciseCount > rhs.sharedExerciseCount
        }
        return lhs.priorWorkoutDate > rhs.priorWorkoutDate
    }

    private nonisolated static func rank(for kind: WorkoutSimilarityMatchKind) -> Int {
        switch kind {
        case .exactOrdered:
            return 0
        case .exactExercisesReordered:
            return 1
        case .partial:
            return 2
        }
    }
}
