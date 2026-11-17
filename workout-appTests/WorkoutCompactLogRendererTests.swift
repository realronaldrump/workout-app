import XCTest
@testable import workout_app

final class WorkoutCompactLogRendererTests: XCTestCase {
    func testEveryAnalyticalFieldRoundTripsWithoutTextOrNumericLoss() throws {
        let document = try fixture()
        let decoded = try decode(WorkoutCompactLogRenderer.render(document))
        XCTAssertEqual(decoded.rows.count, document.records.count)
        for (record, row) in zip(document.records, decoded.rows) {
            try assertRecord(record, row: row, columns: document.columns)
        }
        XCTAssertEqual(decoded.breaks.count, document.breaks.count)
        XCTAssertEqual(decoded.breaks.first?["name"] as? String, "Travel\n& recovery | 🏔️")
    }

    func testEveryColumnCanBeSelectedIndependentlyWithoutLeakingOtherFields() throws {
        for column in WorkoutExportColumn.allCases {
            let document = try fixture(columns: [column])
            let decoded = try decode(WorkoutCompactLogRenderer.render(document))
            for (record, row) in zip(document.records, decoded.rows) {
                try assertRecord(record, row: row, columns: [column])
                let expected = Set([column.key] + (column == .tags ? ["muscle_assignments"] : []))
                XCTAssertEqual(Set(row.keys), expected, "Unexpected fields with \(column)")
            }
        }
    }

    func testConsecutiveRepeatedSetsExpandInOrderAndDoNotMergeExerciseOccurrences() throws {
        let date = date("2026-11-01T01:30:00.125-06:00")
        let workout = Workout(date: date, name: "Upper", duration: "60", exercises: [
            exercise("Row", date: date, weights: [50, 60, 60, 60, 50]),
            exercise("Row", date: date, weights: [50, 50])
        ])
        let document = try makeDocument([workout])
        let text = WorkoutCompactLogRenderer.render(document)
        XCTAssertTrue(text.contains("3*(60)"))
        XCTAssertEqual(text.components(separatedBy: "\n").filter { $0 == "e1" || $0.hasPrefix("e1\t") }.count, 3, "One dictionary row and two distinct exercise occurrences")
        let rows = try decode(text).rows
        XCTAssertEqual(rows.compactMap { $0["set_number"] as? Int }, [1, 2, 3, 4, 5, 1, 2])
        XCTAssertEqual(rows.compactMap { $0["weight"] as? Double }, [50, 60, 60, 60, 50, 50, 50])
    }

    func testNonSequentialAndDuplicateSetNumbersRemainExplicit() throws {
        let document = try fixture()
        let text = WorkoutCompactLogRenderer.render(document)
        XCTAssertFalse(text.contains("set_number: 1..N"))
        XCTAssertEqual(try decode(text).rows.compactMap { $0["set_number"] as? Int }, document.records.map { Int($0.value(.setNumber).text)! })
    }

    func testMissingNonfiniteZeroEmptyAndUnspecifiedUnitsStayDistinct() throws {
        let document = try fixture()
        let text = WorkoutCompactLogRenderer.render(document)
        let rows = try decode(text).rows
        XCTAssertTrue(rows.contains { $0["weight"] is NSNull })
        XCTAssertTrue(rows.contains { ($0["weight"] as? Double) == 0 })
        XCTAssertTrue(rows.contains { ($0["logged_duration"] as? String) == "" })
        XCTAssertTrue(text.contains("weight_unit null"))
        XCTAssertTrue(text.contains("distance_unit null"))
        XCTAssertFalse(text.contains("nan"))
        XCTAssertFalse(text.contains("inf"))
    }

    func testTimestampsRetainMillisecondsAndDSTOffsets() throws {
        let document = try fixture()
        let rows = try decode(WorkoutCompactLogRenderer.render(document)).rows
        let starts = Set(rows.compactMap { $0["workout_start"] as? String })
        XCTAssertTrue(starts.contains("2026-11-01T01:30:00.125-06:00"))
        XCTAssertTrue(starts.contains("2026-11-01T01:30:00.875-07:00"))
    }

