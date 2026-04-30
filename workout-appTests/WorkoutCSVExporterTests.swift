import XCTest
@testable import workout_app

final class WorkoutCSVExporterTests: XCTestCase {
    func testWorkoutHistoryExportUsesSelectedColumnsAndGymName() throws {
        let workoutDate = date(year: 2026, month: 4, day: 10, hour: 8)
        let workout = Workout(
            date: workoutDate,
            name: "Upper, A",
            duration: "45m",
            exercises: [
                Exercise(
                    name: "Bench Press",
                    sets: [
                        makeSet(date: workoutDate, setOrder: 1, weight: 185, reps: 5),
                        makeSet(date: workoutDate.addingTimeInterval(60), setOrder: 2, weight: 190, reps: 3)
                    ]
                )
            ]
        )

        let data = try WorkoutCSVExporter.exportWorkoutHistoryCSV(
            workouts: [workout],
            startDate: workoutDate,
            endDateInclusive: workoutDate,
            gymNamesByWorkoutID: [workout.id: "Downtown, Gym"],
            selectedColumns: [.workoutName, .gymName, .exercise, .weight, .reps],
            weightUnit: "lbs",
            calendar: calendar
        )

        let csv = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = csv.components(separatedBy: "\n")

        XCTAssertEqual(lines[0], "Workout Name,Gym,Exercise,Weight (lbs),Reps")
        XCTAssertEqual(lines[1], "\"Upper, A\",\"Downtown, Gym\",Bench Press,185,5")
        XCTAssertEqual(lines[2], ",,,190,3")
    }

    func testWorkoutHistoryExportCanIncludeIntentionalBreakContextRows() throws {
        let firstWorkoutDate = date(year: 2026, month: 4, day: 10, hour: 8)
        let secondWorkoutDate = date(year: 2026, month: 4, day: 15, hour: 8)
        let firstWorkout = Workout(
            date: firstWorkoutDate,
            name: "Upper A",
            duration: "45m",
            exercises: [
                Exercise(
                    name: "Bench Press",
                    sets: [
                        makeSet(date: firstWorkoutDate, setOrder: 1, weight: 185, reps: 5)
                    ]
                )
            ]
        )
        let secondWorkout = Workout(
            date: secondWorkoutDate,
            name: "Lower A",
            duration: "50m",
            exercises: [
                Exercise(
                    name: "Squat",
                    sets: [
                        makeSet(date: secondWorkoutDate, setOrder: 1, weight: 225, reps: 5)
                    ]
                )
            ]
        )
        let breakRange = IntentionalBreakRange(
            startDate: date(year: 2026, month: 4, day: 12, hour: 0),
            endDate: date(year: 2026, month: 4, day: 14, hour: 0),
            name: "Vacation, Recovery",
            calendar: calendar
        )

        let data = try WorkoutCSVExporter.exportWorkoutHistoryCSV(
            workouts: [secondWorkout, firstWorkout],
            startDate: firstWorkoutDate,
            endDateInclusive: secondWorkoutDate,
            selectedColumns: [.workoutStart, .workoutName, .exercise, .weight, .reps],
            intentionalBreaks: [breakRange],
            includeIntentionalBreaks: true,
            weightUnit: "lbs",
            calendar: calendar
        )

        let csv = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = csv.components(separatedBy: "\n")

        XCTAssertEqual(
            lines[0],
            "Record Type,Workout Start,Workout Name,Exercise,Weight (lbs),Reps,Break Start,Break End,Break Name,Break Days"
        )
        XCTAssertEqual(lines[1], "Workout,2026-04-10 08:00,Upper A,Bench Press,185,5,,,,")
        XCTAssertEqual(lines[2], "Break,,,,,,2026-04-12,2026-04-14,\"Vacation, Recovery\",3")
        XCTAssertEqual(lines[3], "Workout,2026-04-15 08:00,Lower A,Squat,225,5,,,,")
    }

    func testWorkoutHistoryExportRejectsEmptyColumnSelection() throws {
        let workoutDate = date(year: 2026, month: 4, day: 10, hour: 8)
        let workout = Workout(
            date: workoutDate,
            name: "Upper A",
            duration: "45m",
            exercises: [
                Exercise(
                    name: "Bench Press",
                    sets: [
                        makeSet(date: workoutDate, setOrder: 1, weight: 185, reps: 5)
                    ]
                )
            ]
        )

        XCTAssertThrowsError(
            try WorkoutCSVExporter.exportWorkoutHistoryCSV(
                workouts: [workout],
                startDate: workoutDate,
                endDateInclusive: workoutDate,
                selectedColumns: [],
                calendar: calendar
            )
        ) { error in
            guard case WorkoutExportError.noColumnsSelected = error else {
                XCTFail("Expected noColumnsSelected, got \(error)")
                return
            }
        }
    }

