import SwiftUI

struct WorkoutSimilarityComparisonSelection: Identifiable, Hashable {
    let selectedWorkoutId: UUID
    let priorWorkoutId: UUID

    var id: String {
        WorkoutSimilarityEngine.comparisonKey(
            selectedWorkoutId: selectedWorkoutId,
            priorWorkoutId: priorWorkoutId
        )
    }
}

struct WorkoutSimilarityCompareView: View {
    let selection: WorkoutSimilarityComparisonSelection

    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var similarityEngine: WorkoutSimilarityEngine

    private let maxContentWidth: CGFloat = 820

    private var selectedWorkout: Workout? {
        dataManager.workouts.first(where: { $0.id == selection.selectedWorkoutId })
    }

    private var priorWorkout: Workout? {
        dataManager.workouts.first(where: { $0.id == selection.priorWorkoutId })
    }

    private var comparison: WorkoutSimilarityComparison? {
        similarityEngine.comparison(
            selectedWorkoutId: selection.selectedWorkoutId,
            priorWorkoutId: selection.priorWorkoutId
        )
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    if let selectedWorkout, let priorWorkout, let comparison {
                        header(selectedWorkout: selectedWorkout, priorWorkout: priorWorkout)
                        summarySection(comparison: comparison)
                        comparisonRowsSection(rows: comparison.rows)
                    } else {
                        unavailableState
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Workout Match")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(selectedWorkout: Workout, priorWorkout: Workout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Compare Sessions")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.5)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    workoutHeaderCard(title: "Selected", workout: selectedWorkout)
                    workoutHeaderCard(title: "Prior Match", workout: priorWorkout)
                }

                VStack(spacing: Theme.Spacing.md) {
                    workoutHeaderCard(title: "Selected", workout: selectedWorkout)
                    workoutHeaderCard(title: "Prior Match", workout: priorWorkout)
                }
            }
        }
    }

    private func workoutHeaderCard(title: String, workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)

            Text(workout.name)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func summarySection(comparison: WorkoutSimilarityComparison) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Summary")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    summaryPill(title: "Match", value: comparison.kind.title)
                    summaryPill(title: "Shared", value: "\(comparison.sharedExerciseCount)")
                    summaryPill(title: "Same Position", value: "\(comparison.samePositionCount)")
                }

                VStack(spacing: Theme.Spacing.sm) {
                    summaryPill(title: "Match", value: comparison.kind.title)
                    HStack(spacing: Theme.Spacing.md) {
                        summaryPill(title: "Shared", value: "\(comparison.sharedExerciseCount)")
                        summaryPill(title: "Same Position", value: "\(comparison.samePositionCount)")
                    }
                }
            }
        }
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text(value)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }

    private func comparisonRowsSection(rows: [WorkoutSimilarityComparisonRow]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Exercise Order")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if rows.isEmpty {
                unavailableState
            } else {
                ForEach(rows) { row in
                    WorkoutSimilarityComparisonRowCard(row: row)
                }
            }
        }
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Comparison unavailable")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("The workout match data for this pair is no longer available.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

private struct WorkoutSimilarityComparisonRowCard: View {
    let row: WorkoutSimilarityComparisonRow

    private var tint: Color {
        switch row.kind {
        case .samePosition:
            return Theme.Colors.success
        case .moved:
            return Theme.Colors.accent
        case .onlyInSelected:
            return Theme.Colors.warning
        case .onlyInPrior:
            return Theme.Colors.accentSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(row.kind.title)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(tint)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                if let selectedPosition = row.selectedPosition, let priorPosition = row.priorPosition {
                    Text("#\(selectedPosition) / #\(priorPosition)")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textTertiary)
                } else if let selectedPosition = row.selectedPosition {
                    Text("Selected #\(selectedPosition)")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textTertiary)
                } else if let priorPosition = row.priorPosition {
                    Text("Prior #\(priorPosition)")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    exerciseColumn(title: "Selected", name: row.selectedExerciseName)
                    exerciseColumn(title: "Prior", name: row.priorExerciseName)
                }

                VStack(spacing: Theme.Spacing.md) {
                    exerciseColumn(title: "Selected", name: row.selectedExerciseName)
                    exerciseColumn(title: "Prior", name: row.priorExerciseName)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func exerciseColumn(title: String, name: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(name ?? "—")
                .font(Theme.Typography.bodyBold)
                .foregroundStyle(name == nil ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
