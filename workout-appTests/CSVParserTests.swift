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
