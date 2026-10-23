import XCTest
@testable import workout_app

final class BodyMeasurementDateRangeTests: XCTestCase {
    func testDayPresetsIncludeTodayWithoutAnExtraCalendarDay() {
        let reference = date(year: 2026, month: 10, day: 21, hour: 12)
        let cases: [(AppTimeRange, Int)] = [(.week, 7), (.fourWeeks, 28), (.sixWeeks, 42)]

        for (selection, dayCount) in cases {
            let range = resolve(selection, reference: reference)
            let elapsedDays = calendar.dateComponents([.day], from: range.start, to: calendar.startOfDay(for: reference)).day
            XCTAssertEqual(elapsedDays, dayCount - 1)
            XCTAssertEqual(range.start, calendar.startOfDay(for: range.start))
            XCTAssertEqual(range.end, reference)
        }
    }

    func testMonthAndYearPresetsUseCalendarComponentsFromMidnight() {
        let reference = date(year: 2026, month: 5, day: 31, hour: 15)

        XCTAssertEqual(resolve(.threeMonths, reference: reference).start, date(year: 2026, month: 2, day: 28))
        XCTAssertEqual(resolve(.sixMonths, reference: reference).start, date(year: 2025, month: 11, day: 30))
        XCTAssertEqual(resolve(.year, reference: reference).start, date(year: 2025, month: 5, day: 31))
        XCTAssertEqual(
            resolve(.year, reference: date(year: 2024, month: 2, day: 29, hour: 12)).start,
            date(year: 2023, month: 2, day: 28)
        )
    }

    func testAllTimeNormalizesEarliestMeasurementToItsCalendarDay() {
        let reference = date(year: 2026, month: 10, day: 21, hour: 12)
        let earliest = date(year: 2023, month: 5, day: 4, hour: 17)
        let range = resolve(.allTime, reference: reference, earliest: earliest)

        XCTAssertEqual(range.start, date(year: 2023, month: 5, day: 4))
        XCTAssertEqual(range.end, reference)
    }

    func testUnknownHistoryAndMissingCustomRangeUseThirtyCalendarDaysIncludingToday() {
        let reference = date(year: 2026, month: 10, day: 21, hour: 12)
        let expectedStart = date(year: 2026, month: 9, day: 22)

        XCTAssertEqual(resolve(.allTime, reference: reference).start, expectedStart)
        XCTAssertEqual(resolve(.custom, reference: reference).start, expectedStart)
    }

    func testPastCustomRangeIncludesEntireEndDayAndItsFinalFractionalSecond() {
        let custom = DateInterval(
            start: date(year: 2026, month: 10, day: 3, hour: 16),
            end: date(year: 2026, month: 10, day: 5, hour: 9)
        )
        let range = resolve(.custom, reference: date(year: 2026, month: 10, day: 21, hour: 12), custom: custom)
        let finalReading = date(year: 2026, month: 10, day: 6).addingTimeInterval(-0.001)

        XCTAssertEqual(range.start, date(year: 2026, month: 10, day: 3))
        XCTAssertEqual(range.end, date(year: 2026, month: 10, day: 6))
        XCTAssertGreaterThanOrEqual(finalReading, range.start)
        XCTAssertLessThan(finalReading, range.end)
    }

    func testSingleCustomCalendarDateIncludesTheWholeDay() {
        let selectedDay = date(year: 2026, month: 10, day: 5)
        let custom = DateInterval(start: selectedDay, end: selectedDay)
        let range = resolve(.custom, reference: date(year: 2026, month: 10, day: 21), custom: custom)

        XCTAssertEqual(range.start, selectedDay)
        XCTAssertEqual(range.end, date(year: 2026, month: 10, day: 6))
    }

    func testCustomRangeEndingTodayStopsAtNow() {
        let reference = date(year: 2026, month: 10, day: 21, hour: 12)
        let custom = DateInterval(
            start: date(year: 2026, month: 10, day: 3),
            end: calendar.startOfDay(for: reference)
        )

        XCTAssertEqual(resolve(.custom, reference: reference, custom: custom).end, reference)
    }

    func testFutureCustomRangeBecomesEmptyWithoutConstructingReversedInterval() {
        let reference = date(year: 2026, month: 10, day: 21, hour: 12)
        let custom = DateInterval(
            start: date(year: 2026, month: 10, day: 25),
            end: date(year: 2026, month: 10, day: 27)
        )
        let range = resolve(.custom, reference: reference, custom: custom)

        XCTAssertEqual(range.start, reference)
        XCTAssertEqual(range.end, reference)
        XCTAssertEqual(range.duration, 0)
    }

    func testPartlyFutureCustomRangeRetainsPastDaysAndClampsItsEnd() {
        let reference = date(year: 2026, month: 10, day: 21, hour: 12)
        let custom = DateInterval(
            start: date(year: 2026, month: 10, day: 19),
            end: date(year: 2026, month: 10, day: 27)
        )
        let range = resolve(.custom, reference: reference, custom: custom)

        XCTAssertEqual(range.start, custom.start)
        XCTAssertEqual(range.end, reference)
    }

    func testFutureEarliestMeasurementDoesNotCreateReversedAllTimeInterval() {
        let reference = date(year: 2026, month: 10, day: 21, hour: 12)
        let range = resolve(.allTime, reference: reference, earliest: date(year: 2026, month: 10, day: 25))

        XCTAssertEqual(range.start, reference)
        XCTAssertEqual(range.end, reference)
    }

    func testWeekRemainsSevenCalendarDaysAcrossDaylightSavingChange() {
        var daylightCalendar = Calendar(identifier: .gregorian)
        daylightCalendar.timeZone = TimeZone(identifier: "America/Denver") ?? .current
        let reference = daylightCalendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)) ?? .distantPast
        let expectedStart = daylightCalendar.date(from: DateComponents(year: 2026, month: 3, day: 4)) ?? .distantPast
        let range = BodyMeasurementDateRange.resolve(selection: .week, reference: reference, calendar: daylightCalendar)

        XCTAssertEqual(range.start, expectedStart)
        XCTAssertEqual(range.end, reference)
        XCTAssertEqual(range.duration, 155 * 3_600)
    }

    func testCustomEndUsesNextLocalMidnightOnShortDay() {
        var daylightCalendar = Calendar(identifier: .gregorian)
        daylightCalendar.timeZone = TimeZone(identifier: "America/Denver") ?? .current
        let selectedDay = daylightCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8)) ?? .distantPast
        let reference = daylightCalendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? .distantPast
        let range = BodyMeasurementDateRange.resolve(
            selection: .custom,
            reference: reference,
            custom: DateInterval(start: selectedDay, end: selectedDay),
            calendar: daylightCalendar
        )

        XCTAssertEqual(range.duration, 23 * 3_600)
        XCTAssertEqual(daylightCalendar.component(.hour, from: range.end), 0)
        XCTAssertEqual(daylightCalendar.component(.day, from: range.end), 9)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func resolve(
        _ selection: AppTimeRange,
        reference: Date,
        earliest: Date? = nil,
        custom: DateInterval? = nil
    ) -> DateInterval {
        BodyMeasurementDateRange.resolve(selection: selection, reference: reference, earliest: earliest, custom: custom, calendar: calendar)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }
}
