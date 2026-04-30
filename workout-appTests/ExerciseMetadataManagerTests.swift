import XCTest
@testable import workout_app

final class ExerciseMetadataManagerTests: XCTestCase {
    func testDefaultExerciseCatalogMatchesRequestedCSVEntries() {
        let names = ExerciseMetadataManager.defaultExerciseNames

        XCTAssertTrue(names.contains("Barbell Row"))
        XCTAssertTrue(names.contains("Bayesian Curl"))
        XCTAssertTrue(names.contains("Bent Over One Arm Row (Dumbbell)"))
        XCTAssertTrue(names.contains("Calf Press on Seated Leg Press"))
        XCTAssertTrue(names.contains("Chin Up"))
        XCTAssertTrue(names.contains("Deadlift (Barbell)"))
        XCTAssertTrue(names.contains("Dumbbell Press"))
        XCTAssertTrue(names.contains("Incline Chest Press (Machine)"))
        XCTAssertTrue(names.contains("Lunges"))
        XCTAssertTrue(names.contains("Pull Up"))
        XCTAssertTrue(names.contains("Push Up"))
        XCTAssertTrue(names.contains("Single Leg Leg Curl (Left)"))
        XCTAssertTrue(names.contains("Single Leg Leg Curl (Right)"))
        XCTAssertTrue(names.contains("Single Leg Leg Extension (Left)"))
        XCTAssertTrue(names.contains("Single Leg Leg Extension (Right)"))
        XCTAssertTrue(names.contains("Single-Arm Overhead Cable Extension"))
        XCTAssertTrue(names.contains("Squat (Barbell)"))
        XCTAssertTrue(names.contains("Stair Stepper"))
        XCTAssertTrue(names.contains("Running (Treadmill)"))
        XCTAssertTrue(names.contains("Walking (Treadmill)"))
    }

    func testDefaultTagsMatchCSVForNewAndUpdatedExercises() {
        XCTAssertEqual(defaultGroups(for: "Bent Over One Arm Row (Dumbbell)"), [.back, .biceps])
        XCTAssertEqual(defaultGroups(for: "Calf Press on Seated Leg Press"), [.calves])
        XCTAssertEqual(defaultGroups(for: "Face Pull (Cable)"), [.back, .shoulders, .traps])
        XCTAssertEqual(defaultGroups(for: "Hip Adductor (Machine)"), [.adductors])
        XCTAssertEqual(defaultGroups(for: "Reverse Curl (EZ Bar)"), [.biceps, .forearms])
        XCTAssertEqual(defaultGroups(for: "Seated Palms Down Wrist Curl (Dumbbell)"), [.forearms])
        XCTAssertEqual(defaultGroups(for: "Single Leg Leg Curl (Left)"), [.hamstrings])
        XCTAssertEqual(defaultGroups(for: "Single Leg Leg Curl (Right)"), [.hamstrings])
        XCTAssertEqual(defaultGroups(for: "Single Leg Leg Extension (Left)"), [.quads])
        XCTAssertEqual(defaultGroups(for: "Single Leg Leg Extension (Right)"), [.quads])
        XCTAssertEqual(defaultGroups(for: "Stair Stepper"), [.cardio])
        XCTAssertEqual(defaultGroups(for: "Triceps Dip"), [.chest, .shoulders, .triceps])
    }

    func testLegacyRunningAliasStillResolvesToCardio() {
        XCTAssertEqual(defaultGroups(for: "Running (Treadmill)"), [.cardio])
    }

    func testCompatibilityMappingsResolveWithoutDuplicateBuiltIns() {
        XCTAssertFalse(ExerciseMetadataManager.defaultExerciseNames.contains("Push Ups"))
        XCTAssertFalse(ExerciseMetadataManager.defaultExerciseNames.contains("Stair stepper"))
        XCTAssertEqual(defaultGroups(for: "Push Ups"), [.chest, .triceps, .shoulders])
        XCTAssertEqual(defaultGroups(for: "Stair stepper"), [.cardio])
    }

    private func defaultGroups(for exerciseName: String) -> [MuscleGroup] {
        ExerciseMetadataManager.shared
            .defaultTags(for: exerciseName)
            .compactMap(\.builtInGroup)
    }
}
