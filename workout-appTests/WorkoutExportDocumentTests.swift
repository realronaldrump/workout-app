import XCTest
@testable import workout_app

final class WorkoutExportDocumentTests: XCTestCase {
    func testRowsRetainContextPrecisionAndLoggedOrder() throws {
        let document = try makeDocument()
        XCTAssertEqual(document.records.count, 3)
        XCTAssertEqual(document.records.map { $0.value(.exercise).text }, ["Press", "Press", "Row"])
        XCTAssertEqual(document.records.map { $0.value(.workoutName).text }, Array(repeating: "Morning", count: 3))
        XCTAssertEqual(document.records.map { $0.value(.gymName).text }, Array(repeating: "Local Gym", count: 3))
        XCTAssertEqual(document.records[0].value(.weight), .number(12.375))
        XCTAssertEqual(document.records[1].value(.weight), .number(15.125))
        XCTAssertEqual(document.records[0].value(.duration), .number(3930))
        XCTAssertEqual(document.records[0].value(.durationText), .text("1h 5m 30s"))
        XCTAssertEqual(document.records[0].value(.distance), .number(0))
        XCTAssertEqual(document.records[0].workoutID, document.records[2].workoutID)
        XCTAssertNotEqual(document.records[0].exerciseID, document.records[2].exerciseID)
        XCTAssertNotEqual(document.records[0].setID, document.records[1].setID)
        XCTAssertEqual(document.records[0].value(.tags), document.records[1].value(.tags))
    }

    func testSelectedColumnsStayInOrderEvenWhenAllValuesAreZero() throws {
        let document = try makeDocument(columns: [.seconds, .distance, .seconds])
        var lines: [String] = []
        try document.writeCSVLines { lines.append($0) }
        XCTAssertEqual(lines[0], "Record Type,Set Duration (seconds),Distance (unit unspecified),Workout ID,Exercise ID,Set ID")
        XCTAssertTrue(lines.dropFirst().allSatisfy { $0.hasPrefix("set,0,0,") })
        XCTAssertEqual(Set(lines.map { $0.split(separator: ",", omittingEmptySubsequences: false).count }), [6])
    }

