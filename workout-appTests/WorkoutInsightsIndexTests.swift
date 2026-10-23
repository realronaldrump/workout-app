import XCTest
@testable import workout_app

final class WorkoutInsightsIndexTests: XCTestCase {
    func testIndexedExactHistoriesMatchExistingHistoryForCaseVariantsAndDuplicateEntries() {
        let workouts = [
            workout(day: 3, names: ["Bench Press", "Bench Press", "Curl - Left"]),
            workout(day: 1, names: ["bench press", "Curl - Right"]),
            workout(day: 2, names: [" Bench Press ", "Curl - Left", "Curl - Right", " "])
        ]
        let resolver = sideResolver()
        let index = WorkoutInsightsIndex(workouts: workouts, resolver: resolver)

        XCTAssertFalse(index.performanceTrackNames.contains(" "))
        for name in index.performanceTrackNames {
            XCTAssertEqual(
                index.historyByPerformanceTrack[name],
                ExerciseAggregation.historySessions(
                    in: workouts,
                    for: name,
                    includingVariants: false,
                    resolver: resolver
                ),
                "Exact-track history changed for \(name)"
            )
        }
        XCTAssertEqual(index.historyByPerformanceTrack["Bench Press"]?.map(\.sets.count), [2, 2, 4])
        XCTAssertEqual(index.historyByPerformanceTrack["Curl - Left"]?.count, 2)
        XCTAssertEqual(index.historyByPerformanceTrack["Curl - Right"]?.count, 2)
    }

    func testAggregateEvidencePreservesPairedSidesAndOneSessionPerWorkout() {
        let workouts = [
            workout(day: 3, names: ["Curl", "Curl - Left", "Curl - Right"]),
            workout(day: 1, names: ["Curl - Left", "Curl - Right"]),
            workout(day: 2, names: ["Curl - Left", "Bench Press"])
        ]
        let resolver = sideResolver()
        let index = WorkoutInsightsIndex(workouts: workouts, resolver: resolver)

        XCTAssertEqual(index.totalVolume, ExerciseAggregation.totalVolume(for: workouts, resolver: resolver))
        for (name, sessions) in index.aggregateSessionsByName {
            let expected = workouts.sorted { $0.date < $1.date }.compactMap { workout in
                ExerciseAggregation.aggregateExercises(in: workout, resolver: resolver)
                    .first { $0.name == name }
                    .map { (workout.id, workout.date, $0.totalVolume) }
            }
            XCTAssertEqual(sessions.map(\.workoutID), expected.map(\.0))
            XCTAssertEqual(sessions.map(\.date), expected.map(\.1))
            XCTAssertEqual(sessions.map(\.volume), expected.map(\.2))
        }
        XCTAssertEqual(index.aggregateSessionsByName["Curl"]?.count, 3)
        XCTAssertNil(index.aggregateSessionsByName["Curl - Left"])
    }

    func testEmptyExercisesKeepTheirSessionAndEmptyIndexHasNoEvidence() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let emptyExercise = Workout(date: date, name: "Empty", duration: "", exercises: [Exercise(name: "Curl", sets: [])])
        let index = WorkoutInsightsIndex(workouts: [emptyExercise], resolver: .empty)
        XCTAssertEqual(index.historyByPerformanceTrack["Curl"]?.count, 1)
        XCTAssertEqual(index.historyByPerformanceTrack["Curl"]?.first?.sets, [])
        XCTAssertEqual(index.aggregateSessionsByName["Curl"]?.first?.volume, 0)

        let empty = WorkoutInsightsIndex(workouts: [], resolver: .empty)
        XCTAssertTrue(empty.performanceTrackNames.isEmpty)
        XCTAssertTrue(empty.aggregateSessionsByName.isEmpty)
        XCTAssertEqual(empty.totalVolume, 0)
    }

    private func sideResolver() -> ExerciseIdentityResolver {
        ExerciseIdentityResolver(relationships: [
            "left": ExerciseRelationship(exerciseName: "Curl - Left", parentName: "Curl", laterality: .left),
            "right": ExerciseRelationship(exerciseName: "Curl - Right", parentName: "Curl", laterality: .right)
        ])
    }

    private func workout(day: Int, names: [String]) -> Workout {
        let date = Date(timeIntervalSinceReferenceDate: Double(day) * 86_400)
        return Workout(date: date, name: "Session", duration: "30m", exercises: names.map { name in
            Exercise(name: name, sets: [2, 1].map { order in
                WorkoutSet(
                    date: date,
                    workoutName: "Session",
                    duration: "30m",
                    exerciseName: name,
                    setOrder: order,
                    weight: Double(day * 10),
                    reps: 10,
                    distance: 0,
                    seconds: 0
                )
            })
        })
    }
}
