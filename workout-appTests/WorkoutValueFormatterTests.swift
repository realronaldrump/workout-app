import XCTest
@testable import workout_app

final class WorkoutValueFormatterTests: XCTestCase {
    func testEditableWeightsAndDistancesPreserveTheirPrecision() {
        for value in [0, 1.25, 2.75, 42.125, 0.001, 12345.6789, 1.2345678901234567] {
            XCTAssertEqual(WorkoutValueFormatter.parseDecimal(WorkoutValueFormatter.weightText(value)), value)
            XCTAssertEqual(WorkoutValueFormatter.parseDecimal(WorkoutValueFormatter.distanceText(value)), value)
        }
        XCTAssertEqual(WorkoutValueFormatter.weightText(1.25), "1.25")
        XCTAssertEqual(WorkoutValueFormatter.weightText(100), "100")
    }

    func testDecimalInputSupportsCommaWithoutAcceptingNonfiniteOrMalformedValues() {
        XCTAssertEqual(WorkoutValueFormatter.parseDecimal(" 2,75 "), 2.75)
        XCTAssertEqual(WorkoutValueFormatter.parseDecimal(".5"), 0.5)
        for text in ["", "nan", "inf", "1e309", "1,2,3", "1.2.3", "0x1p4"] {
            XCTAssertNil(WorkoutValueFormatter.parseDecimal(text), text)
        }
    }

    func testCountsNeverRoundFractionalReps() {
        XCTAssertEqual(WorkoutValueFormatter.parseWholeNumber("8.0"), 8)
        XCTAssertEqual(WorkoutValueFormatter.parseWholeNumber("8,0"), 8)
        XCTAssertEqual(WorkoutValueFormatter.parseWholeNumber("0"), 0)
        for text in ["8.5", "-1", "nan", "1e30"] {
            XCTAssertNil(WorkoutValueFormatter.parseWholeNumber(text), text)
        }
    }

    func testDurationInputSupportsMinutesAndClockTime() {
        XCTAssertEqual(WorkoutValueFormatter.parseDurationSeconds("12.5"), 750)
        XCTAssertEqual(WorkoutValueFormatter.parseDurationSeconds("12,5"), 750)
        XCTAssertEqual(WorkoutValueFormatter.parseDurationSeconds("12:30"), 750)
        XCTAssertEqual(WorkoutValueFormatter.parseDurationSeconds("1:02:30"), 3750)
        XCTAssertEqual(WorkoutValueFormatter.parseDurationSeconds("0:01.5"), 1.5)
        XCTAssertEqual(WorkoutValueFormatter.parseDurationSeconds("90:00"), 5400)
    }

    func testMalformedAndOverflowingDurationsAreRejectedWithoutTrapping() {
        for text in [":30", "1:", "1::30", "1:60", "1:60:00", "1:00:60", "-1:30", "1:-30",
                     "1.5:00", "1:2:3:4", "999999999999999999999:00", "1e308", "nan", "inf"] {
            XCTAssertNil(WorkoutValueFormatter.parseDurationSeconds(text), text)
        }
    }

    func testDurationFormattingPreservesFractionsAndHandlesInvalidImportedValues() {
        XCTAssertEqual(WorkoutValueFormatter.durationText(seconds: 61.125), "1:01.125")
        XCTAssertEqual(WorkoutValueFormatter.durationText(seconds: 3750), "1:02:30")
        for seconds in [0, 1.5, 61.125, 3750.25, 0.000001] {
            let text = WorkoutValueFormatter.durationText(seconds: seconds)
            XCTAssertEqual(WorkoutValueFormatter.parseDurationSeconds(text), seconds)
        }
        for seconds in [Double.infinity, .nan, .greatestFiniteMagnitude, -1] {
            XCTAssertEqual(WorkoutValueFormatter.durationText(seconds: seconds), "")
        }
    }
}
