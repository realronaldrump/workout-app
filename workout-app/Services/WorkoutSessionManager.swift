import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class RestTimerState: ObservableObject {
    static let durationPreferenceKey = "restTimerDurationSeconds"
    static let automaticStartPreferenceKey = "restTimerAutomaticStartEnabled"
    static let defaultDuration = 90

    @Published private(set) var secondsRemaining: Int = 0
    @Published private(set) var isActive: Bool = false
    /// Default rest length started after a completed set. Persisted across launches.
    @Published private(set) var duration: Int
    /// Length of the countdown currently running (default duration plus any extensions).
    /// Drives the progress ring so extending a rest does not change the saved default.
    @Published private(set) var currentTotal: Int
    @Published private(set) var automaticStartEnabled: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.automaticStartEnabled = (defaults.object(forKey: Self.automaticStartPreferenceKey) as? Bool) ?? true
        let stored = defaults.integer(forKey: Self.durationPreferenceKey)
        let initial = stored > 0 ? Self.clamp(stored) : Self.defaultDuration
        self.duration = initial
        self.currentTotal = initial
    }

    nonisolated deinit {}

    func setAutomaticStartEnabled(_ enabled: Bool) {
        automaticStartEnabled = enabled
        defaults.set(enabled, forKey: Self.automaticStartPreferenceKey)
    }

    func setDuration(_ seconds: Int) {
        let clamped = Self.clamp(seconds)
        guard clamped != duration else { return }
        duration = clamped
        defaults.set(clamped, forKey: Self.durationPreferenceKey)
    }

    func update(isActive: Bool, secondsRemaining: Int) {
        let clampedSeconds = max(0, secondsRemaining)
        if self.isActive != isActive {
            self.isActive = isActive
        }
        if self.secondsRemaining != clampedSeconds {
            self.secondsRemaining = clampedSeconds
        }
    }

    /// Picks up a default changed elsewhere (e.g. Settings) while the app was running.
    func syncDurationFromDefaults() {
        automaticStartEnabled = (defaults.object(forKey: Self.automaticStartPreferenceKey) as? Bool) ?? true
        let stored = defaults.integer(forKey: Self.durationPreferenceKey)
        guard stored > 0 else { return }
        let clamped = Self.clamp(stored)
        if clamped != duration {
            duration = clamped
        }
    }

    func setCurrentTotal(_ seconds: Int) {
        let clamped = max(1, seconds)
        guard clamped != currentTotal else { return }
        currentTotal = clamped
    }

    private static func clamp(_ seconds: Int) -> Int {
        max(15, min(600, seconds))
    }
}

enum WorkoutSessionError: LocalizedError {
    case noActiveSession
    case noCompletedSets
    case finishInProgress
    case sessionChangedWhileSaving
    case savedWorkoutDraftCleanupFailed
    case completedSetMissingFields(exercise: String, setOrder: Int)
    case completedSetMissingCardioFields(exercise: String, setOrder: Int)

    var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active session."
        case .noCompletedSets:
            return "Log at least one completed set before finishing."
        case .finishInProgress:
            return "Your workout is already being saved."
        case .sessionChangedWhileSaving:
            return "An earlier version was saved, but your session changed while saving. Your current draft is still here. Review it and finish again."
        case .savedWorkoutDraftCleanupFailed:
            return "Your workout was saved, but its active draft could not be cleared. "
                + "Try finishing again; this will update the saved workout without making a duplicate."
        case .completedSetMissingFields(let exercise, let setOrder):
            return "Set \(setOrder) in \(exercise) is marked complete but missing valid weight/reps."
        case .completedSetMissingCardioFields(let exercise, let setOrder):
            return "Set \(setOrder) in \(exercise) is marked complete but missing valid cardio metrics."
        }
    }
}

enum SetCompletionToggleResult {
    case toggled(isCompleted: Bool)
    case invalid(message: String)
    case missingSet
}

struct SetPrefill: Sendable {
    var weight: Double?
    var reps: Int?
    var distance: Double?
    var seconds: Double?

