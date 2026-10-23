import Combine
import XCTest
@testable import workout_app

@MainActor
final class WorkoutSessionManagerTests: XCTestCase {
    func testRepeatWorkoutDoesNotReplaceActiveSessionWithoutConfirmation() {
        let manager = makeManager()
        manager.startSession(
            name: "In Progress",
            gymProfileId: nil,
            preselectedExercise: "Bench Press",
            initialSetPrefill: SetPrefill(weight: 135, reps: 8)
        )
        let activeSessionID = manager.activeSession?.id
        let workout = Workout(
            date: Date(),
            name: "Previous Workout",
            duration: "45m",
            exercises: [Exercise(name: "Squat", sets: [])]
        )

        WorkoutRepeatHelper.repeatWorkout(
            workout,
            gymProfileId: nil,
            weightIncrement: 5,
            sessionManager: manager,
            dataManager: WorkoutDataManager()
        )

        XCTAssertEqual(manager.activeSession?.id, activeSessionID)
        XCTAssertEqual(manager.activeSession?.name, "In Progress")
    }

    func testConfirmedRepeatDiscardsAndReplacesActiveSession() async {
        let manager = makeManager()
        manager.startSession(
            name: "In Progress",
            gymProfileId: nil,
            preselectedExercise: "Bench Press"
        )
        let activeSessionID = manager.activeSession?.id
        let workout = Workout(
            date: Date(),
            name: "Previous Workout",
            duration: "45m",
            exercises: [Exercise(name: "Squat", sets: [])]
        )

        await WorkoutRepeatHelper.replaceActiveSessionAndRepeat(
            workout,
            gymProfileId: nil,
            weightIncrement: 5,
            sessionManager: manager,
            dataManager: WorkoutDataManager()
        )

        XCTAssertNotEqual(manager.activeSession?.id, activeSessionID)
        XCTAssertEqual(manager.activeSession?.name, "Previous Workout")
        XCTAssertEqual(manager.activeSession?.exercises.map(\.name), ["Squat"])
        XCTAssertTrue(manager.isPresentingSessionUI)
    }

    func testIncompleteSetsWithEnteredDataCountOnlyIncludesFilledUncheckedSets() {
        let manager = makeManager()
        manager.startSession(
            name: "Upper",
            gymProfileId: nil,
            preselectedExercise: "Bench Press",
            initialSetPrefill: SetPrefill(weight: 135, reps: 8)
        )

        XCTAssertEqual(manager.incompleteSetsWithEnteredDataCount(), 1)
    }

    func testMarkIncompleteSetsWithEnteredDataCompletedMarksEligibleSets() {
        let manager = makeManager()
        manager.startSession(
            name: "Upper",
            gymProfileId: nil,
            preselectedExercise: "Bench Press",
            initialSetPrefill: SetPrefill(weight: 135, reps: 8)
        )

        let markedCount = manager.markIncompleteSetsWithEnteredDataCompleted()

        XCTAssertEqual(markedCount, 1)
        XCTAssertEqual(manager.incompleteSetsWithEnteredDataCount(), 0)
        XCTAssertEqual(manager.activeSession?.exercises.first?.sets.first?.isCompleted, true)
    }

    func testRestTimerTicksDoNotPublishWholeSessionManager() async throws {
        let manager = makeManager()
        var sessionManagerPublishCount = 0
        let cancellable = manager.objectWillChange.sink {
            sessionManagerPublishCount += 1
        }

        manager.startRestTimer()
        XCTAssertTrue(manager.restTimerIsActive)
        XCTAssertEqual(sessionManagerPublishCount, 0)

        try await Task.sleep(nanoseconds: 1_100_000_000)

        XCTAssertTrue(manager.restTimerIsActive)
        XCTAssertLessThan(manager.restTimerSecondsRemaining, manager.restTimerDuration)
        XCTAssertEqual(sessionManagerPublishCount, 0)

        manager.cancelRestTimer()
        cancellable.cancel()
    }

    func testImmediateSaveCannotBeReplacedByAnOlderDebouncedEdit() async throws {
        let manager = makeManager(persistenceDelayNanoseconds: 30_000_000)
        manager.startSession(name: "Original", gymProfileId: nil)
        manager.updateSessionName("Pending")
        XCTAssertEqual(manager.draftSaveState, .saving)
        manager.updateSessionName("Latest")
        XCTAssertTrue(manager.saveImmediately())
        try await Task.sleep(nanoseconds: 100_000_000)

        let restored = makeManager(draftURL: draftURL(for: manager))
        await restored.restoreDraft()
        XCTAssertEqual(restored.activeSession?.name, "Latest")
        if case .saved = manager.draftSaveState {} else { XCTFail("Expected a confirmed save") }
    }

