import XCTest
@testable import workout_app

@MainActor
final class WorkoutRepeatTests: XCTestCase {
    func testRepeatPreservesEveryHistoricalSetAndLeavesThemUnchecked() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = WorkoutSessionManager(draftURL: directory.appendingPathComponent("draft.json"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let strengthSets = (1...12).map { index in
            WorkoutSet(date: date, workoutName: "Upper", duration: "30m", exerciseName: "Bench Press",
                       setOrder: index, weight: 45 + Double(index) * 1.25, reps: 13 - index,
                       distance: 0, seconds: 0)
        }
        let cardioSet = WorkoutSet(date: date, workoutName: "Upper", duration: "30m", exerciseName: "Running",
                                   setOrder: 1, weight: 0, reps: 0, distance: 2.75, seconds: 765)
        let source = Workout(date: date, name: "Upper", duration: "30m", exercises: [
            Exercise(name: "Bench Press", sets: strengthSets.reversed()),
            Exercise(name: "Running", sets: [cardioSet])
        ])

        let outcome = WorkoutRepeatHelper.repeatWorkout(
            source, gymProfileId: nil, weightIncrement: 5,
            sessionManager: manager, dataManager: WorkoutDataManager()
        )
        XCTAssertEqual(outcome, .started)
        let session = try XCTUnwrap(manager.activeSession)
        XCTAssertEqual(session.exercises[0].sets.count, 12, "Repeating must not silently cap the number of sets")
        XCTAssertEqual(session.exercises[0].sets.map(\.weight), strengthSets.map { Optional($0.weight) })
        XCTAssertEqual(session.exercises[0].sets.map(\.reps), strengthSets.map { Optional($0.reps) })
        XCTAssertEqual(session.exercises[1].sets[0].distance, 2.75)
        XCTAssertEqual(session.exercises[1].sets[0].seconds, 765)
        XCTAssertTrue(session.exercises.flatMap(\.sets).allSatisfy { !$0.isCompleted && $0.completedAt == nil })
        XCTAssertNotEqual(session.id, source.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("draft.json").path))
        await manager.discardDraft()
    }
}