    init(weight: Double? = nil, reps: Int? = nil, distance: Double? = nil, seconds: Double? = nil) {
        self.weight = weight
        self.reps = reps
        self.distance = distance
        self.seconds = seconds
    }
}

enum DraftSaveState: Equatable {
    case idle
    case saving
    case saved(Date)
    case failed(String)
}

@MainActor
final class WorkoutSessionManager: ObservableObject {
    @Published var activeSession: ActiveWorkoutSession?
    @Published var isPresentingSessionUI: Bool = false
    @Published private(set) var isFinishing = false
    @Published private(set) var draftSaveState: DraftSaveState = .idle
    @Published private(set) var draftRecoveryMessage: String?
    @Published private(set) var recoveredDraftURL: URL?

    let restTimer: RestTimerState
    var restTimerSecondsRemaining: Int { restTimer.secondsRemaining }
    var restTimerIsActive: Bool { restTimer.isActive }
    var restTimerDuration: Int { restTimer.duration }

    private let draftURL: URL
    private let persistenceDelayNanoseconds: UInt64
    private var unreadableDraftNeedsPreservation = false
    private var persistTask: Task<Void, Never>?
    private var restTimerTask: Task<Void, Never>?
    private var restTimerEndTime: Date?

    init(draftURL: URL? = nil, persistenceDelayNanoseconds: UInt64 = 250_000_000, defaults: UserDefaults = .standard) {
        self.restTimer = RestTimerState(defaults: defaults)
        self.persistenceDelayNanoseconds = persistenceDelayNanoseconds
        self.draftURL = draftURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("active_session_v1.json")
        // Resolve recovery before any caller can decide to start or repeat a workout.
        // Launch-time Health/iCloud loads must never leave an existing draft invisible.
        restoreDraftSynchronously()
    }

    nonisolated deinit {
        persistTask?.cancel()
        restTimerTask?.cancel()
    }

    func restoreDraft() async {
        restoreDraftSynchronously()
    }

