import SwiftUI
import Charts

struct WorkoutSessionInsightsView: View {
    let workout: Workout

    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    private let maxContentWidth: CGFloat = 760
    private var statColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 120, maximum: 210), spacing: Theme.Spacing.md)]
    }

    private struct ExerciseVolumePoint: Identifiable {
        let id = UUID()
        let name: String
        let volume: Double
    }

    private var exerciseVolumes: [ExerciseVolumePoint] {
        workout.exercises
            .map { ExerciseVolumePoint(name: $0.name, volume: $0.totalVolume) }
            .sorted { $0.volume > $1.volume }
            .prefix(12)
            .reversed()
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    volumeChartSection

                    statsSection

                    healthSnapshotSection

                    exerciseLinksSection
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(workout.name)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.5)
            Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var volumeChartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Volume by Exercise")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if exerciseVolumes.isEmpty {
                Text("No exercise volume data.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                Chart(exerciseVolumes) { point in
                    BarMark(
                        x: .value("Volume", point.volume),
                        y: .value("Exercise", point.name)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                    .annotation(position: .trailing) {
                        Text(formatVolume(point.volume))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .frame(height: CGFloat(exerciseVolumes.count) * 34 + 20)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                Text(formatVolume(axisValue))
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }

    private var statsSection: some View {
        let minutes = WorkoutAnalytics.durationMinutes(from: workout.duration)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Stats")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            LazyVGrid(columns: statColumns, spacing: Theme.Spacing.md) {
                MetricStatPill(title: "Duration", value: workout.duration)
                MetricStatPill(title: "Volume", value: formatVolume(workout.totalVolume))
                MetricStatPill(title: "Minutes", value: minutes > 0 ? "\(Int(round(minutes)))" : "--")
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var healthSnapshotSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Health Snapshot")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if let data = healthManager.getHealthData(for: workout.id) {
                LazyVGrid(columns: statColumns, spacing: Theme.Spacing.md) {
                    if let avgHR = data.avgHeartRate {
                        MetricStatPill(title: "Avg HR", value: "\(Int(avgHR)) bpm")
                    }
                    if let maxHR = data.maxHeartRate {
                        MetricStatPill(title: "Max HR", value: "\(Int(maxHR)) bpm")
                    }
                    if let cals = data.activeCalories {
                        MetricStatPill(title: "Calories", value: "\(Int(cals)) cal")
                    }
                }

                if !data.heartRateSamples.isEmpty {
                    WorkoutHRChart(samples: data.heartRateSamples)
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 2)
                }
            } else {
                Text("No health data synced for this workout.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            }
        }
    }

    private var exerciseLinksSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Explore")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            let sorted = workout.exercises
                .map { (name: $0.name, volume: $0.totalVolume) }
                .sorted { $0.volume > $1.volume }
                .prefix(8)

            if sorted.isEmpty {
                EmptyStateCard(title: "No exercises", message: "This workout has no exercises.")
            } else {
                ForEach(sorted, id: \.name) { item in
                    NavigationLink(
                        destination: ExerciseDetailView(
                            exerciseName: item.name,
                            dataManager: dataManager,
                            annotationsManager: annotationsManager,
                            gymProfilesManager: gymProfilesManager
                        )
                    ) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("\(formatVolume(item.volume)) volume")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        }
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
}

private struct MetricStatPill: View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(elevation: 1)
    }
}

private struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}
