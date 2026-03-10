import Combine
import Foundation

@MainActor
final class WorkoutVariantEngine: ObservableObject {
    @Published private(set) var library: WorkoutVariantLibrary = .empty
    @Published private(set) var isAnalyzing = false
    private var generation = 0

    func analyze(
        workouts: [Workout],
        annotations: [UUID: WorkoutAnnotation],
        gymNames: [UUID: String]
    ) async {
        generation += 1
        let currentGeneration = generation

        guard !workouts.isEmpty else {
            library = .empty
            isAnalyzing = false
            return
        }

        isAnalyzing = true
        let workoutsSnapshot = workouts
        let annotationsSnapshot = annotations
        let gymNamesSnapshot = gymNames

        let result = await Task.detached(priority: .userInitiated) {
            WorkoutVariantAnalyzer.buildLibrary(
                workouts: workoutsSnapshot,
                annotations: annotationsSnapshot,
                gymNames: gymNamesSnapshot
            )
        }.value

        guard currentGeneration == generation else { return }
        library = result
        isAnalyzing = false
    }

    func review(for workoutId: UUID) -> WorkoutVariantWorkoutReview? {
        library.reviewsByWorkoutId[workoutId]
    }

    func patterns(for exerciseName: String) -> [WorkoutVariantPattern] {
        library.standoutPatterns.filter { pattern in
            pattern.evidence.contains { $0.exerciseName == exerciseName }
        }
    }
}

private enum WorkoutVariantAnalyzer {
    nonisolated private static let minimumWorkoutGroupCount = 4
    nonisolated private static let minimumComparisonGroupCount = 2

    nonisolated static func buildLibrary(
        workouts: [Workout],
        annotations: [UUID: WorkoutAnnotation],
        gymNames: [UUID: String]
    ) -> WorkoutVariantLibrary {
        let snapshots = workouts.map { snapshot(for: $0, annotations: annotations, gymNames: gymNames) }
        let groups = Dictionary(grouping: snapshots) { $0.workout.name }

        var reviewsByWorkoutId: [UUID: WorkoutVariantWorkoutReview] = [:]
        var patterns: [WorkoutVariantPattern] = []

        for (workoutName, groupedSnapshots) in groups {
            guard groupedSnapshots.count >= minimumWorkoutGroupCount else { continue }
            guard let context = buildContext(workoutName: workoutName, snapshots: groupedSnapshots) else { continue }

            for snapshot in groupedSnapshots {
                if let review = buildReview(for: snapshot, context: context) {
                    reviewsByWorkoutId[review.workout.id] = review
                }
            }

            if let pattern = buildPattern(for: context) {
                patterns.append(pattern)
            }
        }

        let recentReviews = Array(
            reviewsByWorkoutId.values
                .sorted { $0.workout.date > $1.workout.date }
                .prefix(10)
        )

        return WorkoutVariantLibrary(
            standoutPatterns: patterns.sorted { $0.confidence > $1.confidence },
            recentReviews: recentReviews,
            reviewsByWorkoutId: reviewsByWorkoutId
        )
    }

    private struct Snapshot {
        let workout: Workout
        let gymId: UUID?
        let gymLabel: String
        let durationMinutes: Double
        let totalVolume: Double
        let totalSets: Int
        let firstExerciseName: String?
        let timeBucket: TimeBucket
        let exerciseNames: Set<String>
        let exerciseEstimatedMaxes: [String: Double]
    }

    private enum SessionLengthBand: String, CaseIterable, Hashable {
        case short
        case standard
        case long

        nonisolated var label: String {
            switch self {
            case .short: return "Short session"
            case .standard: return "Standard session"
            case .long: return "Long session"
            }
        }
    }

    private enum ExerciseCountBand: String, CaseIterable, Hashable {
        case compact
        case standard
        case extended

        nonisolated var label: String {
            switch self {
            case .compact: return "Compact session"
            case .standard: return "Standard size"
            case .extended: return "Extended session"
            }
        }
    }

