import XCTest
@testable import workout_app

final class HealthDailySnapshotTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    func testIndexedRangePreservesInclusiveDaysAcrossDaylightSavingAndSparseHistory() {
        let entries = [
            DailyHealthData(dayStart: date(7), steps: 7),
            DailyHealthData(dayStart: date(8), steps: 8),
            DailyHealthData(dayStart: date(10), steps: 10)
        ]
        let snapshot = HealthDailySnapshot(
            store: Dictionary(uniqueKeysWithValues: entries.map { ($0.dayStart, $0) }),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.days(in: date(7)...date(8)).map(\.steps), [7, 8])
        XCTAssertEqual(snapshot.days(in: date(8)...date(10)).map(\.steps), [8, 10])
        XCTAssertTrue(snapshot.days(in: date(9)...date(9)).isEmpty)
        XCTAssertTrue(snapshot.days(in: date(1)...date(2)).isEmpty)
        XCTAssertTrue(snapshot.days(in: date(11)...date(12)).isEmpty)
        XCTAssertEqual(snapshot.day(on: date(8, hour: 17))?.steps, 8)
        XCTAssertNil(snapshot.day(on: date(9, hour: 17)))
        XCTAssertEqual(snapshot.earliestDate, date(7))
    }

    func testMetricEarliestDatesExcludeMissingAndNonFiniteValues() {
        let first = DailyHealthData(dayStart: date(7), steps: 7, bodyMass: .nan)
        let second = DailyHealthData(dayStart: date(10), bodyMass: 80)
        let snapshot = HealthDailySnapshot(store: [first.dayStart: first, second.dayStart: second], calendar: calendar)

        XCTAssertEqual(snapshot.earliestDate(for: .steps), first.dayStart)
        XCTAssertEqual(snapshot.earliestDate(for: .bodyMass), second.dayStart)
        XCTAssertNil(snapshot.earliestDate(for: .bodyFatPercentage))
    }

    func testRangeAnalysisKeepsDisplayUnitsAndCompletePreviousPeriod() throws {
        let days = (1...14).map { day in
            DailyHealthData(dayStart: date(day), steps: Double(day * 100), bodyMass: 80)
        }
        let snapshot = HealthDailySnapshot(
            store: Dictionary(uniqueKeysWithValues: days.map { ($0.dayStart, $0) }), calendar: calendar
        )
        let resolved = DateInterval(start: date(8), end: date(14, hour: 12))
        let ranges = HealthDayComparisonRanges(resolvedRange: resolved, comparesPreviousPeriod: true, calendar: calendar)
        let result = try HealthMetricRangeAnalysis(
            snapshot: snapshot, metrics: [.steps, .bodyMass], ranges: ranges,
            resolvedRange: resolved, calendar: calendar, now: date(14, hour: 12)
        )

        XCTAssertEqual(result.analyses[.steps]?.samples.count, 7)
        XCTAssertEqual(result.analyses[.steps]?.completed.count, 6)
        XCTAssertEqual(result.analyses[.steps]?.mean, 1_050)
        XCTAssertEqual(result.previousAverages[.steps], 450)
        XCTAssertEqual(result.analyses[.bodyMass]?.mean ?? 0, 80 * 2.20462, accuracy: 0.0001)
    }

    func testRangeAnalysisFiltersInvalidValuesAndAveragesSleepOncePerNight() throws {
        let sleep = SleepSummary(
            totalSleep: 8 * 3_600, inBed: 9 * 3_600,
            stageDurations: [.deep: 2 * 3_600, .core: 6 * 3_600],
            start: date(7), end: date(8), sourceSelectionMode: .fallback
        )
        let first = DailyHealthData(dayStart: date(8), steps: .infinity, sleepSummary: sleep)
        let second = DailyHealthData(dayStart: date(9), steps: 200)
        let snapshot = HealthDailySnapshot(store: [first.dayStart: first, second.dayStart: second], calendar: calendar)
        let resolved = DateInterval(start: date(8), end: date(9, hour: 23))
        let result = try HealthMetricRangeAnalysis(
            snapshot: snapshot, metrics: [.steps, .sleep],
            ranges: HealthDayComparisonRanges(resolvedRange: resolved, comparesPreviousPeriod: false, calendar: calendar),
            resolvedRange: resolved, calendar: calendar, now: date(10)
        )

        XCTAssertEqual(result.analyses[.steps]?.samples.map(\.value), [200])
        XCTAssertEqual(result.sleepSummaryCount, 1)
        XCTAssertEqual(result.fallbackSleepCount, 1)
        XCTAssertEqual(result.sleepStageAverages[.deep], 2)
        XCTAssertEqual(result.sleepStageAverages[.core], 6)
    }

    func testCancelledRangeAnalysisDoesNotProduceAnEmptySuccess() async {
        let snapshot = HealthDailySnapshot(store: [:])
        let range = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86_400)
        let ranges = HealthDayComparisonRanges(resolvedRange: range, comparesPreviousPeriod: false)
        let worker = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try HealthMetricRangeAnalysis(
                snapshot: snapshot, metrics: [.steps], ranges: ranges, resolvedRange: range
            )
        }
        worker.cancel()
        do {
            _ = try await worker.value
            XCTFail("A superseded range calculation must stop without publishing a result")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testWeekRangeFromLongHistoryMatchesCalendarScan() {
        let entries = (0..<10_000).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: date(1))!
            return DailyHealthData(dayStart: day, steps: Double(offset))
        }
        let snapshot = HealthDailySnapshot(
            store: Dictionary(uniqueKeysWithValues: entries.map { ($0.dayStart, $0) }), calendar: calendar
        )
        let range = entries[5_000].dayStart...entries[5_006].dayStart
        let expected = entries.filter { range.contains(calendar.startOfDay(for: $0.dayStart)) }
        XCTAssertEqual(snapshot.days(in: range).map(\.dayStart), expected.map(\.dayStart))
        XCTAssertEqual(snapshot.days(in: range).count, 7)
    }
}
