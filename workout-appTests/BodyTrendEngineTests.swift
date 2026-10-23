import Foundation
import XCTest
@testable import workout_app

final class BodyTrendEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    private var start: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
    }

    private func date(_ offset: Int, hour: Int = 7) -> Date {
        let day = calendar.date(byAdding: .day, value: offset, to: start)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private func series(_ readings: [(Int, Double)], kind: BodyCompositionMetricKind = .weight) -> BodySeries {
        BodyTrendEngine.build(
            samples: readings.map { BodyRawSample(timestamp: date($0.0), value: $0.1) },
            kind: kind,
            calendar: calendar
        )
    }

    // MARK: Trend

    func testTrendMovesATenthOfTheWayTowardEachReading() {
        let built = series([(0, 200), (1, 210), (2, 210)])

        XCTAssertEqual(built.grid.map(\.trend)[0], 200, accuracy: 1e-9)
        XCTAssertEqual(built.grid.map(\.trend)[1], 201, accuracy: 1e-9)
        XCTAssertEqual(built.grid.map(\.trend)[2], 201.9, accuracy: 1e-9)
    }

    func testMissedDaysAreFilledOnAStraightLine() throws {
        let built = series([(0, 100), (4, 104)])

        XCTAssertEqual(built.grid.map(\.dayIndex).count, 5)
        XCTAssertEqual(built.grid.filter(\.hasReading).count, 2)
        var expected = 100.0
        for filled in [101.0, 102, 103, 104] {
            expected += 0.1 * (filled - expected)
        }
        XCTAssertEqual(try XCTUnwrap(built.latest).trend, expected, accuracy: 1e-9)
    }

    func testGapLongerThanTwoWeeksRestartsTheTrend() throws {
        let built = series([(0, 200), (1, 200), (20, 180)])
        let latest = try XCTUnwrap(built.latest)

        XCTAssertEqual(latest.trend, 180, accuracy: 1e-9)
        XCTAssertEqual(latest.segment, 1)
        XCTAssertTrue(latest.isSettling)
        XCTAssertEqual(built.grid.count, 3, "No days are drawn across the gap")
        XCTAssertEqual(built.currentSegmentStart?.dayIndex, latest.dayIndex)
    }

    func testFirstReadingOfEachDayIsUsedAndRepeatsAreKept() throws {
        let samples = [
            BodyRawSample(timestamp: date(0, hour: 19), value: 182),
            BodyRawSample(timestamp: date(0, hour: 6), value: 180),
            BodyRawSample(timestamp: date(1, hour: 6), value: 180)
        ]
        let built = BodyTrendEngine.build(samples: samples, kind: .weight, calendar: calendar)

        XCTAssertEqual(built.grid.first?.reading, 180)
        XCTAssertEqual(built.readings.count, 3)
        XCTAssertEqual(built.readings(on: try XCTUnwrap(built.grid.first)).count, 2)
    }

    func testImplausibleReadingsAreCountedAndIgnored() {
        let built = series([(0, 180), (1, 9_999), (2, .nan), (3, 181)])

        XCTAssertEqual(built.ignoredReadingCount, 2)
        XCTAssertEqual(built.readingDayCount, 2)
    }

    func testDaylightSavingDoesNotSkipOrRepeatADay() {
        // Clocks spring forward in Denver on March 8, 2026.
        let springStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 7))!
        let samples = (0..<5).map { offset in
            BodyRawSample(
                timestamp: calendar.date(byAdding: .day, value: offset, to: springStart)!,
                value: 180
            )
        }
        let built = BodyTrendEngine.build(samples: samples, kind: .weight, calendar: calendar)
        let indices = built.grid.map(\.dayIndex)

        XCTAssertEqual(indices, Array(indices[0]...(indices[0] + 4)))
    }

    // MARK: Rate

    func testRateOnASteadyLossMatchesTheTrueSlope() throws {
        let readings = (0..<60).map { ($0, 200 - Double($0) * 0.1) }
        let built = series(readings)
        let rate = try XCTUnwrap(built.rate(asOf: date(59)))

        XCTAssertEqual(rate.perWeek, -0.7, accuracy: 0.03)
        XCTAssertEqual(rate.halfWidth, 0, accuracy: 1e-6)
        XCTAssertFalse(rate.isSteady)
        XCTAssertEqual(rate.windowDays, 28)
        XCTAssertEqual(rate.readingCount, 28)
    }

    func testRateNeedsEightWeighInsOverTwoWeeks() {
        let sparse = series([(0, 200), (4, 199), (8, 199), (12, 198), (16, 198)])
        XCTAssertNil(sparse.rate(asOf: date(16)))

        let tooShort = series((0..<10).map { ($0, 200 - Double($0) * 0.1) })
        XCTAssertNil(tooShort.rate(asOf: date(9)), "Ten days is less than the two-week minimum span")
    }

    func testRateIsHiddenWhenTheLastWeighInIsOverAWeekOld() {
        let built = series((0..<40).map { ($0, 200 - Double($0) * 0.1) })

        XCTAssertNotNil(built.rate(asOf: date(46)))
        XCTAssertNil(built.rate(asOf: date(47)))
    }

    func testNoisyFlatWeightReadsAsSteady() throws {
        let noise: [Double] = [0.8, -0.6, 0.3, -0.9, 0.5, -0.2, 0.7, -0.4, 0.1, -0.7]
        let readings = (0..<42).map { ($0, 180 + noise[$0 % noise.count]) }
        let rate = try XCTUnwrap(series(readings).rate(asOf: date(41)))

        XCTAssertTrue(rate.isSteady, "Rate \(rate.perWeek) ± \(rate.halfWidth) should include zero")
    }

    // MARK: Change

    func testChangeComparesTrendValuesAndNeedsEnoughReadings() throws {
        let readings = (0..<40).map { ($0, 200 - Double($0) * 0.1) }
        let built = series(readings)
        let week = try XCTUnwrap(built.change(days: 7))
        let latest = try XCTUnwrap(built.latest)
        let baseline = try XCTUnwrap(built.gridDay(at: latest.dayIndex - 7))

        XCTAssertEqual(week.delta, latest.trend - baseline.trend, accuracy: 1e-9)
        XCTAssertEqual(week.label, "7 days")
        XCTAssertNil(built.change(days: 90), "Ninety days needs readings across that span")

        let sparse = series([(0, 200), (10, 199), (12, 199), (13, 198)])
        XCTAssertNil(sparse.change(days: 7), "Three readings in the last week is not enough")
    }

    func testRangeStatsUseOneReadingPerDay() throws {
        let built = series([(0, 182), (1, 180), (2, 185), (3, 181)])
        let interval = DateInterval(start: date(0, hour: 0), end: date(4, hour: 0))
        let stats = try XCTUnwrap(built.stats(in: interval))

        XCTAssertEqual(stats.heaviest.reading, 185)
        XCTAssertEqual(stats.lightest.reading, 180)
        XCTAssertEqual(stats.average, 182, accuracy: 1e-9)
        XCTAssertEqual(stats.readingDayCount, 4)
    }

    func testWeighInsPerWeekCountsDaysNotReadings() {
        var samples = (0..<28).filter { $0.isMultiple(of: 2) }.map { BodyRawSample(timestamp: date($0), value: 180) }
        samples.append(BodyRawSample(timestamp: date(26, hour: 20), value: 181))
        let built = BodyTrendEngine.build(samples: samples, kind: .weight, calendar: calendar)

        XCTAssertEqual(built.weighInsPerWeek(asOf: date(27)), 3.5, accuracy: 1e-9)
    }

    // MARK: Noise

    func testOneWildReadingIsFlaggedAgainstTheUsualRange() throws {
        var readings = (0..<30).map { ($0, 180 + ($0.isMultiple(of: 2) ? 0.4 : -0.4)) }
        readings.append((30, 186))
        let built = series(readings)
        let latest = try XCTUnwrap(built.latest)

        XCTAssertNotNil(built.residualSigma)
        XCTAssertEqual(built.flags[latest.dayIndex], .high)
        XCTAssertNotNil(built.band(for: latest))
        XCTAssertNil(built.flags[latest.dayIndex - 1])
    }

    // MARK: Goal

    func testGoalProgressAndArrivalRange() {
        let now = date(0)
        let rate = BodyRate(perWeek: -1, halfWidth: 0.25, readingCount: 20, windowDays: 28)
        let status = BodyGoalStatus.make(goal: 180, start: 200, current: 190, rate: rate, now: now, calendar: calendar)

        XCTAssertEqual(status.progress, 0.5, accuracy: 1e-9)
        XCTAssertEqual(status.platesLoaded, 5)
        XCTAssertFalse(status.isReached)
        let startOfToday = calendar.startOfDay(for: now)
        XCTAssertEqual(
            status.arrival,
            .between(
                calendar.date(byAdding: .day, value: 8 * 7, to: startOfToday)!,
                calendar.date(byAdding: .day, value: 13 * 7, to: startOfToday)!
            )
        )
    }

    func testGoalHasNoDateWhenTheTrendIsFlatOrMovingAway() {
        let now = date(0)
        let away = BodyRate(perWeek: 0.5, halfWidth: 0.2, readingCount: 20, windowDays: 28)
        let flat = BodyRate(perWeek: -0.1, halfWidth: 0.3, readingCount: 20, windowDays: 28)

        XCTAssertEqual(BodyGoalStatus.make(goal: 180, start: 200, current: 190, rate: away, now: now).arrival, .noEstimate)
        XCTAssertEqual(BodyGoalStatus.make(goal: 180, start: 200, current: 190, rate: flat, now: now).arrival, .noEstimate)
        XCTAssertEqual(BodyGoalStatus.make(goal: 180, start: 200, current: 190, rate: nil, now: now).arrival, .noEstimate)
    }

    func testGainGoalCountsProgressUpward() {
        let rate = BodyRate(perWeek: 0.5, halfWidth: 0.1, readingCount: 20, windowDays: 28)
        let status = BodyGoalStatus.make(goal: 170, start: 160, current: 172, rate: rate, now: date(0))

        XCTAssertEqual(status.progress, 1)
        XCTAssertTrue(status.isReached)
        XCTAssertEqual(status.platesLoaded, 10)
    }

    // MARK: Composition

    func testLeanAndFatMassSplitTrendWeightByTrendBodyFat() throws {
        let weight = series((0..<10).map { ($0, 200) })
        let bodyFat = series((0..<10).map { ($0, 20) }, kind: .bodyFat)
        let composition = try XCTUnwrap(BodyComposition.latest(weight: weight, bodyFat: bodyFat))

        XCTAssertEqual(composition.fatMass, 40, accuracy: 1e-9)
        XCTAssertEqual(composition.leanMass, 160, accuracy: 1e-9)
    }

    // MARK: Drawing

    func testThinningKeepsSegmentEndsAndCapsTheCount() {
        var readings = (0..<300).map { ($0, 200 - Double($0) * 0.02) }
        readings.append(contentsOf: (330..<600).map { ($0, 194 - Double($0 - 330) * 0.02) })
        let built = series(readings)
        let thinned = BodyTrendEngine.thinned(built.grid[...], limit: 100)

        XCTAssertLessThanOrEqual(thinned.count, 110)
        XCTAssertEqual(thinned.first?.dayIndex, built.grid.first?.dayIndex)
        XCTAssertEqual(thinned.last?.dayIndex, built.grid.last?.dayIndex)
        let boundary = built.grid.first { $0.segment == 1 }
        XCTAssertTrue(thinned.contains { $0.dayIndex == boundary?.dayIndex })
    }
}

