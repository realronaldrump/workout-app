import XCTest
@testable import workout_app

@MainActor
final class WorkoutFinishTests: XCTestCase {
    private struct PersistenceFailure: Error {}

    func testFinishPersistsBeforeClearingDraft() async throws {
        let (manager, draftURL) = makeManager()
        let sessionID = try XCTUnwrap(manager.activeSession?.id)
        var persistedWorkout: LoggedWorkout?

        let finished = try await manager.finish { workout in
            XCTAssertTrue(manager.isFinishing)
            XCTAssertEqual(manager.activeSession?.id, sessionID)
            XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))
            persistedWorkout = workout
        }

        XCTAssertEqual(finished, persistedWorkout)
        XCTAssertEqual(finished.id, sessionID)
        XCTAssertEqual(finished.exercises.first?.sets.first?.weight, 100)
        XCTAssertNil(manager.activeSession)
        XCTAssertFalse(manager.isFinishing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path))
    }

    func testFailedPersistenceRetainsDraftAndAllowsRetry() async throws {
        let (manager, draftURL) = makeManager()
        let original = manager.activeSession

        do {
            _ = try await manager.finish { _ in throw PersistenceFailure() }
            XCTFail("Expected persistence to fail")
        } catch is PersistenceFailure {
            // The original error must reach the caller without ending the session.
        }

        XCTAssertEqual(manager.activeSession, original)
        XCTAssertFalse(manager.isFinishing)
        XCTAssertEqual(try readDraft(at: draftURL).id, original?.id)

        let finished = try await manager.finish { _ in }
        XCTAssertEqual(finished.id, original?.id)
        XCTAssertNil(manager.activeSession)
        XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path))
    }

    func testFinishPreservesSetEditsMadeDuringPersistence() async throws {
        let (manager, draftURL) = makeManager()
        let exercise = try XCTUnwrap(manager.activeSession?.exercises.first)
        let set = try XCTUnwrap(exercise.sets.first)
        var persistedWeight: Double?

        do {
            _ = try await manager.finish { workout in
                persistedWeight = workout.exercises.first?.sets.first?.weight
                manager.updateSet(
                    exerciseId: exercise.id,
                    setId: set.id,
                    prefill: SetPrefill(weight: 120, reps: 8)
                )
            }
            XCTFail("Expected the changed session to remain open")
        } catch WorkoutSessionError.sessionChangedWhileSaving {
            // The saved snapshot must not discard edits that arrived during the write.
        }

        XCTAssertEqual(persistedWeight, 100)
        XCTAssertEqual(manager.activeSession?.exercises.first?.sets.first?.weight, 120)
        XCTAssertEqual(try readDraft(at: draftURL).exercises.first?.sets.first?.weight, 120)
        XCTAssertFalse(manager.isFinishing)
    }

    func testFinishPreservesRenamesMadeDuringPersistence() async throws {
        let (manager, draftURL) = makeManager()

        do {
            _ = try await manager.finish { _ in manager.updateSessionName("Updated Workout") }
            XCTFail("Expected the renamed session to remain open")
        } catch WorkoutSessionError.sessionChangedWhileSaving {
            // Protect the entire session snapshot, including non-set edits.
        }

        XCTAssertEqual(manager.activeSession?.name, "Updated Workout")
        XCTAssertEqual(try readDraft(at: draftURL).name, "Updated Workout")
        XCTAssertFalse(manager.isFinishing)
    }

    func testFinishPreservesReplacementSessionAndItsRestTimer() async throws {
        let (manager, draftURL) = makeManager()
        let oldSessionID = manager.activeSession?.id

        do {
            _ = try await manager.finish { _ in
                manager.startSession(name: "Replacement", gymProfileId: nil)
                manager.startRestTimer()
            }
            XCTFail("Expected the replacement session to remain open")
        } catch WorkoutSessionError.sessionChangedWhileSaving {
            // Completion of the old save must leave the new session's timer alone.
        }

        XCTAssertEqual(manager.activeSession?.name, "Replacement")
        XCTAssertNotEqual(manager.activeSession?.id, oldSessionID)
        XCTAssertEqual(try readDraft(at: draftURL).id, manager.activeSession?.id)
        XCTAssertTrue(manager.restTimerIsActive)
        XCTAssertFalse(manager.isFinishing)
        manager.cancelRestTimer()
    }

    func testFinishDoesNotDeleteAnotherSessionsDraft() async throws {
        let (manager, draftURL) = makeManager()
        let replacement = ActiveWorkoutSession(name: "Replacement on disk")

        _ = try await manager.finish { _ in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(replacement).write(to: draftURL, options: .atomic)
        }

        XCTAssertNil(manager.activeSession)
        XCTAssertEqual(try readDraft(at: draftURL).id, replacement.id)
    }

    func testConcurrentFinishDoesNotPersistTwice() async throws {
        let (manager, _) = makeManager()
        var writeCount = 0

        _ = try await manager.finish { _ in
            writeCount += 1
            do {
                _ = try await manager.finish { _ in writeCount += 1 }
                XCTFail("Expected the second finish to be rejected")
            } catch WorkoutSessionError.finishInProgress {
                // The manager owns the lock even when two views attempt to finish.
            }
        }

        XCTAssertEqual(writeCount, 1)
        XCTAssertFalse(manager.isFinishing)
    }

    func testNoCompletedSetsNeverStartsPersistence() async throws {
        let (manager, _) = makeManager()
        let originalID = manager.activeSession?.id
        manager.activeSession?.exercises[0].sets[0].isCompleted = false
        var didPersist = false

        do {
            _ = try await manager.finish { _ in didPersist = true }
            XCTFail("Expected validation to fail")
        } catch WorkoutSessionError.noCompletedSets {
            // Validation happens before persistence or the finishing state begins.
        }

        XCTAssertFalse(didPersist)
        XCTAssertFalse(manager.isFinishing)
        XCTAssertEqual(manager.activeSession?.id, originalID)
    }

    private func makeManager() -> (WorkoutSessionManager, URL) {
        let draftURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutFinishTests-\(UUID().uuidString).json")
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: draftURL.path) {
                try FileManager.default.removeItem(at: draftURL)
            }
        }
        let manager = WorkoutSessionManager(draftURL: draftURL)
        manager.startSession(
            name: "Workout",
            gymProfileId: nil,
            preselectedExercise: "Bench Press",
            initialSetPrefill: SetPrefill(weight: 100, reps: 8)
        )
        manager.markIncompleteSetsWithEnteredDataCompleted()
        manager.saveImmediately()
        return (manager, draftURL)
    }

    private func readDraft(at url: URL) throws -> ActiveWorkoutSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ActiveWorkoutSession.self, from: Data(contentsOf: url))
    }
}
