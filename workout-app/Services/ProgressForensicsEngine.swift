import Foundation

enum ProgressForensicsEngine {
    private static let minimumSessionsPerExercise = 6
    private static let minimumSessionsPerBlock = 3
    private static let maximumGapDays = 21

    static func review(
        for exerciseName: String,
        workouts: [Workout],
        annotations: [UUID: WorkoutAnnotation],
        bodyMassSamples: [BodyRawSample]
    ) -> ExerciseForensicsReview? {
        let sessions = buildSessions(for: exerciseName, workouts: workouts, annotations: annotations)
        guard sessions.count >= minimumSessionsPerExercise else { return nil }

        let blocks = buildBlocks(from: sessions, bodyMassSamples: bodyMassSamples)
        guard blocks.count >= 2 else { return nil }

        let latestPair = Array(blocks.suffix(2))
        guard latestPair.count == 2 else { return nil }

        let comparison = compare(previous: latestPair[0], current: latestPair[1], exerciseName: exerciseName)
        let findings = findings(for: latestPair[0], current: latestPair[1], comparison: comparison)

        return ExerciseForensicsReview(
            exerciseName: exerciseName,
            latestComparableBlocks: latestPair.map(\.block),
            comparison: comparison,
            findings: findings,
            hasBodyweightContext: latestPair.contains { $0.block.medianBodyweight != nil }
        )
    }

    private struct SessionSnapshot {
        let workoutId: UUID
        let date: Date
        let workoutName: String
        let orderIndex: Int
        let orderBand: ExerciseOrderBand
        let dominantRepLane: ExerciseRepLane
        let sets: [WorkoutSet]
        let gymId: UUID?

        var totalVolume: Double {
            sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        }

        var dominantLaneSets: [WorkoutSet] {
            sets.filter { dominantRepLane.contains($0.reps) }
        }
    }

    private struct DerivedBlock {
        let block: ExerciseTrainingBlock
        let firstAppearanceRate: Double
        let loadRepCounts: [Double: Int]
    }

    private static func buildSessions(
        for exerciseName: String,
        workouts: [Workout],
        annotations: [UUID: WorkoutAnnotation]
    ) -> [SessionSnapshot] {
        workouts
            .sorted { $0.date < $1.date }
            .compactMap { workout in
                guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.name == exerciseName }) else {
                    return nil
                }

                let exercise = workout.exercises[exerciseIndex]
                guard !exercise.sets.isEmpty else { return nil }

