import Foundation
import XCTest
@testable import workout_app

final class BodyCompositionAnalyticsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        calendar.firstWeekday = 2
        return calendar
    }

    private var start: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
    }

    private func date(_ offset: Int, hour: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: offset, to: start)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private func representatives(_ readings: [(Int, Double)]) -> [BodyCompositionAnalytics.DailyRepresentative] {
        BodyCompositionAnalytics.dailyRepresentatives(
            from: readings.map { BodyRawSample(timestamp: date($0.0, hour: 8), value: $0.1) },
            calendar: calendar
        )
    }

    private func points(_ readings: [(Int, Double)]) -> [TimeSeriesPoint] {
        readings.map { TimeSeriesPoint(date: date($0.0), value: $0.1) }
    }

    func testDailyRepresentativeUsesEarliestValidReadingAndRetainsDistinctReadings() {
        let first = BodyRawSample(timestamp: date(0, hour: 8), value: 180)
        let later = BodyRawSample(timestamp: date(0, hour: 18), value: 183)
        let invalid = BodyRawSample(timestamp: date(0, hour: 7), value: .nan)
        let result = BodyCompositionAnalytics.dailyRepresentatives(
            from: [later, first, invalid, first], calendar: calendar
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.value, 180)
        XCTAssertEqual(result.first?.timestamp, first.timestamp)
        XCTAssertEqual(result.first?.samples, [first, later])
    }

    func testEqualTimestampReadingsHaveDeterministicRepresentative() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = BodyRawSample(id: firstID, timestamp: date(0), value: 180)
        let second = BodyRawSample(id: secondID, timestamp: date(0), value: 182)

        let ascending = BodyCompositionAnalytics.dailyRepresentatives(from: [first, second], calendar: calendar)
        let descending = BodyCompositionAnalytics.dailyRepresentatives(from: [second, first], calendar: calendar)

        XCTAssertEqual(ascending, descending)
        XCTAssertEqual(ascending.first?.value, 180)
    }

    func testMetricValidationRejectsNonfiniteAndImpossiblePercentages() {
        for value in [Double.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertFalse(BodyCompositionAnalytics.isValidSampleValue(value, metricKind: .weight))
        }
        XCTAssertFalse(BodyCompositionAnalytics.isValidSampleValue(101, metricKind: .bodyFat))
        XCTAssertTrue(BodyCompositionAnalytics.isValidSampleValue(100, metricKind: .bodyFat))
        XCTAssertTrue(BodyCompositionAnalytics.isValidSampleValue(180, metricKind: .weight))

        let reps = BodyCompositionAnalytics.dailyRepresentatives(
            from: [BodyRawSample(timestamp: date(0), value: 110)], metricKind: .bodyFat, calendar: calendar
        )
        XCTAssertTrue(reps.isEmpty)
    }

    func testSevenDayAverageUsesCalendarBoundaryAndOnlyMeasuredDays() throws {
        let reps = representatives([(0, 180), (6, 186), (7, 184)])
        let stats = BodyCompositionAnalytics.trailingWindowStatistics(
            representatives: reps, windowDays: 7, calendar: calendar
        )
        let beforeBoundary = try XCTUnwrap(stats[date(6)])
        XCTAssertEqual(beforeBoundary.average, 183, accuracy: 0.00001)
        XCTAssertEqual(beforeBoundary.measuredDayCount, 2)
        XCTAssertEqual(beforeBoundary.observedSpanDays, 6)
        let afterBoundary = try XCTUnwrap(stats[date(7)])
        XCTAssertEqual(afterBoundary.average, 185, accuracy: 0.00001)
        XCTAssertEqual(afterBoundary.measuredDayCount, 2)
    }

    func testRepeatedSameDayWeighInsDoNotOverweightAverage() throws {
        let samples = [
            BodyRawSample(timestamp: date(0, hour: 8), value: 180),
            BodyRawSample(timestamp: date(0, hour: 12), value: 190),
            BodyRawSample(timestamp: date(0, hour: 18), value: 200),
            BodyRawSample(timestamp: date(1, hour: 8), value: 182)
        ]
        let reps = BodyCompositionAnalytics.dailyRepresentatives(from: samples, calendar: calendar)
        let average = try XCTUnwrap(BodyCompositionAnalytics.trailingAverages(
            representatives: reps, windowDays: 7, calendar: calendar
        )[date(1)])
        XCTAssertEqual(average, 181, accuracy: 0.00001)
    }

    func testTrailingAveragesSortInputAndDoNotFillMissingDays() throws {
        let reps = representatives([(0, 180), (1, 182), (20, 190)])
        let stats = BodyCompositionAnalytics.trailingWindowStatistics(
            representatives: Array(reps.reversed()), windowDays: 7, calendar: calendar
        )
        XCTAssertEqual(stats.count, 3)
        XCTAssertEqual(stats[date(1)]?.average, 181)
        let isolated = try XCTUnwrap(stats[date(20)])
        XCTAssertEqual(isolated.average, 190)
        XCTAssertEqual(isolated.measuredDayCount, 1)
        XCTAssertEqual(isolated.observedSpanDays, 0)
    }

    func testSevenDayWindowAndRegressionAreUnaffectedByDaylightSaving() throws {
        // Denver changes to daylight time on March 8: March 7 to March 9 is 47 hours, but two days.
        let reps = representatives([(6, 180), (7, 181), (8, 182), (9, 183), (10, 184), (13, 187)])
        let trend = try XCTUnwrap(BodyCompositionAnalytics.trendSummaryForLatest(
            representatives: reps, windowDays: 30, calendar: calendar
        ))
        XCTAssertEqual(trend.pacePerWeek, 7, accuracy: 0.00001)
        XCTAssertEqual(trend.observedSpanDays, 7)
        let stats = BodyCompositionAnalytics.trailingWindowStatistics(
            representatives: reps, windowDays: 7, calendar: calendar
        )
        XCTAssertEqual(stats[date(13)]?.measuredDayCount, 5)
    }

    func testTrendRequiresSixDaysAndAtLeastSevenElapsedDays() {
        let tooFew = representatives([(0, 180), (7, 179)])
        let tooShort = representatives((0..<6).map { ($0, 180 + Double($0)) })
        for reps in [tooFew, tooShort] {
            XCTAssertNil(BodyCompositionAnalytics.trendSummaryForLatest(
                representatives: reps, windowDays: 30, calendar: calendar
            ))
            XCTAssertTrue(BodyCompositionAnalytics.trailingRegression(
                representatives: reps, windowDays: 30, calendar: calendar
            ).isEmpty)
        }
    }

    func testIrregularMeasurementDaysUseElapsedTimeForPace() throws {
        let offsets = [0, 1, 2, 4, 6, 9]
        let reps = representatives(offsets.map { ($0, 180 - Double($0) * 0.2) })
        let trend = try XCTUnwrap(BodyCompositionAnalytics.trendSummaryForLatest(
            representatives: Array(reps.reversed()), windowDays: 30, calendar: calendar
        ))

        XCTAssertEqual(trend.pacePerWeek, -1.4, accuracy: 0.00001)
        XCTAssertEqual(trend.pointCount, 6)
        XCTAssertEqual(trend.observedSpanDays, 9)
        XCTAssertEqual(trend.fittedValueAtEnd, 178.2, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(trend.rSquared), 1, accuracy: 0.00001)
    }

    func testTrendWindowExcludesOldReadingsAndDoesNotInventRecentHistory() {
        let reps = representatives([(0, 180), (1, 181), (2, 182), (3, 183), (4, 184), (60, 185)])
        XCTAssertNil(BodyCompositionAnalytics.trendSummaryForLatest(
            representatives: reps, windowDays: 30, calendar: calendar
        ))
    }

    func testSparseComparisonsDoNotReuseStaleBaselines() {
        let deltas = BodyCompositionAnalytics.intervalDeltas(
            points: points([(0, 180), (39, 170)]), displayRangeStart: date(0), calendar: calendar
        )

        XCTAssertEqual(deltas.map(\.id), ["sinceStart"])
        XCTAssertEqual(deltas.first?.delta, -10)
    }

    func testNearTargetComparisonLabelsActualElapsedDays() throws {
        let deltas = BodyCompositionAnalytics.intervalDeltas(
            points: points([(0, 180), (6, 178), (14, 176)]), displayRangeStart: date(0), calendar: calendar
        )
        let weekly = try XCTUnwrap(deltas.first { $0.id == "7d" })

        XCTAssertEqual(weekly.label, "8d")
        XCTAssertEqual(weekly.baselineDate, date(6))
        XCTAssertEqual(weekly.delta, -2)
        XCTAssertFalse(deltas.contains { $0.id == "30d" })
    }

    func testSingleMeasurementHasNoChangeComparison() {
        XCTAssertTrue(BodyCompositionAnalytics.intervalDeltas(
            points: points([(0, 180)]), displayRangeStart: date(0), calendar: calendar
        ).isEmpty)
    }

    func testProjectionStartsFromFittedEndpointAndUncertaintyWidens() throws {
        let reps = representatives((0..<30).map { ($0, 180 - Double($0) * 0.1 + ($0 == 29 ? 4 : 0)) })
        let regression = try XCTUnwrap(BodyCompositionAnalytics.trailingRegression(
            representatives: reps, windowDays: 30, calendar: calendar
        )[date(29)])
        let forecasts = BodyCompositionAnalytics.forecast(
            latestDay: date(29), currentValue: reps.last!.value, regression: regression,
            horizons: [30, 14, 7, 7, 90, 0, -1], calendar: calendar
        )

        XCTAssertEqual(forecasts.map(\.horizonDays), [7, 14])
        let week = try XCTUnwrap(forecasts.first)
        let fortnight = try XCTUnwrap(forecasts.last)
        let expected = regression.intercept + regression.slopePerDay * (regression.latestDayOffset + 7)
        XCTAssertEqual(week.predicted, expected, accuracy: 0.00001)
        XCTAssertNotEqual(week.predicted, reps.last!.value + regression.slopePerDay * 7)
        XCTAssertGreaterThan(try XCTUnwrap(fortnight.sigma), try XCTUnwrap(week.sigma))
        XCTAssertLessThan(try XCTUnwrap(week.lowerBound), week.predicted)
        XCTAssertGreaterThan(try XCTUnwrap(week.upperBound), week.predicted)
    }

    func testProjectionUsesStudentTAndIndividualPredictionVariance() throws {
        let offsets = [0, 1, 2, 4, 6, 7]
        let reps = representatives(offsets.enumerated().map { index, offset in
            (offset, 180 + Double(offset) * 0.2 + (index.isMultiple(of: 2) ? 0.5 : -0.5))
        })
        let regression = try XCTUnwrap(BodyCompositionAnalytics.trailingRegression(
            representatives: reps, windowDays: 30, calendar: calendar
        )[date(7)])
        let forecast = try XCTUnwrap(BodyCompositionAnalytics.forecast(
            latestDay: date(7), currentValue: reps.last!.value, regression: regression, calendar: calendar
        ).first)
        let offset = regression.latestDayOffset + 7 - regression.meanDay
        let expectedSigma = try XCTUnwrap(regression.residualStdDev)
            * sqrt(1 + 1 / 6.0 + offset * offset / regression.sumSquaredDayOffsets)

        XCTAssertEqual(try XCTUnwrap(forecast.sigma), expectedSigma, accuracy: 0.00001)
        XCTAssertEqual(forecast.predictionIntervalMultiplier, 2.776, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(forecast.upperBound), forecast.predicted + 2.776 * expectedSigma, accuracy: 0.00001)
    }

    func testProjectionNeverExtendsBeyondThirtyDaysOrObservedHistory() throws {
        let reps = representatives((0..<60).map { ($0, 180 - Double($0) * 0.05) })
        let regression = try XCTUnwrap(BodyCompositionAnalytics.trailingRegression(
            representatives: reps, windowDays: 60, calendar: calendar
        )[date(59)])
        let forecasts = BodyCompositionAnalytics.forecast(
            latestDay: date(59), currentValue: reps.last!.value, regression: regression,
            horizons: [7, 30, 60, 90], calendar: calendar
        )
        XCTAssertEqual(forecasts.map(\.horizonDays), [7, 30])
    }

    func testProjectionRejectsImpossibleBodyFatAndUnqualifiedRegression() throws {
        let reps = representatives((0..<15).map { ($0, 70 + Double($0) * 2) })
        let regression = try XCTUnwrap(BodyCompositionAnalytics.trailingRegression(
            representatives: reps, windowDays: 30, calendar: calendar
        )[date(14)])
        XCTAssertTrue(BodyCompositionAnalytics.forecast(
            latestDay: date(14), currentValue: 98, regression: regression, metricKind: .bodyFat, calendar: calendar
        ).isEmpty)

        let unqualified = LinearRegressionResult(
            slopePerDay: 1, intercept: 180, rSquared: 1, residualStdDev: 1, pointCount: 2
        )
        XCTAssertTrue(BodyCompositionAnalytics.forecast(
            latestDay: date(0), currentValue: 180, regression: unqualified, calendar: calendar
        ).isEmpty)
    }

    func testFlatSeriesHasZeroPaceWithoutNonfiniteFitMetrics() throws {
        let reps = representatives((0..<15).map { ($0, 180.0) })
        let trend = try XCTUnwrap(BodyCompositionAnalytics.trendSummaryForLatest(
            representatives: reps, windowDays: 30, calendar: calendar
        ))
        XCTAssertEqual(trend.pacePerWeek, 0, accuracy: 0.00001)
        XCTAssertEqual(trend.fittedValueAtEnd, 180, accuracy: 0.00001)
        XCTAssertNil(trend.rSquared)
        XCTAssertEqual(try XCTUnwrap(trend.residualStdDev), 0, accuracy: 0.00001)
    }

    func testReportsUseChronologicalMeasuredDaysAndIgnoreInvalidPoints() throws {
        let readings = points([(5, 178), (0, 180), (2, 182), (3, .nan)])
        let report = try XCTUnwrap(BodyCompositionAnalytics.reportBuckets(
            points: readings, granularity: .monthly, calendar: calendar
        ).first)
        XCTAssertEqual(report.average, 180, accuracy: 0.00001)
        XCTAssertEqual(report.start, 180)
        XCTAssertEqual(report.end, 178)
        XCTAssertEqual(report.change, -2)
        XCTAssertEqual(report.count, 3)
        XCTAssertEqual(report.min, 178)
        XCTAssertEqual(report.max, 182)
    }

    func testInvalidWindowSizesReturnEmptyResults() {
        let reps = representatives((0..<10).map { ($0, 180.0) })
        XCTAssertTrue(BodyCompositionAnalytics.trailingAverages(
            representatives: reps, windowDays: 0, calendar: calendar
        ).isEmpty)
        XCTAssertTrue(BodyCompositionAnalytics.trailingRegression(
            representatives: reps, windowDays: -1, calendar: calendar
        ).isEmpty)
        XCTAssertNil(BodyCompositionAnalytics.trendSummaryForLatest(
            representatives: reps, windowDays: 0, calendar: calendar
        ))
    }
}
