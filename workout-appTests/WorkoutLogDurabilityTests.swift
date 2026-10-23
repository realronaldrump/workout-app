import XCTest
@testable import workout_app

@MainActor
final class WorkoutLogDurabilityTests: XCTestCase {
    func testSavedLiveWorkoutSurvivesReopeningSQLiteWithEveryField() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("workouts.sqlite")
        let database = AppDatabase(storeURL: storeURL)
        let store = WorkoutLogStore(database: database, legacyFileURL: directory.appendingPathComponent("legacy.json"))
        let original = fixture()

        try await store.save(original)
        let saved = try XCTUnwrap(store.workout(id: original.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        let reopenedDatabase = AppDatabase(storeURL: storeURL)
        let reopened = WorkoutLogStore(
            database: reopenedDatabase,
            legacyFileURL: directory.appendingPathComponent("legacy.json")
        )
        await reopened.load()
        let restored = try XCTUnwrap(reopened.workout(id: original.id))
        XCTAssertEqual(restored, saved)
        XCTAssertEqual(restored.startedAt, original.startedAt)
        XCTAssertEqual(restored.endedAt, original.endedAt)
        XCTAssertEqual(restored.gymProfileId, original.gymProfileId)
        XCTAssertEqual(restored.exercises, original.exercises)
        XCTAssertEqual(restored.analyticsWorkout.exercises.map(\.id), original.exercises.map(\.id))
        XCTAssertEqual(
            restored.analyticsWorkout.exercises.flatMap(\.sets).map(\.id),
            original.exercises.flatMap(\.sets).map(\.id)
        )
        XCTAssertEqual(restored.analyticsWorkout.duration, "30m 1s")
        XCTAssertNil(reopened.persistenceError)
    }

    func testLoggedBackupPayloadRestoresToSQLiteWithoutDuplicates() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("restored.sqlite")
        let database = AppDatabase(storeURL: storeURL)
        let store = WorkoutLogStore(database: database, legacyFileURL: directory.appendingPathComponent("legacy.json"))
        let original = fixture()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // The logged-workouts section uses these exact Codable models in a native backup.
        let payload = try decoder.decode([LoggedWorkout].self, from: encoder.encode([original]))

        let first = store.mergeWorkoutsFromBackup(payload)
        try await store.waitForPendingPersistence()
        let second = store.mergeWorkoutsFromBackup(payload)
        try await store.waitForPendingPersistence()

        let reopened = AppDatabase(storeURL: storeURL)
        let restored = try reopened.loadLoggedWorkouts()
        XCTAssertEqual(first.inserted, 1)
        XCTAssertEqual(second.inserted, 0)
        XCTAssertEqual(second.skipped, 1)
        XCTAssertEqual(restored, [original])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorkoutLogDurability-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fixture() -> LoggedWorkout {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return LoggedWorkout(
            startedAt: date,
            endedAt: date.addingTimeInterval(1_801),
            name: "Strength, cardio & bodyweight",
            gymProfileId: UUID(),
            exercises: [
                LoggedExercise(name: "Bench Press", sets: [
                    LoggedSet(order: 1, weight: 101.25, reps: 8),
                    LoggedSet(order: 2, weight: 103.75, reps: 6)
                ]),
                LoggedExercise(name: "Pull Up", sets: [LoggedSet(order: 1, weight: 0, reps: 12)]),
                LoggedExercise(name: "Running", sets: [
                    LoggedSet(order: 1, weight: 0, reps: 0, distance: 2.75, seconds: 900.5)
                ])
            ],
            createdAt: date,
            updatedAt: date
        )
    }
}
