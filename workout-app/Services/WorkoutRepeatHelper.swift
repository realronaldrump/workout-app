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
        for exerciseName in workout.exercises.map(\.name) {
            let tags = ExerciseMetadataManager.shared.resolvedTags(for: exerciseName)
            let isCardio = tags.contains { $0.builtInGroup == .cardio }

            if isCardio {
                sessionManager.addExercise(name: exerciseName)
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
                sessionManager.addExercise(
                    name: exerciseName,
                    initialSetPrefill: SetPrefill(
                        weight: recommendation.suggestedWeight,
                        reps: midpointReps
                    )
                )
            }
        }

        sessionManager.isPresentingSessionUI = true
        Haptics.notify(.success)
    }
}
