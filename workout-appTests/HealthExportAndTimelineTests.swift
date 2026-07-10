import XCTest
@testable import workout_app

final class HealthExportAndTimelineTests: XCTestCase {
    func testHealthDateRangeContextAllTimeUsesProvidedEarliestDate() {
        let reference = dayStart(year: 2026, month: 6, day: 30).addingTimeInterval(12 * 60 * 60)
        let earliest = dayStart(year: 2024, month: 6, day: 15)
        let context = HealthDateRangeContext(selectedRange: .allTime)

        let resolved = context.resolvedRange(reference: reference, earliest: earliest)

        XCTAssertEqual(resolved.start, earliest)
        XCTAssertEqual(resolved.end, reference)
    }

    func testHealthComparisonRangesUseEqualCompletedCalendarDays() throws {
        let rangeStart = dayStart(year: 2026, month: 7, day: 3)
        let partialEnd = dayStart(year: 2026, month: 7, day: 10)
            .addingTimeInterval(12 * 60 * 60)

        let ranges = HealthDayComparisonRanges(
            resolvedRange: DateInterval(start: rangeStart, end: partialEnd),
            comparesPreviousPeriod: true,
            calendar: calendar
        )

        let current = try XCTUnwrap(ranges.currentComparison)
        let previous = try XCTUnwrap(ranges.previousComparison)
        XCTAssertEqual(ranges.comparisonDayCount, 7)
        XCTAssertEqual(current.lowerBound, dayStart(year: 2026, month: 7, day: 3))
        XCTAssertEqual(current.upperBound, dayStart(year: 2026, month: 7, day: 9))
        XCTAssertEqual(previous.lowerBound, dayStart(year: 2026, month: 6, day: 26))
        XCTAssertEqual(previous.upperBound, dayStart(year: 2026, month: 7, day: 2))
    }

    func testHealthComparisonRangesIncludeACompletedPastEndDay() throws {
        let customStart = dayStart(year: 2026, month: 7, day: 4)
        let customEnd = dayStart(year: 2026, month: 7, day: 10)

        let ranges = HealthDayComparisonRanges(
            resolvedRange: DateInterval(start: customStart, end: endOfDay(customEnd)),
            comparesPreviousPeriod: true,
            calendar: calendar
        )

        let current = try XCTUnwrap(ranges.currentComparison)
        let previous = try XCTUnwrap(ranges.previousComparison)
        XCTAssertEqual(ranges.comparisonDayCount, 7)
        XCTAssertEqual(current.upperBound, customEnd)
        XCTAssertEqual(previous.lowerBound, dayStart(year: 2026, month: 6, day: 27))
        XCTAssertEqual(previous.upperBound, dayStart(year: 2026, month: 7, day: 3))
    }

    @MainActor
    func testBodyCompositionViewModelUsesLocalDailyHealthStoreData() {
        let rangeStart = dayStart(year: 2026, month: 1, day: 10)
        let rangeEnd = endOfDay(dayStart(year: 2026, month: 1, day: 12))
        let displayRange = DateInterval(start: rangeStart, end: rangeEnd)
        let entries = [
            DailyHealthData(dayStart: dayStart(year: 2026, month: 1, day: 5), bodyMass: 80.0),
            DailyHealthData(dayStart: dayStart(year: 2026, month: 1, day: 10), bodyMass: 81.0),
            DailyHealthData(dayStart: dayStart(year: 2026, month: 1, day: 11), bodyMass: 81.5),
            DailyHealthData(dayStart: dayStart(year: 2026, month: 1, day: 12), bodyMass: 82.0)
        ]
        let model = BodyCompositionViewModel()

        model.load(
            dailyEntries: entries,
            metricKind: .weight,
            displayRange: displayRange,
            reportGranularity: .weekly
        )

        XCTAssertEqual(model.earliestSampleDate, dayStart(year: 2026, month: 1, day: 5))
        XCTAssertEqual(model.sampleCountInDisplayRange, 3)
        XCTAssertEqual(model.representativeSeries.map(\.date), [
            dayStart(year: 2026, month: 1, day: 10),
            dayStart(year: 2026, month: 1, day: 11),
            dayStart(year: 2026, month: 1, day: 12)
        ])
    }

    @MainActor
    func testBodyCompositionViewModelPreservesMultipleRawReadingsPerDay() {
        let firstDay = Calendar.current.startOfDay(for: Date())
        let secondDay = Calendar.current.date(byAdding: .day, value: 1, to: firstDay) ?? firstDay
        let displayRange = DateInterval(
            start: firstDay,
            end: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: secondDay) ?? secondDay
        )
        let samples = [
            BodyRawSample(timestamp: firstDay.addingTimeInterval(8 * 3_600), value: 180),
            BodyRawSample(timestamp: firstDay.addingTimeInterval(18 * 3_600), value: 181),
            BodyRawSample(timestamp: secondDay.addingTimeInterval(8 * 3_600), value: 179)
        ]
        let model = BodyCompositionViewModel()

