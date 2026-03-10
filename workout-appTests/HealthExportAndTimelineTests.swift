import XCTest
@testable import workout_app

final class HealthExportAndTimelineTests: XCTestCase {
    func testTimelineSamplingKeepsCompactViewNearTargetCount() {
        let indices = TimelineSampling.sampledIndices(totalCount: 13, targetCount: 12)

        XCTAssertEqual(indices.count, 12)
        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.last, 12)
    }

    func testTimelineSamplingKeepsExpandedViewNearTargetCount() {
        let indices = TimelineSampling.sampledIndices(totalCount: 29, targetCount: 28)

        XCTAssertEqual(indices.count, 28)
        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.last, 28)
    }

    func testWorkoutHealthSummaryExportAllowsBodyMetricsOnlyRows() throws {
        let workoutDate = date(day: 1, hour: 8)
        let workout = Workout(
            date: workoutDate,
            name: "Upper A",
            duration: "45m",
            exercises: [
                Exercise(name: "Bench Press", sets: [])
            ]
        )

        let healthData = WorkoutHealthData(
            workoutId: workout.id,
            workoutDate: workoutDate,
            workoutStartTime: workoutDate,
            workoutEndTime: workoutDate.addingTimeInterval(45 * 60),
            bodyMass: 81.6,
            bodyFatPercentage: 0.18,
            bodyTemperature: 36.7
        )

        let data = try HealthCSVExporter.exportWorkoutHealthSummaryCSV(
            workouts: [workout],
            healthDataByWorkoutID: [workout.id: healthData],
            startDate: Calendar.current.startOfDay(for: workoutDate),
            endDateInclusive: Calendar.current.startOfDay(for: workoutDate),
            includeLocationData: false
        )

        let csv = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(csv.contains("Upper A"))
        XCTAssertTrue(csv.contains(",179.9,18,36.7,"))
    }

    private func date(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "America/Chicago")
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }
}
