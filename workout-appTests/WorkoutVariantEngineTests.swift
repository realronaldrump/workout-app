import XCTest
@testable import workout_app

@MainActor
final class WorkoutVariantEngineTests: XCTestCase {
    func testUnassignedWorkoutsDoNotCreateLocationVariantAnalysis() async {
        let gymId = UUID()
        let assignedFirst = makeWorkout(day: 1, exerciseName: "Bench Press", weight: 205)
        let assignedSecond = makeWorkout(day: 2, exerciseName: "Bench Press", weight: 210)
        let unassignedFirst = makeWorkout(day: 3, exerciseName: "Bench Press", weight: 115)
        let unassignedSecond = makeWorkout(day: 4, exerciseName: "Bench Press", weight: 120)

        let annotations: [UUID: WorkoutAnnotation] = [
            assignedFirst.id: WorkoutAnnotation(workoutId: assignedFirst.id, gymProfileId: gymId),
            assignedSecond.id: WorkoutAnnotation(workoutId: assignedSecond.id, gymProfileId: gymId)
        ]

        let engine = WorkoutVariantEngine()
        await engine.analyze(
            workouts: [assignedFirst, assignedSecond, unassignedFirst, unassignedSecond],
            annotations: annotations,
            gymNames: [gymId: "Downtown Gym"]
        )

        XCTAssertTrue(engine.library.recentReviews.isEmpty)
        XCTAssertTrue(engine.library.standoutPatterns.isEmpty)
        XCTAssertNil(engine.review(for: unassignedFirst.id))
        XCTAssertNil(engine.review(for: unassignedSecond.id))
    }

    func testSharedWorkoutNamesDoNotCreateVariantAnalysisWithoutSharedStructure() async {
        let benchFirst = makeWorkout(name: "Full Body", day: 1, exerciseName: "Bench Press", weight: 205)
        let benchSecond = makeWorkout(name: "Full Body", day: 2, exerciseName: "Bench Press", weight: 210)
        let squatFirst = makeWorkout(name: "Full Body", day: 3, exerciseName: "Back Squat", weight: 315)
        let squatSecond = makeWorkout(name: "Full Body", day: 4, exerciseName: "Back Squat", weight: 320)

        let engine = WorkoutVariantEngine()
        await engine.analyze(
            workouts: [benchFirst, benchSecond, squatFirst, squatSecond],
            annotations: [:],
            gymNames: [:]
        )

        XCTAssertTrue(engine.library.recentReviews.isEmpty)
        XCTAssertTrue(engine.library.standoutPatterns.isEmpty)
        XCTAssertNil(engine.review(for: benchFirst.id))
        XCTAssertNil(engine.review(for: squatFirst.id))
    }

    private func makeWorkout(
        name: String = "Upper A",
        day: Int,
        exerciseName: String,
        weight: Double
    ) -> Workout {
        let workoutDate = date(day: day, hour: 8)
        let duration = "45m"

        return Workout(
            date: workoutDate,
            name: name,
            duration: duration,
            exercises: [
                Exercise(
                    name: exerciseName,
                    sets: [
                        WorkoutSet(
                            date: workoutDate,
                            workoutName: name,
                            duration: duration,
                            exerciseName: exerciseName,
                            setOrder: 0,
                            weight: weight,
                            reps: 5,
                            distance: 0,
                            seconds: 0
                        )
                    ]
                )
            ]
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