    private enum TimeBucket: String, CaseIterable, Hashable {
        case early
        case morning
        case afternoon
        case evening
        case late

        nonisolated var label: String {
            switch self {
            case .early: return "Early session"
            case .morning: return "Morning session"
            case .afternoon: return "Afternoon session"
            case .evening: return "Evening session"
            case .late: return "Late session"
            }
        }
    }

    private struct GroupContext {
        let workoutName: String
        let snapshots: [Snapshot]
        let anchorExerciseName: String?
        let baselineFirstExercise: String?
        let baselineTimeBucket: TimeBucket
        let baselineGymId: UUID?
        let durationMedian: Double
        let exerciseCountMedian: Int
        let baselineDurationBand: SessionLengthBand
        let baselineExerciseCountBand: ExerciseCountBand
    }

    private nonisolated static func buildContext(workoutName: String, snapshots: [Snapshot]) -> GroupContext? {
        guard !snapshots.isEmpty else { return nil }

        let baselineFirstExercise = mode(snapshots.compactMap(\.firstExerciseName))
        let baselineTimeBucket = mode(snapshots.map(\.timeBucket)) ?? .evening
        let baselineGymId = modeOptional(snapshots.map(\.gymId))
        let durationMedian = median(snapshots.map(\.durationMinutes))
        let exerciseCountMedian = max(1, Int(median(snapshots.map { Double($0.workout.exercises.count) }).rounded()))

        let durationBands = snapshots.map { durationBand(for: $0, medianDuration: durationMedian) }
        let exerciseCountBands = snapshots.map { exerciseCountBand(for: $0, medianCount: exerciseCountMedian) }

        let baselineDurationBand = mode(durationBands) ?? .standard
        let baselineExerciseCountBand = mode(exerciseCountBands) ?? .standard
        let anchorExerciseName = baselineFirstExercise ?? mostCommonExerciseName(in: snapshots)

        return GroupContext(
            workoutName: workoutName,
            snapshots: snapshots,
            anchorExerciseName: anchorExerciseName,
            baselineFirstExercise: baselineFirstExercise,
            baselineTimeBucket: baselineTimeBucket,
            baselineGymId: baselineGymId,
            durationMedian: durationMedian,
            exerciseCountMedian: exerciseCountMedian,
            baselineDurationBand: baselineDurationBand,
            baselineExerciseCountBand: baselineExerciseCountBand
        )
    }

    private nonisolated static func buildPattern(for context: GroupContext) -> WorkoutVariantPattern? {
        var candidates: [WorkoutVariantDifferenceInsight] = []

        let firstExercises = Set(context.snapshots.compactMap(\.firstExerciseName))
        for firstExercise in firstExercises {
            guard firstExercise != context.baselineFirstExercise else { continue }
            if let insight = firstExerciseInsight(
                currentValue: firstExercise,
                context: context,
                preferredExercises: [firstExercise, context.anchorExerciseName].compactMap { $0 }
            ) {
                candidates.append(insight)
            }
        }

        for band in SessionLengthBand.allCases where band != context.baselineDurationBand {
            if let insight = durationInsight(currentValue: band, context: context) {
                candidates.append(insight)
            }
        }

        for band in ExerciseCountBand.allCases where band != context.baselineExerciseCountBand {
            if let insight = exerciseCountInsight(currentValue: band, context: context) {
                candidates.append(insight)
            }
        }

        for bucket in TimeBucket.allCases where bucket != context.baselineTimeBucket {
            if let insight = timeOfDayInsight(currentValue: bucket, context: context) {
                candidates.append(insight)
            }
        }

        let gymIds = Set(context.snapshots.map(\.gymId))
        for gymId in gymIds where gymId != context.baselineGymId {
            if let insight = gymInsight(currentValue: gymId, context: context) {
                candidates.append(insight)
            }
        }

        guard let strongest = candidates.max(by: { $0.confidence < $1.confidence }),
              let representative = context.snapshots
                .filter({ representativeMatches(pattern: strongest, snapshot: $0, context: context) })
                .sorted(by: { $0.workout.date > $1.workout.date })
                .first else {
            return nil
        }

        return WorkoutVariantPattern(
            id: "\(context.workoutName)-\(strongest.id)",
            workoutName: context.workoutName,
            representativeWorkout: representative.workout,
            variantLabel: strongest.variantLabel,
            baselineLabel: strongest.baselineLabel,
            summary: strongest.summary,
            sampleSize: strongest.variantSampleSize,
            baselineSampleSize: strongest.baselineSampleSize,
            evidence: strongest.evidence,
            confidence: strongest.confidence
        )
    }

