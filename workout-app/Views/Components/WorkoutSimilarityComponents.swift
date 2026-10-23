import SwiftUI

struct WorkoutSimilaritySection: View {
    let review: WorkoutSimilarityReview
    var onCompare: (WorkoutSimilarityMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(
                title: "Similar workouts",
                help: "Matches earlier workouts by shared exercises and exercise order."
            )

            if let bestMatch = review.bestMatch {
                MetricTileButton(chevronPlacement: .none, action: {
                    onCompare(bestMatch)
                }) {
                    WorkoutSimilarityBestMatchCard(match: bestMatch)
                }
            } else {
                WorkoutSimilarityEmptyState()
            }

            if !review.exactOrderMatches.isEmpty {
                WorkoutSimilarityMatchList(
                    title: "Same exercises, same order",
                    matches: review.exactOrderMatches,
                    onCompare: onCompare
                )
            }

            if !review.reorderedExerciseMatches.isEmpty {
                WorkoutSimilarityMatchList(
                    title: "Same exercises, different order",
                    matches: review.reorderedExerciseMatches,
                    onCompare: onCompare
                )
            }
        }
    }
}

private struct WorkoutSimilarityBestMatchCard: View {
    let match: WorkoutSimilarityMatch

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Closest earlier workout")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(SharedFormatters.workoutTitleParts(match.priorWorkoutName).title)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(match.priorWorkoutDate.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xl) {
                DisplayStat(value: "\(match.sharedExerciseCount)", label: "shared", valueFont: Theme.Typography.numberSmall)
                DisplayStat(value: "\(match.samePositionCount)", label: "same spot", valueFont: Theme.Typography.numberSmall)
                DisplayStat(value: "\(match.priorExerciseCount)", label: "exercises", valueFont: Theme.Typography.numberSmall)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Text("Compare")
                        .font(Theme.Typography.subheadlineStrong)
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.microLabel)
                }
                .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

}

private struct WorkoutSimilarityMatchList: View {
    let title: String
    let matches: [WorkoutSimilarityMatch]
    let onCompare: (WorkoutSimilarityMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: 0) {
                ForEach(matches) { match in
                    MetricTileButton(chevronPlacement: .none, action: {
                        onCompare(match)
                    }) {
                        WorkoutSimilarityMatchRow(match: match)
                    }
                }
            }
        }
    }
}

private struct WorkoutSimilarityMatchRow: View {
    let match: WorkoutSimilarityMatch

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.priorWorkoutDate.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("\(match.sharedExerciseCount) shared, \(match.samePositionCount) in the same spot")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Text("Compare")
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textPrimary)
                .underline()
        }
        .ledgerRow()
    }
}

private struct WorkoutSimilarityEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Nothing like this one in your history yet.")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .ledgerRow()
    }
}
