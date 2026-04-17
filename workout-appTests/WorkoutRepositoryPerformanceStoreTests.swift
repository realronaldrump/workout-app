import XCTest
@testable import workout_app

final class WorkoutRepositoryPerformanceStoreTests: XCTestCase {
    func testNormalizedStoreRoundTripsImportedWorkoutHierarchy() throws {
        let database = AppDatabase(inMemory: true)
        let date = makeDate(hour: 9)
        let workoutId = UUID()
        let exerciseId = UUID()
        let setId = UUID()
        var set = WorkoutSet(
            date: date,
            workoutName: "Upper",
            duration: "45m",
            exerciseName: "Bench Press",
            setOrder: 1,
            weight: 185,
            reps: 5,
            distance: 0,
            seconds: 0
        )
        set.id = setId

        let workout = Workout(
            id: workoutId,
            date: date,
            name: "Upper",
            duration: "45m",
            exercises: [Exercise(id: exerciseId, name: "Bench Press", sets: [set])]
        )

        try database.saveImportedWorkouts([workout])

        let loaded = try XCTUnwrap(database.loadImportedWorkouts().first)
        XCTAssertEqual(loaded.id, workoutId)
        XCTAssertEqual(loaded.exercises.first?.id, exerciseId)
        XCTAssertEqual(loaded.exercises.first?.sets.first?.id, setId)
        XCTAssertEqual(loaded.exercises.first?.sets.first?.weight, 185)
        XCTAssertEqual(loaded.exercises.first?.sets.first?.reps, 5)
    }

    func testNormalizedStoreKeepsLoggedWorkoutFieldsAndDeleteIsScoped() throws {
        let database = AppDatabase(inMemory: true)
        let date = makeDate(hour: 10)
        let loggedId = UUID()
        let logged = LoggedWorkout(
            id: loggedId,
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            name: "Logged Upper",
            gymProfileId: UUID(),
            exercises: [
                LoggedExercise(name: "Row", sets: [
                    LoggedSet(order: 1, weight: 120, reps: 8),
                    LoggedSet(order: 2, weight: 125, reps: 6)
                ])
            ],
            createdAt: date,
            updatedAt: date,
            schemaVersion: 2
        )

        try database.replaceLoggedWorkouts([logged])

        let loaded = try XCTUnwrap(database.loadLoggedWorkouts().first)
        XCTAssertEqual(loaded.id, loggedId)
        XCTAssertEqual(loaded.gymProfileId, logged.gymProfileId)
        XCTAssertEqual(loaded.exercises.first?.sets.count, 2)

        try database.deleteLoggedWorkout(id: loggedId)
        XCTAssertTrue(try database.loadLoggedWorkouts().isEmpty)
    }

    func testRepositoryStrongCSVImportBuildsCleanStoreWorkouts() async throws {
        let database = AppDatabase(inMemory: true)
        let repository = WorkoutRepository(database: database)
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds
        2026-04-10 08:00:00,Upper,45m,Bench Press,1,185,5,0,0
        2026-04-10 08:01:00,Upper,45m,Bench Press,2,190,3,0,0
        2026-04-12 09:00:00,Pull,50m,Row,1,120,8,0,0
        """

        try await repository.importStrongCSV(Data(csv.utf8), sourceSignature: "test-csv")

        let snapshot = try await repository.homeSnapshot()
        XCTAssertEqual(snapshot.stats.totalWorkouts, 2)
        XCTAssertEqual(snapshot.stats.totalSets, 3)
        XCTAssertEqual(snapshot.allExerciseNames, ["Bench Press", "Row"])
        XCTAssertEqual(snapshot.exerciseSummaries.first(where: { $0.name == "Bench Press" })?.stats.frequency, 1)
    }

    private func makeDate(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 10
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "America/Denver")
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }
}