    private nonisolated static func buildReview(for snapshot: Snapshot, context: GroupContext) -> WorkoutVariantWorkoutReview? {
        var differences: [WorkoutVariantDifferenceInsight] = []
        var fingerprintParts: [String] = []

        if let firstExercise = snapshot.firstExerciseName,
           firstExercise != context.baselineFirstExercise,
           let insight = firstExerciseInsight(
               currentValue: firstExercise,
               context: context,
               preferredExercises: [firstExercise, context.anchorExerciseName].compactMap { $0 }
           ) {
            differences.append(insight)
            fingerprintParts.append(insight.variantLabel)
        }

        let snapshotDurationBand = durationBand(for: snapshot, medianDuration: context.durationMedian)
        if snapshotDurationBand != context.baselineDurationBand,
           let insight = durationInsight(currentValue: snapshotDurationBand, context: context) {
            differences.append(insight)
            fingerprintParts.append(insight.variantLabel)
        }

        let snapshotCountBand = exerciseCountBand(for: snapshot, medianCount: context.exerciseCountMedian)
        if snapshotCountBand != context.baselineExerciseCountBand,
           let insight = exerciseCountInsight(currentValue: snapshotCountBand, context: context) {
            differences.append(insight)
            fingerprintParts.append(insight.variantLabel)
        }

        if snapshot.timeBucket != context.baselineTimeBucket,
           let insight = timeOfDayInsight(currentValue: snapshot.timeBucket, context: context) {
            differences.append(insight)
            fingerprintParts.append(insight.variantLabel)
        }

        if snapshot.gymId != context.baselineGymId,
           let insight = gymInsight(currentValue: snapshot.gymId, context: context) {
            differences.append(insight)
            fingerprintParts.append(insight.variantLabel)
        }

        let sortedDifferences = differences.sorted { $0.confidence > $1.confidence }
        guard !sortedDifferences.isEmpty else { return nil }

        let exactVariantSampleSize = exactVariantMatchCount(
            for: snapshot,
            context: context,
            activeDimensions: Set(sortedDifferences.map(\.kind))
        )
        let variantLabel = fingerprintParts.isEmpty
            ? "Variant"
            : fingerprintParts.prefix(3).joined(separator: " • ")
        let summary = sortedDifferences.prefix(2).map(\.summary).joined(separator: " • ")

        return WorkoutVariantWorkoutReview(
            id: snapshot.workout.id,
            workout: snapshot.workout,
            workoutName: context.workoutName,
            variantLabel: variantLabel,
            summary: summary,
            peerSampleSize: context.snapshots.count,
            exactVariantSampleSize: exactVariantSampleSize,
            differences: Array(sortedDifferences.prefix(4))
        )
    }

    private nonisolated static func representativeMatches(
        pattern: WorkoutVariantDifferenceInsight,
        snapshot: Snapshot,
        context: GroupContext
    ) -> Bool {
        switch pattern.kind {
        case .firstExercise:
            return snapshot.firstExerciseName == patternValue(from: pattern.variantLabel)
        case .durationBand:
            return durationBand(for: snapshot, medianDuration: context.durationMedian).label == pattern.variantLabel
        case .exerciseCountBand:
            return exerciseCountBand(for: snapshot, medianCount: context.exerciseCountMedian).label == pattern.variantLabel
        case .timeOfDay:
            return snapshot.timeBucket.label == pattern.variantLabel
        case .gym:
            return snapshot.gymLabel == pattern.variantLabel
        }
    }

