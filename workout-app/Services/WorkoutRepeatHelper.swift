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
        await sessionManager.discardDraft()
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

        let increment = weightIncrement > 0 ? weightIncrement : 2.5
        for exercise in workout.exercises {
            let exerciseName = exercise.name
            let tags = ExerciseMetadataManager.shared.resolvedTags(for: exerciseName)
            let isCardio = tags.contains { $0.builtInGroup == .cardio }
            // Recreate the same number of sets as the original workout (within reason) so a
            // repeated session doesn't need every set re-added by hand.
            let setCount = min(max(exercise.sets.count, 1), 10)

            let prefill: SetPrefill
            if isCardio {
                prefill = SetPrefill()
            } else {
                let history = dataManager.getExerciseHistory(for: exerciseName)
                let recommendation = ExerciseRecommendationEngine.recommend(
                    exerciseName: exerciseName,
                    history: history,
                    weightIncrement: increment
                )
                let midpointReps = (
                    recommendation.repRange.lowerBound + recommendation.repRange.upperBound
                ) / 2
                prefill = SetPrefill(
                    weight: recommendation.suggestedWeight,
                    reps: midpointReps
                )
            }

            let existingIds = Set(sessionManager.activeSession?.exercises.map(\.id) ?? [])
            sessionManager.addExercise(
                name: exerciseName,
                initialSetPrefill: isCardio ? nil : prefill
            )
            guard setCount > 1,
                  let added = sessionManager.activeSession?.exercises.first(where: { !existingIds.contains($0.id) }) else {
                continue
            }
            for _ in 1..<setCount {
                sessionManager.addSet(exerciseId: added.id, prefill: prefill)
            }
        }

        sessionManager.isPresentingSessionUI = true
        Haptics.notify(.success)
    }
}
