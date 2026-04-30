import Foundation

struct SuggestedExerciseOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let lastPerformed: Date
    let frequency: Int

    nonisolated init(name: String, lastPerformed: Date, frequency: Int) {
        self.id = name
        self.name = name
        self.lastPerformed = lastPerformed
        self.frequency = frequency
    }
}

struct MuscleGroupSuggestion: Identifiable, Hashable, Sendable {
    var id: String { group.rawValue }
    let group: MuscleGroup
    let lastTrained: Date
    let daysSince: Int
    let options: [SuggestedExerciseOption]
}

struct MuscleGroupRecency: Identifiable, Hashable, Sendable {
    var id: String { group.rawValue }
    let group: MuscleGroup
    let lastTrained: Date?
    let daysSince: Int?
    let lastExercise: SuggestedExerciseOption?
}

enum MuscleRecencySuggestionEngine {
    /// Returns suggestions sorted by most-neglected (largest `daysSince`) first.
    nonisolated static func suggestions(
        workouts: [Workout],
        muscleGroupsByExerciseName: [String: [MuscleGroup]],
        excluding alreadyCoveredGroups: Set<MuscleGroup> = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        maxGroups: Int = 3,
        maxOptionsPerGroup: Int = 6,
        resolver: ExerciseIdentityResolver = .empty
    ) -> [MuscleGroupSuggestion] {
        guard !workouts.isEmpty else { return [] }

        let aggregated = aggregate(
            workouts: workouts,
            muscleGroupsByExerciseName: muscleGroupsByExerciseName,
            excluding: alreadyCoveredGroups,
            resolver: resolver
        )
        let lastTrainedByGroup = aggregated.lastTrainedByGroup
        let exerciseStatsByGroup = aggregated.exerciseStatsByGroup

        let groupSuggestions: [MuscleGroupSuggestion] = lastTrainedByGroup.compactMap { group, lastTrained in
            let start = calendar.startOfDay(for: lastTrained)
            let end = calendar.startOfDay(for: now)
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0

            let options = sortedExerciseOptions(for: group, from: exerciseStatsByGroup)

            return MuscleGroupSuggestion(
                group: group,
                lastTrained: lastTrained,
                daysSince: max(0, days),
                options: Array(options.prefix(maxOptionsPerGroup))
            )
        }

        return groupSuggestions
            .sorted { lhs, rhs in
                if lhs.daysSince != rhs.daysSince { return lhs.daysSince > rhs.daysSince }
                return lhs.group.displayName.localizedCaseInsensitiveCompare(rhs.group.displayName) == .orderedAscending
            }
            .prefix(maxGroups)
            .map { $0 }
    }

    nonisolated static func allGroupRecency(
        workouts: [Workout],
        muscleGroupsByExerciseName: [String: [MuscleGroup]],
        now: Date = Date(),
        calendar: Calendar = .current,
        resolver: ExerciseIdentityResolver = .empty
    ) -> [MuscleGroupRecency] {
        let aggregated = aggregate(
            workouts: workouts,
            muscleGroupsByExerciseName: muscleGroupsByExerciseName,
            resolver: resolver
        )

        return MuscleGroup.allCases
            .map { group in
                let lastTrained = aggregated.lastTrainedByGroup[group]
                let daysSince: Int?
                if let lastTrained {
                    let start = calendar.startOfDay(for: lastTrained)
                    let end = calendar.startOfDay(for: now)
                    let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
                    daysSince = max(0, days)
                } else {
                    daysSince = nil
                }

                return MuscleGroupRecency(
                    group: group,
                    lastTrained: lastTrained,
                    daysSince: daysSince,
                    lastExercise: sortedExerciseOptions(for: group, from: aggregated.exerciseStatsByGroup).first
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.daysSince, rhs.daysSince) {
                case let (left?, right?):
                    if left != right { return left > right }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }

                return lhs.group.displayName.localizedCaseInsensitiveCompare(rhs.group.displayName) == .orderedAscending
            }
    }

    nonisolated private static func sortedExerciseOptions(
        for group: MuscleGroup,
        from exerciseStatsByGroup: [MuscleGroup: [String: (last: Date, count: Int)]]
    ) -> [SuggestedExerciseOption] {
        (exerciseStatsByGroup[group] ?? [:])
            .map { name, stat in
                SuggestedExerciseOption(name: name, lastPerformed: stat.last, frequency: stat.count)
            }
            .sorted { lhs, rhs in
                if lhs.lastPerformed != rhs.lastPerformed { return lhs.lastPerformed > rhs.lastPerformed }
                if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    nonisolated private static func aggregate(
        workouts: [Workout],
        muscleGroupsByExerciseName: [String: [MuscleGroup]],
        excluding: Set<MuscleGroup> = [],
        resolver: ExerciseIdentityResolver
    ) -> (lastTrainedByGroup: [MuscleGroup: Date], exerciseStatsByGroup: [MuscleGroup: [String: (last: Date, count: Int)]]) {
        var lastTrainedByGroup: [MuscleGroup: Date] = [:]
        var exerciseStatsByGroup: [MuscleGroup: [String: (last: Date, count: Int)]] = [:]

        for workout in workouts {
            for exercise in ExerciseAggregation.aggregateExercises(in: workout, resolver: resolver) {
                let aggregateName = exercise.name
                let groups = muscleGroupsByExerciseName[exercise.name]
                    ?? muscleGroupsByExerciseName[aggregateName]
                    ?? []
                guard !groups.isEmpty else { continue }

                for group in groups {
                    if excluding.contains(group) { continue }

                    if let existing = lastTrainedByGroup[group] {
                        if workout.date > existing { lastTrainedByGroup[group] = workout.date }
                    } else {
                        lastTrainedByGroup[group] = workout.date
                    }

                    var groupStats = exerciseStatsByGroup[group] ?? [:]
                    if let existing = groupStats[aggregateName] {
                        let last = max(existing.last, workout.date)
                        groupStats[aggregateName] = (last, existing.count + 1)
                    } else {
                        groupStats[aggregateName] = (workout.date, 1)
                    }
                    exerciseStatsByGroup[group] = groupStats
                }
            }
        }

        return (lastTrainedByGroup, exerciseStatsByGroup)
    }
}
