import XCTest
@testable import workout_app

final class ExerciseAnalysisEngineTests: XCTestCase {
    func testDirectoryVolumeRouteOnlyAppearsForSupportedStrengthVolume() {
        XCTAssertTrue(
            ExerciseDirectoryMetricPolicy.supportsSessionVolume(
                exerciseName: "Bench Press",
                isCardio: false,
                totalVolume: 1_250
            )
        )
        XCTAssertFalse(
            ExerciseDirectoryMetricPolicy.supportsSessionVolume(
                exerciseName: "Assisted Pull Up",
                isCardio: false,
                totalVolume: 400
            )
        )
        XCTAssertFalse(
            ExerciseDirectoryMetricPolicy.supportsSessionVolume(
                exerciseName: "Running (Treadmill)",
                isCardio: true,
                totalVolume: 0
            )
        )
        XCTAssertFalse(
            ExerciseDirectoryMetricPolicy.supportsSessionVolume(
                exerciseName: "Bench Press",
                isCardio: false,
                totalVolume: 0
            )
        )
    }

    func testDeltaPrefixDoesNotDoubleSignLoadMetrics() {
        XCTAssertEqual(
            ExerciseMetricDeltaFormatting.signPrefix(for: .maxLoad, value: 5),
            ""
        )
        XCTAssertEqual(
            ExerciseMetricDeltaFormatting.signPrefix(for: .estimatedOneRepMax, value: 5),
            ""
        )
        XCTAssertEqual(
            ExerciseMetricDeltaFormatting.signPrefix(for: .sessionVolume, value: 500),
            "+"
        )
        XCTAssertEqual(
            ExerciseMetricDeltaFormatting.signPrefix(for: .averageReps, value: -1),
            ""
        )
    }

    func testMaxLoadHistoryKeepsOnlyStrictMilestonesAndPreservesWorkoutSources() {
        let firstWorkoutID = UUID()
        let matchedWorkoutID = UUID()
        let finalWorkoutID = UUID()
        let sessions = [
            makeSession(day: 1, workoutID: firstWorkoutID, weights: [100, 95]),
            makeSession(day: 8, weights: [110, 105]),
            makeSession(day: 15, workoutID: matchedWorkoutID, weights: [110, 100]),
            makeSession(day: 22, weights: [108, 105]),
            makeSession(day: 29, workoutID: finalWorkoutID, weights: [120, 115])
        ]

        let analysis = ExerciseAnalysisEngine.analyze(
            exerciseName: "Bench Press",
            metric: .maxLoad,
            sessions: sessions
        )

        XCTAssertEqual(analysis.observations.map(\.value), [100, 110, 110, 108, 120])
        XCTAssertEqual(analysis.recordEvents.map(\.value), [100, 110, 120])
        XCTAssertEqual(analysis.recordEvents.map(\.source), [
            .workout(firstWorkoutID),
            .workout(sessions[1].workoutId),
            .workout(finalWorkoutID)
        ])
        XCTAssertEqual(analysis.matchedRecords.map(\.source), [.workout(matchedWorkoutID)])
    }

    func testAssistedLoadTreatsLowerAndZeroAssistanceAsBetter() {
        let sessions = [
            makeSession(day: 1, exerciseName: "Assisted Pull Up", weights: [50]),
            makeSession(day: 8, exerciseName: "Assisted Pull Up", weights: [40]),
            makeSession(day: 15, exerciseName: "Assisted Pull Up", weights: [40]),
            makeSession(day: 22, exerciseName: "Assisted Pull Up", weights: [0])
        ]

        let analysis = ExerciseAnalysisEngine.analyze(
            exerciseName: "Assisted Pull Up",
            metric: .maxLoad,
            sessions: sessions
        )

        XCTAssertEqual(analysis.direction, .lowerIsBetter)
        XCTAssertEqual(analysis.recordEvents.map(\.value), [50, 40, 0])
        XCTAssertEqual(analysis.matchedRecords.map(\.value), [40])
        XCTAssertEqual(analysis.headlineValue, 0)
    }

    func testSetVolumeUsesTheBestSetPerWorkoutAndKeepsItsLoadRepContext() {
        let workoutID = UUID()
        let session = makeSession(
            day: 1,
            workoutID: workoutID,
            sets: [(weight: 100, reps: 5), (weight: 90, reps: 10)]
        )

        let analysis = ExerciseAnalysisEngine.analyze(
            exerciseName: "Bench Press",
            metric: .setVolume,
            sessions: [session]
        )

        XCTAssertEqual(analysis.observations.map(\.value), [900])
        XCTAssertEqual(analysis.observations.first?.weight, 90)
        XCTAssertEqual(analysis.observations.first?.reps, 10)
        XCTAssertEqual(analysis.observations.first?.source, .workout(workoutID))
    }

