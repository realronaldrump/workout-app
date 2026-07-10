import Combine
import XCTest
@testable import workout_app

@MainActor
final class WorkoutSessionManagerTests: XCTestCase {
    func testRepeatWorkoutDoesNotReplaceActiveSessionWithoutConfirmation() {
        let manager = WorkoutSessionManager()
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
        let manager = WorkoutSessionManager()
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
        let manager = WorkoutSessionManager()
        manager.startSession(
            name: "Upper",
            gymProfileId: nil,
            preselectedExercise: "Bench Press",
            initialSetPrefill: SetPrefill(weight: 135, reps: 8)
        )

        XCTAssertEqual(manager.incompleteSetsWithEnteredDataCount(), 1)
    }

    func testMarkIncompleteSetsWithEnteredDataCompletedMarksEligibleSets() {
        let manager = WorkoutSessionManager()
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
        let manager = WorkoutSessionManager()
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
}
