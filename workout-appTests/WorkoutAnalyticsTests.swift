import XCTest
@testable import workout_app

final class WorkoutAnalyticsTests: XCTestCase {
    func testCurrentWeeklyStreakCountsConsecutiveWeeks() {
        let calendar = makeCalendar()
        let workouts = [
            makeWorkout(on: date(2026, 1, 5, hour: 8, calendar: calendar)),
            makeWorkout(on: date(2026, 1, 12, hour: 8, calendar: calendar)),
            makeWorkout(on: date(2026, 1, 20, hour: 8, calendar: calendar))
        ]

        let streak = WorkoutAnalytics.currentWeeklyStreak(
            for: workouts,
            intentionalBreakRanges: [],
            referenceDate: date(2026, 1, 21, hour: 12, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(streak, 3)
    }

    func testCurrentWeeklyStreakResetsWhenCurrentWeekHasNoWorkout() {
        let calendar = makeCalendar()
        let workouts = [
            makeWorkout(on: date(2026, 1, 5, hour: 8, calendar: calendar)),
            makeWorkout(on: date(2026, 1, 12, hour: 8, calendar: calendar))
        ]

        let streak = WorkoutAnalytics.currentWeeklyStreak(
            for: workouts,
            intentionalBreakRanges: [],
            referenceDate: date(2026, 1, 21, hour: 12, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(streak, 0)
    }

    func testCurrentWeeklyStreakSkipsFullyExcusedCurrentWeek() {
        let calendar = makeCalendar()
        let workouts = [
            makeWorkout(on: date(2026, 1, 5, hour: 8, calendar: calendar)),
            makeWorkout(on: date(2026, 1, 12, hour: 8, calendar: calendar))
        ]
        let breaks = [
            IntentionalBreakRange(
                startDate: date(2026, 1, 18, hour: 0, calendar: calendar),
                endDate: date(2026, 1, 21, hour: 0, calendar: calendar),
                name: "Travel",
                calendar: calendar
            )
        ]

        let streak = WorkoutAnalytics.currentWeeklyStreak(
            for: workouts,
            intentionalBreakRanges: breaks,
            referenceDate: date(2026, 1, 21, hour: 12, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(streak, 2)
    }

    private func makeWorkout(on date: Date) -> Workout {
        Workout(
            date: date,
            name: "Workout",
            duration: "45m",
            exercises: []
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.timeZone = calendar.timeZone
        return calendar.date(from: components) ?? .distantPast
    }
}