    func testStrengthSessionProducesTheCanonicalSetRepVolumeAndOneRepMaxMetrics() {
        let session = makeSession(
            day: 1,
            sets: [(weight: 100, reps: 5), (weight: 90, reps: 10)]
        )

        let maxReps = analyze(.maxReps, sessions: [session])
        let estimatedOneRepMax = analyze(.estimatedOneRepMax, sessions: [session])
        let sessionVolume = analyze(.sessionVolume, sessions: [session])
        let averageReps = analyze(.averageReps, sessions: [session])
        let setCount = analyze(.setCount, sessions: [session])
        let sessions = analyze(.sessions, sessions: [session])

        XCTAssertEqual(maxReps.headlineValue, 10)
        XCTAssertEqual(maxReps.observations.first?.weight, 90)
        XCTAssertEqual(
            estimatedOneRepMax.headlineValue ?? 0,
            OneRepMax.estimate(weight: 90, reps: 10),
            accuracy: 0.001
        )
        XCTAssertEqual(sessionVolume.headlineValue, 1_400)
        XCTAssertEqual(averageReps.headlineValue, 7.5)
        XCTAssertEqual(setCount.headlineValue, 2)
        XCTAssertEqual(sessions.headlineValue, 1)
    }

    func testCardioMetricsExposeTotalsBestSessionsAndRecordProgressionWithoutInventingPace() {
        let firstWorkoutID = UUID()
        let secondWorkoutID = UUID()
        let sessions = [
            makeCardioSession(
                day: 1,
                workoutID: firstWorkoutID,
                measurements: [
                    (distance: 1.2, seconds: 600, count: 30),
                    (distance: 0.8, seconds: 300, count: 20)
                ]
            ),
            makeCardioSession(
                day: 8,
                workoutID: secondWorkoutID,
                measurements: [(distance: 3, seconds: 1_200, count: 40)]
            ),
            makeCardioSession(
                day: 15,
                measurements: [(distance: 0, seconds: 0, count: 0)]
            )
        ]

        let distance = analyze(.distance, exerciseName: "Running", sessions: sessions)
        let duration = analyze(.duration, exerciseName: "Running", sessions: sessions)
        let count = analyze(.count, exerciseName: "Running", sessions: sessions)

        XCTAssertEqual(distance.observations.map(\.value), [2, 3])
        XCTAssertEqual(distance.headlineValue, 5)
        XCTAssertEqual(distance.bestValue, 3)
        XCTAssertEqual(distance.recordEvents.map(\.value), [2, 3])
        XCTAssertEqual(duration.observations.map(\.value), [900, 1_200])
        XCTAssertEqual(duration.headlineValue, 2_100)
        XCTAssertEqual(count.observations.map(\.value), [50, 40])
        XCTAssertEqual(count.headlineValue, 90)
        XCTAssertEqual(count.recordEvents.map(\.source), [.workout(firstWorkoutID)])
        XCTAssertEqual(distance.topAttempts.first?.source, .workout(secondWorkoutID))
    }

    func testBodyweightAndRecentComparisonOnlyExposeMeaningfulEvidence() {
        let bodyweight = makeSession(
            day: 1,
            exerciseName: "Pull Up",
            sets: [(weight: 0, reps: 12)]
        )
        let weightedSessions = (1...10).map { index in
            makeSession(day: index, weights: [Double(99 + index)])
        }

        XCTAssertTrue(analyze(.maxLoad, exerciseName: "Pull Up", sessions: [bodyweight]).observations.isEmpty)
        XCTAssertTrue(
            analyze(.estimatedOneRepMax, exerciseName: "Pull Up", sessions: [bodyweight])
                .observations
                .isEmpty
        )
        XCTAssertEqual(
            analyze(.maxReps, exerciseName: "Pull Up", sessions: [bodyweight]).headlineValue,
            12
        )

        let load = analyze(.maxLoad, sessions: weightedSessions)
        XCTAssertEqual(load.recentComparison?.previousAverage, 102)
        XCTAssertEqual(load.recentComparison?.currentAverage, 107)
        XCTAssertEqual(load.recentComparison?.improvement, 5)
        XCTAssertEqual(load.topAttempts.map(\.value), Array(stride(from: 109, through: 100, by: -1)))
    }

