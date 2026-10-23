import XCTest
@testable import workout_app

final class StrongExerciseCatalogTests: XCTestCase {
    func testEveryExerciseFromStrongExportIsAvailableWithoutImportingWorkouts() {
        let pickerNames = Set(ExerciseMetadataManager.defaultExerciseNames)
        let entriesByName = Dictionary(uniqueKeysWithValues: DefaultExerciseCatalog.entries.map { ($0.name, $0) })
        XCTAssertEqual(Self.exportExerciseNames.count, 178)

        for name in Self.exportExerciseNames {
            XCTAssertTrue(pickerNames.contains(name), "Missing default exercise: \(name)")
            guard let entry = entriesByName[name] else {
                XCTFail("Missing catalog metadata: \(name)")
                continue
            }
            XCTAssertFalse(entry.primaryGroups.isEmpty, "Missing primary muscle: \(name)")
            XCTAssertEqual(
                ExerciseMetadataManager.shared.defaultAssignments(for: name),
                entry.assignments,
                "Incorrect default assignments: \(name)"
            )
        }
    }

    func testEveryExplicitSideInStrongExportHasADefaultRelationship() {
        let relationships = Dictionary(uniqueKeysWithValues: DefaultExerciseCatalog.relationships.map { ($0.exerciseName, $0) })
        for name in Self.exportExerciseNames {
            let side: ExerciseLaterality?
            if name.hasSuffix(" - Left") || name.hasSuffix("(Left)") {
                side = .left
            } else if name.hasSuffix(" - Right") || name.hasSuffix("(Right)") {
                side = .right
            } else {
                side = nil
            }
            guard let side else { continue }
            XCTAssertEqual(relationships[name]?.laterality, side, "Missing or incorrect side: \(name)")
        }
    }

    func testNewExerciseMuscleRolesAndFacePullCorrection() {
        let expected: [String: [ExerciseMuscleAssignment]] = [
            "Cable Y-Raise (Both Arms)": [.primary(.builtIn(.shoulders)), .primary(.builtIn(.traps))],
            "Chest Supported DB Row - Both Arms": [.primary(.builtIn(.back)), .secondary(.builtIn(.biceps))],
            "Glute Bridge Machine (Planet Fitness)": [.primary(.builtIn(.glutes))],
            "Hallow Hold": [.primary(.builtIn(.core))],
            "Hanging Knee Raise": [.primary(.builtIn(.core)), .secondary(.builtIn(.hipFlexors))],
            "Hip Thrust (Barbell)": [.primary(.builtIn(.glutes))],
            "Incline Chest Fly (Dumbbell)": [.primary(.builtIn(.chest)), .secondary(.builtIn(.shoulders))],
            "Lateral Lunge": [.primary(.builtIn(.quads)), .primary(.builtIn(.glutes)), .secondary(.builtIn(.adductors))],
            "Reverse Fly (Cable)": [.primary(.builtIn(.back)), .primary(.builtIn(.shoulders)), .secondary(.builtIn(.traps))],
            "Seated Leg Press (Machine)": [.primary(.builtIn(.quads)), .secondary(.builtIn(.glutes))],
            "Seated Row (Machine)": [.primary(.builtIn(.back)), .secondary(.builtIn(.biceps))],
            "Seated Two-Arm Triceps Extension": [.primary(.builtIn(.triceps))],
            "Supported Split Squat": [.primary(.builtIn(.quads)), .secondary(.builtIn(.glutes))],
            "Triceps Pushdown (Cable - Rope)": [.primary(.builtIn(.triceps))],
            "Face Pull (Cable)": [.primary(.builtIn(.back)), .primary(.builtIn(.shoulders)), .secondary(.builtIn(.traps))]
        ]
        for (name, assignments) in expected {
            XCTAssertEqual(ExerciseMetadataManager.shared.defaultAssignments(for: name), assignments, name)
        }
        XCTAssertEqual(
            ExerciseMetadataManager.shared.defaultAssignments(for: "Hallow Hold"),
            ExerciseMetadataManager.shared.defaultAssignments(for: "Hollow Hold")
        )
    }

