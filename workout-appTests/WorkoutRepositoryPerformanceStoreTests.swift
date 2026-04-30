import XCTest
@testable import workout_app

final class WorkoutRepositoryPerformanceStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ExerciseRelationshipManager.shared.clearRelationships()
    }

    override func tearDown() {
        ExerciseRelationshipManager.shared.clearRelationships()
        super.tearDown()
    }

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

    func testExerciseDetailUsesIndexedExerciseLookupAndPreservesWorkoutContext() async throws {
        let database = AppDatabase(inMemory: true)
        let repository = WorkoutRepository(database: database)
        let gymId = UUID()
        let targetWorkoutId = UUID()
        let otherTargetWorkoutId = UUID()

        let targetWorkout = makeWorkout(
            id: targetWorkoutId,
            day: 10,
            name: "Upper",
            exercises: [
                makeExercise(name: "Warmup", orderOffset: 0, date: makeDate(day: 10, hour: 8)),
                makeExercise(name: "Bench Press", orderOffset: 10, date: makeDate(day: 10, hour: 8))
            ]
        )
        let otherTargetWorkout = makeWorkout(
            id: otherTargetWorkoutId,
            day: 12,
            name: "Upper 2",
            exercises: [
                makeExercise(name: "bench press", orderOffset: 20, date: makeDate(day: 12, hour: 8)),
                makeExercise(name: "Row", orderOffset: 30, date: makeDate(day: 12, hour: 8))
            ]
        )
        let unrelatedWorkout = makeWorkout(
            id: UUID(),
            day: 13,
            name: "Lower",
            exercises: [makeExercise(name: "Squat", orderOffset: 40, date: makeDate(day: 13, hour: 8))]
        )

        try database.saveImportedWorkouts([targetWorkout, otherTargetWorkout, unrelatedWorkout])
        try database.replaceAnnotations([
            WorkoutAnnotation(workoutId: targetWorkoutId, gymProfileId: gymId)
        ])

        let allSnapshot = try await repository.exerciseDetail(name: "Bench Press", scope: .all)
        XCTAssertEqual(Set(allSnapshot.workouts.map(\.id)), [targetWorkoutId, otherTargetWorkoutId])
        XCTAssertEqual(allSnapshot.history.count, 2)
        XCTAssertEqual(allSnapshot.workouts.first(where: { $0.id == targetWorkoutId })?.exercises.map(\.name), ["Warmup", "Bench Press"])

        let gymSnapshot = try await repository.exerciseDetail(name: "Bench Press", scope: .gym(gymId))
        XCTAssertEqual(gymSnapshot.workouts.map(\.id), [targetWorkoutId])

        let unassignedSnapshot = try await repository.exerciseDetail(name: "Bench Press", scope: .unassigned)
        XCTAssertEqual(unassignedSnapshot.workouts.map(\.id), [otherTargetWorkoutId])
    }

    func testExerciseDirectorySearchMatchesChildVariantNames() async throws {
        let database = AppDatabase(inMemory: true)
        let repository = WorkoutRepository(database: database)
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Extension (Machine) - Left",
            parentName: "Leg Extension (Machine)",
            laterality: .left
        )

        try database.saveImportedWorkouts([
            makeWorkout(
                id: UUID(),
                day: 10,
                name: "Lower",
                exercises: [
                    makeExercise(name: "Leg Extension (Machine) - Left", orderOffset: 0, date: makeDate(day: 10, hour: 8))
                ]
            )
        ])

        let page = try await repository.exerciseDirectory(
            query: "Left",
            sort: .alphabetical,
            limit: 20
        )

        XCTAssertEqual(page.exercises.map(\.name), ["Leg Extension (Machine)"])
        XCTAssertEqual(page.totalCount, 1)
    }

    func testWorkoutHistoryFilterMatchesParentRollupForChildVariantWorkouts() async throws {
        let database = AppDatabase(inMemory: true)
        let repository = WorkoutRepository(database: database)
        let matchingWorkoutId = UUID()
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Extension (Machine) - Left",
            parentName: "Leg Extension (Machine)",
            laterality: .left
        )

        try database.saveImportedWorkouts([
            makeWorkout(
                id: matchingWorkoutId,
                day: 10,
                name: "Lower",
                exercises: [
                    makeExercise(name: "Leg Extension (Machine) - Left", orderOffset: 0, date: makeDate(day: 10, hour: 8))
                ]
            ),
            makeWorkout(
                id: UUID(),
                day: 11,
                name: "Upper",
                exercises: [
                    makeExercise(name: "Bench Press", orderOffset: 10, date: makeDate(day: 11, hour: 8))
                ]
            )
        ])

        let page = try await repository.workoutHistoryPage(
            filter: WorkoutHistoryFilter(exerciseNames: ["Leg Extension (Machine)"]),
            limit: 20
        )

        XCTAssertEqual(page.workouts.map(\.id), [matchingWorkoutId])
        XCTAssertEqual(page.totalCount, 1)
    }

    func testRepositoryExerciseDetailAggregatesParentAndKeepsVariantExact() async throws {
        let database = AppDatabase(inMemory: true)
        let repository = WorkoutRepository(database: database)
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Extension (Machine) - Left",
            parentName: "Leg Extension (Machine)",
            laterality: .left
        )
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Extension (Machine) - Right",
            parentName: "Leg Extension (Machine)",
            laterality: .right
        )

        try database.saveImportedWorkouts([
            makeWorkout(
                id: UUID(),
                day: 10,
                name: "Lower A",
                exercises: [
                    makeExercise(name: "Leg Extension (Machine) - Left", orderOffset: 0, date: makeDate(day: 10, hour: 8))
                ]
            ),
            makeWorkout(
                id: UUID(),
                day: 12,
                name: "Lower B",
                exercises: [
                    makeExercise(name: "Leg Extension (Machine) - Right", orderOffset: 10, date: makeDate(day: 12, hour: 8))
                ]
            )
        ])

        let parent = try await repository.exerciseDetail(name: "Leg Extension (Machine)", scope: .all)
        XCTAssertEqual(parent.history.count, 2)
        XCTAssertEqual(parent.history.reduce(0) { $0 + $1.sets.count }, 2)

        let left = try await repository.exerciseDetail(name: "Leg Extension (Machine) - Left", scope: .all)
        XCTAssertEqual(left.history.count, 1)
        XCTAssertEqual(left.history.first?.sets.first?.exerciseName, "Leg Extension (Machine) - Left")
    }

    private func makeDate(hour: Int) -> Date {
        makeDate(day: 10, hour: hour)
    }

    private func makeDate(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "America/Denver")
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }

    private func makeWorkout(id: UUID, day: Int, name: String, exercises: [Exercise]) -> Workout {
        Workout(
            id: id,
            date: makeDate(day: day, hour: 8),
            name: name,
            duration: "45m",
            exercises: exercises
        )
    }

    private func makeExercise(name: String, orderOffset: Int, date: Date) -> Exercise {
        Exercise(
            name: name,
            sets: [
                WorkoutSet(
                    date: date,
                    workoutName: "Workout",
                    duration: "45m",
                    exerciseName: name,
                    setOrder: orderOffset + 1,
                    weight: 100 + Double(orderOffset),
                    reps: 5,
                    distance: 0,
                    seconds: 0
                )
            ]
        )
    }
}
