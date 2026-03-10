import XCTest
@testable import workout_app

@MainActor
final class WorkoutSimilarityEngineTests: XCTestCase {
    func testExactSameOrderAcrossDifferentWorkoutNamesIsExactOrdered() async throws {
        let prior = makeWorkout(
            name: "Push A",
            date: date(day: 1, hour: 8),
            exercises: ["Bench Press", "Row", "Pulldown"]
        )
        let selected = makeWorkout(
            name: "Upper Mix",
            date: date(day: 2, hour: 8),
            exercises: ["Bench Press", "Row", "Pulldown"]
        )

        let engine = WorkoutSimilarityEngine()
        await engine.analyze(workouts: [selected, prior])

        let review = try XCTUnwrap(engine.review(for: selected.id))
        let bestMatch = try XCTUnwrap(review.bestMatch)

        XCTAssertEqual(bestMatch.kind, .exactOrdered)
        XCTAssertEqual(bestMatch.priorWorkoutId, prior.id)
        XCTAssertEqual(review.exactOrderMatches.map(\.priorWorkoutId), [prior.id])
    }

    func testSameExercisesDifferentOrderIsReorderedExactMatch() async throws {
        let prior = makeWorkout(
            name: "Prior",
            date: date(day: 1, hour: 7),
            exercises: ["Squat", "Bench", "Row"]
        )
        let selected = makeWorkout(
            name: "Selected",
            date: date(day: 2, hour: 7),
            exercises: ["Bench", "Squat", "Row"]
        )

        let engine = WorkoutSimilarityEngine()
        await engine.analyze(workouts: [selected, prior])

        let review = try XCTUnwrap(engine.review(for: selected.id))
        let bestMatch = try XCTUnwrap(review.bestMatch)

        XCTAssertEqual(bestMatch.kind, .exactExercisesReordered)
        XCTAssertTrue(review.exactOrderMatches.isEmpty)
        XCTAssertEqual(review.reorderedExerciseMatches.map(\.priorWorkoutId), [prior.id])
    }

    func testPartialOverlapPicksHighestScoringPriorWorkout() async throws {
        let lowerScore = makeWorkout(
            name: "Lower Score",
            date: date(day: 1, hour: 6),
            exercises: ["Bench", "Dip", "Curl", "Lunge"]
        )
        let higherScore = makeWorkout(
            name: "Higher Score",
            date: date(day: 2, hour: 6),
            exercises: ["Bench", "Row", "Curl", "Fly"]
        )
        let selected = makeWorkout(
            name: "Selected",
            date: date(day: 3, hour: 6),
            exercises: ["Bench", "Row", "Curl", "Press"]
        )

        let engine = WorkoutSimilarityEngine()
        await engine.analyze(workouts: [selected, higherScore, lowerScore])

        let review = try XCTUnwrap(engine.review(for: selected.id))
        let bestMatch = try XCTUnwrap(review.bestMatch)

        XCTAssertEqual(bestMatch.kind, .partial)
        XCTAssertEqual(bestMatch.priorWorkoutId, higherScore.id)
        XCTAssertGreaterThan(bestMatch.score, 0.6)
    }

    func testOnlyEarlierWorkoutsAreEligibleMatches() async throws {
        let prior = makeWorkout(
            name: "Prior",
            date: date(day: 1, hour: 9),
            exercises: ["Bench", "Row"]
        )
        let selected = makeWorkout(
            name: "Selected",
            date: date(day: 2, hour: 9),
            exercises: ["Bench", "Row"]
        )
        let later = makeWorkout(
            name: "Later",
            date: date(day: 3, hour: 9),
            exercises: ["Bench", "Row"]
        )

        let engine = WorkoutSimilarityEngine()
        await engine.analyze(workouts: [later, selected, prior])

        let selectedReview = try XCTUnwrap(engine.review(for: selected.id))
        XCTAssertEqual(selectedReview.exactOrderMatches.map(\.priorWorkoutId), [prior.id])

        let priorReview = try XCTUnwrap(engine.review(for: prior.id))
        XCTAssertNil(priorReview.bestMatch)
    }

    func testWhitespaceAndCaseNormalizationStillCountsAsExactOrder() async throws {
        let prior = makeWorkout(
            name: "Prior",
            date: date(day: 1, hour: 10),
            exercises: [" bench press", "ROW "]
        )
        let selected = makeWorkout(
            name: "Selected",
            date: date(day: 2, hour: 10),
            exercises: ["Bench Press", "row"]
        )

        let engine = WorkoutSimilarityEngine()
        await engine.analyze(workouts: [selected, prior])

        let bestMatch = try XCTUnwrap(engine.review(for: selected.id)?.bestMatch)
        XCTAssertEqual(bestMatch.kind, .exactOrdered)
    }

    func testNoOverlapProducesNoBestMatchAndEmptyExactLists() async throws {
        let prior = makeWorkout(
            name: "Prior",
            date: date(day: 1, hour: 11),
            exercises: ["Squat", "Lunge"]
        )
        let selected = makeWorkout(
            name: "Selected",
            date: date(day: 2, hour: 11),
            exercises: ["Bench", "Row"]
        )

        let engine = WorkoutSimilarityEngine()
        await engine.analyze(workouts: [selected, prior])

        let review = try XCTUnwrap(engine.review(for: selected.id))
        XCTAssertNil(review.bestMatch)
        XCTAssertTrue(review.exactOrderMatches.isEmpty)
        XCTAssertTrue(review.reorderedExerciseMatches.isEmpty)
    }

    func testComparisonRowsMarkSamePositionMovedAndUniqueExercises() async throws {
        let prior = makeWorkout(
            name: "Prior",
            date: date(day: 1, hour: 12),
            exercises: ["Bench", "Row", "Pulldown"]
        )
        let selected = makeWorkout(
            name: "Selected",
            date: date(day: 2, hour: 12),
            exercises: ["Bench", "Squat", "Row"]
        )

        let engine = WorkoutSimilarityEngine()
        await engine.analyze(workouts: [selected, prior])

        let comparison = try XCTUnwrap(
            engine.comparison(selectedWorkoutId: selected.id, priorWorkoutId: prior.id)
        )

        XCTAssertTrue(comparison.rows.contains(where: {
            $0.selectedExerciseName == "Bench" && $0.kind == .samePosition
        }))
        XCTAssertTrue(comparison.rows.contains(where: {
            $0.selectedExerciseName == "Row" && $0.kind == .moved
        }))
        XCTAssertTrue(comparison.rows.contains(where: {
            $0.selectedExerciseName == "Squat" && $0.kind == .onlyInSelected
        }))
        XCTAssertTrue(comparison.rows.contains(where: {
            $0.priorExerciseName == "Pulldown" && $0.kind == .onlyInPrior
        }))
    }

    private func makeWorkout(name: String, date: Date, exercises: [String]) -> Workout {
        Workout(
            date: date,
            name: name,
            duration: "45m",
            exercises: exercises.map { Exercise(name: $0, sets: []) }
        )
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