    func testDraftWriteFailureIsObservableAndRetryable() throws {
        let directory = temporaryDirectory()
        let blocker = directory.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blocker)
        let manager = makeManager(draftURL: blocker.appendingPathComponent("draft.json"))
        manager.startSession(name: "Still here", gymProfileId: nil)

        if case .failed = manager.draftSaveState {} else { XCTFail("Expected the storage error") }
        XCTAssertEqual(manager.activeSession?.name, "Still here")
        try FileManager.default.removeItem(at: blocker)
        manager.retryDraftSave()
        if case .saved = manager.draftSaveState {} else { XCTFail("Retry should save successfully") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: blocker.appendingPathComponent("draft.json").path))
    }

    func testUnreadableDraftIsPreservedBeforeStartingAnotherWorkout() async throws {
        let url = temporaryDirectory().appendingPathComponent("draft.json")
        let original = Data("{broken workout draft".utf8)
        try original.write(to: url)
        let manager = makeManager(draftURL: url)
        await manager.restoreDraft()

        XCTAssertNil(manager.activeSession)
        XCTAssertNotNil(manager.draftRecoveryMessage)
        let preservedURL = try XCTUnwrap(manager.recoveredDraftURL)
        manager.startSession(name: "New workout", gymProfileId: nil)

        XCTAssertEqual(try Data(contentsOf: preservedURL), original)
        let restored = makeManager(draftURL: url)
        await restored.restoreDraft()
        XCTAssertEqual(restored.activeSession?.name, "New workout")
    }

    func testLateRestoreDoesNotReplaceAnActiveWorkout() async throws {
        let manager = makeManager()
        manager.startSession(name: "Current", gymProfileId: nil)
        let currentID = manager.activeSession?.id
        await manager.restoreDraft()
        XCTAssertEqual(manager.activeSession?.id, currentID)
        XCTAssertEqual(manager.activeSession?.name, "Current")
    }

    func testRestDeadlineSurvivesDraftRestoration() async throws {
        let manager = makeManager()
        manager.startSession(name: "Workout", gymProfileId: nil)
        manager.startRestTimer()
        manager.extendRestTimer(by: 30)
        manager.saveImmediately()
        let expectedDeadline = try XCTUnwrap(manager.activeSession?.restTimerEndsAt)
        let expectedTotal = manager.restTimer.currentTotal
        let restored = makeManager(draftURL: draftURL(for: manager))
        await restored.restoreDraft()
        defer { manager.cancelRestTimer(); restored.cancelRestTimer() }

        XCTAssertTrue(restored.restTimerIsActive)
        XCTAssertEqual(restored.restTimer.currentTotal, expectedTotal)
        XCTAssertEqual(try XCTUnwrap(restored.activeSession?.restTimerEndsAt).timeIntervalSince1970,
                       expectedDeadline.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(restored.restTimerSecondsRemaining, manager.restTimerSecondsRemaining, accuracy: 1)
    }

    func testExpiredRestIsNotRestartedAfterRecovery() async throws {
        let url = temporaryDirectory().appendingPathComponent("draft.json")
        let session = ActiveWorkoutSession(name: "Workout", restTimerEndsAt: Date().addingTimeInterval(-60), restTimerTotalSeconds: 90)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(session).write(to: url)
        let manager = makeManager(draftURL: url)
        await manager.restoreDraft()
        XCTAssertFalse(manager.restTimerIsActive)
        XCTAssertNil(manager.activeSession?.restTimerEndsAt)
    }

    func testUndoingCompletedSetCancelsOnlyItsOwnRest() throws {
        let manager = makeManager()
        manager.startSession(name: "Workout", gymProfileId: nil, preselectedExercise: "Bench Press", initialSetPrefill: SetPrefill(weight: 100, reps: 8))
        let exercise = try XCTUnwrap(manager.activeSession?.exercises.first)
        let firstSet = try XCTUnwrap(exercise.sets.first)
        manager.toggleSetComplete(exerciseId: exercise.id, setId: firstSet.id)
        XCTAssertTrue(manager.restTimerIsActive)
        manager.toggleSetComplete(exerciseId: exercise.id, setId: firstSet.id)
        XCTAssertFalse(manager.restTimerIsActive)
        XCTAssertNil(manager.activeSession?.restTimerEndsAt)
    }

    func testAutomaticRestCanBeDisabled() throws {
        let manager = makeManager()
        manager.setRestTimerAutomaticStartEnabled(false)
        manager.startSession(name: "Workout", gymProfileId: nil, preselectedExercise: "Bench Press", initialSetPrefill: SetPrefill(weight: 100, reps: 8))
        let exercise = try XCTUnwrap(manager.activeSession?.exercises.first)
        let set = try XCTUnwrap(exercise.sets.first)
        manager.toggleSetComplete(exerciseId: exercise.id, setId: set.id)
        XCTAssertFalse(manager.restTimerIsActive)
        XCTAssertFalse(manager.restTimer.automaticStartEnabled)
    }

    func testNonfiniteWeightCannotCompleteOrPoisonSavedHistory() throws {
        let manager = makeManager()
        manager.startSession(name: "Workout", gymProfileId: nil, preselectedExercise: "Bench Press", initialSetPrefill: SetPrefill(weight: .infinity, reps: 8))
        let exercise = try XCTUnwrap(manager.activeSession?.exercises.first)
        let set = try XCTUnwrap(exercise.sets.first)
        if case .invalid = manager.toggleSetComplete(exerciseId: exercise.id, setId: set.id) {} else {
            XCTFail("Infinity must not be marked complete")
        }
        XCTAssertEqual(manager.markIncompleteSetsWithEnteredDataCompleted(), 0)
        XCTAssertFalse(manager.saveImmediately())
        manager.updateSet(exerciseId: exercise.id, setId: set.id, prefill: SetPrefill(weight: 0, reps: 8))
        XCTAssertTrue(manager.saveImmediately())
        XCTAssertNil(manager.setCompletionValidationMessage(exerciseId: exercise.id, setId: set.id))
    }

    func testInvalidEditUnchecksCompletedSetAndCancelsItsRest() throws {
        let manager = makeManager()
        manager.startSession(name: "Workout", gymProfileId: nil, preselectedExercise: "Bench Press", initialSetPrefill: SetPrefill(weight: 100, reps: 8))
        let exercise = try XCTUnwrap(manager.activeSession?.exercises.first)
        let set = try XCTUnwrap(exercise.sets.first)
        manager.toggleSetComplete(exerciseId: exercise.id, setId: set.id)
        manager.updateSet(exerciseId: exercise.id, setId: set.id, prefill: SetPrefill(weight: 100, reps: nil))
        XCTAssertFalse(try XCTUnwrap(manager.activeSession?.exercises.first?.sets.first?.isCompleted))
        XCTAssertFalse(manager.restTimerIsActive)
    }

    func testAutomaticRestPreferenceSurvivesRecreation() {
        let suiteName = "RestTimerStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let timer = RestTimerState(defaults: defaults)
        XCTAssertTrue(timer.automaticStartEnabled)
        timer.setAutomaticStartEnabled(false)
        XCTAssertFalse(RestTimerState(defaults: defaults).automaticStartEnabled)
    }

    func testCardioRejectsInvalidOptionalMetricsAndDoesNotAutoStartRest() throws {
        let manager = makeManager()
        manager.startSession(name: "Cardio", gymProfileId: nil, preselectedExercise: "Running (Treadmill)", initialSetPrefill: SetPrefill(distance: -1, seconds: 60))
        let exercise = try XCTUnwrap(manager.activeSession?.exercises.first)
        let set = try XCTUnwrap(exercise.sets.first)
        if case .invalid = manager.toggleSetComplete(exerciseId: exercise.id, setId: set.id) {} else {
            XCTFail("A positive time must not mask a negative distance")
        }
        manager.updateSet(exerciseId: exercise.id, setId: set.id, prefill: SetPrefill(distance: 1, seconds: 60))
        if case .toggled(isCompleted: true) = manager.toggleSetComplete(exerciseId: exercise.id, setId: set.id) {} else {
            XCTFail("Expected valid cardio completion")
        }
        XCTAssertFalse(manager.restTimerIsActive)
    }

    func testPartialFieldTextSurvivesRecoveryWithoutCompletingFromOtherMetrics() async throws {
        let manager = makeManager()
        manager.startSession(name: "Cardio", gymProfileId: nil, preselectedExercise: "Running (Treadmill)")
        let exercise = try XCTUnwrap(manager.activeSession?.exercises.first)
        let set = try XCTUnwrap(exercise.sets.first)
        let input = SetInputDraft(distance: "1.25", duration: "1:")
        manager.updateSet(exerciseId: exercise.id, setId: set.id, prefill: SetPrefill(distance: 1.25), inputDraft: input)
        manager.saveImmediately()
        let restored = makeManager(draftURL: draftURL(for: manager))
        await restored.restoreDraft()

        XCTAssertEqual(restored.activeSession?.exercises.first?.sets.first?.inputDraft, input)
        if case .invalid = restored.toggleSetComplete(exerciseId: exercise.id, setId: set.id) {} else {
            XCTFail("An incomplete time must not be silently dropped when distance is valid")
        }
    }

    func testDiscardFailureKeepsActiveWorkoutOpen() async throws {
        let manager = makeManager()
        manager.startSession(name: "Keep this workout", gymProfileId: nil)
        try Data("unreadable identity".utf8).write(to: draftURL(for: manager))
        let discarded = await manager.discardDraft()
        XCTAssertFalse(discarded)
        XCTAssertEqual(manager.activeSession?.name, "Keep this workout")
        if case .failed = manager.draftSaveState {} else { XCTFail("Expected discard failure") }
    }

    func testSetVolumeOverflowIsRejected() throws {
        let manager = makeManager()
        manager.startSession(name: "Workout", gymProfileId: nil, preselectedExercise: "Bench Press", initialSetPrefill: SetPrefill(weight: 1e308, reps: 8))
        let exercise = try XCTUnwrap(manager.activeSession?.exercises.first)
        let set = try XCTUnwrap(exercise.sets.first)
        if case .invalid = manager.toggleSetComplete(exerciseId: exercise.id, setId: set.id) {} else {
            XCTFail("Finite fields must not create infinite volume")
        }
    }

    func testInitializationRestoresSessionAndTimerBeforeRepeatCanReplaceIt() throws {
        let original = makeManager()
        original.startSession(name: "Workout already in progress", gymProfileId: nil, preselectedExercise: "Bench Press")
        original.startRestTimer()
        original.saveImmediately()
        let url = draftURL(for: original)
        let originalBytes = try Data(contentsOf: url)

        let recovered = makeManager(draftURL: url)
        defer { original.cancelRestTimer(); recovered.cancelRestTimer() }
        XCTAssertEqual(recovered.activeSession?.id, original.activeSession?.id)
        XCTAssertTrue(recovered.restTimerIsActive, "Rest is available before any launch task runs")
        let outcome = WorkoutRepeatHelper.repeatWorkout(
            Workout(date: Date(), name: "New repeat", duration: "30m", exercises: []),
            gymProfileId: nil, weightIncrement: 5,
            sessionManager: recovered, dataManager: WorkoutDataManager()
        )

        XCTAssertEqual(outcome, .requiresActiveSessionReplacement)
        XCTAssertEqual(recovered.activeSession?.name, "Workout already in progress")
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
    }

    func testInitializationPreservesCorruptDraftOnlyOnceAcrossRetry() async throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent("draft.json")
        let original = Data("{incomplete draft".utf8)
        try original.write(to: url)

        let manager = makeManager(draftURL: url)
        let recoveryURL = try XCTUnwrap(manager.recoveredDraftURL)
        XCTAssertNotNil(manager.draftRecoveryMessage)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), original)
        await manager.restoreDraft()

        XCTAssertEqual(manager.recoveredDraftURL, recoveryURL)
        let recoveryFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("recovery-") }
        XCTAssertEqual(recoveryFiles.count, 1)
        manager.startSession(name: "New workout", gymProfileId: nil)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), original)
    }

    private var draftLocations: [ObjectIdentifier: URL] = [:]

    private func makeManager(draftURL: URL? = nil, persistenceDelayNanoseconds: UInt64 = 250_000_000) -> WorkoutSessionManager {
        let url = draftURL ?? temporaryDirectory().appendingPathComponent("draft.json")
        let suiteName = "WorkoutSessionManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let manager = WorkoutSessionManager(draftURL: url, persistenceDelayNanoseconds: persistenceDelayNanoseconds, defaults: defaults)
        draftLocations[ObjectIdentifier(manager)] = url
        return manager
    }

    private func draftURL(for manager: WorkoutSessionManager) -> URL {
        draftLocations[ObjectIdentifier(manager)]!
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WorkoutSessionTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
