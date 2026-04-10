import XCTest
@testable import workout_app

final class WorkoutAnalyticsTests: XCTestCase {
    func testAssistedExerciseUsesLowestLoggedWeightAsBestWeight() {
        let exercise = Exercise(
            name: "Assisted Pull Up",
            sets: [
                makeSet(weight: 80, reps: 5),
                makeSet(weight: 40, reps: 5),
                makeSet(weight: 60, reps: 5)
            ]
        )

        XCTAssertEqual(exercise.maxWeight, 40)
    }

    func testAssistedExerciseUsesLowestEstimatedAssistanceAsBestScore() {
        let exercise = Exercise(
            name: "Assisted Dip",
            sets: [
                makeSet(weight: 70, reps: 6),
                makeSet(weight: 35, reps: 6)
            ]
        )

        XCTAssertEqual(
            exercise.oneRepMax,
            OneRepMax.estimate(weight: 35, reps: 6, exerciseName: "Assisted Dip"),
            accuracy: 0.001
        )
    }

    func testAssistedExerciseRewardsHigherRepsAtSameAssistance() {
        let exercise = Exercise(
            name: "Assisted Pull Up",
            sets: [
                makeSet(weight: 35, reps: 5),
                makeSet(weight: 35, reps: 10)
            ]
        )

        XCTAssertEqual(
            exercise.oneRepMax,
            OneRepMax.estimate(weight: 35, reps: 10, exerciseName: "Assisted Pull Up"),
            accuracy: 0.001
        )
        XCTAssertLessThan(exercise.oneRepMax, 35)
    }

    func testAssistedProgressDeltaRewardsLessAssistance() {
        let delta = ExerciseLoad.progressDelta(
            current: 35,
            previous: 50,
            exerciseName: "Assisted Chin Up"
        )

        XCTAssertEqual(delta, 15, accuracy: 0.001)
    }

    func testAssistedRelativeIntensityUsesInverseRatio() {
        let intensity = ExerciseLoad.relativeIntensity(
            weight: 60,
            referenceWeight: 40,
            exerciseName: "Assisted Pull Up"
        )

        XCTAssertEqual(intensity, 40.0 / 60.0, accuracy: 0.001)
    }

    func testAssistedRecommendationKeepsZeroAssistanceSessionAsBestHistory() {
        let calendar = makeCalendar()
        let history = [
            (date: date(2026, 1, 1, hour: 8, calendar: calendar), sets: [makeSet(weight: 20, reps: 10)]),
            (date: date(2026, 1, 8, hour: 8, calendar: calendar), sets: [makeSet(weight: 15, reps: 10)]),
            (date: date(2026, 1, 15, hour: 8, calendar: calendar), sets: [makeSet(weight: 0, reps: 5)])
        ]

        let recommendation = ExerciseRecommendationEngine.recommend(
            exerciseName: "Assisted Pull Up",
            history: history,
            weightIncrement: 5
        )

        XCTAssertNotNil(recommendation.suggestedWeight)
        XCTAssertEqual(recommendation.suggestedWeight ?? -1, 0, accuracy: 0.001)
    }

    @MainActor
    func testCalculateStatsKeepsWorkoutsPerWeekScopedToSelectedRange() {
        let calendar = makeCalendar()
        let workouts = [
            makeWorkout(on: date(2026, 1, 5, hour: 8, calendar: calendar)),
            makeWorkout(on: date(2026, 1, 7, hour: 8, calendar: calendar)),
            makeWorkout(on: date(2026, 1, 10, hour: 8, calendar: calendar))
        ]
        let interval = DateInterval(start: workouts[0].date, end: workouts[2].date)
        let expectedWeeks = max(
            IntentionalBreaksAnalytics.effectiveWeekUnits(in: interval, breakDays: [], calendar: calendar),
            1
        )

        let manager = WorkoutDataManager()
        manager.workouts = workouts

        let stats = manager.calculateStats(for: workouts, intentionalBreakRanges: [])

        XCTAssertEqual(stats.workoutsPerWeek, Double(workouts.count) / expectedWeeks, accuracy: 0.001)
    }

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

    private func makeSet(weight: Double, reps: Int) -> WorkoutSet {
        WorkoutSet(
            date: Date(timeIntervalSince1970: 0),
            workoutName: "Workout",
            duration: "45m",
            exerciseName: "Exercise",
            setOrder: 1,
            weight: weight,
            reps: reps,
            distance: 0,
            seconds: 0
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
