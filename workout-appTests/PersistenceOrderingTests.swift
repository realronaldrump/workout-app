import XCTest
@testable import workout_app

final class PersistenceOrderingTests: XCTestCase {
    @MainActor
    func testBackupMergePersistenceCanBeExplicitlyDrained() async throws {
        let database = AppDatabase(inMemory: true)
        let logStore = WorkoutLogStore(database: database)
        let annotations = WorkoutAnnotationsManager(database: database, loadOnInit: false)
        let gyms = GymProfilesManager(
            annotationsManager: annotations,
            database: database,
            loadOnInit: false
        )
        let date = Date()
        let workout = LoggedWorkout(
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            name: "Restored workout",
            exercises: []
        )
        let gym = GymProfile(name: "Restored gym")
        let annotation = WorkoutAnnotation(workoutId: workout.id, gymProfileId: gym.id)

        _ = logStore.mergeWorkoutsFromBackup([workout])
        _ = gyms.mergeGymsFromBackup([gym])
        _ = annotations.mergeAnnotationsFromBackup(
            [annotation],
            workoutIdMap: [:],
            gymIdMap: [:]
        )

        try await logStore.waitForPendingPersistence()
        try await gyms.waitForPendingPersistence()
        try await annotations.waitForPendingPersistence()

        XCTAssertEqual(try database.loadLoggedWorkouts().map(\.id), [workout.id])
        XCTAssertEqual(try database.loadGymProfiles().map(\.id), [gym.id])
        XCTAssertEqual(try database.loadAnnotations().map(\.workoutId), [workout.id])
    }

    @MainActor
    func testQueuedWorkoutReplacementCannotResurrectDataAfterClear() async throws {
        let database = AppDatabase(inMemory: true)
        let store = WorkoutLogStore(database: database)
        let date = Date()
        let workout = LoggedWorkout(
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            name: "Queued workout",
            exercises: []
        )

        _ = store.mergeWorkoutsFromBackup([workout])
        try await store.clearAll()

        XCTAssertTrue(try database.loadLoggedWorkouts().isEmpty)
    }

    @MainActor
    func testQueuedAnnotationSaveCannotResurrectAssignmentsAfterClear() async throws {
        let database = AppDatabase(inMemory: true)
        let manager = WorkoutAnnotationsManager(database: database, loadOnInit: false)

        manager.setGym(for: UUID(), gymProfileId: UUID())
        try await manager.clearAll()

        XCTAssertTrue(try database.loadAnnotations().isEmpty)
    }

    @MainActor
    func testQueuedGymSaveCannotResurrectProfilesAfterClear() async throws {
        let database = AppDatabase(inMemory: true)
        let annotations = WorkoutAnnotationsManager(database: database, loadOnInit: false)
        let manager = GymProfilesManager(
            annotationsManager: annotations,
            database: database,
            loadOnInit: false
        )

        manager.addGym(name: "Queued gym")
        try await manager.clearAll()

        XCTAssertTrue(try database.loadGymProfiles().isEmpty)
    }
}
