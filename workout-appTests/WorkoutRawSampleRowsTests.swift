import XCTest
@testable import workout_app

final class WorkoutRawSampleRowsTests: XCTestCase {
    func testSummaryChangesAndRegeneratedSampleIDsDoNotInvalidateRows() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        var data = healthData(date: date)
        data.heartRateSamples = [HeartRateSample(timestamp: date, value: 120)]
        data.hrvSamples = [HRVSample(timestamp: date, value: 45)]
        data.bloodOxygenSamples = [BloodOxygenSample(timestamp: date, value: 97)]
        let original = WorkoutRawSampleSnapshot(data: data)

        data.avgHeartRate = 125
        data.heartRateSamples = [HeartRateSample(timestamp: date, value: 120)]
        data.hrvSamples = [HRVSample(timestamp: date, value: 45)]
        data.bloodOxygenSamples = [BloodOxygenSample(timestamp: date, value: 97)]
        XCTAssertEqual(original, WorkoutRawSampleSnapshot(data: data))

        data.heartRateSamples = [HeartRateSample(timestamp: date, value: 130)]
        XCTAssertNotEqual(original, WorkoutRawSampleSnapshot(data: data))
    }

    func testRowsKeepLatestFortySamplesInDescendingOrderAndCorrectUnits() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        var data = healthData(date: date)
        data.heartRateSamples = (0..<100).map { index in
            HeartRateSample(timestamp: date.addingTimeInterval(Double(index)), value: Double(index + 100))
        }.reversed()
        data.hrvSamples = [HRVSample(timestamp: date, value: 45)]
        data.bloodOxygenSamples = [BloodOxygenSample(timestamp: date, value: 97.5)]

        let rows = WorkoutRawSampleSnapshot(data: data).rows()
        XCTAssertEqual(rows.heartRate.count, 40)
        XCTAssertEqual(rows.heartRate.first?.0, date.addingTimeInterval(99))
        XCTAssertEqual(rows.heartRate.last?.0, date.addingTimeInterval(60))
        XCTAssertEqual(rows.heartRate.first?.1, "199 bpm")
        XCTAssertEqual(rows.hrv.first?.1, "45 ms")
        XCTAssertEqual(rows.bloodOxygen.first?.1, "97.5%")
    }

    func testRemovingSamplesInvalidatesSnapshotAndClearsAllRows() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        var data = healthData(date: date)
        data.heartRateSamples = [HeartRateSample(timestamp: date, value: 120)]
        let original = WorkoutRawSampleSnapshot(data: data)
        let cleared = WorkoutRawSampleSnapshot(data: nil)

        XCTAssertNotEqual(original, cleared)
        XCTAssertTrue(cleared.rows().heartRate.isEmpty)
        XCTAssertTrue(cleared.rows().hrv.isEmpty)
        XCTAssertTrue(cleared.rows().bloodOxygen.isEmpty)
    }

    private func healthData(date: Date) -> WorkoutHealthData {
        WorkoutHealthData(
            workoutId: UUID(),
            workoutDate: date,
            workoutStartTime: date,
            workoutEndTime: date.addingTimeInterval(3_600)
        )
    }
}
