import XCTest
@testable import workout_app

final class CSVParserTests: XCTestCase {
    private let header = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE"

    func testParsesBasicStrongExport() throws {
        let csv = """
        \(header)
        2026-01-05 07:30:00,Push Day,1h 5m,Bench Press (Barbell),1,135.0,8.0,0,0,,,
        2026-01-05 07:30:00,Push Day,1h 5m,Bench Press (Barbell),2,145.5,6.0,0,0,,,
        """

        let sets = try CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8))

        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[0].exerciseName, "Bench Press (Barbell)")
        XCTAssertEqual(sets[0].reps, 8)
        XCTAssertEqual(sets[1].weight, 145.5, accuracy: 0.0001)
        XCTAssertEqual(sets[1].setOrder, 2)
    }

    func testQuotedNotesWithLineBreaksDoNotSplitRows() throws {
        let csv = "\(header)\r\n"
            + "2026-01-05 07:30:00,Push Day,1h,\"Squat, High Bar\",1,225,5,0,0,\"felt good\nlast rep slow\",,\r\n"
            + "2026-01-05 07:30:00,Push Day,1h,\"Squat, High Bar\",2,225,5,0,0,\"said \"\"easy\"\"\",,\r\n"

        let sets = try CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8))

        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets.map(\.exerciseName), ["Squat, High Bar", "Squat, High Bar"])
        XCTAssertEqual(sets.map(\.setOrder), [1, 2])
    }

    func testHandlesByteOrderMarkAndSemicolonDelimitedCommaDecimals() throws {
        let csv = "\u{FEFF}Date;Workout Name;Duration;Exercise Name;Set Order;Weight;Reps;Distance;Seconds\n"
            + "2026-01-05 07:30:00;Leg Day;50m;Leg Press;1;102,5;10;0;0\n"

        let sets = try CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8))

        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets[0].weight, 102.5, accuracy: 0.0001)
        XCTAssertEqual(sets[0].reps, 10)
    }

    func testMissingOptionalColumnsDefaultToZero() throws {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps
        2026-01-05 07:30,Pull Day,45m,Pull Up,1,0,12
        """

        let sets = try CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8))

        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets[0].distance, 0)
        XCTAssertEqual(sets[0].seconds, 0)
    }

    func testDelimiterDetectionIgnoresQuotedNotesForEveryLineEnding() throws {
        let notes = String(repeating: ";", count: 40)
        for newline in ["\n", "\r", "\r\n"] {
            let csv = header + newline
                + "2026-01-05 07:30:00,Push Day,45m,Bench Press,1,135,8,0,0,\"\(notes)\",," + newline

            let sets = try CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8))

            XCTAssertEqual(sets.count, 1, "Line ending: \(newline.debugDescription)")
            XCTAssertEqual(sets.first?.exerciseName, "Bench Press")
        }
    }

    func testSemicolonDelimiterIgnoresCommaHeavyNotesWithWindowsLineEndings() throws {
        let notes = String(repeating: ",", count: 40)
        let csv = header.replacingOccurrences(of: ",", with: ";") + "\r\n"
            + "2026-01-05 07:30:00;Leg Day;50m;Leg Press;1;102,5;10;0;0;\"\(notes)\";;\r\n"

        let sets = try CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8))

        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets.first?.weight, 102.5)
    }

    func testSecondsColumnDoesNotBecomeDistanceWhenDistanceHeaderIsMissing() throws {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Seconds
        2026-01-05 07:30:00,Cardio,45m,Running,1,0,0,180
        """

        let set = try XCTUnwrap(CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8)).first)

        XCTAssertEqual(set.distance, 0)
        XCTAssertEqual(set.seconds, 180)
    }

    func testDistanceColumnDoesNotBecomeSecondsWhenSecondsHeaderIsMissing() throws {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,RPE,Distance
        2026-01-05 07:30:00,Cardio,45m,Running,1,0,0,8,2.5
        """

        let set = try XCTUnwrap(CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8)).first)

        XCTAssertEqual(set.distance, 2.5)
        XCTAssertEqual(set.seconds, 0)
    }

    func testMissingMetricHeadersDoNotReadOtherNumericColumns() throws {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,RPE,Notes
        2026-01-05 07:30:00,Push Day,45m,Bench Press,1,135,8,9,10
        """

        let set = try XCTUnwrap(CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8)).first)

        XCTAssertEqual(set.distance, 0)
        XCTAssertEqual(set.seconds, 0)
    }

    func testReorderedMetricHeadersKeepTheirOwnValues() throws {
        let csv = """
        Exercise Name,Seconds,Workout Name,Reps,Date,Weight,Set Order,Duration,Distance
        Running,180,Cardio,0,2026-01-05 07:30:00,0,1,45m,2.5
        """

        let set = try XCTUnwrap(CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8)).first)

        XCTAssertEqual(set.exerciseName, "Running")
        XCTAssertEqual(set.distance, 2.5)
        XCTAssertEqual(set.seconds, 180)
    }

    func testExplicitKilogramWeightsConvertToTheAppsPoundUnit() throws {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight (kg),Reps,Distance,Seconds
        2026-01-05 07:30:00,Pull,45m,Row,1,50,8,0,0
        2026-01-05 07:30:00,Pull,45m,Assisted Pull Up,1,-20,8,0,0
        """
        let sets = try CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8))
        XCTAssertEqual(sets[0].weight, 110.2311310924, accuracy: 0.000001)
        XCTAssertEqual(sets[1].weight, -44.0924524369, accuracy: 0.000001)
    }

    func testBodyweightAndCardioRowsKeepBlankStrengthCells() throws {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds
        2026-01-05 07:30:00,Mixed,45m,Pull Up,1,,12,,
        2026-01-05 07:30:00,Mixed,45m,Running,1,,,2.5,900
        2026-01-05 07:30:00,Mixed,45m,Plank,1,,,,60
        """

        let sets = try CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8))

        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets[0].weight, 0)
        XCTAssertEqual(sets[0].reps, 12)
        XCTAssertEqual(sets[1].distance, 2.5)
        XCTAssertEqual(sets[1].seconds, 900)
        XCTAssertEqual(sets[2].seconds, 60)
    }

    func testUnsupportedExportCannotBecomeAnEmptyHistoryReplacement() {
        let csv = """
        Record Type,Workout Start,Workout Name,Exercise,Weight (lbs),Reps,Workout ID
        set,2026-01-05T07:30:00.000-07:00,Mixed,Pull Up,0,12,\(UUID())
        """

        XCTAssertThrowsError(try CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8))) { error in
            guard case CSVParserError.noWorkoutSets = error else {
                return XCTFail("Expected noWorkoutSets, got \(error)")
            }
        }
    }

    func testInvalidNonemptyStrengthValuesAreNotInventedAsZero() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds
        2026-01-05 07:30:00,Mixed,45m,Running,1,invalid,,2.5,900
        """

        XCTAssertThrowsError(try CSVParser.parseStrongWorkoutsCSV(from: Data(csv.utf8)))
    }

    func testHeaderOnlyFileThrowsEmptyFile() {
        XCTAssertThrowsError(try CSVParser.parseStrongWorkoutsCSV(from: Data("\(header)\n\n".utf8))) { error in
            guard case CSVParserError.emptyFile = error else {
                return XCTFail("Expected emptyFile, got \(error)")
            }
        }
    }

    func testParseDecimalAcceptsCommaSeparator() {
        XCTAssertEqual(WorkoutValueFormatter.parseDecimal("62,5"), 62.5)
        XCTAssertEqual(WorkoutValueFormatter.parseDecimal(" 100 "), 100)
        XCTAssertNil(WorkoutValueFormatter.parseDecimal(""))
        XCTAssertNil(WorkoutValueFormatter.parseDecimal("abc"))
        XCTAssertEqual(WorkoutValueFormatter.parseDurationSeconds("1,5"), 90)
    }
}
