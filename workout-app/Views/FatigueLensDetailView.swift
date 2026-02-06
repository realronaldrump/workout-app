import SwiftUI

struct FatigueLensDetailView: View {
    let workout: Workout
    let summary: FatigueSummary

    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager

    @State private var selectedExercise: ExerciseSelection?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    metricsSection

                    entriesSection
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle("Fatigue")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedExercise) { selection in
            ExerciseDetailView(
                exerciseName: selection.id,
                dataManager: dataManager,
                annotationsManager: annotationsManager,
                gymProfilesManager: gymProfilesManager
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Fatigue Lens")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.5)
            Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Signals")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    if let restIndex = summary.restTimeIndex {
                        MetricPill(title: "Rest / Set", value: String(format: "%.1f min", restIndex))
                    }
                    if let density = summary.effortDensity {
                        MetricPill(title: "Effort Density", value: String(format: "%.1f", density))
                    }
                    if let rpe = summary.averageRPE {
                        MetricPill(title: "Avg RPE", value: String(format: "%.1f", rpe))
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                    if let restIndex = summary.restTimeIndex {
                        MetricPill(title: "Rest / Set", value: String(format: "%.1f min", restIndex))
                    }
                    if let density = summary.effortDensity {
                        MetricPill(title: "Effort Density", value: String(format: "%.1f", density))
                    }
                    if let rpe = summary.averageRPE {
                        MetricPill(title: "Avg RPE", value: String(format: "%.1f", rpe))
                    }
                }
            }

            if let trend = summary.restTimeTrend {
                Text(trend)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Text("Lower rest per set and falling density can signal accumulated fatigue. Use the exercise drops below to spot where it’s showing up.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Drops")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if summary.entries.isEmpty {
                Text("No drops detected for this workout.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                ForEach(summary.entries) { entry in
                    MetricTileButton(action: {
                        selectedExercise = ExerciseSelection(id: entry.exerciseName)
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.exerciseName)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(entry.note)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            Text("-\(Int(entry.dropPercent * 100))%")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.warning)
                        }
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 1)
                    }
                }
            }
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