    private func restoreDraftSynchronously() {
        // A retry must never replace a workout the user already started.
        guard activeSession == nil else { return }
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(ActiveWorkoutSession.self, from: data)
            activeSession = decoded
            draftRecoveryMessage = nil
            unreadableDraftNeedsPreservation = false
            draftSaveState = .saved(decoded.lastModifiedAt)
            restoreRestTimer(from: decoded)
        } catch {
            unreadableDraftNeedsPreservation = true
            draftRecoveryMessage = "Your previous workout draft could not be opened. It has been kept for recovery. "
                + "You can retry opening it or start a new workout."
            draftSaveState = .failed("The previous workout draft could not be opened.")
            // Keep the original bytes before a later workout can use the draft path.
            // If preservation itself fails, subsequent writes remain blocked.
            preserveUnreadableDraftIfNeeded()
        }
    }

    func dismissDraftRecoveryMessage() {
        draftRecoveryMessage = nil
    }

    func retryDraftSave() {
        saveImmediately()
    }

    private func preserveUnreadableDraftIfNeeded() {
        guard unreadableDraftNeedsPreservation else { return }
        if let recoveredDraftURL,
           let original = try? Data(contentsOf: draftURL),
           let preserved = try? Data(contentsOf: recoveredDraftURL),
           original == preserved {
            unreadableDraftNeedsPreservation = false
            return
        }
        do {
            let recoveryURL = draftURL.deletingPathExtension()
                .appendingPathExtension("recovery-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: draftURL, to: recoveryURL)
            recoveredDraftURL = recoveryURL
            unreadableDraftNeedsPreservation = false
        } catch {
            draftSaveState = .failed("Your previous draft could not be backed up. Free up storage and tap Retry. Your current workout is still open.")
        }
    }

    func startSession(
        name: String,
        gymProfileId: UUID?,
        preselectedExercise: String? = nil,
        initialSetPrefill: SetPrefill? = nil
    ) {
        cancelRestTimer()

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preselected = preselectedExercise?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = !trimmedName.isEmpty ? trimmedName
            : ((preselected?.isEmpty == false) ? (preselected ?? "Workout") : "Workout")

        var session = ActiveWorkoutSession(
            startedAt: Date(),
            name: sessionName,
            gymProfileId: gymProfileId
        )

        if let exercise = preselectedExercise?.trimmingCharacters(in: .whitespacesAndNewlines),
           !exercise.isEmpty {
            let prefill = initialSetPrefill ?? SetPrefill()
            session.exercises = [
                ActiveExercise(name: exercise, sets: [
                    ActiveSet(
                        order: 1,
                        weight: prefill.weight,
                        reps: prefill.reps,
                        distance: prefill.distance,
                        seconds: prefill.seconds
                    )
                ])
            ]
        }

        activeSession = session
        saveImmediately()
        AppAnalytics.shared.track(
            AnalyticsSignal.sessionStarted,
            payload: [
                "Session.hasGymProfile": gymProfileId == nil ? "false" : "true",
                "Session.hasPrefilledExercise": (preselected?.isEmpty == false) ? "true" : "false"
            ]
        )
    }

    func updateSessionName(_ name: String) {
        guard var session = activeSession else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        session.name = trimmed
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func setGymProfileId(_ gymProfileId: UUID?) {
        guard var session = activeSession else { return }
        session.gymProfileId = gymProfileId
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func addExercise(name: String) {
        addExercise(name: name, initialSetPrefill: nil)
    }

    func addExercise(name: String, initialSetPrefill: SetPrefill? = nil) {
        guard var session = activeSession else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = normalizedExerciseName(trimmed)
        let exists = session.exercises.contains { normalizedExerciseName($0.name) == normalized }
        guard !exists else { return }

        let prefill = initialSetPrefill ?? SetPrefill()
        session.exercises.append(ActiveExercise(name: trimmed, sets: [
            ActiveSet(
                order: 1,
                weight: prefill.weight,
                reps: prefill.reps,
                distance: prefill.distance,
                seconds: prefill.seconds
            )
        ]))
        touch(&session)
        activeSession = session
        schedulePersistDraft()
        AppAnalytics.shared.track(
            AnalyticsSignal.sessionExerciseAdded,
            payload: ["Session.isPrefilled": initialSetPrefill == nil ? "false" : "true"]
        )
    }

    func removeExercise(id: UUID) {
        guard var session = activeSession else { return }
        let removedSetIDs = Set(session.exercises.first(where: { $0.id == id })?.sets.map(\.id) ?? [])
        if let source = session.restTimerSourceSetId, removedSetIDs.contains(source) {
            clearRestTimerMetadata(in: &session)
            stopRestTimer()
        }
        session.exercises.removeAll { $0.id == id }
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func addSet(exerciseId: UUID) {
        addSet(exerciseId: exerciseId, prefill: SetPrefill())
    }

    func addSet(exerciseId: UUID, prefill: SetPrefill) {
        guard var session = activeSession else { return }
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }

        let nextOrder = (session.exercises[exerciseIndex].sets.map(\.order).max() ?? 0) + 1
        let newSet = ActiveSet(
            order: nextOrder,
            weight: prefill.weight,
            reps: prefill.reps,
            distance: prefill.distance,
            seconds: prefill.seconds
        )
        session.exercises[exerciseIndex].sets.append(newSet)

        touch(&session)
        activeSession = session
        schedulePersistDraft()
        AppAnalytics.shared.track(AnalyticsSignal.sessionSetAdded)
    }

    func updateSet(exerciseId: UUID, setId: UUID, prefill: SetPrefill, inputDraft: SetInputDraft? = nil) {
        guard var session = activeSession else { return }
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        guard let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else { return }

        let currentSet = session.exercises[exerciseIndex].sets[setIndex]
        if currentSet.weight == prefill.weight,
           currentSet.reps == prefill.reps,
           currentSet.distance == prefill.distance,
           currentSet.seconds == prefill.seconds,
           currentSet.inputDraft == inputDraft {
            return
        }

        session.exercises[exerciseIndex].sets[setIndex].weight = prefill.weight
        session.exercises[exerciseIndex].sets[setIndex].reps = prefill.reps
        session.exercises[exerciseIndex].sets[setIndex].distance = prefill.distance
        session.exercises[exerciseIndex].sets[setIndex].seconds = prefill.seconds
        session.exercises[exerciseIndex].sets[setIndex].inputDraft = inputDraft
        let updatedSet = session.exercises[exerciseIndex].sets[setIndex]
        if updatedSet.isCompleted,
           !hasEnteredData(updatedSet, isCardio: isCardioExercise(session.exercises[exerciseIndex].name)) {
            session.exercises[exerciseIndex].sets[setIndex].isCompleted = false
            session.exercises[exerciseIndex].sets[setIndex].completedAt = nil
            if session.restTimerSourceSetId == setId {
                clearRestTimerMetadata(in: &session)
                stopRestTimer()
            }
        }

        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func deleteSet(exerciseId: UUID, setId: UUID) {
        guard var session = activeSession else { return }
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        if session.restTimerSourceSetId == setId {
            clearRestTimerMetadata(in: &session)
            stopRestTimer()
        }
        session.exercises[exerciseIndex].sets.removeAll { $0.id == setId }
        renumberSets(&session.exercises[exerciseIndex])
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    @discardableResult
    func toggleSetComplete(exerciseId: UUID, setId: UUID) -> SetCompletionToggleResult {
        guard var session = activeSession else { return .missingSet }
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }) else {
            return .missingSet
        }
        guard let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return .missingSet
        }

        var set = session.exercises[exerciseIndex].sets[setIndex]
        let isCardio = isCardioExercise(session.exercises[exerciseIndex].name)

        if !set.isCompleted, let validationMessage = validationMessageForSetCompletion(set, isCardio: isCardio) {
            return .invalid(message: validationMessage)
        }

        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? Date() : nil
        if set.isCompleted { set.inputDraft = nil }
        session.exercises[exerciseIndex].sets[setIndex] = set

        if !set.isCompleted, session.restTimerSourceSetId == setId {
            clearRestTimerMetadata(in: &session)
            stopRestTimer()
        }
        touch(&session)
        activeSession = session
        restTimer.syncDurationFromDefaults()
        if set.isCompleted, !isCardio, restTimer.automaticStartEnabled {
            startRestTimer(sourceSetId: setId)
        }
        saveImmediately()
        if set.isCompleted {
            AppAnalytics.shared.track(
                AnalyticsSignal.sessionSetCompleted,
                payload: ["Session.isCardio": isCardio ? "true" : "false"]
            )
        }
        return .toggled(isCompleted: set.isCompleted)
    }

    func dismissMuscleGroupSuggestion(_ group: MuscleGroup) {
        guard var session = activeSession else { return }
        if !session.dismissedMuscleGroupSuggestions.contains(group.rawValue) {
            session.dismissedMuscleGroupSuggestions.append(group.rawValue)
            touch(&session)
            activeSession = session
            schedulePersistDraft()
        }
    }

    func clearAllMuscleGroupSuggestionDismissals() {
        guard var session = activeSession else { return }
        session.dismissedMuscleGroupSuggestions.removeAll()
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func moveExercise(from source: IndexSet, to destination: Int) {
        guard var session = activeSession else { return }
        session.exercises.move(fromOffsets: source, toOffset: destination)
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    // MARK: - Rest Timer

    func startRestTimer(sourceSetId: UUID? = nil) {
        restTimer.syncDurationFromDefaults()
        restTimer.setCurrentTotal(restTimerDuration)
        beginRestTimer(until: Date().addingTimeInterval(TimeInterval(restTimerDuration)), sourceSetId: sourceSetId)
    }

    /// Adds time to the running rest (or starts a short rest if none is running)
    /// without changing the saved default duration.
    func extendRestTimer(by seconds: Int) {
        let clampedSeconds = min(3_600, max(0, seconds))
        guard clampedSeconds > 0 else { return }

        let now = Date()
        if let endTime = restTimerEndTime, endTime > now, restTimerIsActive {
            let extendedEnd = min(endTime.addingTimeInterval(TimeInterval(clampedSeconds)), now.addingTimeInterval(3_600))
            restTimer.setCurrentTotal(min(3_600, restTimer.currentTotal + clampedSeconds))
            beginRestTimer(until: extendedEnd, sourceSetId: activeSession?.restTimerSourceSetId)
        } else {
            restTimer.setCurrentTotal(clampedSeconds)
            beginRestTimer(until: now.addingTimeInterval(TimeInterval(clampedSeconds)))
        }
    }

    func incompleteSetsWithEnteredDataCount() -> Int {
        guard let session = activeSession else { return 0 }

        return session.exercises.reduce(into: 0) { count, exercise in
            let isCardio = isCardioExercise(exercise.name)
            count += exercise.sets.filter { !$0.isCompleted && hasEnteredData($0, isCardio: isCardio) }.count
        }
    }

    @discardableResult
    func markIncompleteSetsWithEnteredDataCompleted() -> Int {
        guard var session = activeSession else { return 0 }

        var markedCount = 0
        for exerciseIndex in session.exercises.indices {
            let isCardio = isCardioExercise(session.exercises[exerciseIndex].name)

            for setIndex in session.exercises[exerciseIndex].sets.indices {
                guard !session.exercises[exerciseIndex].sets[setIndex].isCompleted else { continue }
                guard hasEnteredData(session.exercises[exerciseIndex].sets[setIndex], isCardio: isCardio) else { continue }

                session.exercises[exerciseIndex].sets[setIndex].isCompleted = true
                session.exercises[exerciseIndex].sets[setIndex].completedAt = Date()
                markedCount += 1
            }
        }

        guard markedCount > 0 else { return 0 }

        touch(&session)
        activeSession = session
        schedulePersistDraft()
        return markedCount
    }

    private func beginRestTimer(until endTime: Date, sourceSetId: UUID? = nil, persist: Bool = true) {
        restTimerEndTime = endTime
        restTimerTask?.cancel()
        if !Self.isRunningTests {
            RestTimerNotifier.schedule(at: endTime)
        }

        updateRestTimerState(notifyOnCompletion: false)
        if persist, var session = activeSession {
            session.restTimerEndsAt = endTime
            session.restTimerTotalSeconds = restTimer.currentTotal
            session.restTimerSourceSetId = sourceSetId
            activeSession = session
            schedulePersistDraft()
        }
        restTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self?.restTimerIsActive == true, let endTime = self?.restTimerEndTime,
                      let sleepNanoseconds = self?.sleepNanosecondsUntilNextRestTimerTick(endTime: endTime) else { return }
                do {
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch { return }
                self?.updateRestTimerState(notifyOnCompletion: true)
            }
        }
    }

    func cancelRestTimer() {
        stopRestTimer()
        if var session = activeSession, session.restTimerEndsAt != nil {
            clearRestTimerMetadata(in: &session)
            activeSession = session
            saveImmediately()
        }
    }

    private func stopRestTimer() {
        restTimerTask?.cancel()
        restTimerTask = nil
        restTimerEndTime = nil
        restTimer.update(isActive: false, secondsRemaining: 0)
        if !Self.isRunningTests {
            RestTimerNotifier.cancel()
        }
    }

    func setRestTimerDuration(_ seconds: Int) {
        restTimer.setDuration(seconds)
    }

    func setRestTimerAutomaticStartEnabled(_ enabled: Bool) {
        restTimer.setAutomaticStartEnabled(enabled)
    }

    func setCompletionValidationMessage(exerciseId: UUID, setId: UUID) -> String? {
        guard let exercise = activeSession?.exercises.first(where: { $0.id == exerciseId }),
              let set = exercise.sets.first(where: { $0.id == setId }) else { return nil }
        return validationMessageForSetCompletion(set, isCardio: isCardioExercise(exercise.name))
    }

    /// Persists one snapshot before clearing its draft. Edits or a replacement session that
    /// arrive during persistence are preserved, and overlapping finish requests are rejected.
    func finish(persist: @MainActor (LoggedWorkout) async throws -> Void) async throws -> LoggedWorkout {
        guard !isFinishing else { throw WorkoutSessionError.finishInProgress }
        guard let session = activeSession else { throw WorkoutSessionError.noActiveSession }
        let workout = try prepareFinishedWorkout(from: session)

        isFinishing = true
        defer { isFinishing = false }
        saveImmediately()
        try await persist(workout)
        try await completeFinish(workout, matching: session)
        return workout
    }

    private func prepareFinishedWorkout(from session: ActiveWorkoutSession) throws -> LoggedWorkout {

        var totalLoggedSets = 0
        var loggedExercises: [LoggedExercise] = []

        for exercise in session.exercises {
            let completedSets = exercise.sets
                .sorted { $0.order < $1.order }
                .filter { $0.isCompleted }

            let isCardio = isCardioExercise(exercise.name)
            var loggedSets: [LoggedSet] = []
            loggedSets.reserveCapacity(completedSets.count)

            // Validate + map completed sets.
            for set in completedSets {
                guard hasEnteredData(set, isCardio: isCardio) else {
                    if isCardio {
                        throw WorkoutSessionError.completedSetMissingCardioFields(exercise: exercise.name, setOrder: set.order)
                    }
                    throw WorkoutSessionError.completedSetMissingFields(exercise: exercise.name, setOrder: set.order)
                }
                if isCardio {
                    let reps = max(set.reps ?? 0, 0)
                    let distance = max(set.distance ?? 0, 0)
                    let seconds = max(set.seconds ?? 0, 0)

                    let hasAnyMetric = reps > 0 || distance > 0 || seconds > 0
                    guard hasAnyMetric else {
                        throw WorkoutSessionError.completedSetMissingCardioFields(exercise: exercise.name, setOrder: set.order)
                    }

                    let weight = max(set.weight ?? 0, 0)
                    loggedSets.append(
                        LoggedSet(
                            id: set.id,
                            order: set.order,
                            weight: weight,
                            reps: reps,
                            distance: distance > 0 ? distance : nil,
                            seconds: seconds > 0 ? seconds : nil
                        )
                    )
                } else {
                    guard let weight = set.weight,
                          let reps = set.reps,
                          weight >= 0,
                          reps > 0 else {
                        throw WorkoutSessionError.completedSetMissingFields(exercise: exercise.name, setOrder: set.order)
                    }
                    loggedSets.append(LoggedSet(id: set.id, order: set.order, weight: weight, reps: reps))
                }
            }

            if !loggedSets.isEmpty {
                totalLoggedSets += loggedSets.count
                loggedExercises.append(LoggedExercise(id: exercise.id, name: exercise.name, sets: loggedSets))
            }
        }

        guard totalLoggedSets > 0 else { throw WorkoutSessionError.noCompletedSets }

        let endedAt = Date()
        return LoggedWorkout(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: endedAt,
            name: session.name,
            gymProfileId: session.gymProfileId,
            exercises: loggedExercises,
            createdAt: endedAt,
            updatedAt: endedAt
        )
    }

    private func completeFinish(_ workout: LoggedWorkout, matching session: ActiveWorkoutSession) async throws {
        guard sessionMatchesWorkoutContent(session) else {
            saveImmediately()
            throw WorkoutSessionError.sessionChangedWhileSaving
        }
        do {
            try deleteDraftFile(matching: session.id)
        } catch {
            draftSaveState = .failed("Workout saved. The active draft could not be cleared; try finishing again.")
            throw WorkoutSessionError.savedWorkoutDraftCleanupFailed
        }
        stopRestTimer()
        activeSession = nil
        draftSaveState = .idle
        let completedSetCount = workout.exercises.reduce(0) { $0 + $1.sets.count }
        AppAnalytics.shared.track(
            AnalyticsSignal.sessionFinished,
            payload: [
                "Session.exerciseCount": "\(workout.exercises.count)",
                "Session.completedSetCount": "\(completedSetCount)"
            ],
            floatValue: max(0, workout.endedAt.timeIntervalSince(workout.startedAt))
        )
    }

    @discardableResult
    func discardDraft() async -> Bool {
        let didHaveActiveSession = activeSession != nil
        do {
            try deleteDraftFile(matching: activeSession?.id)
        } catch {
            draftSaveState = .failed("The workout draft could not be discarded. Try again; your workout is still open.")
            return false
        }
        stopRestTimer()
        activeSession = nil
        draftSaveState = .idle
        isPresentingSessionUI = false
        if didHaveActiveSession {
            AppAnalytics.shared.track(AnalyticsSignal.sessionDiscarded)
        }
        return true
    }

    /// Lifecycle flushes and debounced writes use the same main-actor writer. A cancelled
    /// async writer can never overwrite this newer snapshot after the app backgrounds.
    @discardableResult
    func saveImmediately() -> Bool {
        persistTask?.cancel()
        persistTask = nil
        guard let session = activeSession else { return true }
        preserveUnreadableDraftIfNeeded()
        guard !unreadableDraftNeedsPreservation else { return false }
        draftSaveState = .saving
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(session)
            try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Resting with the phone locked must not make a lifecycle save fail.
            try data.write(to: draftURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            draftSaveState = .saved(Date())
            return true
        } catch {
            draftSaveState = .failed("Could not save this workout on your device. Your workout is still open. Check available storage, then tap Retry.")
            return false
        }
    }

    // MARK: - Draft Persistence

    private func schedulePersistDraft() {
        guard activeSession != nil else { return }
        persistTask?.cancel()
        draftSaveState = .saving
        persistTask = Task { [weak self] in
            guard let delay = self?.persistenceDelayNanoseconds else { return }
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch { return }
            guard !Task.isCancelled else { return }
            self?.saveImmediately()
        }
    }

    private func deleteDraftFile(matching sessionID: UUID? = nil) throws {
        persistTask?.cancel()
        persistTask = nil
        guard FileManager.default.fileExists(atPath: draftURL.path) else { return }
        if let sessionID {
            let stored = try JSONDecoder().decode(DraftIdentity.self, from: Data(contentsOf: draftURL))
            guard stored.id == sessionID else { return }
        }
        try FileManager.default.removeItem(at: draftURL)
    }

    private struct DraftIdentity: Decodable {
        let id: UUID
    }

    private func sessionMatchesWorkoutContent(_ snapshot: ActiveWorkoutSession) -> Bool {
        guard var current = activeSession else { return false }
        // Timer expiration/extension is not an edit to the workout being saved.
        current.restTimerEndsAt = snapshot.restTimerEndsAt
        current.restTimerTotalSeconds = snapshot.restTimerTotalSeconds
        current.restTimerSourceSetId = snapshot.restTimerSourceSetId
        return current == snapshot
    }

    private func restoreRestTimer(from session: ActiveWorkoutSession) {
        guard let endTime = session.restTimerEndsAt else { return }
        let remaining = endTime.timeIntervalSinceNow
        guard remaining > 0, remaining <= 3_600 else {
            clearStoredRestTimer()
            return
        }
        restTimer.setCurrentTotal(min(3_600, max(Int(ceil(remaining)), session.restTimerTotalSeconds ?? restTimerDuration)))
        beginRestTimer(until: endTime, sourceSetId: session.restTimerSourceSetId, persist: false)
    }

    private func clearRestTimerMetadata(in session: inout ActiveWorkoutSession) {
        session.restTimerEndsAt = nil
        session.restTimerTotalSeconds = nil
        session.restTimerSourceSetId = nil
    }

    private func clearStoredRestTimer() {
        guard var session = activeSession, session.restTimerEndsAt != nil else { return }
        clearRestTimerMetadata(in: &session)
        activeSession = session
        saveImmediately()
    }

    private func fileURL() -> URL {
        draftURL
    }

    private func touch(_ session: inout ActiveWorkoutSession) {
        session.lastModifiedAt = Date()
    }

    private func renumberSets(_ exercise: inout ActiveExercise) {
        // Keep order stable and continuous after deletes.
        let sorted = exercise.sets.sorted { $0.order < $1.order }
        var updated: [ActiveSet] = []
        updated.reserveCapacity(sorted.count)
        for (index, set) in sorted.enumerated() {
            var copy = set
            copy.order = index + 1
            updated.append(copy)
        }
        exercise.sets = updated
    }

    private func validationMessageForSetCompletion(_ set: ActiveSet, isCardio: Bool) -> String? {
        if isCardio {
            return hasEnteredData(set, isCardio: true)
                ? nil
                : "Enter a positive distance, time, or rep count. Metrics cannot be negative."
        }

        guard hasEnteredData(set, isCardio: false) else {
            return "Enter a weight of 0 or more and at least 1 rep. Use 0 for bodyweight."
        }

        return nil
    }

    private func hasEnteredData(_ set: ActiveSet, isCardio: Bool) -> Bool {
        if let draft = set.inputDraft {
            let rawMetrics: [(String, Double?)] = [
                (draft.weight, WorkoutValueFormatter.parseDecimal(draft.weight)),
                (draft.reps, WorkoutValueFormatter.parseWholeNumber(draft.reps).map(Double.init)),
                (draft.distance, WorkoutValueFormatter.parseDecimal(draft.distance)),
                (draft.duration, WorkoutValueFormatter.parseDurationSeconds(draft.duration))
            ]
            for (text, value) in rawMetrics where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let value, value.isFinite, value >= 0 else { return false }
            }
        }
        let numericValues = [set.weight, set.distance, set.seconds].compactMap { $0 }
        guard numericValues.allSatisfy({ $0.isFinite && $0 >= 0 }), (set.reps ?? 0) >= 0,
              ((set.weight ?? 0) * Double(set.reps ?? 0)).isFinite else { return false }
        if isCardio {
            let reps = max(set.reps ?? 0, 0)
            let distance = max(set.distance ?? 0, 0)
            let seconds = max(set.seconds ?? 0, 0)
            return reps > 0 || distance > 0 || seconds > 0
        }

        guard let weight = set.weight, let reps = set.reps else {
            return false
        }
        return weight >= 0 && reps > 0
    }

    private func updateRestTimerState(notifyOnCompletion: Bool) {
        guard let endTime = restTimerEndTime else {
            restTimerTask?.cancel()
            restTimerTask = nil
            restTimer.update(isActive: false, secondsRemaining: 0)
            return
        }

        let remainingInterval = endTime.timeIntervalSinceNow
        if remainingInterval <= 0 {
            restTimerTask?.cancel()
            restTimerTask = nil
            restTimerEndTime = nil
            restTimer.update(isActive: false, secondsRemaining: 0)
            clearStoredRestTimer()
            if notifyOnCompletion {
                Haptics.notify(.success)
            }
            return
        }

        restTimer.update(isActive: true, secondsRemaining: Int(ceil(remainingInterval)))
    }

    private func sleepNanosecondsUntilNextRestTimerTick(endTime: Date) -> UInt64 {
        let remaining = max(0, endTime.timeIntervalSinceNow)
        let fractional = remaining - floor(remaining)
        let secondsUntilNextDisplayChange = fractional > 0.02 ? fractional : 1.0
        let clamped = min(max(secondsUntilNextDisplayChange, 0.05), 1.0)
        return UInt64(clamped * 1_000_000_000)
    }

    private func normalizedExerciseName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isCardioExercise(_ name: String) -> Bool {
        ExerciseMetadataManager.shared
            .resolvedTags(for: name)
            .contains(where: { $0.builtInGroup == .cardio })
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// Schedules a local notification for the end of a rest period so lifters who lock their
/// phone between sets still get alerted. Notifications are not shown while the app is in the
/// foreground (no presentation delegate), where the in-app timer and haptic handle it.
private enum RestTimerNotifier {
    private static let identifier = "rest-timer-complete"
    /// Bumped on every schedule/cancel so an in-flight scheduling task never re-adds a
    /// notification after the timer was cancelled or rescheduled.
    private static var generation = 0

    static func schedule(at endTime: Date) {
        let interval = endTime.timeIntervalSinceNow
        guard interval > 1 else {
            cancel()
            return
        }

        generation += 1
        let scheduledGeneration = generation
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                guard granted else { return }
            case .authorized, .provisional, .ephemeral:
                break
            default:
                return
            }

            let remaining = endTime.timeIntervalSinceNow
            guard remaining > 1, scheduledGeneration == generation else { return }

            let content = UNMutableNotificationContent()
            content.title = "Rest complete"
            content.body = "Time for your next set."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            try? await center.add(request)
        }
    }

    static func cancel() {
        generation += 1
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