    func testWorkoutHistoryFileExportMatchesDataExport() throws {
        let workoutDate = date(year: 2026, month: 4, day: 10, hour: 8)
        let workout = Workout(
            date: workoutDate,
            name: "Upper A",
            duration: "45m",
            exercises: [
                Exercise(
                    name: "Bench Press",
                    sets: [
                        makeSet(date: workoutDate, setOrder: 1, weight: 185, reps: 5),
                        makeSet(date: workoutDate.addingTimeInterval(60), setOrder: 2, weight: 190, reps: 3)
                    ]
                )
            ]
        )

        let expected = try WorkoutCSVExporter.exportWorkoutHistoryCSV(
            workouts: [workout],
            startDate: workoutDate,
            endDateInclusive: workoutDate,
            selectedColumns: [.workoutName, .exercise, .weight, .reps],
            weightUnit: "lbs",
            calendar: calendar
        )

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("history.csv")
        try WorkoutCSVExporter.exportWorkoutHistoryCSV(
            to: fileURL,
            workouts: [workout],
            startDate: workoutDate,
            endDateInclusive: workoutDate,
            selectedColumns: [.workoutName, .exercise, .weight, .reps],
            weightUnit: "lbs",
            calendar: calendar
        )

        let actual = try Data(contentsOf: fileURL)
        XCTAssertEqual(actual, expected)
    }

    func testWorkoutHistoryExportCanIncludeRelationshipColumns() throws {
        let workoutDate = date(year: 2026, month: 4, day: 10, hour: 8)
        let workout = Workout(
            date: workoutDate,
            name: "Lower A",
            duration: "45m",
            exercises: [
                Exercise(
                    name: "Leg Extension (Machine) - Left",
                    sets: [
                        WorkoutSet(
                            date: workoutDate,
                            workoutName: "Lower A",
                            duration: "45m",
                            exerciseName: "Leg Extension (Machine) - Left",
                            setOrder: 1,
                            weight: 50,
                            reps: 10,
                            distance: 0,
                            seconds: 0
                        )
                    ]
                )
            ]
        )
        let resolver = ExerciseIdentityResolver(relationships: [
            "left": ExerciseRelationship(
                exerciseName: "Leg Extension (Machine) - Left",
                parentName: "Leg Extension (Machine)",
                laterality: .left
            )
        ])

        let data = try WorkoutCSVExporter.exportWorkoutHistoryCSV(
            workouts: [workout],
            startDate: workoutDate,
            endDateInclusive: workoutDate,
            selectedColumns: [.exercise, .parentExercise, .side, .weight, .reps],
            resolver: resolver,
            calendar: calendar
        )

        let csv = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Exercise,Parent Exercise,Side,Weight,Reps")
        XCTAssertEqual(lines[1], "Leg Extension (Machine) - Left,Leg Extension (Machine),Left,50,10")
    }

    func testExerciseListExportIncludesRelationshipMetadataWhenTagsAreIncluded() throws {
        let workoutDate = date(year: 2026, month: 4, day: 10, hour: 8)
        let workout = Workout(
            date: workoutDate,
            name: "Lower A",
            duration: "45m",
            exercises: [
                Exercise(
                    name: "Leg Extension (Machine) - Right",
                    sets: [makeSet(date: workoutDate, setOrder: 1, weight: 55, reps: 8)]
                )
            ]
        )
        let resolver = ExerciseIdentityResolver(relationships: [
            "right": ExerciseRelationship(
                exerciseName: "Leg Extension (Machine) - Right",
                parentName: "Leg Extension (Machine)",
                laterality: .right
            )
        ])

        let data = try WorkoutCSVExporter.exportExerciseListCSV(
            workouts: [workout],
            startDate: workoutDate,
            endDateInclusive: workoutDate,
            includeTags: true,
            exerciseTagsByName: ["Leg Extension (Machine) - Right": "Quads"],
            resolver: resolver,
            calendar: calendar
        )

        let csv = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Exercise,Tags,Parent Exercise,Side")
        XCTAssertEqual(lines[1], "Leg Extension (Machine) - Right,Quads,Leg Extension (Machine),Right")
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver") ?? .current
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.timeZone = calendar.timeZone
        return calendar.date(from: components) ?? .distantPast
    }

    private func makeSet(date: Date, setOrder: Int, weight: Double, reps: Int) -> WorkoutSet {
        WorkoutSet(
            date: date,
            workoutName: "Upper A",
            duration: "45m",
            exerciseName: "Bench Press",
            setOrder: setOrder,
            weight: weight,
            reps: reps,
            distance: 0,
            seconds: 0
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
