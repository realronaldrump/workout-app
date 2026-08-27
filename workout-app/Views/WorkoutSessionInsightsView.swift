import SwiftUI
import Charts

private enum SessionInsightFocus: Hashable {
    case volume
    case exercises
    case health
}

struct WorkoutSessionInsightsView: View {
    let workout: Workout

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @State private var selectedFocus: SessionInsightFocus?
    @State private var selectedVolumeExerciseName: String?
    @State private var selectedExercise: ExerciseSelection?
    private let maxContentWidth: CGFloat = 760
    private var statColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 120, maximum: 210), spacing: Theme.Spacing.md)]
    }

    private struct ExerciseVolumePoint: Identifiable {
        let name: String
        let volume: Double

        var id: String { name }
    }

    private var exerciseVolumes: [ExerciseVolumePoint] {
        ExerciseAggregation.aggregateExercises(in: workout, resolver: ExerciseIdentityResolver.current)
            .compactMap { exercise in
                guard exercise.hasVolume else { return nil }
                return ExerciseVolumePoint(name: exercise.name, volume: exercise.totalVolume)
            }
            .sorted { $0.volume > $1.volume }
            .prefix(12)
            .reversed()
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                        header

                        volumeChartSection
                            .id(SessionInsightFocus.volume)

                        statsSection

                        healthSnapshotSection
                            .id(SessionInsightFocus.health)

                        exerciseLinksSection
                            .id(SessionInsightFocus.exercises)
                    }
                    .padding(.vertical, Theme.Spacing.xxl)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .frame(maxWidth: maxContentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .onChange(of: selectedFocus) { _, focus in
                    guard let focus else { return }
                    withAnimation(reduceMotion ? nil : Theme.Animation.smooth) {
                        proxy.scrollTo(focus, anchor: .top)
                    }
                }
            }
        }
        .navigationTitle("Session")
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
                if let selectedVolumeExercise {
                    AnalysisTile(
                        role: .navigate,
                        destination: "\(selectedVolumeExercise.name) analysis",
                        accessibilityLabel: "\(selectedVolumeExercise.name), \(SharedFormatters.volumeWithUnit(selectedVolumeExercise.volume))",
                        action: {
                            selectedExercise = ExerciseSelection(id: selectedVolumeExercise.name)
                        },
                        content: {
                            HStack(spacing: Theme.Spacing.sm) {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text("Selected Exercise")
                                        .sectionHeaderStyle()
                                    Text(selectedVolumeExercise.name)
                                        .font(Theme.Typography.bodyBold)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(SharedFormatters.volumeWithUnit(selectedVolumeExercise.volume))
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    )
                }

                Chart(exerciseVolumes) { point in
                    BarMark(
                        x: .value("Volume", point.volume),
                        y: .value("Exercise", point.name)
                    )
                    .foregroundStyle(
                        selectedVolumeExerciseName == nil || selectedVolumeExerciseName == point.name
                            ? Theme.Colors.accent
                            : Theme.Colors.textTertiary
                    )
                    .annotation(position: .trailing) {
                        Text(SharedFormatters.volumeCompact(point.volume))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }

                    if selectedVolumeExerciseName == point.name {
                        RuleMark(y: .value("Selected exercise", point.name))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYSelection(value: $selectedVolumeExerciseName)
                .frame(height: CGFloat(exerciseVolumes.count) * 38 + 20)
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                Text(SharedFormatters.volumeCompact(axisValue))
                            }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Volume by exercise")
                .accessibilityValue(volumeChartAccessibilityValue)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }

    private var volumeChartAccessibilityValue: String {
        guard let highest = exerciseVolumes.max(by: { $0.volume < $1.volume }) else {
            return "No exercise volume data"
        }
        let total = exerciseVolumes.reduce(0) { $0 + $1.volume }
        return "\(exerciseVolumes.count) exercises. Highest: \(highest.name), "
            + "\(SharedFormatters.volumeCompact(highest.volume)). Total \(SharedFormatters.volumeCompact(total))."
    }

    private var selectedVolumeExercise: ExerciseVolumePoint? {
        guard let selectedVolumeExerciseName else { return nil }
        return exerciseVolumes.first { $0.name == selectedVolumeExerciseName }
    }

    private var statsSection: some View {
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Stats")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            LazyVGrid(columns: statColumns, spacing: Theme.Spacing.md) {
                MetricStatPill(
                    title: "Volume",
                    value: SharedFormatters.volumeCompact(
                        ExerciseAggregation.totalVolume(for: workout, resolver: ExerciseIdentityResolver.current)
                    ),
                    isSelected: selectedFocus == .volume,
                    action: { selectedFocus = .volume }
                )
                MetricStatPill(
                    title: "Total Sets",
                    value: "\(ExerciseAggregation.totalSets(for: workout, resolver: ExerciseIdentityResolver.current))",
                    isSelected: selectedFocus == .exercises,
                    action: { selectedFocus = .exercises }
                )
                MetricStatPill(
                    title: "Exercises",
                    value: "\(ExerciseAggregation.exerciseCount(for: workout, resolver: ExerciseIdentityResolver.current))",
                    isSelected: selectedFocus == .exercises,
                    action: { selectedFocus = .exercises }
                )
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
                        MetricStatPill(
                            title: "Avg HR",
                            value: "\(Int(avgHR)) bpm",
                            isSelected: selectedFocus == .health,
                            action: { selectedFocus = .health }
                        )
                    }
                    if let maxHR = data.maxHeartRate {
                        MetricStatPill(
                            title: "Max HR",
                            value: "\(Int(maxHR)) bpm",
                            isSelected: selectedFocus == .health,
                            action: { selectedFocus = .health }
                        )
                    }
                    if let cals = data.activeCalories {
                        MetricStatPill(
                            title: "Calories",
                            value: "\(Int(cals)) cal",
                            isSelected: selectedFocus == .health,
                            action: { selectedFocus = .health }
                        )
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

            let sorted = Array(
                ExerciseAggregation.aggregateExercises(in: workout, resolver: ExerciseIdentityResolver.current)
                    .compactMap { exercise -> (name: String, volume: Double)? in
                        guard exercise.hasVolume else { return nil }
                        return (name: exercise.name, volume: exercise.totalVolume)
                    }
                    .sorted { $0.volume > $1.volume }
                    .prefix(8)
            )

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
                                Text("\(SharedFormatters.volumeCompact(item.volume)) volume")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Theme.Typography.caption)
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
}

private struct MetricStatPill: View {
    let title: String
    let value: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        AnalysisTile(
            role: .focus,
            destination: title,
            accessibilityLabel: "\(title), \(value)",
            isSelected: isSelected,
            action: action,
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .sectionHeaderStyle()
                    Text(value)
                        .font(Theme.Typography.cardHeader)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        )
    }
}
