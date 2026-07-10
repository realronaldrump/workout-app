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

    func testRepRangeDistributionIncludesUnboundedHighRepsAndExcludesInvalidReps() {
        let workout = Workout(
            date: Date(),
            name: "High Rep Day",
            duration: "45m",
            exercises: [
                Exercise(
                    name: "Bench Press",
                    sets: [0, 1, 4, 7, 11, 16, 21, 101].map { reps in
                        makeSet(weight: 100, reps: reps, exerciseName: "Bench Press")
                    }
                )
            ]
        )

        let buckets = WorkoutAnalytics.repRangeDistribution(for: [workout])

        XCTAssertEqual(buckets.map(\.count), [1, 1, 1, 1, 1, 2])
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.percent }, 1, accuracy: 0.001)
    }

    func testIntensityZoneClassifierHasNoBoundaryGaps() {
        let valuesAndExpectedBuckets: [(Double, Int)] = [
            (0.495, 0),
            (0.5, 1),
            (0.655, 2),
            (0.755, 3),
            (0.855, 4),
            (2.0, 4)
        ]

        for (value, expectedBucket) in valuesAndExpectedBuckets {
            XCTAssertEqual(
                WorkoutAnalytics.intensityZoneBucketIndex(for: value),
                expectedBucket,
                "Unexpected bucket for \(value)"
            )
        }
    }

    func testExplicitProgressWindowDoesNotReanchorToStaleLatestWorkout() {
        let calendar = makeCalendar()
        let oldWorkout = makeWorkout(
            on: date(2026, 5, 1, hour: 8, calendar: calendar),
            exercises: [
                Exercise(
                    name: "Bench Press",
                    sets: [makeSet(weight: 200, reps: 5, exerciseName: "Bench Press")]
                )
            ]
        )
        let window = ChangeMetricWindow(
            label: "Recent",
            current: DateInterval(
                start: date(2026, 7, 1, hour: 0, calendar: calendar),
                end: date(2026, 7, 14, hour: 23, calendar: calendar)
            ),
            previous: DateInterval(
                start: date(2026, 6, 17, hour: 0, calendar: calendar),
                end: date(2026, 6, 30, hour: 23, calendar: calendar)
            )
        )

        let contributions = WorkoutAnalytics.progressContributions(
            workouts: [oldWorkout],
            window: window,
            mappings: [:]
        )

        XCTAssertTrue(contributions.isEmpty)
    }

    func testSinglePassProgressAggregationMatchesNormalAndAssistedLoadSemantics() {
        let calendar = makeCalendar()
        let previous = makeWorkout(
            on: date(2026, 6, 20, hour: 8, calendar: calendar),
            exercises: [
                Exercise(
                    name: "Bench Press",
                    sets: [makeSet(weight: 180, reps: 5, exerciseName: "Bench Press")]
                ),
                Exercise(
                    name: "Assisted Pull Up",
                    sets: [makeSet(weight: 40, reps: 8, exerciseName: "Assisted Pull Up")]
                )
            ]
        )
        let current = makeWorkout(
            on: date(2026, 7, 5, hour: 8, calendar: calendar),
            exercises: [
                Exercise(
                    name: "Bench Press",
                    sets: [makeSet(weight: 200, reps: 5, exerciseName: "Bench Press")]
                ),
                Exercise(
                    name: "Assisted Pull Up",
                    sets: [makeSet(weight: 30, reps: 8, exerciseName: "Assisted Pull Up")]
                )
            ]
        )

        let contributions = WorkoutAnalytics.progressContributions(
            current: [current],
            previous: [previous],
            mappings: [:]
        )
        let exerciseContributions = Dictionary(
            uniqueKeysWithValues: contributions
                .filter { $0.category == .exercise }
                .map { ($0.name, $0) }
        )

        XCTAssertEqual(exerciseContributions["Bench Press"]?.delta, 20)
        XCTAssertEqual(exerciseContributions["Assisted Pull Up"]?.delta, 10)
        XCTAssertEqual(
            exerciseContributions["Bench Press"]?.id,
            "exercise:Bench Press"
        )
    }

    func testStrengthContributionsRequireExerciseInBothPeriods() {
        let current = makeWorkout(
            on: Date(),
            exercises: [
                Exercise(
                    name: "New Bench Press",
                    sets: [makeSet(weight: 200, reps: 5, exerciseName: "New Bench Press")]
                )
            ]
        )
        let previous = makeWorkout(
            on: Date().addingTimeInterval(-86_400),
            exercises: [
                Exercise(
                    name: "Old Assisted Pull Up",
                    sets: [makeSet(weight: 40, reps: 8, exerciseName: "Old Assisted Pull Up")]
                )
            ]
        )

        let contributions = WorkoutAnalytics.progressContributions(
            current: [current],
            previous: [previous],
            mappings: [:]
        )

        XCTAssertTrue(contributions.filter { $0.category == .exercise }.isEmpty)
    }

    func testCurrentDayStreakExpiresAfterAllowedRestGap() {
        let calendar = makeCalendar()
        let workout = makeWorkout(on: date(2026, 1, 5, hour: 8, calendar: calendar))

        let streak = WorkoutAnalytics.currentDayStreak(
            for: [workout],
            intentionalRestDays: 1,
            intentionalBreakRanges: [],
            referenceDate: date(2026, 1, 8, hour: 12, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(streak, 0)
    }

    func testWorkoutsPerWeekUsesFullSelectedRange() {
        let calendar = makeCalendar()
        let range = DateInterval(
            start: date(2026, 1, 1, hour: 0, calendar: calendar),
            end: date(2026, 3, 25, hour: 23, calendar: calendar)
        )
        let workouts = [
            makeWorkout(on: date(2026, 3, 20, hour: 8, calendar: calendar)),
            makeWorkout(on: date(2026, 3, 20, hour: 17, calendar: calendar))
        ]
        let effectiveWeeks = max(
            IntentionalBreaksAnalytics.effectiveWeekUnits(in: range, breakDays: [], calendar: calendar),
            1
        )

        let result = WorkoutAnalytics.workoutsPerWeek(
            for: workouts,
            in: range,
            intentionalBreakRanges: [],
            calendar: calendar
        )

        XCTAssertEqual(result, Double(workouts.count) / effectiveWeeks, accuracy: 0.001)
    }

    private func makeWorkout(on date: Date) -> Workout {
        makeWorkout(on: date, exercises: [])
    }

    private func makeWorkout(on date: Date, exercises: [Exercise]) -> Workout {
        Workout(
            date: date,
            name: "Workout",
            duration: "45m",
            exercises: exercises
        )
    }

    private func makeSet(
        weight: Double,
        reps: Int,
        exerciseName: String = "Exercise"
    ) -> WorkoutSet {
        WorkoutSet(
            date: Date(timeIntervalSince1970: 0),
            workoutName: "Workout",
            duration: "45m",
            exerciseName: exerciseName,
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