final class BodyLiftAnalyzerTests: XCTestCase {
    private let calendar = Calendar.current

    private func workout(daysAgo: Int, _ exercises: [(String, Double, Int)]) -> Workout {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
            .addingTimeInterval(18 * 3_600)
        return Workout(
            date: date,
            name: "Workout",
            duration: "1h",
            exercises: exercises.map { name, weight, reps in
                Exercise(name: name, sets: [
                    WorkoutSet(
                        date: date, workoutName: "Workout", duration: "1h", exerciseName: name,
                        setOrder: 1, weight: weight, reps: reps, distance: 0, seconds: 0
                    )
                ])
            }
        )
    }

    func testRowsCompareTheLastFourWeeksWithThreeMonthsAgo() throws {
        let workouts = [
            workout(daysAgo: 3, [("Squat", 300, 5), ("Curl", 50, 20)]),
            workout(daysAgo: 10, [("Squat", 290, 5), ("Curl", 50, 20)]),
            workout(daysAgo: 95, [("Squat", 270, 5)]),
            workout(daysAgo: 100, [("Squat", 260, 5)])
        ]
        let weightSamples = (0..<120).map { offset in
            BodyRawSample(
                timestamp: calendar.date(byAdding: .day, value: -offset, to: Date())!,
                value: 200
            )
        }
        let weight = BodyTrendEngine.build(samples: weightSamples, kind: .weight)

        let rows = BodyLiftAnalyzer.rows(
            workouts: workouts,
            resolver: ExerciseRelationshipManager.shared.resolverSnapshot(),
            excludedNames: [],
            favorites: [],
            weight: weight,
            now: Date()
        )
        let squat = try XCTUnwrap(rows.first)

        XCTAssertEqual(rows.count, 1, "Curl has no sets of 10 reps or fewer, so it doesn't qualify")
        XCTAssertEqual(squat.name, "Squat")
        XCTAssertEqual(squat.estimatedMaxNow, OneRepMax.estimate(weight: 300, reps: 5), accuracy: 1e-9)
        XCTAssertEqual(squat.estimatedMaxThen, OneRepMax.estimate(weight: 270, reps: 5), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(squat.multipleNow), squat.estimatedMaxNow / 200, accuracy: 1e-6)
        XCTAssertEqual(squat.direction, .up)
    }

    func testSummaryOnlyAppearsWhenWeightMovedEnough() {
        let rows = [
            BodyLiftRow(name: "A", estimatedMaxNow: 110, estimatedMaxThen: 100, multipleNow: nil, multipleThen: nil),
            BodyLiftRow(name: "B", estimatedMaxNow: 100, estimatedMaxThen: 100, multipleNow: nil, multipleThen: nil)
        ]
        let small = BodyChange(id: "90", label: "90 days", baselineDate: Date(), baseline: 200, current: 199)
        let large = BodyChange(id: "90", label: "90 days", baselineDate: Date(), baseline: 200, current: 190)

        XCTAssertNil(BodyLiftAnalyzer.summary(rows: rows, weightChange: small))
        XCTAssertEqual(
            BodyLiftAnalyzer.summary(rows: rows, weightChange: large),
            "Weight is down 5.0% in 90 days. Of these 2 lifts: 1 up, 1 flat."
        )
    }
}