        model.load(
            rawSamples: samples,
            displayRange: displayRange,
            reportGranularity: .weekly
        )

        XCTAssertEqual(model.sampleCountInDisplayRange, 3)
        XCTAssertEqual(model.representativeSeries.count, 2)
        XCTAssertEqual(model.logbookDays.last?.samples.count, 2)
        XCTAssertEqual(model.logbookDays.last?.representativeTimestamp, samples[0].timestamp)
    }

    func testMetricSampleStreamWriterDeduplicatesChunkBoundaries() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetricStreamWriter-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("samples.csv")
        defer { try? FileManager.default.removeItem(at: directory) }
        let duplicateID = UUID()
        let writer = try HealthCSVExporter.MetricSamplesStreamWriter(fileURL: fileURL)

        try await writer.append(
            metric: .bodyMass,
            samples: [HealthMetricSample(id: duplicateID, timestamp: Date(), value: 81)]
        )
        try await writer.append(
            metric: .bodyMass,
            samples: [
                HealthMetricSample(id: duplicateID, timestamp: Date(), value: 81),
                HealthMetricSample(timestamp: Date().addingTimeInterval(60), value: 82)
            ]
        )
        let count = try await writer.finish()
        let csv = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(csv.split(separator: "\n").count, 3)
    }

    func testTimelineDisplayPolicyKeepsCompactRowsContiguous() {
        let items = Array(0..<29)
        let visible = DailyTimelineDisplayPolicy.visibleItems(from: items, density: .compact)

        XCTAssertEqual(visible, Array(0..<DailyTimelineDisplayPolicy.compactCount))
    }

    func testTimelineDisplayPolicyKeepsExpandedRowsContiguous() {
        let items = Array(0..<29)
        let visible = DailyTimelineDisplayPolicy.visibleItems(from: items, density: .expanded)

        XCTAssertEqual(visible.count, DailyTimelineDisplayPolicy.expandedCount)
        XCTAssertEqual(visible.first, 0)
        XCTAssertEqual(visible.last, 27)
    }

    func testHealthTrendPointIdentityIsStableForLogicalPointUpdates() {
        let date = dayStart(year: 2026, month: 4, day: 20)

        let original = HealthTrendPoint(date: date, value: 72, label: "Resting HR")
        let updatedValue = HealthTrendPoint(date: date, value: 74, label: "Resting HR")
        let differentMetric = HealthTrendPoint(date: date, value: 74, label: "Walking HR")

        XCTAssertEqual(original.id, updatedValue.id)
        XCTAssertNotEqual(original.id, differentMetric.id)
    }

    func testTimelineDisplayPolicyShowAllKeepsFullRange() {
        let start = dayStart(year: 2025, month: 1, day: 1)
        let allDays = (0..<150).map { offset in
            DailyHealthData(dayStart: day(offset: offset, from: start), steps: Double(offset))
        }

        let displayed = DailyTimelineDisplayPolicy.visibleItems(from: allDays, density: .all)

        XCTAssertEqual(displayed.count, allDays.count)
        XCTAssertEqual(displayed.first?.dayStart, start)
        XCTAssertEqual(displayed.last?.dayStart, day(offset: 149, from: start))
    }

    func testDailyTimelineSortOrderNewestFirst() {
        let start = dayStart(year: 2026, month: 2, day: 1)
        let allDays = (0..<3).map { offset in
            DailyHealthData(dayStart: day(offset: offset, from: start), steps: Double(offset))
        }

        let sorted = DailyTimelineSortOrder.newestFirst.sortedDays(allDays)

        XCTAssertEqual(sorted.map(\.dayStart), [
            day(offset: 2, from: start),
            day(offset: 1, from: start),
            start
        ])
    }

    func testDailyTimelineSortOrderOldestFirst() {
        let start = dayStart(year: 2026, month: 2, day: 1)
        let allDays = (0..<3).reversed().map { offset in
            DailyHealthData(dayStart: day(offset: offset, from: start), steps: Double(offset))
        }

        let sorted = DailyTimelineSortOrder.oldestFirst.sortedDays(allDays)

        XCTAssertEqual(sorted.map(\.dayStart), [
            start,
            day(offset: 1, from: start),
            day(offset: 2, from: start)
        ])
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