                return SessionSnapshot(
                    workoutId: workout.id,
                    date: workout.date,
                    workoutName: workout.name,
                    orderIndex: exerciseIndex,
                    orderBand: orderBand(for: exerciseIndex),
                    dominantRepLane: dominantLane(for: exercise.sets),
                    sets: exercise.sets,
                    gymId: annotations[workout.id]?.gymProfileId
                )
            }
    }

    private static func buildBlocks(
        from sessions: [SessionSnapshot],
        bodyMassSamples: [BodyRawSample]
    ) -> [DerivedBlock] {
        guard !sessions.isEmpty else { return [] }

        var sessionBlocks: [[SessionSnapshot]] = []
        var currentBlock: [SessionSnapshot] = []
        var pendingLaneChange: [SessionSnapshot] = []

        for session in sessions {
            guard let previousSession = currentBlock.last else {
                currentBlock = [session]
                continue
            }

            let gapDays = dayDistance(from: previousSession.date, to: session.date)
            if gapDays > maximumGapDays {
                if !pendingLaneChange.isEmpty {
                    currentBlock.append(contentsOf: pendingLaneChange)
                    pendingLaneChange.removeAll()
                }
                sessionBlocks.append(currentBlock)
                currentBlock = [session]
                continue
            }

            let currentLane = dominantLane(for: currentBlock)
            if session.dominantRepLane == currentLane || currentBlock.count < 2 {
                if !pendingLaneChange.isEmpty {
                    currentBlock.append(contentsOf: pendingLaneChange)
                    pendingLaneChange.removeAll()
                }
                currentBlock.append(session)
                continue
            }

            pendingLaneChange.append(session)
            let pendingLane = dominantLane(for: pendingLaneChange)
            if pendingLaneChange.count >= 2, pendingLane != currentLane {
                sessionBlocks.append(currentBlock)
                currentBlock = pendingLaneChange
                pendingLaneChange.removeAll()
            }
        }

        if !pendingLaneChange.isEmpty {
            currentBlock.append(contentsOf: pendingLaneChange)
        }
        if !currentBlock.isEmpty {
            sessionBlocks.append(currentBlock)
        }

        return sessionBlocks
            .filter { $0.count >= minimumSessionsPerBlock }
            .compactMap { deriveBlock(from: $0, bodyMassSamples: bodyMassSamples) }
    }

    private static func deriveBlock(
        from sessions: [SessionSnapshot],
        bodyMassSamples: [BodyRawSample]
    ) -> DerivedBlock? {
        guard let first = sessions.first, let last = sessions.last else { return nil }

        let lane = dominantLane(for: sessions)
        let laneSets = sessions.flatMap(\.dominantLaneSets).filter { lane.contains($0.reps) }
        guard !laneSets.isEmpty else { return nil }

        let spanDays = max(1, dayDistance(from: first.date, to: last.date) + 1)
        let sessionCount = sessions.count
        let sessionsPerWeek = (Double(sessionCount) * 7.0) / Double(spanDays)

        let setCounts = sessions.map { Double($0.sets.count) }
        let volumes = sessions.map(\.totalVolume)
        let firstAppearanceRate = Double(sessions.filter { $0.orderBand == .first }.count) / Double(max(sessionCount, 1))
        let commonOrderBand = mode(sessions.map(\.orderBand)) ?? .secondToThird
        let commonGymId = modeOptional(sessions.map(\.gymId))

        let bodyweightValues = bodyMassSamples
            .filter { $0.timestamp >= first.date && $0.timestamp <= last.date }
            .map(\.value)

        let loadRepCounts = laneSets.reduce(into: [Double: Int]()) { partialResult, set in
            partialResult[set.weight, default: 0] += set.reps
        }

        let outcome = ExerciseBlockOutcome(
            lane: lane,
            bestWeight: laneSets.map(\.weight).max() ?? 0,
            repeatedLoad: nil,
            repsAtRepeatedLoad: nil,
            laneVolume: laneSets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        )

        let block = ExerciseTrainingBlock(
            id: "\(Int(first.date.timeIntervalSince1970))-\(Int(last.date.timeIntervalSince1970))-\(sessionCount)",
            startDate: first.date,
            endDate: last.date,
            sessionCount: sessionCount,
            sessionsPerWeek: sessionsPerWeek,
            dominantRepLane: lane,
            commonOrderBand: commonOrderBand,
            commonGymId: commonGymId,
            commonGym: commonGymId == nil ? "Unassigned" : nil,
            medianSetsPerSession: median(setCounts),
            medianVolumePerSession: median(volumes),
            medianBodyweight: bodyweightValues.isEmpty ? nil : median(bodyweightValues),
            outcome: outcome
        )

        return DerivedBlock(
            block: block,
            firstAppearanceRate: firstAppearanceRate,
            loadRepCounts: loadRepCounts
        )
    }

    private static func compare(
        previous: DerivedBlock,
        current: DerivedBlock,
        exerciseName: String
    ) -> ExerciseBlockComparison {
        guard previous.block.dominantRepLane == current.block.dominantRepLane else {
            return ExerciseBlockComparison(
                previousBlockId: previous.block.id,
                currentBlockId: current.block.id,
                outcomeStatus: .notComparable,
                primaryMetricKind: .notComparable,
                primaryObservedMetric: "Rep lane changed",
                delta: 0,
                deltaLabel: "Not comparable",
                summary: "\(exerciseName) changed rep lanes, so the last two blocks are not directly comparable.",
                supportingEvidence: supportingEvidence(previous: previous, current: current).prefix(3).map { $0.0 }
            )
        }

        let lane = current.block.dominantRepLane
        let bestWeightDelta = current.block.outcome.bestWeight - previous.block.outcome.bestWeight
        if abs(bestWeightDelta) > 0.01 {
            return ExerciseBlockComparison(
                previousBlockId: previous.block.id,
                currentBlockId: current.block.id,
                outcomeStatus: status(for: bestWeightDelta),
                primaryMetricKind: .bestWeight,
                primaryObservedMetric: "Best weight in \(lane.label)",
                delta: bestWeightDelta,
                deltaLabel: signedWeightLabel(bestWeightDelta),
                summary: summary(
                    exerciseName: exerciseName,
                    lane: lane,
                    status: status(for: bestWeightDelta),
                    metricDescription: "best weight moved \(signedWeightLabel(bestWeightDelta).lowercased())"
                ),
                supportingEvidence: supportingEvidence(previous: previous, current: current).prefix(3).map { $0.0 }
            )
        }

        let sharedLoad = Set(previous.loadRepCounts.keys).intersection(current.loadRepCounts.keys).max()
        if let sharedLoad {
            let previousReps = previous.loadRepCounts[sharedLoad] ?? 0
            let currentReps = current.loadRepCounts[sharedLoad] ?? 0
            let repDelta = currentReps - previousReps
            return ExerciseBlockComparison(
                previousBlockId: previous.block.id,
                currentBlockId: current.block.id,
                outcomeStatus: status(for: Double(repDelta)),
                primaryMetricKind: .repsAtRepeatedLoad,
                primaryObservedMetric: "Total reps at \(Int(sharedLoad.rounded())) lbs in \(lane.label)",
                delta: Double(repDelta),
                deltaLabel: signedRepLabel(repDelta),
                summary: summary(
                    exerciseName: exerciseName,
                    lane: lane,
                    status: status(for: Double(repDelta)),
                    metricDescription: "total reps at \(Int(sharedLoad.rounded())) lbs moved \(signedRepLabel(repDelta).lowercased())"
                ),
                supportingEvidence: supportingEvidence(previous: previous, current: current).prefix(3).map { $0.0 }
            )
        }

        let volumeDelta = current.block.outcome.laneVolume - previous.block.outcome.laneVolume
        return ExerciseBlockComparison(
            previousBlockId: previous.block.id,
            currentBlockId: current.block.id,
            outcomeStatus: status(for: volumeDelta),
            primaryMetricKind: .laneVolume,
            primaryObservedMetric: "Lane volume in \(lane.label)",
            delta: volumeDelta,
            deltaLabel: signedVolumeLabel(volumeDelta),
            summary: summary(
                exerciseName: exerciseName,
                lane: lane,
                status: status(for: volumeDelta),
                metricDescription: "lane volume moved \(signedVolumeLabel(volumeDelta).lowercased())"
            ),
            supportingEvidence: supportingEvidence(previous: previous, current: current).prefix(3).map { $0.0 }
        )
    }

    private static func findings(
        for previous: DerivedBlock,
        current: DerivedBlock,
        comparison: ExerciseBlockComparison
    ) -> [ExerciseForensicsFinding] {
        let candidates = supportingEvidence(previous: previous, current: current)
        return Array(candidates.prefix(4).map { item in
            ExerciseForensicsFinding(id: item.0, title: item.1, message: item.2)
        })
    }

    private static func supportingEvidence(
        previous: DerivedBlock,
        current: DerivedBlock
    ) -> [(String, String, String)] {
        var evidence: [(priority: Int, id: String, title: String, message: String)] = []

        let previousFrequency = previous.block.sessionsPerWeek
        let currentFrequency = current.block.sessionsPerWeek
        let frequencyDelta = currentFrequency - previousFrequency
        let frequencyMessage: String
        if abs(frequencyDelta) >= 0.25 {
            frequencyMessage = "Sessions per week moved from \(decimal(previousFrequency)) to \(decimal(currentFrequency)) during this stretch."
        } else {
            frequencyMessage = "Sessions per week stayed close at \(decimal(previousFrequency)) to \(decimal(currentFrequency)) during this stretch."
        }
        evidence.append((0, "frequency", "Frequency", frequencyMessage))

        let previousFirstRate = previous.firstAppearanceRate * 100
        let currentFirstRate = current.firstAppearanceRate * 100
        let orderMessage: String
        if previous.block.commonOrderBand != current.block.commonOrderBand {
            orderMessage = "This lift moved from \(previous.block.commonOrderBand.label) to \(current.block.commonOrderBand.label) most often, while first-position use shifted from \(percent(previousFirstRate)) to \(percent(currentFirstRate))."
        } else {
            orderMessage = "Its common slot stayed at \(current.block.commonOrderBand.label), with first-position use moving from \(percent(previousFirstRate)) to \(percent(currentFirstRate))."
        }
        evidence.append((1, "order", "Exercise Order", orderMessage))

        let previousSets = previous.block.medianSetsPerSession
        let currentSets = current.block.medianSetsPerSession
        let setMessage = "Median sets per session moved from \(decimal(previousSets)) to \(decimal(currentSets)) in this block."
        evidence.append((2, "sets", "Sets Per Session", setMessage))

        let previousVolume = previous.block.outcome.laneVolume
        let currentVolume = current.block.outcome.laneVolume
        let volumeMessage = "Volume in the \(current.block.dominantRepLane.label) lane moved from \(SharedFormatters.volumeWithUnit(previousVolume)) to \(SharedFormatters.volumeWithUnit(currentVolume)) during this stretch."
        evidence.append((3, "volume", "Lane Volume", volumeMessage))

        if previous.block.commonGymId != current.block.commonGymId {
            let previousGym = gymContextLabel(for: previous.block)
            let currentGym = gymContextLabel(for: current.block)
            let gymMessage = "The dominant location context changed from \(previousGym) to \(currentGym) in this block."
            evidence.append((4, "gym", "Gym Context", gymMessage))
        }

        if let previousWeight = previous.block.medianBodyweight,
           let currentWeight = current.block.medianBodyweight {
            let weightMessage = "Median bodyweight moved from \(decimal(previousWeight)) lb to \(decimal(currentWeight)) lb during this stretch."
            evidence.append((5, "bodyweight", "Bodyweight", weightMessage))
        }

        return evidence
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.id < rhs.id
                }
                return lhs.priority < rhs.priority
            }
            .map { ($0.id, $0.title, $0.message) }
    }

    private static func status(for delta: Double) -> ExerciseBlockOutcomeStatus {
        if delta > 0.01 { return .improved }
        if delta < -0.01 { return .regressed }
        return .flat
    }

    private static func summary(
        exerciseName: String,
        lane: ExerciseRepLane,
        status: ExerciseBlockOutcomeStatus,
        metricDescription: String
    ) -> String {
        switch status {
        case .improved:
            return "\(exerciseName) improved in the \(lane.label) lane, and \(metricDescription)."
        case .flat:
            return "\(exerciseName) held flat in the \(lane.label) lane, and \(metricDescription)."
        case .regressed:
            return "\(exerciseName) regressed in the \(lane.label) lane, and \(metricDescription)."
        case .notComparable:
            return "\(exerciseName) changed patterns enough that the last two blocks are not directly comparable."
        }
    }

    private static func orderBand(for index: Int) -> ExerciseOrderBand {
        switch index {
        case 0:
            return .first
        case 1...2:
            return .secondToThird
        default:
            return .fourthPlus
        }
    }

    private static func dominantLane(for sets: [WorkoutSet]) -> ExerciseRepLane {
        mode(sets.map { ExerciseRepLane.lane(for: $0.reps) }) ?? .sevenToTen
    }

    private static func dominantLane(for sessions: [SessionSnapshot]) -> ExerciseRepLane {
        mode(sessions.map(\.dominantRepLane)) ?? .sevenToTen
    }

    private static func dayDistance(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func mode<T: Hashable>(_ values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        let counts = values.reduce(into: [T: Int]()) { partialResult, value in
            partialResult[value, default: 0] += 1
        }
        return counts.max { lhs, rhs in
            if lhs.value == rhs.value {
                return String(describing: lhs.key) > String(describing: rhs.key)
            }
            return lhs.value < rhs.value
        }?.key
    }

    private static func modeOptional<T: Hashable>(_ values: [T?]) -> T? {
        let nonNil = values.compactMap { $0 }
        return mode(nonNil)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func gymContextLabel(for block: ExerciseTrainingBlock) -> String {
        if let label = block.commonGym, !label.isEmpty {
            return label.lowercased()
        }
        return block.commonGymId == nil ? "unassigned" : "a different assigned gym"
    }

    private static func signedWeightLabel(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded == 0 { return "0 lbs" }
        return rounded > 0 ? "+\(rounded) lbs" : "\(rounded) lbs"
    }

    private static func signedRepLabel(_ value: Int) -> String {
        if value == 0 { return "0 reps" }
        return value > 0 ? "+\(value) reps" : "\(value) reps"
    }

    private static func signedVolumeLabel(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded == 0 { return "0 lbs" }
        return rounded > 0 ? "+\(rounded) lbs" : "\(rounded) lbs"
    }
}
