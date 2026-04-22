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
