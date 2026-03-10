import SwiftUI

struct WorkoutSimilaritySection: View {
    let review: WorkoutSimilarityReview
    var onCompare: (WorkoutSimilarityMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Workout Match")
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)

            if let bestMatch = review.bestMatch {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Best Prior Match")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    MetricTileButton(chevronPlacement: .none, action: {
                        onCompare(bestMatch)
                    }) {
                        WorkoutSimilarityBestMatchCard(match: bestMatch)
                    }
                }
            } else {
                WorkoutSimilarityEmptyState()
            }

            if !review.exactOrderMatches.isEmpty {
                WorkoutSimilarityMatchList(
                    title: "Exact Same Order",
                    matches: review.exactOrderMatches,
                    onCompare: onCompare
                )
            }

            if !review.reorderedExerciseMatches.isEmpty {
                WorkoutSimilarityMatchList(
                    title: "Same Exercises, Different Order",
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
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Label(match.kind.title, systemImage: match.kind.iconName)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)

                Spacer()

                Text(match.priorWorkoutDate.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.trailing)
            }

            Text(match.priorWorkoutName)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.sm) {
                WorkoutSimilarityInlinePill(
                    title: "Shared",
                    value: "\(match.sharedExerciseCount)"
                )
                WorkoutSimilarityInlinePill(
                    title: "Same Spot",
                    value: "\(match.samePositionCount)"
                )
                WorkoutSimilarityInlinePill(
                    title: "Exercises",
                    value: "\(match.priorExerciseCount)"
                )
            }

            HStack {
                Text(matchExplanation(match))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Spacer(minLength: Theme.Spacing.md)

                Text("Compare")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func matchExplanation(_ match: WorkoutSimilarityMatch) -> String {
        switch match.kind {
        case .exactOrdered:
            return "You previously ran this exact exercise sequence."
        case .exactExercisesReordered:
            return "You previously ran the same exercise lineup, but in a different order."
        case .partial:
            return "This earlier session is the closest overlap in your history."
        }
    }
}

private struct WorkoutSimilarityMatchList: View {
    let title: String
    let matches: [WorkoutSimilarityMatch]
    let onCompare: (WorkoutSimilarityMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)

            VStack(spacing: Theme.Spacing.sm) {
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
            Image(systemName: match.kind.iconName)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 30, height: 30)
                .background(Theme.Colors.accentTint)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))

            VStack(alignment: .leading, spacing: 4) {
                Text(match.priorWorkoutDate.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("\(match.sharedExerciseCount) shared • \(match.samePositionCount) same spot")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Text("Compare")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

private struct WorkoutSimilarityInlinePill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.microcopySmall)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }
}

private struct WorkoutSimilarityEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No prior overlap yet")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("No earlier workout shares any exercises with this session.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}