    func testNeutralMetricsRankHighestAttemptsAndUseNewestAttemptToBreakTies() {
        let olderTieID = UUID()
        let newerTieID = UUID()
        let sessions = [
            makeSession(day: 1, sets: [(weight: 100, reps: 5)]),
            makeSession(day: 8, workoutID: olderTieID, sets: [(weight: 100, reps: 10)]),
            makeSession(day: 15, workoutID: newerTieID, sets: [(weight: 100, reps: 10)])
        ]

        let analysis = analyze(.averageReps, sessions: sessions)

        XCTAssertEqual(analysis.bestValue, 10)
        XCTAssertEqual(analysis.topAttempts.map(\.value), [10, 10, 5])
        XCTAssertEqual(analysis.topAttempts.first?.source, .workout(newerTieID))
        XCTAssertEqual(analysis.topAttempts.dropFirst().first?.source, .workout(olderTieID))
    }

    func testSelectedRangeFiltersEvidenceAndRankingWithoutChangingAllTimeHeadline() {
        let sessions = [
            makeSession(day: 1, weights: [100]),
            makeSession(day: 8, weights: [110]),
            makeSession(day: 15, weights: [105]),
            makeSession(day: 22, weights: [120]),
            makeSession(day: 29, weights: [130])
        ]
        let analysis = analyze(.maxLoad, sessions: sessions)
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 8)) ?? .distantPast
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 23)) ?? .distantFuture

        let slice = analysis.slice(in: DateInterval(start: start, end: end))

        XCTAssertEqual(analysis.headlineValue, 130)
        XCTAssertEqual(slice.observations.map(\.value), [110, 105, 120])
        XCTAssertEqual(slice.recordEvents.map(\.value), [110, 120])
        XCTAssertEqual(slice.topAttempts.map(\.value), [120, 110, 105])
        XCTAssertEqual(slice.bestValue, 120)
    }

    func testMissingNegativeAndNonFiniteCardioFieldsAreExcludedIndependently() {
        let distanceOnly = makeCardioSession(
            day: 1,
            measurements: [(distance: 2, seconds: 0, count: 0)]
        )
        let durationAndCountOnly = makeCardioSession(
            day: 8,
            measurements: [(distance: 0, seconds: 600, count: 12)]
        )
        let invalid = makeCardioSession(
            day: 15,
            measurements: [(distance: .nan, seconds: .infinity, count: -4)]
        )
        let sessions = [distanceOnly, durationAndCountOnly, invalid]

        XCTAssertEqual(analyze(.distance, exerciseName: "Running", sessions: sessions).observations.map(\.value), [2])
        XCTAssertEqual(analyze(.duration, exerciseName: "Running", sessions: sessions).observations.map(\.value), [600])
        XCTAssertEqual(analyze(.count, exerciseName: "Running", sessions: sessions).observations.map(\.value), [12])
    }

    func testReanalysisRewritesRecordsAfterSourceWorkoutEditAndDeletion() {
        let firstID = UUID()
        let editedID = UUID()
        let first = makeSession(day: 1, workoutID: firstID, weights: [100])
        let original = makeSession(day: 8, workoutID: editedID, weights: [120])
        let edited = makeSession(day: 8, workoutID: editedID, weights: [90])

        XCTAssertEqual(analyze(.maxLoad, sessions: [first, original]).recordEvents.map(\.value), [100, 120])

        let afterEdit = analyze(.maxLoad, sessions: [first, edited])
        XCTAssertEqual(afterEdit.headlineValue, 100)
        XCTAssertEqual(afterEdit.recordEvents.map(\.source), [.workout(firstID)])

        let afterDelete = analyze(.maxLoad, sessions: [edited])
        XCTAssertEqual(afterDelete.headlineValue, 90)
        XCTAssertEqual(afterDelete.recordEvents.map(\.source), [.workout(editedID)])
    }

    func testCacheSeparatesExactVariantAndGymScopesAndInvalidatesChangedSessions() async {
        let leftGymID = UUID()
        let rightGymID = UUID()
        let leftScope = ExerciseAnalysisScope(
            exerciseName: "Single Arm Row",
            performanceTrackName: "Single Arm Row - Left",
            gym: .gym(leftGymID)
        )
        let rightScope = ExerciseAnalysisScope(
            exerciseName: "Single Arm Row",
            performanceTrackName: "Single Arm Row - Right",
            gym: .gym(rightGymID)
        )
        let leftSessions = [makeSession(day: 1, exerciseName: leftScope.performanceTrackName, weights: [45])]
        let rightSessions = [makeSession(day: 1, exerciseName: rightScope.performanceTrackName, weights: [70])]

        let left = await ExerciseAnalysisCache.shared.analysis(
            datasetRevision: 9001,
            scope: leftScope,
            metric: .maxLoad,
            sessions: leftSessions
        )
        let right = await ExerciseAnalysisCache.shared.analysis(
            datasetRevision: 9001,
            scope: rightScope,
            metric: .maxLoad,
            sessions: rightSessions
        )
        let editedLeft = await ExerciseAnalysisCache.shared.analysis(
            datasetRevision: 9001,
            scope: leftScope,
            metric: .maxLoad,
            sessions: [makeSession(day: 1, exerciseName: leftScope.performanceTrackName, weights: [55])]
        )

        XCTAssertEqual(left.headlineValue, 45)
        XCTAssertEqual(right.headlineValue, 70)
        XCTAssertEqual(editedLeft.headlineValue, 55)
    }

    func testLongHistoryAnalysisRemainsLinearAndSourceComplete() {
        let sessions = (0..<5_000).map { index in
            makeSession(offsetDays: index, weights: [Double(100 + index % 250)])
        }
        let start = ProcessInfo.processInfo.systemUptime

        let analysis = analyze(.maxLoad, sessions: sessions)
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        XCTAssertEqual(analysis.observations.count, 5_000)
        XCTAssertEqual(analysis.topAttempts.count, 10)
        XCTAssertTrue(analysis.observations.allSatisfy { observation in
            if case .workout = observation.source { return true }
            return false
        })
        XCTAssertLessThan(elapsed, 5, "A 5,000-session history should remain comfortably interactive")
    }

    private func makeSession(
        day: Int,
        workoutID: UUID = UUID(),
        exerciseName: String = "Bench Press",
        weights: [Double]
    ) -> ExerciseHistorySession {
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 1, day: day, hour: 8)
        ) ?? .distantPast
        return ExerciseHistorySession(
            workoutId: workoutID,
            date: date,
            sets: weights.enumerated().map { index, weight in
                WorkoutSet(
                    date: date,
                    workoutName: "Upper",
                    duration: "45m",
                    exerciseName: exerciseName,
                    setOrder: index + 1,
                    weight: weight,
                    reps: 5,
                    distance: 0,
                    seconds: 0
                )
            }
        )
    }

    private func analyze(
        _ metric: ExerciseAnalysisMetric,
        exerciseName: String = "Bench Press",
        sessions: [ExerciseHistorySession]
    ) -> ExerciseMetricAnalysis {
        ExerciseAnalysisEngine.analyze(
            exerciseName: exerciseName,
            metric: metric,
            sessions: sessions
        )
    }

    private func makeSession(
        day: Int,
        workoutID: UUID = UUID(),
        exerciseName: String = "Bench Press",
        sets: [(weight: Double, reps: Int)]
    ) -> ExerciseHistorySession {
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 1, day: day, hour: 8)
        ) ?? .distantPast
        return ExerciseHistorySession(
            workoutId: workoutID,
            date: date,
            sets: sets.enumerated().map { index, values in
                WorkoutSet(
                    date: date,
                    workoutName: "Upper",
                    duration: "45m",
                    exerciseName: exerciseName,
                    setOrder: index + 1,
                    weight: values.weight,
                    reps: values.reps,
                    distance: 0,
                    seconds: 0
                )
            }
        )
    }

    private func makeCardioSession(
        day: Int,
        workoutID: UUID = UUID(),
        measurements: [(distance: Double, seconds: Double, count: Int)]
    ) -> ExerciseHistorySession {
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 1, day: day, hour: 8)
        ) ?? .distantPast
        return ExerciseHistorySession(
            workoutId: workoutID,
            date: date,
            sets: measurements.enumerated().map { index, values in
                WorkoutSet(
                    date: date,
                    workoutName: "Cardio",
                    duration: "30m",
                    exerciseName: "Running",
                    setOrder: index + 1,
                    weight: 0,
                    reps: values.count,
                    distance: values.distance,
                    seconds: values.seconds
                )
            }
        )
    }

    private func makeSession(
        offsetDays: Int,
        exerciseName: String = "Bench Press",
        weights: [Double]
    ) -> ExerciseHistorySession {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(
            from: DateComponents(year: 2000, month: 1, day: 1, hour: 8)
        ) ?? .distantPast
        let date = calendar.date(byAdding: .day, value: offsetDays, to: start) ?? start
        let workoutID = UUID()
        return ExerciseHistorySession(
            workoutId: workoutID,
            date: date,
            sets: weights.enumerated().map { index, weight in
                WorkoutSet(
                    date: date,
                    workoutName: "Long History",
                    duration: "45m",
                    exerciseName: exerciseName,
                    setOrder: index + 1,
                    weight: weight,
                    reps: 5,
                    distance: 0,
                    seconds: 0
                )
            }
        )
    }
}
