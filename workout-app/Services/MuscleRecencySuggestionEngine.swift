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

enum MuscleRecencySuggestionEngine {
    /// Returns suggestions sorted by most-neglected (largest `daysSince`) first.
    nonisolated static func suggestions(
        workouts: [Workout],
        muscleGroupsByExerciseName: [String: [MuscleGroup]],
        excluding alreadyCoveredGroups: Set<MuscleGroup> = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        maxGroups: Int = 3,
        maxOptionsPerGroup: Int = 6
    ) -> [MuscleGroupSuggestion] {
        guard !workouts.isEmpty else { return [] }

        var lastTrainedByGroup: [MuscleGroup: Date] = [:]
        var exerciseStatsByGroup: [MuscleGroup: [String: (last: Date, count: Int)]] = [:]

        for workout in workouts {
            for exercise in workout.exercises {
                let groups = muscleGroupsByExerciseName[exercise.name] ?? []
                guard !groups.isEmpty else { continue }

                for group in groups {
                    if alreadyCoveredGroups.contains(group) { continue }

                    if let existing = lastTrainedByGroup[group] {
                        if workout.date > existing { lastTrainedByGroup[group] = workout.date }
                    } else {
                        lastTrainedByGroup[group] = workout.date
                    }

                    var groupStats = exerciseStatsByGroup[group] ?? [:]
                    if let existing = groupStats[exercise.name] {
                        let last = max(existing.last, workout.date)
                        groupStats[exercise.name] = (last, existing.count + 1)
                    } else {
                        groupStats[exercise.name] = (workout.date, 1)
                    }
                    exerciseStatsByGroup[group] = groupStats
                }
            }
        }

        let groupSuggestions: [MuscleGroupSuggestion] = lastTrainedByGroup.compactMap { group, lastTrained in
            let start = calendar.startOfDay(for: lastTrained)
            let end = calendar.startOfDay(for: now)
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0

            let options: [SuggestedExerciseOption] = (exerciseStatsByGroup[group] ?? [:])
                .map { name, stat in
                    SuggestedExerciseOption(name: name, lastPerformed: stat.last, frequency: stat.count)
                }
                .sorted { lhs, rhs in
                    if lhs.lastPerformed != rhs.lastPerformed { return lhs.lastPerformed > rhs.lastPerformed }
                    if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }

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
}
