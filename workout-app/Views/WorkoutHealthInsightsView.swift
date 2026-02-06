import SwiftUI

struct WorkoutHealthInsightsView: View {
    let workout: Workout

    @EnvironmentObject var healthManager: HealthKitManager

    @State private var showHeartRateSamples = false
    @State private var showHRVSamples = false
    @State private var showBloodOxygenSamples = false

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    if let data = healthManager.getHealthData(for: workout.id) {
                        HealthDataView(healthData: data)

                        rawSamplesSection(data: data)
                    } else {
                        EmptyStateCard(
                            title: "No health data",
                            message: "Sync Apple Health for this workout to unlock charts and samples."
                        )
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(workout.name)
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private func rawSamplesSection(data: WorkoutHealthData) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Raw Samples")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if data.heartRateSamples.isEmpty, data.hrvSamples.isEmpty, data.bloodOxygenSamples.isEmpty {
                Text("No raw samples stored for this workout.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                if !data.heartRateSamples.isEmpty {
                    Toggle(isOn: $showHeartRateSamples) {
                        Text("Heart Rate")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Theme.Colors.accent))

                    if showHeartRateSamples {
                        samplesList(
                            title: "Heart Rate Samples",
                            rows: data.heartRateSamples.sorted { $0.timestamp > $1.timestamp }.map {
                                ($0.timestamp, "\(Int($0.value)) bpm")
                            }
                        )
                    }
                }

                if !data.hrvSamples.isEmpty {
                    Toggle(isOn: $showHRVSamples) {
                        Text("HRV")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Theme.Colors.accent))

                    if showHRVSamples {
                        samplesList(
                            title: "HRV Samples",
                            rows: data.hrvSamples.sorted { $0.timestamp > $1.timestamp }.map {
                                ($0.timestamp, "\(Int($0.value)) ms")
                            }
                        )
                    }
                }

                if !data.bloodOxygenSamples.isEmpty {
                    Toggle(isOn: $showBloodOxygenSamples) {
                        Text("Blood Oxygen")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Theme.Colors.accent))

                    if showBloodOxygenSamples {
                        samplesList(
                            title: "Blood Oxygen Samples",
                            rows: data.bloodOxygenSamples.sorted { $0.timestamp > $1.timestamp }.map {
                                ($0.timestamp, String(format: "%.1f%%", $0.value))
                            }
                        )
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func samplesList(title: String, rows: [(Date, String)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(Array(rows.prefix(40).enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(row.1)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .padding(Theme.Spacing.md)
                .softCard(elevation: 1)
            }
        }
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
