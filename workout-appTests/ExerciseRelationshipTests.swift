import XCTest
@testable import workout_app

@MainActor
final class ExerciseRelationshipTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ExerciseRelationshipManager.shared.clearRelationships()
        ExerciseMetadataManager.shared.clearOverrides()
        ExerciseMetricManager.shared.clearOverrides()
    }

    override func tearDown() {
        ExerciseRelationshipManager.shared.clearRelationships()
        ExerciseMetadataManager.shared.clearOverrides()
        ExerciseMetricManager.shared.clearOverrides()
        super.tearDown()
    }

    func testResolverRollsExplicitSideVariantsToParentButKeepsPerformanceTracksExact() {
        let resolver = ExerciseIdentityResolver(relationships: [
            "left": ExerciseRelationship(
                exerciseName: "Leg Extension (Machine) - Left",
                parentName: "Leg Extension (Machine)",
                laterality: .left
            ),
            "right": ExerciseRelationship(
                exerciseName: "Leg Extension (Machine) - Right",
                parentName: "Leg Extension (Machine)",
                laterality: .right
            )
        ])

        XCTAssertEqual(
            resolver.aggregateName(for: "Leg Extension (Machine) - Left"),
            "Leg Extension (Machine)"
        )
        XCTAssertEqual(
            resolver.performanceTrackName(for: "Leg Extension (Machine) - Left"),
            "Leg Extension (Machine) - Left"
        )
        XCTAssertEqual(resolver.children(of: "Leg Extension (Machine)").map(\.laterality), [.left, .right])
        XCTAssertEqual(resolver.displayIdentity(for: "Leg Extension (Machine) - Right").sideLabel, "Right")
    }

    func testInferredSuggestionRecognizesCommonSideNamingWithoutCreatingRelationship() {
        let suggestion = ExerciseIdentityResolver.inferredSuggestion(
            for: "Leg Extension (Machine) - Left",
            knownExerciseNames: ["Leg Extension (Machine)", "Squat (Barbell)"]
        )

        XCTAssertEqual(suggestion?.exerciseName, "Leg Extension (Machine) - Left")
        XCTAssertEqual(suggestion?.parentName, "Leg Extension (Machine)")
        XCTAssertEqual(suggestion?.laterality, .left)

        let resolver = ExerciseIdentityResolver()
        XCTAssertEqual(
            resolver.aggregateName(for: "Leg Extension (Machine) - Left"),
            "Leg Extension (Machine) - Left"
        )
    }

    func testWorkoutDataManagerAggregatesParentHistoryWhileKeepingExactHistoriesSeparate() {
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Extension (Machine) - Left",
            parentName: "Leg Extension (Machine)",
            laterality: .left
        )
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Extension (Machine) - Right",
            parentName: "Leg Extension (Machine)",
            laterality: .right
        )

        let date = makeDate(day: 1)
        let workout = LoggedWorkout(
            startedAt: date,
            endedAt: date.addingTimeInterval(30 * 60),
            name: "Legs",
            exercises: [
                LoggedExercise(name: "Leg Extension (Machine) - Left", sets: [
                    LoggedSet(order: 1, weight: 50, reps: 10)
                ]),
                LoggedExercise(name: "Leg Extension (Machine) - Right", sets: [
                    LoggedSet(order: 1, weight: 55, reps: 8)
                ])
            ]
        )

        let manager = WorkoutDataManager()
        manager.setLoggedWorkouts([workout])

        let summaries = manager.exerciseSummaries()
        XCTAssertEqual(summaries.map(\.name), ["Leg Extension (Machine)"])
        XCTAssertEqual(summaries.first?.stats.frequency, 1)
        XCTAssertEqual(summaries.first?.stats.totalVolume, 470)
        XCTAssertEqual(summaries.first?.stats.maxWeight, 0)
        XCTAssertEqual(summaries.first?.stats.oneRepMax, 0)
        XCTAssertEqual(manager.calculateStats().totalExercises, 1)
        XCTAssertEqual(manager.recentExerciseNames(limit: 10), ["Leg Extension (Machine)"])

        let aggregate = manager.exerciseHistorySessions(for: "Leg Extension (Machine)", includingVariants: true)
        XCTAssertEqual(aggregate.count, 1)
        XCTAssertEqual(aggregate.first?.sets.count, 1)

        let leftExact = manager.exerciseHistorySessions(for: "Leg Extension (Machine) - Left", includingVariants: false)
        let rightExact = manager.exerciseHistorySessions(for: "Leg Extension (Machine) - Right", includingVariants: false)
        XCTAssertEqual(leftExact.first?.sets.first?.weight, 50)
        XCTAssertEqual(rightExact.first?.sets.first?.weight, 55)
    }

    func testAggregateHistorySessionsCreditPairedSidesOnce() {
        let resolver = ExerciseIdentityResolver(relationships: [
            "left": ExerciseRelationship(
                exerciseName: "Leg Curl - Left",
                parentName: "Leg Curl",
                laterality: .left
            ),
            "right": ExerciseRelationship(
                exerciseName: "Leg Curl - Right",
                parentName: "Leg Curl",
                laterality: .right
            )
        ])

        let date = makeDate(day: 1)
        let workout = Workout(
            date: date,
            name: "Lower",
            duration: "30m",
            exercises: [
                Exercise(name: "Leg Curl - Left", sets: [
                    workoutSet(date: date, exerciseName: "Leg Curl - Left", order: 1, weight: 50, reps: 10)
                ]),
                Exercise(name: "Leg Curl - Right", sets: [
                    workoutSet(date: date, exerciseName: "Leg Curl - Right", order: 1, weight: 60, reps: 10)
                ])
            ]
        )

        let aggregateHistory = ExerciseAggregation.historySessions(
            in: [workout],
            for: "Leg Curl",
            includingVariants: true,
            resolver: resolver
        )
        let exactLeftHistory = ExerciseAggregation.historySessions(
            in: [workout],
            for: "Leg Curl - Left",
            includingVariants: false,
            resolver: resolver
        )

        XCTAssertEqual(ExerciseAggregation.exerciseCount(for: workout, resolver: resolver), 1)
        XCTAssertEqual(ExerciseAggregation.totalSets(for: workout, resolver: resolver), 1)
        XCTAssertEqual(ExerciseAggregation.totalVolume(for: workout, resolver: resolver), 550)
        XCTAssertEqual(aggregateHistory.first?.sets.count, 1)
        XCTAssertEqual(aggregateHistory.first?.sets.first?.weight, 55)
        XCTAssertEqual(exactLeftHistory.first?.sets.first?.weight, 50)
    }

    func testRecommendationsUseExactPerformanceTrackInsteadOfParentRollup() {
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Extension (Machine) - Left",
            parentName: "Leg Extension (Machine)",
            laterality: .left
        )
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Extension (Machine) - Right",
            parentName: "Leg Extension (Machine)",
            laterality: .right
        )

        let firstDate = makeDate(day: 1)
        let secondDate = makeDate(day: 8)
        let manager = WorkoutDataManager()
        manager.setLoggedWorkouts([
            LoggedWorkout(
                startedAt: firstDate,
                endedAt: firstDate.addingTimeInterval(30 * 60),
                name: "Left Track",
                exercises: [
                    LoggedExercise(name: "Leg Extension (Machine) - Left", sets: [
                        LoggedSet(order: 1, weight: 50, reps: 10)
                    ])
                ]
            ),
            LoggedWorkout(
                startedAt: secondDate,
                endedAt: secondDate.addingTimeInterval(30 * 60),
                name: "Right Track",
                exercises: [
                    LoggedExercise(name: "Leg Extension (Machine) - Right", sets: [
                        LoggedSet(order: 1, weight: 100, reps: 10)
                    ])
                ]
            )
        ])

        let leftHistory = manager.getExerciseHistory(for: "Leg Extension (Machine) - Left")
        let rightHistory = manager.getExerciseHistory(for: "Leg Extension (Machine) - Right")
        let parentExactHistory = manager.getExerciseHistory(for: "Leg Extension (Machine)")

        XCTAssertEqual(leftHistory.flatMap(\.sets).map(\.weight), [50])
        XCTAssertEqual(rightHistory.flatMap(\.sets).map(\.weight), [100])
        XCTAssertTrue(parentExactHistory.isEmpty)

        let leftRecommendation = ExerciseRecommendationEngine.recommend(
            exerciseName: "Leg Extension (Machine) - Left",
            history: leftHistory,
            weightIncrement: 5
        )
        let rightRecommendation = ExerciseRecommendationEngine.recommend(
            exerciseName: "Leg Extension (Machine) - Right",
            history: rightHistory,
            weightIncrement: 5
        )

        XCTAssertEqual(leftRecommendation.suggestedWeight, 55)
        XCTAssertEqual(rightRecommendation.suggestedWeight, 105)
    }

    func testRelationshipBackupMergeKeepsLocalRelationshipWhenIncomingConflicts() {
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Extension (Machine) - Left",
            parentName: "Leg Extension (Machine)",
            laterality: .left
        )

        let result = ExerciseRelationshipManager.shared.mergeRelationshipsFromBackup([
            ExerciseRelationship(
                exerciseName: "Leg Extension (Machine) - Left",
                parentName: "Different Parent",
                laterality: .right
            ),
            ExerciseRelationship(
                exerciseName: "Leg Extension (Machine) - Right",
                parentName: "Leg Extension (Machine)",
                laterality: .right
            )
        ])

        XCTAssertEqual(result.inserted, 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(
            ExerciseRelationshipManager.shared.relationship(for: "Leg Extension (Machine) - Left")?.parentName,
            "Leg Extension (Machine)"
        )
        XCTAssertEqual(
            ExerciseRelationshipManager.shared.relationship(for: "Leg Extension (Machine) - Right")?.laterality,
            .right
        )
    }

    func testRelationshipManagerRejectsCyclesAndStoresRootParent() {
        XCTAssertTrue(ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Curl - Left",
            parentName: "Leg Curl",
            laterality: .left
        ))
        XCTAssertTrue(ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Curl - Right",
            parentName: "Leg Curl",
            laterality: .right
        ))

        XCTAssertFalse(ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Custom Right Curl",
            parentName: "Leg Curl - Right",
            laterality: .right
        ))
        XCTAssertNil(ExerciseRelationshipManager.shared.relationship(for: "Custom Right Curl"))

        XCTAssertTrue(ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Curl - Unilateral",
            parentName: "Leg Curl - Right",
            laterality: .unilateral
        ))
        XCTAssertEqual(
            ExerciseRelationshipManager.shared.relationship(for: "Leg Curl - Unilateral")?.parentName,
            "Leg Curl"
        )

        XCTAssertFalse(ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Curl",
            parentName: "Leg Curl - Unilateral",
            laterality: .unilateral
        ))
        XCTAssertNil(ExerciseRelationshipManager.shared.relationship(for: "Leg Curl"))
    }

    func testRelationshipRenameReplacesOldChildWithoutCreatingDuplicateSide() {
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Curl - Left",
            parentName: "Leg Curl",
            laterality: .left
        )

        XCTAssertTrue(ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Custom Left Curl",
            parentName: "Leg Curl",
            laterality: .left,
            replacingExerciseName: "Leg Curl - Left"
        ))

        XCTAssertNil(ExerciseRelationshipManager.shared.relationship(for: "Leg Curl - Left"))
        XCTAssertEqual(
            ExerciseRelationshipManager.shared.relationship(for: "Custom Left Curl")?.parentName,
            "Leg Curl"
        )
        XCTAssertEqual(
            ExerciseRelationshipManager.shared.children(of: "Leg Curl").map(\.exerciseName),
            ["Custom Left Curl"]
        )
    }

    func testCreateStandardSideVariantsAddsLeftAndRightChildrenForAnyParent() {
        let result = ExerciseRelationshipManager.shared.createStandardSideVariants(
            parentName: "Bench Press (Barbell)"
        )

        XCTAssertEqual(result.created.map(\.exerciseName), [
            "Bench Press (Barbell) - Left",
            "Bench Press (Barbell) - Right"
        ])
        XCTAssertTrue(result.skipped.isEmpty)

        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()
        XCTAssertEqual(
            resolver.children(of: "Bench Press (Barbell)").map(\.laterality),
            [.left, .right]
        )
        XCTAssertEqual(
            resolver.aggregateName(for: "Bench Press (Barbell) - Left"),
            "Bench Press (Barbell)"
        )
        XCTAssertEqual(
            resolver.performanceTrackName(for: "Bench Press (Barbell) - Left"),
            "Bench Press (Barbell) - Left"
        )

        let duplicateResult = ExerciseRelationshipManager.shared.createStandardSideVariants(
            parentName: "Bench Press (Barbell)"
        )
        XCTAssertTrue(duplicateResult.created.isEmpty)
        XCTAssertEqual(duplicateResult.skipped, [.left, .right])
    }

    func testCreateStandardSideVariantsOnlyFillsMissingSideWhenOneSideAlreadyExists() {
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Custom Left Row",
            parentName: "Seated Row (Cable)",
            laterality: .left
        )

        let result = ExerciseRelationshipManager.shared.createStandardSideVariants(
            parentName: "Seated Row (Cable)"
        )

        XCTAssertEqual(result.created.map(\.exerciseName), ["Seated Row (Cable) - Right"])
        XCTAssertEqual(result.skipped, [.left])
        XCTAssertEqual(
            ExerciseRelationshipManager.shared.resolverSnapshot().children(of: "Seated Row (Cable)").map(\.exerciseName),
            ["Custom Left Row", "Seated Row (Cable) - Right"]
        )
    }

    func testMuscleTagsAndCardioPreferencesInheritFromParentUnlessChildOverrides() {
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Extension (Machine) - Left",
            parentName: "Leg Extension (Machine)",
            laterality: .left
        )
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Stair Stepper - Left",
            parentName: "Stair Stepper",
            laterality: .left
        )

        XCTAssertEqual(
            ExerciseMetadataManager.shared.resolvedTags(for: "Leg Extension (Machine) - Left").compactMap(\.builtInGroup),
            [.quads]
        )

        ExerciseMetadataManager.shared.setTags(for: "Leg Extension (Machine) - Left", to: [.builtIn(.hamstrings)])
        XCTAssertEqual(
            ExerciseMetadataManager.shared.resolvedTags(for: "Leg Extension (Machine) - Left").compactMap(\.builtInGroup),
            [.hamstrings]
        )

        ExerciseMetricManager.shared.setCountLabel(for: "Stair Stepper", to: "floors")
        XCTAssertEqual(ExerciseMetricManager.shared.preferences(for: "Stair Stepper - Left").countLabel, "floors")

        ExerciseMetricManager.shared.setCountLabel(for: "Stair Stepper - Left", to: "steps")
        XCTAssertEqual(ExerciseMetricManager.shared.preferences(for: "Stair Stepper - Left").countLabel, "steps")
    }

    func testRecoveryCoverageUsesParentTagsForSideVariants() async {
        ExerciseRelationshipManager.shared.setRelationship(
            exerciseName: "Leg Extension (Machine) - Left",
            parentName: "Leg Extension (Machine)",
            laterality: .left
        )

        let workoutDate = Date()
        let workout = Workout(
            date: workoutDate,
            name: "Lower",
            duration: "30m",
            exercises: [
                Exercise(name: "Leg Extension (Machine) - Left", sets: [
                    WorkoutSet(
                        date: workoutDate,
                        workoutName: "Lower",
                        duration: "30m",
                        exerciseName: "Leg Extension (Machine) - Left",
                        setOrder: 1,
                        weight: 50,
                        reps: 10,
                        distance: 0,
                        seconds: 0
                    )
                ])
            ]
        )

        let engine = RecoveryCoverageEngine()
        await engine.analyze(
            workouts: [workout],
            healthStore: [:],
            dailyHealth: [:],
            muscleMappings: ["Leg Extension (Machine)": [.builtIn(.quads)]],
            intentionalBreakRanges: []
        )

        let quads = engine.frequencyInsights(for: .allTime).first { $0.muscleGroup == MuscleGroup.quads.displayName }
        XCTAssertEqual(quads?.weeksHit, 1)
    }

    private func makeDate(day: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = day
        components.hour = 9
        components.timeZone = TimeZone(identifier: "America/Denver")
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }

    private func workoutSet(
        date: Date,
        exerciseName: String,
        order: Int,
        weight: Double,
        reps: Int
    ) -> WorkoutSet {
        WorkoutSet(
            date: date,
            workoutName: "Lower",
            duration: "30m",
            exerciseName: exerciseName,
            setOrder: order,
            weight: weight,
            reps: reps,
            distance: 0,
            seconds: 0
        )
    }
}
