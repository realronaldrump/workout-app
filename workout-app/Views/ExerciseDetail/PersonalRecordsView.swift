import SwiftUI

struct PersonalRecordsView: View {
    let exerciseName: String
    let history: [(date: Date, sets: [WorkoutSet])]
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared

    private struct PersonalRecord: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let date: Date
    }

    private struct CardioSessionMetrics {
        let date: Date
        let distance: Double
        let seconds: Double
        let repCount: Int
    }

    private var isCardio: Bool {
        metadataManager
            .resolvedTags(for: exerciseName)
            .contains(where: { $0.builtInGroup == .cardio })
    }

    private var cardioConfig: ResolvedCardioMetricConfiguration {
        let sets = history.flatMap(\.sets)
        return metricManager.resolvedCardioConfiguration(for: exerciseName, historySets: sets)
    }

    private var isAssisted: Bool {
        ExerciseLoad.isAssistedExercise(exerciseName)
    }

    private var records: [PersonalRecord] {
        if isCardio {
            let sessions: [CardioSessionMetrics] = history.map { session in
                let distance = session.sets.reduce(0.0) { $0 + $1.distance }
                let seconds = session.sets.reduce(0.0) { $0 + $1.seconds }
                let repCount = session.sets.reduce(0) { $0 + $1.reps }
                return CardioSessionMetrics(date: session.date, distance: distance, seconds: seconds, repCount: repCount)
            }

            var records: [PersonalRecord] = []

            if let bestDistance = sessions.max(by: { $0.distance < $1.distance }), bestDistance.distance > 0 {
                records.append(PersonalRecord(
                    title: "Longest Distance",
                    value: "\(WorkoutValueFormatter.distanceText(bestDistance.distance)) dist",
                    date: bestDistance.date
                ))
            }

            if let bestTime = sessions.max(by: { $0.seconds < $1.seconds }), bestTime.seconds > 0 {
                records.append(PersonalRecord(
                    title: "Longest Time",
                    value: WorkoutValueFormatter.durationText(seconds: bestTime.seconds),
                    date: bestTime.date
                ))
            }

            if let bestCount = sessions.max(by: { $0.repCount < $1.repCount }), bestCount.repCount > 0 {
                records.append(PersonalRecord(
                    title: "Most \(cardioConfig.countLabel)",
                    value: "\(bestCount.repCount) \(cardioConfig.countLabel)",
                    date: bestCount.date
                ))
            }

            return records
        } else {
            let allSets = history.flatMap { session in
                session.sets.map { (set: $0, date: session.date) }
            }

            var records: [PersonalRecord] = []

            let bestWeightSet = allSets.max(by: { lhs, rhs in
                ExerciseLoad.comparisonValue(for: lhs.set.weight, exerciseName: exerciseName) <
                ExerciseLoad.comparisonValue(for: rhs.set.weight, exerciseName: exerciseName)
            })
            if let bestWeightSet {
                records.append(PersonalRecord(
                    title: ExerciseLoad.weightRecordTitle(for: exerciseName),
                    value: "\(ExerciseLoad.formatWeight(bestWeightSet.set.weight, exerciseName: exerciseName)) × \(bestWeightSet.set.reps)",
                    date: bestWeightSet.date
                ))
            }

            if !isAssisted,
               let maxVolumeSet = allSets.max(by: {
                   $0.set.weight * Double($0.set.reps) < $1.set.weight * Double($1.set.reps)
               }) {
                let volume = maxVolumeSet.set.weight * Double(maxVolumeSet.set.reps)
                records.append(PersonalRecord(title: "Max Volume (Single Set)", value: "\(Int(volume)) lbs", date: maxVolumeSet.date))
            }

            if let maxRepsSet = allSets.max(by: { $0.set.reps < $1.set.reps }) {
                records.append(PersonalRecord(
                    title: "Most Reps",
                    value: "\(maxRepsSet.set.reps) @ \(ExerciseLoad.formatWeight(maxRepsSet.set.weight, exerciseName: exerciseName))",
                    date: maxRepsSet.date
                ))
            }

            if let best1RM = allSets.max(by: { lhs, rhs in
                OneRepMax.comparisonValue(
                    weight: lhs.set.weight,
                    reps: lhs.set.reps,
                    exerciseName: exerciseName
                ) <
                OneRepMax.comparisonValue(
                    weight: rhs.set.weight,
                    reps: rhs.set.reps,
                    exerciseName: exerciseName
                )
            }) {
                let orm = OneRepMax.estimate(
                    weight: best1RM.set.weight,
                    reps: best1RM.set.reps,
                    exerciseName: exerciseName
                )
                records.append(
                    PersonalRecord(
                        title: ExerciseLoad.oneRepMaxTitle(for: exerciseName),
                        value: ExerciseLoad.formatWeight(orm, exerciseName: exerciseName),
                        date: best1RM.date
                    )
                )
            }

            return records
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Personal Records")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(records) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title)
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.textSecondary)
                            Text(record.value)
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }

                        Spacer()

                        Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
                }
            }
        }
    }
}
