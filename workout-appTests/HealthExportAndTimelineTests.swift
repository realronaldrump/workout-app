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

    func testDailyTimelineRangePolicyLimitsAllTimeToRecentWindow() {
        let start = dayStart(year: 2025, month: 1, day: 1)
        let allDays = (0..<150).map { offset in
            DailyHealthData(dayStart: day(offset: offset, from: start), steps: Double(offset))
        }
        let endDay = day(offset: 149, from: start)
        let range = DateInterval(start: start, end: endOfDay(endDay))

        let displayed = DailyTimelineRangePolicy.displayedDays(
            from: allDays,
            selectedRange: .allTime,
            range: range,
            calendar: calendar
        )

        XCTAssertEqual(displayed.count, DailyTimelineRangePolicy.recentWindowDays)
        XCTAssertEqual(displayed.first?.dayStart, day(offset: 60, from: start))
        XCTAssertEqual(displayed.last?.dayStart, endDay)
    }

    func testDailyTimelineRangePolicyKeepsShortCustomRangeUntouched() {
        let start = dayStart(year: 2026, month: 2, day: 1)
        let allDays = (0..<21).map { offset in
            DailyHealthData(dayStart: day(offset: offset, from: start), steps: Double(offset))
        }
        let endDay = day(offset: 20, from: start)
        let range = DateInterval(start: start, end: endOfDay(endDay))

        let displayed = DailyTimelineRangePolicy.displayedDays(
            from: allDays,
            selectedRange: .custom,
            range: range,
            calendar: calendar
        )

        XCTAssertEqual(displayed.count, allDays.count)
        XCTAssertEqual(displayed.first?.dayStart, start)
        XCTAssertEqual(displayed.last?.dayStart, endDay)
    }

    func testDailyHealthCoveragePlannerBatchesMissingRangesBackward() {
        let start = dayStart(year: 2026, month: 3, day: 1)
        let endDay = day(offset: 9, from: start)
        let range = DateInterval(start: start, end: endOfDay(endDay))
        let coveredDays: Set<Date> = [
            day(offset: 8, from: start),
            endDay
        ]

        let missingRanges = DailyHealthCoveragePlanner.missingRanges(
            in: range,
            coveredDays: coveredDays,
            batchSizeDays: 3,
            direction: .backward,
            calendar: calendar
        )

        XCTAssertEqual(missingRanges.count, 3)
        XCTAssertEqual(missingRanges[0].start, day(offset: 5, from: start))
        XCTAssertEqual(calendar.startOfDay(for: missingRanges[0].end), day(offset: 7, from: start))
        XCTAssertEqual(missingRanges[1].start, day(offset: 2, from: start))
        XCTAssertEqual(calendar.startOfDay(for: missingRanges[1].end), day(offset: 4, from: start))
        XCTAssertEqual(missingRanges[2].start, start)
        XCTAssertEqual(calendar.startOfDay(for: missingRanges[2].end), day(offset: 1, from: start))
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

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        return calendar
    }

    private func dayStart(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "America/Chicago")
        return calendar.date(from: components) ?? .distantPast
    }

    private func day(offset: Int, from start: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start) ?? .distantPast
    }

    private func endOfDay(_ date: Date) -> Date {
        calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
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