    func testDistinctSetTimestampsAreRetainedOnlyWhenDatesAreSelected() throws {
        let start = date("2026-11-01T01:30:00.125-06:00")
        let workout = Workout(date: start, name: "Upper", duration: "1h", exercises: [
            Exercise(name: "Row", sets: [makeSet(1, 50, date: start), makeSet(2, 60, date: start.addingTimeInterval(60.25))])
        ])
        let text = WorkoutCompactLogRenderer.render(try makeDocument([workout]))
        let rows = try decode(text).rows
        XCTAssertEqual(rows[1]["set_timestamp"] as? String, "2026-11-01T01:31:00.375-06:00")
        let restricted = try makeDocument([workout], columns: [.weight])
        XCTAssertFalse(WorkoutCompactLogRenderer.render(restricted).contains("set_timestamp"))
    }

    func testDeterministicAndSubstantiallySmallerThanMinifiedJSON() throws {
        let document = try fixture(repetitions: 50)
        let text = WorkoutCompactLogRenderer.render(document)
        XCTAssertEqual(text, WorkoutCompactLogRenderer.render(document))
        let object = try JSONSerialization.jsonObject(with: document.jsonData())
        let minified = try JSONSerialization.data(withJSONObject: object)
        XCTAssertLessThan(text.utf8.count, minified.count / 3)
        XCTAssertFalse(text.contains(document.records[0].workoutID.uuidString))
        if let folder = ProcessInfo.processInfo.environment["WORKOUT_EXPORT_SAMPLE_DIR"] {
            let directory = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: directory.appendingPathComponent("training-log.txt"), atomically: true, encoding: .utf8)
            try document.jsonData().write(to: directory.appendingPathComponent("training-log.json"))
        }
        print("COMPACT_EXPORT bytes=\(text.utf8.count) minified_json=\(minified.count) pretty_json=\(try document.jsonData().count) sets=\(document.records.count)")
    }

    func testNativeLogRetainsUnloggedMeasurementsAndExactElapsedDuration() throws {
        let start = date("2026-11-01T01:30:00.125-06:00")
        let native = LoggedWorkout(startedAt: start, endedAt: start.addingTimeInterval(60.875), name: "Native", exercises: [
            LoggedExercise(name: "Row", sets: [
                LoggedSet(order: 1, weight: 50, reps: 8),
                LoggedSet(order: 2, weight: 50, reps: 8, distance: 0, seconds: 0)
            ])
        ])
        let document = try WorkoutExportDocument(
            workouts: [native.analyticsWorkout], startDate: start, endDateInclusive: start,
            calendar: calendar, nativeWorkouts: [native]
        )
        let decoded = try decode(WorkoutCompactLogRenderer.render(document)).rows
        XCTAssertEqual(decoded.count, 2)
        XCTAssertTrue(decoded[0]["distance"] is NSNull)
        XCTAssertTrue(decoded[0]["set_duration_seconds"] is NSNull)
        XCTAssertEqual(decoded[1]["distance"] as? Double, 0)
        XCTAssertEqual(decoded[1]["set_duration_seconds"] as? Double, 0)
        XCTAssertEqual(decoded[0]["workout_duration_seconds"] as? Double, 60.875)
        XCTAssertEqual(decoded[0]["workout_ended_at"] as? String, "2026-11-01T01:31:01.000-06:00")
    }

    func testEmptyAndUnavailableMuscleAssignmentsRemainDistinct() throws {
        let start = date("2026-11-01T01:30:00.125-06:00")
        let workout = Workout(date: start, name: "Upper", duration: "30m", exercises: [
            exercise("Known empty", date: start, weights: [50]),
            exercise("Unavailable", date: start, weights: [50])
        ])
        let document = try WorkoutExportDocument(
            workouts: [workout], startDate: start, endDateInclusive: start,
            exerciseMusclesByName: ["Known empty": []], calendar: calendar
        )
        let rows = try decode(WorkoutCompactLogRenderer.render(document)).rows
        XCTAssertEqual((rows[0]["muscle_assignments"] as? [Any])?.count, 0)
        XCTAssertTrue(rows[1]["muscle_assignments"] is NSNull)
    }

    func testCustomCardioCountMeaningIsPreservedAndNotLeakedWhenRepsAreExcluded() throws {
        let start = date("2026-11-01T01:30:00.125-06:00")
        let workout = Workout(date: start, name: "Cardio", duration: "30m", exercises: [exercise("Stairs", date: start, weights: [0])])
        let document = try WorkoutExportDocument(
            workouts: [workout], startDate: start, endDateInclusive: start,
            calendar: calendar, exerciseCountLabelsByName: ["Stairs": "floors"]
        )
        let row = try XCTUnwrap(decode(WorkoutCompactLogRenderer.render(document)).rows.first)
        XCTAssertEqual(row["reps_label"] as? String, "floors")
        XCTAssertEqual(row["reps"] as? Int, 8)
        let restricted = try WorkoutExportDocument(
            workouts: [workout], startDate: start, endDateInclusive: start,
            selectedColumns: [.weight], calendar: calendar, exerciseCountLabelsByName: ["Stairs": "floors"]
        )
        XCTAssertFalse(WorkoutCompactLogRenderer.render(restricted).contains("floors"))
    }

    func testFormatWritesRecognizedTextFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try fixture()
        let file = directory.appendingPathComponent(WorkoutExportFormat.llm.fileName(from: "workout_export_20261101.csv"))
        try document.write(to: file, format: .llm)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), WorkoutCompactLogRenderer.render(document))
        XCTAssertTrue(iCloudDocumentManager.isExportOrBackupFile(file))
    }

    private func assertRecord(_ record: WorkoutExportRecord, row: [String: Any], columns: [WorkoutExportColumn], file: StaticString = #filePath, line: UInt = #line) throws {
        var expected: [String: Any] = [:]
        for column in columns {
            expected[column.key] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record.value(column)), options: .fragmentsAllowed)
        }
        if columns.contains(.tags) {
            expected["muscle_assignments"] = record.muscles.map { $0.map { [$0.name, $0.role] } } ?? (NSNull() as Any)
        }
        XCTAssertEqual(row as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)!
    }

    private func makeSet(_ order: Int, _ weight: Double, date: Date, reps: Int = 8, distance: Double = 0, seconds: Double = 0) -> WorkoutSet {
        WorkoutSet(date: date, workoutName: "", duration: "", exerciseName: "", setOrder: order, weight: weight, reps: reps, distance: distance, seconds: seconds)
    }

    private func exercise(_ name: String, date: Date, weights: [Double]) -> Exercise {
        Exercise(name: name, sets: weights.enumerated().map { makeSet($0.offset + 1, $0.element, date: date) })
    }

    private func makeDocument(_ workouts: [Workout], columns: [WorkoutExportColumn] = WorkoutExportColumn.allCases) throws -> WorkoutExportDocument {
        try WorkoutExportDocument(workouts: workouts, startDate: workouts.map(\.date).min()!, endDateInclusive: workouts.map(\.date).max()!, selectedColumns: columns, calendar: calendar)
    }

    private func fixture(columns: [WorkoutExportColumn] = WorkoutExportColumn.allCases, repetitions: Int = 1) throws -> WorkoutExportDocument {
        let first = date("2026-11-01T01:30:00.125-06:00")
        let second = date("2026-11-01T01:30:00.875-07:00")
        var workouts: [Workout] = []
        for index in 0..<repetitions {
            let a = first.addingTimeInterval(Double(index) * 86400)
            let b = second.addingTimeInterval(Double(index) * 86400)
            workouts += [
                Workout(date: a, name: "Push | \"heavy\"\n🏋️", duration: "1h 5m 0.25s", exercises: [
                    exercise("Press\tA: | ;,\n雪", date: a, weights: [135.125, 185, 185, 135.125]),
                    Exercise(name: "Row - Left", sets: [
                        makeSet(2, 0, date: a, reps: 0, distance: 1.23456789, seconds: 90.125),
                        makeSet(4, -25.5, date: a, reps: 5),
                        makeSet(4, .nan, date: a, reps: 0, seconds: .infinity)
                    ])
                ]),
                Workout(date: b, name: "Pull", duration: "", exercises: [exercise("Press\tA: | ;,\n雪", date: b, weights: [50, 50])])
            ]
        }
        return try WorkoutExportDocument(
            workouts: workouts, startDate: first, endDateInclusive: workouts.map(\.date).max()!,
            exerciseTagsByName: ["Press\tA: | ;,\n雪": "Chest; triceps", "Row - Left": "Legacy role text"],
            exerciseMusclesByName: ["Press\tA: | ;,\n雪": [.init(name: "Chest", role: "primary"), .init(name: "Triceps", role: "secondary")]],
            gymNamesByWorkoutID: [workouts[0].id: " Home\tGym "], selectedColumns: columns,
            intentionalBreaks: [.init(startDate: first, endDate: first, name: "Travel\n& recovery | 🏔️", calendar: calendar)],
            includeIntentionalBreaks: true, resolver: ExerciseIdentityResolver(relationships: [
                "row - left": .init(exerciseName: "Row - Left", parentName: "Row", laterality: .left)
            ]), calendar: calendar
        )
    }

    /// Independent reader for the documented grammar; compares expanded analytical
    /// records to the source instead of testing the renderer's private helpers.
    private func decode(_ text: String) throws -> (rows: [[String: Any]], breaks: [[String: Any]]) {
        var defaults: [String: Any] = [:]
        var headers: [String: [String]] = [:]
        var contexts: [String: [String: Any]] = [:]
        var exercises: [String: [String: Any]] = [:]
        var workout: [String: Any] = [:]
        var rows: [[String: Any]] = []
        var breaks: [[String: Any]] = []
        var inLog = false
        let implicit = text.contains("set_number: 1..N")
        func value(_ cell: String) throws -> Any {
            try JSONSerialization.jsonObject(with: Data(cell.utf8), options: .fragmentsAllowed)
        }
        func record(_ keys: [String], _ cells: [String]) throws -> [String: Any] {
            XCTAssertEqual(keys.count, cells.count)
            return try Dictionary(uniqueKeysWithValues: zip(keys, cells).map { ($0, try value($1)) })
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("defaults ") {
                defaults = try XCTUnwrap(try value(String(line.dropFirst(9))) as? [String: Any])
            } else if let open = line.firstIndex(of: "["), open == line.index(after: line.startIndex), let close = line.firstIndex(of: "]") {
                let kind = String(line.prefix(1))
                let names = String(line[line.index(after: open)..<close])
                headers[kind] = names.isEmpty ? [] : names.components(separatedBy: ",")
                if kind == "S" { inLog = true }
            } else if line.hasPrefix("c") || line.hasPrefix("e") || line == "W" || line.hasPrefix("W\t") || line.hasPrefix("B\t") {
                let cells = line.components(separatedBy: "\t")
                let id = cells[0]
                if id.hasPrefix("c"), !inLog {
                    contexts[id] = try record(Array((headers["C"] ?? []).dropFirst()), Array(cells.dropFirst()))
                } else if id.hasPrefix("e"), !inLog {
                    exercises[id] = try record(Array((headers["E"] ?? []).dropFirst()), Array(cells.dropFirst()))
                } else if id == "W" {
                    var fields = headers["W"] ?? []
                    var values = Array(cells.dropFirst())
                    workout = defaults
                    if fields.first == "context" {
                        workout.merge(try XCTUnwrap(contexts[values.removeFirst()])) { _, new in new }
                        fields.removeFirst()
                    }
                    workout.merge(try record(fields, values)) { _, new in new }
                } else if id.hasPrefix("e"), inLog {
                    var context = workout
                    context.merge(try XCTUnwrap(exercises[id])) { _, new in new }
                    var order = 1
                    for raw in cells[1].components(separatedBy: ";") {
                        var tuple = raw
                        var count = 1
                        if let marker = raw.range(of: "*(") {
                            count = try XCTUnwrap(Int(raw[..<marker.lowerBound]))
                            tuple = String(raw[marker.upperBound...].dropLast())
                        } else if tuple == "()" { tuple = "" }
                        let set = try record(headers["S"] ?? [], tuple.isEmpty ? [] : tuple.components(separatedBy: ","))
                        for _ in 0..<count {
                            var row = context.merging(set) { _, new in new }
                            if implicit { row["set_number"] = order }
                            order += 1
                            rows.append(row)
                        }
                    }
                } else if id == "B" {
                    breaks.append(try record(headers["B"] ?? [], Array(cells.dropFirst())))
                }
            }
        }
        return (rows, breaks)
    }
}