    private nonisolated static func firstExerciseInsight(
        currentValue: String,
        context: GroupContext,
        preferredExercises: [String]
    ) -> WorkoutVariantDifferenceInsight? {
        guard let baseline = context.baselineFirstExercise, currentValue != baseline else { return nil }
        let variantGroup = context.snapshots.filter { $0.firstExerciseName == currentValue }
        let baselineGroup = context.snapshots.filter { $0.firstExerciseName == baseline }
        return buildInsight(
            kind: .firstExercise,
            variantLabel: "\(currentValue) first",
            baselineLabel: "\(baseline) first",
            variantGroup: variantGroup,
            baselineGroup: baselineGroup,
            preferredExercises: preferredExercises,
            excludedMetricKinds: []
        )
    }

    private nonisolated static func durationInsight(
        currentValue: SessionLengthBand,
        context: GroupContext
    ) -> WorkoutVariantDifferenceInsight? {
        let baseline = context.baselineDurationBand
        guard currentValue != baseline else { return nil }

        let variantGroup = context.snapshots.filter {
            durationBand(for: $0, medianDuration: context.durationMedian) == currentValue
        }
        let baselineGroup = context.snapshots.filter {
            durationBand(for: $0, medianDuration: context.durationMedian) == baseline
        }

        return buildInsight(
            kind: .durationBand,
            variantLabel: currentValue.label,
            baselineLabel: baseline.label,
            variantGroup: variantGroup,
            baselineGroup: baselineGroup,
            preferredExercises: [context.anchorExerciseName].compactMap { $0 },
            excludedMetricKinds: [.durationMinutes]
        )
    }

    private nonisolated static func exerciseCountInsight(
        currentValue: ExerciseCountBand,
        context: GroupContext
    ) -> WorkoutVariantDifferenceInsight? {
        let baseline = context.baselineExerciseCountBand
        guard currentValue != baseline else { return nil }

        let variantGroup = context.snapshots.filter {
            exerciseCountBand(for: $0, medianCount: context.exerciseCountMedian) == currentValue
        }
        let baselineGroup = context.snapshots.filter {
            exerciseCountBand(for: $0, medianCount: context.exerciseCountMedian) == baseline
        }

        return buildInsight(
            kind: .exerciseCountBand,
            variantLabel: currentValue.label,
            baselineLabel: baseline.label,
            variantGroup: variantGroup,
            baselineGroup: baselineGroup,
            preferredExercises: [context.anchorExerciseName].compactMap { $0 },
            excludedMetricKinds: [.totalSets]
        )
    }

    private nonisolated static func timeOfDayInsight(
        currentValue: TimeBucket,
        context: GroupContext
    ) -> WorkoutVariantDifferenceInsight? {
        let baseline = context.baselineTimeBucket
        guard currentValue != baseline else { return nil }

        let variantGroup = context.snapshots.filter { $0.timeBucket == currentValue }
        let baselineGroup = context.snapshots.filter { $0.timeBucket == baseline }

        return buildInsight(
            kind: .timeOfDay,
            variantLabel: currentValue.label,
            baselineLabel: baseline.label,
            variantGroup: variantGroup,
            baselineGroup: baselineGroup,
            preferredExercises: [context.anchorExerciseName].compactMap { $0 },
            excludedMetricKinds: []
        )
    }