    func testExplicitTwoArmExercisesRemainIndependentTracks() {
        let resolver = ExerciseIdentityResolver(relationships: Dictionary(
            uniqueKeysWithValues: DefaultExerciseCatalog.relationships.map { ($0.exerciseName, $0) }
        ))
        for name in ["Cable Y-Raise (Both Arms)", "Chest Supported DB Row - Both Arms", "Seated Two-Arm Triceps Extension"] {
            XCTAssertNil(resolver.relationship(for: name))
            XCTAssertEqual(resolver.aggregateName(for: name), name)
            XCTAssertEqual(resolver.performanceTrackName(for: name), name)
        }
    }

    func testNewDefaultsPreserveSavedMuscleOverridesAndExplicitlyUntaggedExercises() throws {
        let suiteName = "StrongExerciseCatalogTests.overrides.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let overrides: [String: [ExerciseMuscleAssignment]] = [
            "Cable Y-Raise (Both Arms)": [.primary(.builtIn(.shoulders))],
            "Hallow Hold": []
        ]
        defaults.set(try JSONEncoder().encode(overrides), forKey: ExerciseMetadataManager.assignmentMetadataKey)
        let manager = ExerciseMetadataManager(userDefaults: defaults)

        XCTAssertEqual(manager.resolvedAssignments(for: "Cable Y-Raise (Both Arms)"), overrides["Cable Y-Raise (Both Arms)"])
        XCTAssertEqual(manager.resolvedAssignments(for: "Hallow Hold"), [])
        XCTAssertEqual(manager.resolvedAssignments(for: "Hip Thrust (Barbell)"), [.primary(.builtIn(.glutes))])
    }

    // Names only from the supplied Strong export. Workout dates, weights, and other personal history are omitted.
    private static let exportExerciseNames = """
    45° Donkey Calf
    Ab Wheel
    Arnold Press (Dumbbell)
    Back Extension
    Back Extension (Machine)
    Bayesian Curl
    Bayesian Curl - Left
    Bayesian Curl - Right
    Bench Press (Barbell)
    Bench Press - Close Grip (Barbell)
    Bent Over One Arm Row (Dumbbell)
    Bent Over Row (Dumbbell)
    Bicep Curl (Barbell)
    Bicep Curl (Cable)
    Bicep Curl (Dumbbell)
    Bicep Curl (Machine)
    Bicep Curl (Machine) (Bands)
    Bulgarian Split Squat
    Bulgarian Split Squat - Left
    Bulgarian Split Squat - Right
    Cable Y-Raise (Both Arms)
    Calf Extension Machine
    Calf Press on Seated Leg Press
    Chest Fly
    Chest Fly (Dumbbell)
    Chest Fly - Kinesis Machine
    Chest Press (Machine)
    Chest Supported DB Row - Both Arms
    Cossack Squat - Left
    Cossack Squat - Right
    Crucifix Crunches
    Crunch
    Crunch (Machine)
    Cycling (Indoor)
    Dead Hang
    Deadlift (Smith Machine)
    EZ Bar Curl
    Elliptical Machine
    Face Pull (Cable)
    Flutter Kicks
    Front Raise (Dumbbell)
    Glute Bridge (Dumbbell) - 20lb
    Glute Bridge Machine (Planet Fitness)
    Glute Kickback (Cable) - Left
    Glute Kickback (Cable) - Right
    Glute Kickback (Machine)
    Goblet Squat (Kettlebell)
    Hack Squat
    Hallow Hold
    Hammer Curl (Cable)
    Hammer Curl (Dumbbell)
    Hammer Curl (Dumbbell) - Left
    Hammer Curl (Dumbbell) - Right
    Hanging Knee Raise
    Hip Abductor (Cable)
    Hip Abductor (Cable) - Left
    Hip Abductor (Cable) - Right
    Hip Abductor (Machine)
    Hip Adductor (Cable)
    Hip Adductor (Cable) - Left
    Hip Adductor (Cable) - Right
    Hip Adductor (Machine)
    Hip Thrust (Barbell)
    Hip Thrust (Bodyweight)
    Hip Thrust Machine
    Incline Bench Press (Barbell)
    Incline Bench Press (Dumbbell)
    Incline Bench Press (Smith Machine)
    Incline Chest Fly (Dumbbell)
    Incline Chest Press (Machine)
    Incline Curl (Dumbbell)
    Incline Curl (Dumbbell) - Left
    Incline Curl (Dumbbell) - Right
    Incline Treadmill
    Iso-Lateral Row (Machine)
    Knee Raise (Captain's Chair)
    Kneeling Bilateral Lat Pulldown - Kinesis Machine
    Lat Pulldown (Cable)
    Lat Pulldown (Machine)
    Lateral Lunge - Left
    Lateral Lunge - Right
    Lateral Raise (Cable)
    Lateral Raise (Cable) - Left
    Lateral Raise (Cable) - Right
    Lateral Raise (Dumbbell)
    Lateral Raise (Machine)
    Leg Extension (Machine)
    Leg Press
    Low to High Cable Fly
    Lunge (Dumbbell)
    Lunge (Kinesis Machine) - Left
    Lunge (Kinesis Machine) - Right
    Lying Leg Curl (Machine)
    Lying Leg Raise Hold
    MTS Abdominal Crunch
    MTS Row
    Overhead Press (Dumbbell)
    Overhead Press (Machine)
    Overhead Tricep Extensions (single arm, no attachment)
    Overhead Tricep Extensions (single arm, no attachment) - Left
    Overhead Tricep Extensions (single arm, no attachment) - Right
    Overhead Tricep Extensions with Cable (low to high)
    Plank
    Preacher Curl (Barbell)
    Preacher Curl (Dumbbell)
    Preacher Curl (Machine)
    Pull Up (Assisted)
    Push Up
    RDL (Kettlebell)
    Reverse Crunch
    Reverse Curl (Barbell)
    Reverse Curl (EZ Bar)
    Reverse Fly (Cable)
    Reverse Fly (Dumbbell)
    Reverse Fly (Machine)
    Reverse Fly Cable - Left
    Reverse Fly Cable - Right
    Reverse Plank
    Romanian Deadlift (Dumbbell)
    Romanian Deadlift (Smith Machine)
    Rotary Torso Machine
    Seated Calf Raise (Plate Loaded)
    Seated Leg Curl (Machine)
    Seated Leg Press (Machine)
    Seated Leg Press (Machine) - Left
    Seated Leg Press (Machine) - Right
    Seated Overhead Press (Dumbbell)
    Seated Palms Down Wrist Curl (Dumbbell)
    Seated Palms Up Wrist Curl (Dumbbell)
    Seated Row (Cable)
    Seated Row (Machine)
    Seated Row (Machine) - Left
    Seated Row (Machine) - Right
    Seated Two-Arm Triceps Extension
    Shoulder Press (Machine)
    Shrug (Barbell)
    Shrug (Dumbbell)
    Shrug (Smith Machine)
    Shrug - Kinesis Machine
    Side Leg Raises
    Side Plank Hip Raise (both sides)
    Single Arm Tricep Extension (dumbbell)
    Single Leg Leg Extension (Left)
    Single Leg Leg Extension (Right)
    Single Leg Seated Leg Curl (Left)
    Single Leg Seated Leg Curl (Right)
    Single-Arm Overhead Cable Extension
    Single-Leg RDL
    Single-arm cable pressdown - Left
    Single-arm cable pressdown - Right
    Skullcrusher (Barbell)
    Squat (Band)
    Squat (Barbell)
    Squat (Dumbbell)
    Squat (Smith Machine)
    Stair Stepper
    Standing Calf Raise (Bodyweight)
    Standing Calf Raise (Dumbbell)
    Standing Calf Raise (Machine)
    Standing Calf Raise (Smith Machine)
    Standing Row - Kinesis Machine
    Straight Arm Pulldown
    Superman
    Supported Split Squat - Left
    Supported Split Squat - Right
    T Bar Row
    Tricep Overhead Extension With Rope
    Triceps Dip
    Triceps Dip (Assisted)
    Triceps Extension (Dumbbell)
    Triceps Extension (Machine)
    Triceps Kickback (dumbbell)
    Triceps Press Machine
    Triceps Pushdown (Cable - Rope)
    Triceps Pushdown (Cable - Straight Bar)
    Upright Row (Dumbbell)
    V-bar Pulldown
    Walking (Treadmill)
    """.split(separator: "\n").map(String.init)
}
