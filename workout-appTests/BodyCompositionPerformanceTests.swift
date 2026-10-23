import XCTest
@testable import workout_app

final class BodyCompositionPerformanceTests: XCTestCase {
    func testTrailingRegressionMatchesCalendarReferenceAcrossSparseHistoryAndDST() throws {
        let calendar = denverCalendar
        let start = calendar.date(from: DateComponents(year: 2023, month: 1, day: 1))!
        let samples = (0..<420).filter { $0 % 7 != 0 && !(180..<215).contains($0) }.map { index in
            BodyRawSample(
                timestamp: calendar.date(byAdding: .day, value: index, to: start)!,
                value: 180 + sin(Double(index) / 11) * 4
            )
        }
        let daily = BodyCompositionAnalytics.dailyRepresentatives(from: samples, calendar: calendar)
        for windowDays in [7, 30, 90] {
            let actual = BodyCompositionAnalytics.trailingRegression(
                representatives: Array(daily.reversed()), windowDays: windowDays, calendar: calendar
            )
            for index in daily.indices {
                let reference = BodyCompositionAnalytics.trendSummaryForLatest(
                    representatives: Array(daily[...index]), windowDays: windowDays, calendar: calendar
                )
                let result = actual[daily[index].dayStart]
                XCTAssertEqual(result == nil, reference == nil)
                if let reference, let result {
                    XCTAssertEqual(result.slopePerDay, reference.slopePerDay, accuracy: 1e-10)
                    XCTAssertEqual(result.intercept, reference.intercept, accuracy: 1e-10)
                    XCTAssertEqual(result.residualStdDev ?? 0, reference.residualStdDev ?? 0, accuracy: 1e-10)
                    XCTAssertEqual(result.observedSpanDays, reference.observedSpanDays)
                    XCTAssertEqual(result.pointCount, reference.pointCount)
                }
            }
        }
    }

    private var denverCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }
}