    private nonisolated static func gymInsight(
        currentValue: UUID?,
        context: GroupContext
    ) -> WorkoutVariantDifferenceInsight? {
        let baseline = context.baselineGymId
        guard currentValue != baseline else { return nil }

        let variantGroup = context.snapshots.filter { $0.gymId == currentValue }
        let baselineGroup = context.snapshots.filter { $0.gymId == baseline }
        let variantLabel = variantGroup.first?.gymLabel ?? "Unassigned"
        let baselineLabel = baselineGroup.first?.gymLabel ?? "Unassigned"

        return buildInsight(
            kind: .gym,
            variantLabel: variantLabel,
            baselineLabel: baselineLabel,
            variantGroup: variantGroup,
            baselineGroup: baselineGroup,
            preferredExercises: [context.anchorExerciseName].compactMap { $0 },
            excludedMetricKinds: []
        )
    }

    private nonisolated static func buildInsight(
        kind: WorkoutVariantDimensionKind,
        variantLabel: String,
        baselineLabel: String,
        variantGroup: [Snapshot],
        baselineGroup: [Snapshot],
        preferredExercises: [String],
        excludedMetricKinds: Set<WorkoutVariantMetricKind>
    ) -> WorkoutVariantDifferenceInsight? {
        guard variantGroup.count >= minimumComparisonGroupCount,
              baselineGroup.count >= minimumComparisonGroupCount else {
            return nil
        }

        var evidence: [WorkoutVariantMetricComparison] = []

        if let exerciseComparison = bestExerciseEstimatedMaxComparison(
            variantGroup: variantGroup,
            baselineGroup: baselineGroup,
            preferredExercises: preferredExercises
        ) {
            evidence.append(exerciseComparison)
        }

        if !excludedMetricKinds.contains(.totalVolume),
           let totalVolume = groupMetricComparison(
               kind: .totalVolume,
               label: "Total volume",
               variantValues: variantGroup.map(\.totalVolume),
               baselineValues: baselineGroup.map(\.totalVolume)
           ) {
            evidence.append(totalVolume)
        }

        if !excludedMetricKinds.contains(.totalSets),
           let totalSets = groupMetricComparison(
               kind: .totalSets,
               label: "Total sets",
               variantValues: variantGroup.map { Double($0.totalSets) },
               baselineValues: baselineGroup.map { Double($0.totalSets) }
           ) {
            evidence.append(totalSets)
        }

        if !excludedMetricKinds.contains(.durationMinutes),
           let duration = groupMetricComparison(
               kind: .durationMinutes,
               label: "Session duration",
               variantValues: variantGroup.map(\.durationMinutes),
               baselineValues: baselineGroup.map(\.durationMinutes)
           ) {
            evidence.append(duration)
        }

        let sortedEvidence = evidence
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)

        guard !sortedEvidence.isEmpty else { return nil }

        let evidenceArray = Array(sortedEvidence)
        let summary = evidenceArray.prefix(2).map(\.summarySnippet).joined(separator: " • ")

