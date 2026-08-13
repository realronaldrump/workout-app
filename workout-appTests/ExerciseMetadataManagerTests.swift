import XCTest
@testable import workout_app

final class ExerciseMetadataManagerTests: XCTestCase {
    func testCatalogIsFullyIntegratedIntoDefaults() {
        XCTAssertEqual(DefaultExerciseCatalog.entries.count, 215)
        XCTAssertEqual(Set(DefaultExerciseCatalog.entries.map(\.name)).count, 215)

        let pickerNames = Set(ExerciseMetadataManager.defaultExerciseNames)
        for entry in DefaultExerciseCatalog.entries {
            XCTAssertTrue(pickerNames.contains(entry.name), "Missing default exercise: \(entry.name)")
            XCTAssertEqual(
                defaultGroups(for: entry.name),
                entry.groups,
                "Incorrect default tags for: \(entry.name)"
            )
        }
    }

    func testFinalCSVRelationshipsReferenceParentsWithMatchingTags() {
        let entriesByName = Dictionary(
            uniqueKeysWithValues: DefaultExerciseCatalog.entries.map { ($0.name, $0) }
        )

        XCTAssertEqual(DefaultExerciseCatalog.relationships.count, 50)
        for child in DefaultExerciseCatalog.entries where child.parentName != nil {
            guard let parentName = child.parentName, let parent = entriesByName[parentName] else {
                XCTFail("Missing parent for \(child.name)")
                continue
            }
            XCTAssertNotNil(child.laterality, "Missing side for \(child.name)")
            XCTAssertEqual(child.groups, parent.groups, "Child/parent tags diverge for \(child.name)")
        }
    }

