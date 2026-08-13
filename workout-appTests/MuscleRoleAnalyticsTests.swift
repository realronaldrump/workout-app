import XCTest
@testable import workout_app

@MainActor
final class MuscleRoleAnalyticsTests: XCTestCase {
    func testContributionPolicyCountsSecondarySetsAtHalfWeight() {
        let primary = ExerciseMuscleAssignment.primary(.builtIn(.chest))
        let secondary = ExerciseMuscleAssignment.secondary(.builtIn(.triceps))

        XCTAssertEqual(MuscleContributionPolicy.effectiveSets(setCount: 3, assignment: primary), 3)
        XCTAssertEqual(MuscleContributionPolicy.effectiveSets(setCount: 3, assignment: secondary), 1.5)
        XCTAssertEqual(
            MuscleContributionPolicy.exportDescription([primary, secondary]),
            "Primary: Chest; Secondary: Triceps"
        )
    }

    func testRecencyNeedsTwoSecondarySetsForMeaningfulExposure() throws {
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let oneSetWorkout = workout(on: date, setCount: 1)
        let twoSetWorkout = workout(on: date, setCount: 2)
        let mappings = [
            "Bench Press": [ExerciseMuscleAssignment.secondary(.builtIn(.triceps))]
        ]

        let oneSetRows = MuscleRecencySuggestionEngine.allGroupRecency(
            workouts: [oneSetWorkout],
            muscleAssignmentsByExerciseName: mappings,
            now: date
        )
        let twoSetRows = MuscleRecencySuggestionEngine.allGroupRecency(
            workouts: [twoSetWorkout],
            muscleAssignmentsByExerciseName: mappings,
            now: date
        )

        XCTAssertNil(try XCTUnwrap(oneSetRows.first { $0.group == .triceps }).lastTrained)
        XCTAssertEqual(try XCTUnwrap(twoSetRows.first { $0.group == .triceps }).lastTrained, date)
    }

    func testWeeklyCoverageUsesEffectiveSetThreshold() async throws {
        let date = Date()
        let mappings = [
            "Bench Press": [ExerciseMuscleAssignment.secondary(.builtIn(.triceps))]
        ]

        let oneSetEngine = RecoveryCoverageEngine()
        await oneSetEngine.analyze(
            workouts: [workout(on: date, setCount: 1)],
            healthStore: [:],
            dailyHealth: [:],
            muscleMappings: mappings
        )
        let oneSetInsight = try XCTUnwrap(
            oneSetEngine.frequencyInsights(for: .allTime).first { $0.muscleGroup == "Triceps" }
        )

        let twoSetEngine = RecoveryCoverageEngine()
        await twoSetEngine.analyze(
            workouts: [workout(on: date, setCount: 2)],
            healthStore: [:],
            dailyHealth: [:],
            muscleMappings: mappings
        )
        let twoSetInsight = try XCTUnwrap(
            twoSetEngine.frequencyInsights(for: .allTime).first { $0.muscleGroup == "Triceps" }
        )

        XCTAssertEqual(oneSetInsight.weeksHit, 0)
        XCTAssertEqual(twoSetInsight.weeksHit, 1)
    }

    private func workout(on date: Date, setCount: Int) -> Workout {
        Workout(
            date: date,
            name: "Upper",
            duration: "30m",
            exercises: [
                Exercise(
                    name: "Bench Press",
                    sets: (1...setCount).map { order in
                        WorkoutSet(
                            date: date,
                            workoutName: "Upper",
                            duration: "30m",
                            exerciseName: "Bench Press",
                            setOrder: order,
                            weight: 100,
                            reps: 8,
                            distance: 0,
                            seconds: 0
                        )
                    }
                )
            ]
        )
    }
}
