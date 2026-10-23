import Foundation

/// Per-analysis evidence shared by the insight detectors. Each workout's hierarchy
/// is aggregated once; exact performance tracks remain separate from parent totals.
nonisolated struct WorkoutInsightsIndex: Sendable {
    struct AggregateSession: Sendable {
        let workoutID: UUID
        let date: Date
        let volume: Double
    }

    let performanceTrackNames: [String]
    let historyByPerformanceTrack: [String: [ExerciseHistorySession]]
    let aggregateSessionsByName: [String: [AggregateSession]]
    let totalVolume: Double

    init(workouts: [Workout], resolver: ExerciseIdentityResolver) {
        let names = Set(workouts.flatMap { workout in
            workout.exercises.map { resolver.performanceTrackName(for: $0.name) }
        }.filter { !ExerciseIdentityResolver.trimmedName($0).isEmpty })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        performanceTrackNames = names

        // Match the history API's localized case-insensitive identity exactly,
        // while preserving each original display name used by existing insights.
        var canonicalByName: [String: String] = [:]
        var previousCanonical: String?
        for name in names {
            if let previousCanonical,
               previousCanonical.localizedCaseInsensitiveCompare(name) == .orderedSame {
                canonicalByName[name] = previousCanonical
            } else {
                canonicalByName[name] = name
                previousCanonical = name
            }
        }

        var histories: [String: [ExerciseHistorySession]] = [:]
        var aggregateSessions: [String: [AggregateSession]] = [:]
        var volume = 0.0
        for workout in workouts {
            guard !Task.isCancelled else { break }
            var setsByTrack: [String: [WorkoutSet]] = [:]
            for exercise in workout.exercises {
                let name = resolver.performanceTrackName(for: exercise.name)
                guard let canonical = canonicalByName[name] else { continue }
                setsByTrack[canonical, default: []].append(contentsOf: exercise.sets)
            }
            for (track, sets) in setsByTrack {
                histories[track, default: []].append(ExerciseHistorySession(
                    workoutId: workout.id,
                    date: workout.date,
                    sets: sets.sorted { lhs, rhs in
                        if lhs.setOrder != rhs.setOrder { return lhs.setOrder < rhs.setOrder }
                        return lhs.date < rhs.date
                    }
                ))
            }

            let exercises = ExerciseAggregation.aggregateExercises(in: workout, resolver: resolver)
            var workoutVolume = 0.0
            for exercise in exercises {
                let exerciseVolume = exercise.totalVolume
                workoutVolume += exerciseVolume
                aggregateSessions[exercise.name, default: []].append(AggregateSession(
                    workoutID: workout.id,
                    date: workout.date,
                    volume: exerciseVolume
                ))
            }
            volume += workoutVolume
        }

        histories = histories.mapValues { $0.sorted { $0.date < $1.date } }
        historyByPerformanceTrack = Dictionary(uniqueKeysWithValues: names.map { name in
            (name, histories[canonicalByName[name] ?? name] ?? [])
        })
        aggregateSessionsByName = aggregateSessions.mapValues { $0.sorted { $0.date < $1.date } }
        totalVolume = volume
    }
}