    func testAllCSVMuscleGroupsExistAsBuiltIns() {
        XCTAssertEqual(Set(MuscleGroup.allCases.map(\.displayName)), [
            "Adductors", "Back", "Biceps", "Calves", "Cardio", "Chest", "Core", "Forearms",
            "Glutes", "Hamstrings", "Hip Flexors", "Quads", "Shoulders", "Traps", "Triceps"
        ])
        XCTAssertEqual(defaultGroups(for: "Flutter Kicks"), [.core, .hipFlexors])
        XCTAssertEqual(defaultGroups(for: "Lying Leg Raise Hold"), [.core, .hipFlexors])
    }

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
        XCTAssertTrue(names.contains("Single Leg Seated Leg Curl (Left)"))
        XCTAssertTrue(names.contains("Single Leg Seated Leg Curl (Right)"))
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
        XCTAssertEqual(defaultGroups(for: "Triceps Dip"), [.triceps, .chest, .shoulders])
    }

    func testAdditionalStrongExportExercisesAreDefaultAndTagged() {
        let expectedMappings: [String: [MuscleGroup]] = [
            "Bench Press (Dumbbell)": [.chest, .triceps, .shoulders],
            "Bench Press - Wide Grip (Barbell)": [.chest, .shoulders, .triceps],
            "Bent Over Row - Underhand (Barbell)": [.back, .biceps],
            "Calf Press on Leg Press": [.calves],
            "Chest Dip (Assisted)": [.chest, .triceps, .shoulders],
            "Chest Fly (Band)": [.chest],
            "Chest Fly - Kinesis Machine": [.chest],
            "Cossack Squat - Left": [.quads, .glutes, .adductors],
            "Cossack Squat - Right": [.quads, .glutes, .adductors],
            "Decline Bench Press (Barbell)": [.chest, .triceps, .shoulders],
            "Front Raise (Cable)": [.shoulders],
            "Glute Kickback (Cable) - Left": [.glutes],
            "Glute Kickback (Cable) - Right": [.glutes],
            "Incline Treadmill": [.cardio],
            "Iso-Lateral Chest Press (Machine)": [.chest, .triceps, .shoulders],
            "Kneeling Bilateral Lat Pulldown - Kinesis Machine": [.back, .biceps],
            "Kneeling Single Arm Press": [.shoulders, .triceps],
            "Landmine Twist": [.core],
            "Lat Pulldown (Single Arm)": [.back, .biceps],
            "Laying Bicep Curl": [.biceps],
            "LifeFitness Crunch": [.core],
            "Lunge (Barbell)": [.quads, .glutes],
            "MTS Shoulder Press": [.shoulders, .triceps],
            "Overhead Press (Barbell)": [.shoulders, .triceps],
            "Rhino Belt Squat": [.quads, .glutes],
            "Seated Calf Raise (Machine)": [.calves],
            "Shrug (Machine)": [.traps],
            "Shrug - Kinesis Machine": [.traps],
            "Single Arm Tricep Pushdown (airport)": [.triceps],
            "Single Leg Extension": [.quads],
            "Single-arm cable pressdown - Left": [.triceps],
            "Single-arm cable pressdown - Right": [.triceps],
            "Skullcrusher (Dumbbell)": [.triceps],
            "Squat (Barbell)": [.quads, .glutes],
            "Standing Lat Pushdown": [.back],
            "Standing Row - Kinesis Machine": [.back, .biceps],
            "Torso Rotation (Machine)": [.core],
            "Tricep On Pull-Up Machine": [.triceps],
            "Triceps Extension": [.triceps],
            "Triceps Extension (Barbell)": [.triceps],
            "Triceps Extension (Cable)": [.triceps],
            "Upright Row (Barbell)": [.shoulders, .traps],
            "Hallow Hold": [.core],
            "Kneeling Bilateral Lat Pulldown - Kinesis Machind": [.back, .biceps],
            "Single Arm Tricep Extension (dumbell)": [.triceps]
        ]

        let pickerNames = Set(ExerciseMetadataManager.defaultExerciseNames)
        for (name, groups) in expectedMappings {
            XCTAssertEqual(defaultGroups(for: name), groups, "Incorrect default tags for: \(name)")
        }

        XCTAssertTrue(pickerNames.contains("Cossack Squat"))
        XCTAssertTrue(pickerNames.contains("Glute Kickback (Cable)"))
        XCTAssertTrue(pickerNames.contains("Single-arm cable pressdown"))
        XCTAssertFalse(pickerNames.contains("Hallow Hold"))
        XCTAssertFalse(pickerNames.contains("Kneeling Bilateral Lat Pulldown - Kinesis Machind"))
        XCTAssertFalse(pickerNames.contains("Single Arm Tricep Extension (dumbell)"))

        for (name, groups) in expectedMappings where !name.contains("Machind") && name != "Hallow Hold" && name != "Single Arm Tricep Extension (dumbell)" {
            XCTAssertTrue(pickerNames.contains(name), "Missing default exercise: \(name)")
            XCTAssertEqual(defaultGroups(for: name), groups, "Incorrect default tags for: \(name)")
        }
    }

    func testLegacyRunningAliasStillResolvesToCardio() {
        XCTAssertEqual(defaultGroups(for: "Running (Treadmill)"), [.cardio])
    }

    func testCompatibilityMappingsResolveWithoutDuplicateBuiltIns() {
        XCTAssertFalse(ExerciseMetadataManager.defaultExerciseNames.contains("Push Ups"))
        XCTAssertFalse(ExerciseMetadataManager.defaultExerciseNames.contains("Stair stepper"))
        XCTAssertFalse(ExerciseMetadataManager.defaultExerciseNames.contains("Single Arm Tricep Extension (dumbell)"))
        XCTAssertFalse(ExerciseMetadataManager.defaultExerciseNames.contains("Single Leg Leg Curl (Left)"))
        XCTAssertFalse(ExerciseMetadataManager.defaultExerciseNames.contains("Single Leg Leg Curl (Right)"))
        XCTAssertEqual(defaultGroups(for: "Push Ups"), [.chest, .triceps, .shoulders])
        XCTAssertEqual(defaultGroups(for: "Stair stepper"), [.cardio])
        XCTAssertEqual(defaultGroups(for: "Single Arm Tricep Extension (dumbell)"), [.triceps])
    }

    private func defaultGroups(for exerciseName: String) -> [MuscleGroup] {
        ExerciseMetadataManager.shared
            .defaultTags(for: exerciseName)
            .compactMap(\.builtInGroup)
    }
}
