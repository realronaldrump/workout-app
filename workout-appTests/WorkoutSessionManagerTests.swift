import XCTest
@testable import workout_app

@MainActor
final class WorkoutSessionManagerTests: XCTestCase {
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
}