        return WorkoutVariantDifferenceInsight(
            id: "\(kind.rawValue)-\(variantLabel)-\(baselineLabel)",
            kind: kind,
            variantLabel: variantLabel,
            baselineLabel: baselineLabel,
            variantSampleSize: variantGroup.count,
            baselineSampleSize: baselineGroup.count,
            summary: summary,
            evidence: evidenceArray,
            confidence: evidenceArray.map(\.confidence).max() ?? 0
        )
    }

    private nonisolated static func bestExerciseEstimatedMaxComparison(
        variantGroup: [Snapshot],
        baselineGroup: [Snapshot],
        preferredExercises: [String]
    ) -> WorkoutVariantMetricComparison? {
        let variantCounts = frequencyMap(variantGroup.flatMap { $0.exerciseNames.map { ($0, 1) } })
        let baselineCounts = frequencyMap(baselineGroup.flatMap { $0.exerciseNames.map { ($0, 1) } })

        let commonExerciseNames = Set(variantCounts.keys)
            .intersection(baselineCounts.keys)
            .filter { (variantCounts[$0] ?? 0) >= minimumComparisonGroupCount && (baselineCounts[$0] ?? 0) >= minimumComparisonGroupCount }

        guard !commonExerciseNames.isEmpty else { return nil }

        let orderedCandidates = preferredExercises.filter(commonExerciseNames.contains)
            + commonExerciseNames.filter { !preferredExercises.contains($0) }.sorted()

        var best: WorkoutVariantMetricComparison?
        for exerciseName in orderedCandidates {
            let variantValues = variantGroup.compactMap { $0.exerciseEstimatedMaxes[exerciseName] }
            let baselineValues = baselineGroup.compactMap { $0.exerciseEstimatedMaxes[exerciseName] }
            guard let comparison = groupMetricComparison(
                kind: .exerciseEstimatedMax,
                label: "\(exerciseName) e1RM",
                exerciseName: exerciseName,
                variantValues: variantValues,
                baselineValues: baselineValues
            ) else {
                continue
            }

            if let currentBest = best {
                let preferredBias = preferredExercises.first == exerciseName ? 0.2 : 0.0
                if comparison.confidence + preferredBias > currentBest.confidence {
                    best = comparison
                }
            } else {
                best = comparison
            }
        }

        return best
    }

    private nonisolated static func groupMetricComparison(
        kind: WorkoutVariantMetricKind,
        label: String,
        exerciseName: String? = nil,
        variantValues: [Double],
        baselineValues: [Double]
    ) -> WorkoutVariantMetricComparison? {
        guard variantValues.count >= minimumComparisonGroupCount,
              baselineValues.count >= minimumComparisonGroupCount else {
            return nil
        }

        let variantAverage = average(variantValues)
        let baselineAverage = average(baselineValues)
        guard baselineAverage > 0 else { return nil }

        let deltaAbsolute = variantAverage - baselineAverage
        let deltaPercent = (deltaAbsolute / baselineAverage) * 100
        guard isMeaningful(kind: kind, deltaAbsolute: deltaAbsolute, deltaPercent: deltaPercent) else {
            return nil
        }

        let confidence = abs(deltaPercent) * log(Double(min(variantValues.count, baselineValues.count)) + 1)
        let trend: WorkoutVariantTrend = deltaAbsolute >= 0 ? .higher : .lower

        return WorkoutVariantMetricComparison(
            id: "\(kind.rawValue)-\(label)-\(exerciseName ?? "none")",
            kind: kind,
            label: label,
            exerciseName: exerciseName,
            variantAverage: variantAverage,
            baselineAverage: baselineAverage,
            variantSampleSize: variantValues.count,
            baselineSampleSize: baselineValues.count,
            deltaAbsolute: deltaAbsolute,
            deltaPercent: deltaPercent,
            trend: trend,
            confidence: confidence
        )
    }

    private nonisolated static func exactVariantMatchCount(
        for snapshot: Snapshot,
        context: GroupContext,
        activeDimensions: Set<WorkoutVariantDimensionKind>
    ) -> Int {
        context.snapshots.filter { candidate in
            for dimension in activeDimensions {
                switch dimension {
                case .firstExercise:
                    if candidate.firstExerciseName != snapshot.firstExerciseName { return false }
                case .durationBand:
                    if durationBand(for: candidate, medianDuration: context.durationMedian) != durationBand(for: snapshot, medianDuration: context.durationMedian) {
                        return false
                    }
                case .exerciseCountBand:
                    if exerciseCountBand(for: candidate, medianCount: context.exerciseCountMedian) != exerciseCountBand(for: snapshot, medianCount: context.exerciseCountMedian) {
                        return false
                    }
                case .timeOfDay:
                    if candidate.timeBucket != snapshot.timeBucket { return false }
                case .gym:
                    if candidate.gymId != snapshot.gymId { return false }
                }
            }
            return true
        }.count
    }

    private nonisolated static func snapshot(
        for workout: Workout,
        annotations: [UUID: WorkoutAnnotation],
        gymNames: [UUID: String]
    ) -> Snapshot {
        let gymId = annotations[workout.id]?.gymProfileId
        let gymLabel: String
        if let gymId {
            gymLabel = gymNames[gymId] ?? "Deleted gym"
        } else {
            gymLabel = "Unassigned"
        }

        var exerciseEstimatedMaxes: [String: Double] = [:]
        for exercise in workout.exercises {
            let estimated = exercise.sets
                .filter { $0.weight > 0 && $0.reps > 0 }
                .map { estimateOneRepMax(weight: $0.weight, reps: $0.reps) }
                .max()
            if let estimated, estimated > 0 {
                exerciseEstimatedMaxes[exercise.name] = estimated
            }
        }

        return Snapshot(
            workout: workout,
            gymId: gymId,
            gymLabel: gymLabel,
            durationMinutes: Double(workout.estimatedDurationMinutes()),
            totalVolume: workout.totalVolume,
            totalSets: workout.totalSets,
            firstExerciseName: workout.exercises.first?.name,
            timeBucket: timeBucket(for: workout.date),
            exerciseNames: Set(workout.exercises.map(\.name)),
            exerciseEstimatedMaxes: exerciseEstimatedMaxes
        )
    }

    private nonisolated static func timeBucket(for date: Date) -> TimeBucket {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 0..<5:
            return .late
        case 5..<9:
            return .early
        case 9..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<22:
            return .evening
        default:
            return .late
        }
    }

    private nonisolated static func durationBand(
        for snapshot: Snapshot,
        medianDuration: Double
    ) -> SessionLengthBand {
        let shortThreshold = max(20, medianDuration * 0.85)
        let longThreshold = medianDuration * 1.15

        if snapshot.durationMinutes <= shortThreshold {
            return .short
        }
        if snapshot.durationMinutes >= longThreshold {
            return .long
        }
        return .standard
    }

    private nonisolated static func exerciseCountBand(
        for snapshot: Snapshot,
        medianCount: Int
    ) -> ExerciseCountBand {
        if snapshot.workout.exercises.count <= max(1, medianCount - 1) {
            return .compact
        }
        if snapshot.workout.exercises.count >= medianCount + 1 {
            return .extended
        }
        return .standard
    }

    private nonisolated static func mostCommonExerciseName(in snapshots: [Snapshot]) -> String? {
        let counts = snapshots.flatMap { $0.exerciseNames.map { ($0, 1) } }
        return frequencyMap(counts).max(by: { $0.value < $1.value })?.key
    }

    private nonisolated static func estimateOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }

    private nonisolated static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private nonisolated static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private nonisolated static func mode<T: Hashable>(_ values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        return Dictionary(grouping: values, by: { $0 })
            .max { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count < rhs.value.count
                }
                return String(describing: lhs.key) > String(describing: rhs.key)
            }?
            .key
    }

    private nonisolated static func modeOptional<T: Hashable>(_ values: [T?]) -> T? {
        guard !values.isEmpty else { return nil }
        return Dictionary(grouping: values, by: { $0 })
            .max { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count < rhs.value.count
                }
                return String(describing: lhs.key) > String(describing: rhs.key)
            }?
            .key ?? nil
    }

    private nonisolated static func frequencyMap<T: Hashable>(_ pairs: [(T, Int)]) -> [T: Int] {
        pairs.reduce(into: [:]) { result, pair in
            result[pair.0, default: 0] += pair.1
        }
    }

    private nonisolated static func isMeaningful(
        kind: WorkoutVariantMetricKind,
        deltaAbsolute: Double,
        deltaPercent: Double
    ) -> Bool {
        switch kind {
        case .exerciseEstimatedMax:
            return abs(deltaPercent) >= 3 || abs(deltaAbsolute) >= 5
        case .totalVolume:
            return abs(deltaPercent) >= 5 || abs(deltaAbsolute) >= 500
        case .totalSets:
            return abs(deltaAbsolute) >= 1 || abs(deltaPercent) >= 10
        case .durationMinutes:
            return abs(deltaAbsolute) >= 5 || abs(deltaPercent) >= 10
        }
    }

    private nonisolated static func patternValue(from label: String) -> String {
        label.replacingOccurrences(of: " first", with: "")
    }
}
