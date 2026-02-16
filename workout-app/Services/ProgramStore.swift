import Foundation
import Combine

private struct ProgramStoreSnapshot: Codable {
    var activePlan: ProgramPlan?
    var archivedPlans: [ProgramPlan]
    var schemaVersion: Int
}

private struct ProgramDayLocation {
    var weekIndex: Int
    var dayIndex: Int
}

private struct ProgramCompletionSource {
    var plannedDayId: UUID?
    var plannedDayDate: Date?
    var plannedTargetsSnapshot: [PlannedExerciseTarget]?
}

@MainActor
final class ProgramStore: ObservableObject {
    @Published private(set) var activePlan: ProgramPlan?
    @Published private(set) var archivedPlans: [ProgramPlan] = []
    @Published private(set) var isLoaded = false

    private let fileName = "program_store_v1.json"
    private let snapshotPersistenceStore = ProgramSnapshotPersistenceStore()
    private var persistRevision: Int = 0

    struct ProgramCreationRequest: Sendable {
        var goal: ProgramGoal
        var daysPerWeek: Int
        var startDate: Date
        var weightIncrement: Double
        var name: String?
    }

    func load() async {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            activePlan = nil
            archivedPlans = []
            isLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(ProgramStoreSnapshot.self, from: data)
            activePlan = snapshot.activePlan
            archivedPlans = snapshot.archivedPlans
            resortArchivedPlans()
            isLoaded = true
        } catch {
            print("Failed to load program store: \(error)")
            activePlan = nil
            archivedPlans = []
            isLoaded = true
        }
    }

    func createPlan(
        request: ProgramCreationRequest,
        workouts: [Workout],
        dailyHealthStore: [Date: DailyHealthData]
    ) {
        _ = dailyHealthStore // Reserved for future generation heuristics.

        let config = ProgramGenerator.Config(
            goal: request.goal,
            daysPerWeek: request.daysPerWeek,
            startDate: request.startDate,
            weightIncrement: request.weightIncrement,
            name: request.name
        )
        var generated = ProgramGenerator.generate(workouts: workouts, config: config)
        generated.updatedAt = Date()

        if var existing = activePlan {
            existing.archivedAt = Date()
            archivedPlans.insert(existing, at: 0)
            resortArchivedPlans()
        }

        activePlan = generated
        persist()
    }

    func archiveActivePlan() {
        guard var activePlan else { return }
        activePlan.archivedAt = Date()
        archivedPlans.insert(activePlan, at: 0)
        resortArchivedPlans()
        self.activePlan = nil
        persist()
    }

    func restoreArchivedPlan(planId: UUID) {
        guard let index = archivedPlans.firstIndex(where: { $0.id == planId }) else { return }

        var restored = archivedPlans.remove(at: index)
        restored.archivedAt = nil
        restored.updatedAt = Date()

        if var currentActive = activePlan {
            currentActive.archivedAt = Date()
            archivedPlans.insert(currentActive, at: 0)
        }

        resortArchivedPlans()
        activePlan = restored
        persist()
    }

    func deleteArchivedPlan(planId: UUID) {
        let originalCount = archivedPlans.count
        archivedPlans.removeAll { $0.id == planId }
        guard archivedPlans.count != originalCount else { return }
        persist()
    }

    func todayPlan(
        referenceDate: Date = Date(),
        dailyHealthStore: [Date: DailyHealthData],
        ouraScores: [Date: OuraDailyScoreDay]? = nil
    ) -> ProgramTodayPlan? {
        guard let plan = activePlan else { return nil }

        let dayStart = Calendar.current.startOfDay(for: referenceDate)
        let eligibleStates: Set<ProgramSessionState> = [.planned, .moved]

        let candidates = plan.allDays.filter { day in
            eligibleStates.contains(day.state)
        }

        guard !candidates.isEmpty else { return nil }

        let todays = candidates
            .filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: dayStart) }
            .sorted { $0.scheduledDate < $1.scheduledDate }

        let overdue = candidates
            .filter { Calendar.current.startOfDay(for: $0.scheduledDate) < dayStart }
            .max(by: { $0.scheduledDate < $1.scheduledDate })

        let upcoming = candidates
            .filter { Calendar.current.startOfDay(for: $0.scheduledDate) > dayStart }
            .min(by: { $0.scheduledDate < $1.scheduledDate })

        let selectedDay = todays.first
            ?? overdue
            ?? upcoming
            ?? candidates.min(by: { $0.scheduledDate < $1.scheduledDate })

        guard let selectedDay else { return nil }

        let readiness = ProgramAutoregulationEngine.readinessSnapshot(
            dailyHealthStore: dailyHealthStore,
            ouraScores: ouraScores,
            on: referenceDate,
            rule: plan.progressionRule
        )
        let adjusted = ProgramAutoregulationEngine.adjustedTargets(
            from: selectedDay.exercises,
            readiness: readiness,
            roundingIncrement: plan.progressionRule.weightIncrement
        )

        return ProgramTodayPlan(
            planId: plan.id,
            day: selectedDay,
            adjustedExercises: adjusted,
            readiness: readiness
        )
    }

    func dayPlan(dayId: UUID) -> ProgramDayPlan? {
        activePlan?.allDays.first(where: { $0.id == dayId })
    }

    func week(weekNumber: Int) -> ProgramWeek? {
        activePlan?.weeks.first(where: { $0.weekNumber == weekNumber })
    }

    func completionRecord(for dayId: UUID) -> ProgramCompletionRecord? {
        activePlan?
            .completionRecords
            .filter { $0.dayId == dayId }
            .max(by: { $0.completedAt < $1.completedAt })
    }

    func workoutContext(for workoutId: UUID) -> ProgramWorkoutContext? {
        if let context = workoutContext(in: activePlan, workoutId: workoutId, isArchivedPlan: false) {
            return context
        }

        for plan in archivedPlans {
            if let context = workoutContext(in: plan, workoutId: workoutId, isArchivedPlan: true) {
                return context
            }
        }
        return nil
    }

    func recordCompletion(
        workout: Workout,
        plannedProgramId: UUID?,
        plannedDayId: UUID?,
        plannedDayDate: Date?,
        plannedTargetsSnapshot: [PlannedExerciseTarget]? = nil,
        dailyHealthStore: [Date: DailyHealthData],
        ouraScores: [Date: OuraDailyScoreDay]? = nil
    ) {
        // Only sessions explicitly started from a program day should mutate plan state.
        guard plannedProgramId != nil || plannedDayId != nil || plannedDayDate != nil else { return }
        let completionSource = ProgramCompletionSource(
            plannedDayId: plannedDayId,
            plannedDayDate: plannedDayDate,
            plannedTargetsSnapshot: plannedTargetsSnapshot
        )

        if let plannedProgramId {
            if let activePlan,
               activePlan.id == plannedProgramId,
               let updated = applyCompletion(
                   to: activePlan,
                   workout: workout,
                   source: completionSource,
                   dailyHealthStore: dailyHealthStore,
                   ouraScores: ouraScores
               ) {
                self.activePlan = updated
                persist()
            } else if let archivedIndex = archivedPlans.firstIndex(where: { $0.id == plannedProgramId }),
                      let updated = applyCompletion(
                        to: archivedPlans[archivedIndex],
                        workout: workout,
                        source: completionSource,
                        dailyHealthStore: dailyHealthStore,
                        ouraScores: ouraScores
                      ) {
                archivedPlans[archivedIndex] = updated
                resortArchivedPlans()
                persist()
            }
            return
        }

        guard let activePlan,
              let updated = applyCompletion(
                to: activePlan,
                workout: workout,
                source: completionSource,
                dailyHealthStore: dailyHealthStore,
                ouraScores: ouraScores
              ) else {
            return
        }

        self.activePlan = updated
        persist()
    }

    func skipDay(dayId: UUID) {
        guard var plan = activePlan,
              let location = dayLocation(dayId: dayId, in: plan) else { return }
        let currentState = plan.weeks[location.weekIndex].days[location.dayIndex].state
        guard currentState == .planned || currentState == .moved else { return }

        plan.weeks[location.weekIndex].days[location.dayIndex].state = .skipped
        plan.weeks[location.weekIndex].days[location.dayIndex].completionDate = Date()
        plan.updatedAt = Date()
        activePlan = plan
        persist()
    }

    func moveDay(dayId: UUID, to newDate: Date) {
        guard var plan = activePlan,
              let location = dayLocation(dayId: dayId, in: plan) else { return }
        let currentState = plan.weeks[location.weekIndex].days[location.dayIndex].state
        guard currentState == .planned || currentState == .moved else { return }

        var day = plan.weeks[location.weekIndex].days[location.dayIndex]
        day.movedFromDate = day.scheduledDate
        day.scheduledDate = Calendar.current.startOfDay(for: newDate)
        day.state = .moved
        plan.weeks[location.weekIndex].days[location.dayIndex] = day
        plan.updatedAt = Date()

        activePlan = plan
        persist()
    }

    func resetDayToPlanned(dayId: UUID) {
        guard var plan = activePlan,
              let location = dayLocation(dayId: dayId, in: plan) else { return }

        var day = plan.weeks[location.weekIndex].days[location.dayIndex]
        guard day.state == .skipped || day.state == .moved else { return }

        day.state = .planned
        day.completionDate = nil
        day.completedWorkoutId = nil
        day.movedFromDate = nil
        plan.weeks[location.weekIndex].days[location.dayIndex] = day
        plan.updatedAt = Date()

        activePlan = plan
        persist()
    }

    // MARK: - Private

    private func workoutContext(
        in plan: ProgramPlan?,
        workoutId: UUID,
        isArchivedPlan: Bool
    ) -> ProgramWorkoutContext? {
        guard let plan else { return nil }

        for week in plan.weeks {
            if let day = week.days.first(where: { $0.completedWorkoutId == workoutId }) {
                let completion = plan.completionRecords
                    .filter { $0.workoutId == workoutId }
                    .max(by: { $0.completedAt < $1.completedAt })
                return ProgramWorkoutContext(
                    planId: plan.id,
                    planName: plan.name,
                    dayId: day.id,
                    weekNumber: day.weekNumber,
                    dayNumber: day.dayNumber,
                    readinessScore: completion?.readinessScore,
                    readinessBand: completion?.readinessBand,
                    isArchivedPlan: isArchivedPlan
                )
            }
        }
        return nil
    }

    private func applyCompletion(
        to sourcePlan: ProgramPlan,
        workout: Workout,
        source: ProgramCompletionSource,
        dailyHealthStore: [Date: DailyHealthData],
        ouraScores: [Date: OuraDailyScoreDay]? = nil
    ) -> ProgramPlan? {
        var plan = sourcePlan

        guard let location = dayLocationForCompletion(
            in: plan,
            workoutDate: workout.date,
            plannedDayId: source.plannedDayId,
            plannedDayDate: source.plannedDayDate
        ) else {
            return nil
        }

        var day = plan.weeks[location.weekIndex].days[location.dayIndex]
        guard day.state != .completed else { return nil }

        let readiness = ProgramAutoregulationEngine.readinessSnapshot(
            dailyHealthStore: dailyHealthStore,
            ouraScores: ouraScores,
            on: workout.date,
            rule: plan.progressionRule
        )

        let plannedTargetsByName = (source.plannedTargetsSnapshot ?? []).reduce(into: [String: PlannedExerciseTarget]()) { partial, target in
            partial[normalize(target.exerciseName)] = target
        }
        let evaluationTargets = day.exercises.map { target in
            plannedTargetsByName[normalize(target.exerciseName)] ?? target
        }

        let evaluations = evaluationTargets.map { target -> ExerciseProgressEvaluation in
            let completedSets = workout.exercises
                .first(where: { normalize($0.name) == normalize(target.exerciseName) })?
                .sets ?? []
            return ProgramAutoregulationEngine.evaluateCompletion(
                planned: target,
                completedSets: completedSets,
                rule: plan.progressionRule
            )
        }

        let successfulCount = evaluations.filter { $0.wasSuccessful }.count
        let totalCount = max(evaluationTargets.count, 1)
        let adherenceRatio = Double(successfulCount) / Double(totalCount)

        day.state = .completed
        day.completedWorkoutId = workout.id
        day.completionDate = workout.date
        plan.weeks[location.weekIndex].days[location.dayIndex] = day

        var nextTargetsByName: [String: PlannedExerciseTarget] = [:]
        for evaluation in evaluations {
            let key = normalize(evaluation.nextTarget.exerciseName)
            nextTargetsByName[key] = evaluation.nextTarget
        }

        propagateTargets(
            plan: &plan,
            fromDate: day.scheduledDate,
            targetsByName: nextTargetsByName
        )

        plan.completionRecords.append(
            ProgramCompletionRecord(
                planId: plan.id,
                dayId: day.id,
                workoutId: workout.id,
                completedAt: workout.date,
                readinessScore: readiness.score,
                readinessBand: readiness.band,
                adherenceRatio: adherenceRatio,
                successfulExerciseCount: successfulCount,
                totalExerciseCount: evaluationTargets.count
            )
        )
        plan.updatedAt = Date()
        return plan
    }

    private func dayLocation(dayId: UUID, in plan: ProgramPlan) -> ProgramDayLocation? {
        for weekIndex in plan.weeks.indices {
            if let dayIndex = plan.weeks[weekIndex].days.firstIndex(where: { $0.id == dayId }) {
                return ProgramDayLocation(weekIndex: weekIndex, dayIndex: dayIndex)
            }
        }
        return nil
    }

    private func dayLocationForCompletion(
        in plan: ProgramPlan,
        workoutDate: Date,
        plannedDayId: UUID?,
        plannedDayDate: Date?
    ) -> ProgramDayLocation? {
        if let plannedDayId,
           let exact = dayLocation(dayId: plannedDayId, in: plan) {
            return exact
        }

        if let plannedDayDate {
            let plannedStart = Calendar.current.startOfDay(for: plannedDayDate)
            let eligibleStates: Set<ProgramSessionState> = [.planned, .moved]
            for weekIndex in plan.weeks.indices {
                for dayIndex in plan.weeks[weekIndex].days.indices {
                    let day = plan.weeks[weekIndex].days[dayIndex]
                    guard eligibleStates.contains(day.state) else { continue }
                    if Calendar.current.isDate(day.scheduledDate, inSameDayAs: plannedStart) {
                        return ProgramDayLocation(weekIndex: weekIndex, dayIndex: dayIndex)
                    }
                }
            }
        }

        let workoutDay = Calendar.current.startOfDay(for: workoutDate)
        let eligibleStates: Set<ProgramSessionState> = [.planned, .moved]

        var nearest: (location: ProgramDayLocation, distance: TimeInterval)?

        for weekIndex in plan.weeks.indices {
            for dayIndex in plan.weeks[weekIndex].days.indices {
                let day = plan.weeks[weekIndex].days[dayIndex]
                guard eligibleStates.contains(day.state) else { continue }

                if Calendar.current.isDate(day.scheduledDate, inSameDayAs: workoutDay) {
                    return ProgramDayLocation(weekIndex: weekIndex, dayIndex: dayIndex)
                }

                let distance = abs(day.scheduledDate.timeIntervalSince(workoutDate))
                if let currentNearest = nearest {
                    if distance < currentNearest.distance {
                        nearest = (ProgramDayLocation(weekIndex: weekIndex, dayIndex: dayIndex), distance)
                    }
                } else {
                    nearest = (ProgramDayLocation(weekIndex: weekIndex, dayIndex: dayIndex), distance)
                }
            }
        }

        return nearest?.location
    }

    private func propagateTargets(
        plan: inout ProgramPlan,
        fromDate: Date,
        targetsByName: [String: PlannedExerciseTarget]
    ) {
        guard !targetsByName.isEmpty else { return }

        for weekIndex in plan.weeks.indices {
            for dayIndex in plan.weeks[weekIndex].days.indices {
                var day = plan.weeks[weekIndex].days[dayIndex]
                guard day.scheduledDate > fromDate else { continue }
                guard day.state == .planned || day.state == .moved else { continue }

                day.exercises = day.exercises.map { exercise in
                    let key = normalize(exercise.exerciseName)
                    guard let replacement = targetsByName[key] else { return exercise }

                    var updated = exercise
                    updated.targetWeight = replacement.targetWeight
                    updated.failureStreak = replacement.failureStreak
                    return updated
                }

                plan.weeks[weekIndex].days[dayIndex] = day
            }
        }
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func fileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }

    private func resortArchivedPlans() {
        archivedPlans.sort { lhs, rhs in
            archivedSortKey(lhs) > archivedSortKey(rhs)
        }
    }

    private func archivedSortKey(_ plan: ProgramPlan) -> Date {
        plan.archivedAt ?? plan.updatedAt
    }

    private func persist() {
        persistRevision += 1
        let revision = persistRevision
        let snapshot = ProgramStoreSnapshot(
            activePlan: activePlan,
            archivedPlans: archivedPlans,
            schemaVersion: 1
        )
        let url = fileURL()
        let persistenceStore = snapshotPersistenceStore
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            print("Failed to encode program store: \(error)")
            return
        }

        Task.detached(priority: .utility) {
            await persistenceStore.writeIfCurrent(data, to: url, revision: revision)
        }
    }
}

private actor ProgramSnapshotPersistenceStore {
    private var lastWrittenRevision: Int = 0

    func writeIfCurrent(_ data: Data, to url: URL, revision: Int) {
        guard revision >= lastWrittenRevision else { return }

        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            lastWrittenRevision = revision
        } catch {
            print("Failed to persist program store: \(error)")
        }
    }
}
