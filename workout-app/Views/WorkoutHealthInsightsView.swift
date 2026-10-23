import Combine
import SwiftUI

struct WorkoutHealthInsightsView: View {
    let workout: Workout

    @EnvironmentObject var healthManager: HealthKitManager

    @State private var showHeartRateSamples = false
    @State private var showHRVSamples = false
    @State private var showBloodOxygenSamples = false
    @State private var isLoadingRawSamples = false
    @State private var rawSampleError: String?
    @State private var rawSampleSnapshot = WorkoutRawSampleSnapshot(data: nil)
    @State private var rawSampleRevision = 0
    @State private var rawSampleRows = WorkoutRawSampleRows.empty

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
                            message: "Sync Apple Health for this workout."
                        )
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
                .contentColumn()
            }
        }
        .collapsingTitle("Health")
        .onReceive(healthManager.$healthDataStore.map { store in
            WorkoutRawSampleSnapshot(data: store[workout.id])
        }.removeDuplicates()) { snapshot in
            guard snapshot != rawSampleSnapshot else { return }
            rawSampleSnapshot = snapshot
            rawSampleRevision &+= 1
        }
        .task(id: rawSampleRevision) {
            await refreshRawSampleRows()
        }
    }

    private var header: some View {
        StatsPageHeader(
            eyebrow: "Workout health",
            title: workout.name,
            subtitle: workout.date.formatted(date: .complete, time: .shortened),
            systemImage: "heart.fill"
        )
    }

    @ViewBuilder
    private func rawSamplesSection(data: WorkoutHealthData) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(
                title: "Measurements",
                help: "Loads the individual heart rate, HRV, blood oxygen, and respiratory readings for this workout from Apple Health."
            )

            if data.heartRateSamples.isEmpty, data.hrvSamples.isEmpty, data.bloodOxygenSamples.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Measurements haven’t been loaded for this workout.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Button {
                        loadRawSamples()
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            if isLoadingRawSamples {
                                ProgressView()
                                    .tint(Theme.Colors.onAccent)
                            } else {
                                Image(systemName: "waveform.path.ecg")
                                    .font(Theme.Typography.subheadlineStrong)
                            }

                            Text(isLoadingRawSamples ? "Loading measurements" : "Load measurements")
                                .font(Theme.Typography.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: Theme.Layout.primaryControlHeight)
                    }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .disabled(isLoadingRawSamples)

                    if let rawSampleError {
                        Text(rawSampleError)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.error)
                    }
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 1)
            } else {
                if !data.heartRateSamples.isEmpty {
                    Toggle(isOn: $showHeartRateSamples) {
                        Text("Heart rate")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Theme.Colors.accent))

                    if showHeartRateSamples {
                        samplesList(
                            title: "Heart rate readings",
                            rows: rawSampleRows.heartRate
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
                            title: "HRV readings",
                            rows: rawSampleRows.hrv
                        )
                    }
                }

                if !data.bloodOxygenSamples.isEmpty {
                    Toggle(isOn: $showBloodOxygenSamples) {
                        Text("Blood oxygen")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Theme.Colors.accent))

                    if showBloodOxygenSamples {
                        samplesList(
                            title: "Blood oxygen readings",
                            rows: rawSampleRows.bloodOxygen
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

    private func loadRawSamples() {
        guard !isLoadingRawSamples else { return }

        rawSampleError = nil
        isLoadingRawSamples = true

        Task {
            do {
                _ = try await healthManager.loadDetailedSamplesIfNeeded(for: workout.id, force: true)
            } catch {
                rawSampleError = error.localizedDescription
            }
            isLoadingRawSamples = false
        }
    }

    private func refreshRawSampleRows() async {
        let snapshot = rawSampleSnapshot
        let revision = rawSampleRevision
        let task = Task.detached(priority: .userInitiated) {
            snapshot.rows()
        }
        let rows = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard !Task.isCancelled, revision == rawSampleRevision else { return }
        rawSampleRows = rows
    }
}
