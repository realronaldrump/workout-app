import Foundation
import UIKit

@MainActor
enum WorkoutRepeatHelper {
    enum Outcome: Equatable {
        case started
        case requiresActiveSessionReplacement
    }

    @discardableResult
    static func repeatWorkout(
        _ workout: Workout,
        gymProfileId: UUID?,
        weightIncrement: Double,
        sessionManager: WorkoutSessionManager,
        dataManager: WorkoutDataManager
    ) -> Outcome {
        guard sessionManager.activeSession == nil else {
            return .requiresActiveSessionReplacement
        }

        startWorkout(
            workout,
            gymProfileId: gymProfileId,
            weightIncrement: weightIncrement,
            sessionManager: sessionManager,
            dataManager: dataManager
        )
        return .started
    }

    static func replaceActiveSessionAndRepeat(
        _ workout: Workout,
        gymProfileId: UUID?,
        weightIncrement: Double,
        sessionManager: WorkoutSessionManager,
        dataManager: WorkoutDataManager
    ) async {
        guard await sessionManager.discardDraft() else { return }
        startWorkout(
            workout,
            gymProfileId: gymProfileId,
            weightIncrement: weightIncrement,
            sessionManager: sessionManager,
            dataManager: dataManager
        )
    }

    private static func startWorkout(
        _ workout: Workout,
        gymProfileId: UUID?,
        weightIncrement: Double,
        sessionManager: WorkoutSessionManager,
        dataManager: WorkoutDataManager
    ) {
        sessionManager.startSession(
            name: workout.name,
            gymProfileId: gymProfileId
        )

        // Repeat the actual sequence, including ramp-up loads and cardio metrics.
        // Suggestions are available in the logger, but must not rewrite past performance.
        for exercise in workout.exercises {
            let sourceSets = exercise.sets.sorted { $0.setOrder < $1.setOrder }
            let prefills = sourceSets.map {
                SetPrefill(weight: $0.weight, reps: $0.reps > 0 ? $0.reps : nil,
                           distance: $0.distance > 0 ? $0.distance : nil,
                           seconds: $0.seconds > 0 ? $0.seconds : nil)
            }
            let existingIds = Set(sessionManager.activeSession?.exercises.map(\.id) ?? [])
            sessionManager.addExercise(name: exercise.name, initialSetPrefill: prefills.first)
            guard let added = sessionManager.activeSession?.exercises.first(where: { !existingIds.contains($0.id) }) else {
                continue
            }
            for prefill in prefills.dropFirst() {
                sessionManager.addSet(exerciseId: added.id, prefill: prefill)
            }
        }
        sessionManager.saveImmediately()

        sessionManager.isPresentingSessionUI = true
        Haptics.notify(.success)
    }
}