    func testJSONHasTypedValuesExplicitDefinitionsAndMuscleArrays() throws {
        let document = try makeDocument()
        let json = try jsonObject(document)
        XCTAssertEqual(json["schema_version"] as? Int, 2)
        XCTAssertEqual(json["time_zone"] as? String, "America/Denver")
        let records = try XCTUnwrap(json["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0]["weight"] as? Double, 12.375)
        XCTAssertEqual(records[0]["reps"] as? Int, 8)
        XCTAssertEqual(records[0]["workout_duration_seconds"] as? Int, 3930)
        XCTAssertEqual(records[0]["distance"] as? Int, 0)
        XCTAssertTrue(records[0]["parent_exercise"] is NSNull)
        let muscles = try XCTUnwrap(records[0]["muscle_assignments"] as? [[String: String]])
        XCTAssertEqual(muscles, [["name": "Chest", "role": "primary"], ["name": "Triceps", "role": "secondary"]])
        let fields = try XCTUnwrap(json["fields"] as? [[String: Any]])
        XCTAssertEqual(fields.first { $0["key"] as? String == "weight" }?["unit"] as? String, "lbs")
        XCTAssertNil(fields.first { $0["key"] as? String == "distance" }?["unit"])
        XCTAssertEqual(Set(fields.compactMap { $0["key"] as? String }), Set(records[0].keys))
    }

    func testExcludedFieldsDoNotLeakIntoReportOrJSON() throws {
        let document = try makeDocument(columns: [.weight, .reps])
        let records = try XCTUnwrap(try jsonObject(document)["records"] as? [[String: Any]])
        XCTAssertEqual(Set(records[0].keys), ["weight", "reps", "workout_id", "exercise_id", "set_id"])
        let html = try WorkoutReportRenderer.render(document)
        for secret in ["Morning", "Local Gym", "Press", "Triceps", "1h 5m 30s"] {
            XCTAssertFalse(html.contains(secret), "Excluded field leaked: \(secret)")
        }
    }

    func testDurationParsingDoesNotEstimateUnknownValues() {
        for (input, seconds) in ["29m": 1740.0, "1h": 3600, "1h 1m": 3660, "01:05:30": 3930,
                                 "05:30": 330, "90": 5400, "1.5h": 5400, "0s": 0, "2m 0.25s": 120.25] {
            XCTAssertEqual(WorkoutExportDocument.durationSeconds(input), seconds, input)
        }
        for invalid in ["", "unknown", "-5m", "1h junk", "1h 2h", "01:70:00", "NaN", "1:2:3:4", "1e309"] {
            XCTAssertNil(WorkoutExportDocument.durationSeconds(invalid), invalid)
        }
        XCTAssertEqual(WorkoutExportValue.number(.infinity).text, "")
        XCTAssertEqual(WorkoutExportValue.number(.nan).text, "")
    }

    func testUnrecognizedDurationIsNullAndOriginalTextIsPreserved() throws {
        let document = try makeDocument(duration: "unrecorded")
        let row = try XCTUnwrap((try jsonObject(document)["records"] as? [[String: Any]])?.first)
        XCTAssertTrue(row["workout_duration_seconds"] is NSNull)
        XCTAssertEqual(row["logged_duration"] as? String, "unrecorded")
    }

    func testTimestampAndFilenamesUseExportCalendarTimeZone() throws {
        var exportCalendar = Calendar(identifier: .buddhist)
        exportCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-04-09T12:30:00Z"))
        let workout = fixture(date: date)
        let document = try WorkoutExportDocument(
            workouts: [workout], startDate: date, endDateInclusive: date, calendar: exportCalendar
        )
        XCTAssertEqual(document.startDay, "2026-04-10")
        XCTAssertEqual(document.records[0].value(.workoutStart).text, "2026-04-10T02:30:00.000+14:00")
        let fileName = try WorkoutCSVExporter.makeWorkoutExportFileName(
            startDate: date, endDateInclusive: date, calendar: exportCalendar
        )
        XCTAssertTrue(fileName.hasPrefix("workout_export_20260410_20260410_"))
    }

    func testDayFilteringAcrossDaylightSavingTransition() throws {
        let formatter = ISO8601DateFormatter()
        let day = try XCTUnwrap(formatter.date(from: "2026-03-08T07:00:00Z"))
        let nextDay = try XCTUnwrap(formatter.date(from: "2026-03-09T06:00:00Z"))
        let early = fixture(date: day)
        let late = fixture(date: nextDay.addingTimeInterval(-1))
        let excluded = fixture(date: nextDay)
        let document = try WorkoutExportDocument(
            workouts: [excluded, late, early], startDate: day, endDateInclusive: day, calendar: calendar
        )
        XCTAssertEqual(Set(document.records.map(\.workoutID)), [early.id, late.id])
        XCTAssertTrue(document.records.first?.value(.workoutStart).text.hasSuffix("-07:00") == true)
        XCTAssertTrue(document.records.last?.value(.workoutStart).text.hasSuffix("-06:00") == true)
    }

    func testBreaksStaySeparateInJSONAndClipToFullSelectedRange() throws {
        let workout = fixture()
        let start = calendar.date(byAdding: .day, value: -3, to: workout.date)!
        let end = calendar.date(byAdding: .day, value: 3, to: workout.date)!
        let saved = IntentionalBreakRange(
            startDate: calendar.date(byAdding: .day, value: -5, to: start)!,
            endDate: calendar.date(byAdding: .day, value: -1, to: workout.date)!,
            name: "Travel, rest", calendar: calendar
        )
        let document = try WorkoutExportDocument(
            workouts: [workout], startDate: start, endDateInclusive: end,
            intentionalBreaks: [saved], includeIntentionalBreaks: true, calendar: calendar
        )
        XCTAssertEqual(document.breaks.count, 1)
        XCTAssertEqual(document.breaks[0].days, 3)
        XCTAssertEqual(document.breaks[0].startDate, document.startDay)
        let json = try jsonObject(document)
        XCTAssertEqual((json["records"] as? [Any])?.count, 3)
        XCTAssertEqual((json["breaks"] as? [Any])?.count, 1)
        var lines: [String] = []
        try document.writeCSVLines { lines.append($0) }
        XCTAssertTrue(lines[1].hasPrefix("break,"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("set,") }.count, 3)
    }

    func testCSVQuotesMultilineUnicodeTextAndKeepsNegativeNumbersNumeric() {
        XCTAssertEqual(WorkoutExportValue.text("Gym, \"West\"\r\nCafé").csv, "\"Gym, \"\"West\"\"\r\nCafé\"")
        for input in ["=1+1", "+SUM(A1)", "-formula", "@lookup", " \t=1+1"] {
            XCTAssertTrue(WorkoutExportValue.text(input).csv.hasPrefix("'"))
        }
        XCTAssertEqual(WorkoutExportValue.number(-12.375).csv, "-12.375")
    }

    func testReportEscapesContentAndEmbedsExactlyTheSelectedJSON() throws {
        let name = "</script><script>alert(1)</script> & \"Café\""
        let document = try makeDocument(name: name)
        let html = try WorkoutReportRenderer.render(document)
        XCTAssertFalse(html.contains(name))
        XCTAssertTrue(html.contains("&lt;/script&gt;&lt;script&gt;alert(1)&lt;/script&gt;"))
        let marker = "<script type=\"application/json\" id=\"workout-data\">"
        let start = try XCTUnwrap(html.range(of: marker)).upperBound
        let end = try XCTUnwrap(html.range(of: "</script>", range: start..<html.endIndex)).lowerBound
        let embedded = try XCTUnwrap(String(html[start..<end]).data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: embedded) as? NSDictionary
        XCTAssertEqual(object, try JSONSerialization.jsonObject(with: document.jsonData()) as? NSDictionary)
        XCTAssertTrue(html.contains("<caption"))
        XCTAssertTrue(html.contains("@media print"))
        XCTAssertEqual(html.components(separatedBy: "data-set-id=").count - 1, 3)
    }

    func testReportHidesUnusedCardioColumnsWhileJSONRetainsTheirValues() throws {
        let document = try makeDocument()
        let html = try WorkoutReportRenderer.render(document)
        XCTAssertFalse(html.contains("<th scope=\"col\">Distance</th>"))
        let rows = try XCTUnwrap(try jsonObject(document)["records"] as? [[String: Any]])
        XCTAssertTrue(rows.allSatisfy { ($0["distance"] as? Int) == 0 && ($0["set_duration_seconds"] as? Int) == 0 })
    }

    func testFormatsWriteReadableFilesWithMatchingExtensions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try makeDocument()
        for format in WorkoutExportFormat.allCases {
            let destination = directory.appendingPathComponent(format.fileName(from: "workout_export_example.csv"))
            try document.write(to: destination, format: format)
            let data = try Data(contentsOf: destination)
            XCTAssertFalse(data.isEmpty)
            XCTAssertEqual(destination.pathExtension, format.fileExtension)
            if format == .json { XCTAssertEqual(data, try document.jsonData()) }
            if format == .report { XCTAssertEqual(String(data: data, encoding: .utf8), try WorkoutReportRenderer.render(document)) }
        }
    }

    func testEmptyWorkoutsWithNoSetsDoNotCreateAnApparentlySuccessfulExport() {
        let date = fixture().date
        let workout = Workout(date: date, name: "Empty", duration: "", exercises: [])
        XCTAssertThrowsError(try WorkoutExportDocument(workouts: [workout], startDate: date, endDateInclusive: date)) {
            guard case WorkoutExportError.noSetsInRange = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    private func fixture(date: Date? = nil, name: String = "Morning", duration: String = "1h 5m 30s") -> Workout {
        let date = date ?? calendar.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 8))!
        func set(_ order: Int, _ weight: Double, exercise: String) -> WorkoutSet {
            WorkoutSet(date: date, workoutName: name, duration: duration, exerciseName: exercise,
                       setOrder: order, weight: weight, reps: 8, distance: 0, seconds: 0)
        }
        return Workout(date: date, name: name, duration: duration, exercises: [
            Exercise(name: "Press", sets: [set(2, 15.125, exercise: "Press"), set(1, 12.375, exercise: "Press")]),
            Exercise(name: "Row", sets: [set(1, 20, exercise: "Row")])
        ])
    }

    private func makeDocument(
        columns: [WorkoutExportColumn] = WorkoutExportColumn.defaultColumns,
        name: String = "Morning", duration: String = "1h 5m 30s"
    ) throws -> WorkoutExportDocument {
        let workout = fixture(name: name, duration: duration)
        return try WorkoutExportDocument(
            workouts: [workout], startDate: workout.date, endDateInclusive: workout.date,
            exerciseTagsByName: ["Press": "Primary: Chest; Secondary: Triceps"],
            exerciseMusclesByName: ["Press": [.init(name: "Chest", role: "primary"), .init(name: "Triceps", role: "secondary")]],
            gymNamesByWorkoutID: [workout.id: "Local Gym"], selectedColumns: columns, weightUnit: "lbs", calendar: calendar
        )
    }

    private func jsonObject(_ document: WorkoutExportDocument) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: document.jsonData()) as? [String: Any])
    }
}
