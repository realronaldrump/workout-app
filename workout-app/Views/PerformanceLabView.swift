import SwiftUI
import Charts

struct PerformanceLabView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager

    @State private var progressWindow = 8
    @State private var changeWindow = 14
    @State private var selectedCategory: ProgressContributionCategory = .exercise
    @State private var selectedWorkout: Workout?
    @State private var selectedExercise: ExerciseSelection?
    @State private var selectedChangeMetric: ChangeMetric?

    private var workouts: [Workout] {
        dataManager.workouts
    }

    private var muscleMapping: [String: [MuscleTag]] {
        let names = Set(workouts.flatMap { $0.exercises.map { $0.name } })
        return ExerciseMetadataManager.shared.resolvedMappings(for: names)
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    progressMapSection

                    changeSection

                    volumeBalanceSection

                    repRangeSection

                    mostImprovedSection
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
        .navigationDestination(item: $selectedExercise) { selection in
            ExerciseDetailView(
                exerciseName: selection.id,
                dataManager: dataManager,
                annotationsManager: annotationsManager,
                gymProfilesManager: gymProfilesManager
            )
        }
        .navigationDestination(item: $selectedChangeMetric) { metric in
            let fallbackNow = Date()
            let fallbackWindow = ChangeMetricWindow(
                label: "Last \(changeWindow)d",
                current: DateInterval(start: fallbackNow, end: fallbackNow),
                previous: DateInterval(start: fallbackNow, end: fallbackNow)
            )
            ChangeMetricDetailView(
                metric: metric,
                window: WorkoutAnalytics.rollingChangeWindow(for: workouts, windowDays: changeWindow) ?? fallbackWindow,
                workouts: workouts
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Performance Analytics")
                .font(Theme.Typography.screenTitle)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.5)
            Text(headerSummary)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private var headerSummary: String {
        "\(workouts.count) sessions, \(healthManager.healthDataStore.count) health snapshots, \(annotationsManager.annotations.count) annotations."
    }

    private var progressMapSection: some View {
        let contributions = WorkoutAnalytics.progressContributions(
            workouts: workouts,
            weeks: progressWindow,
            mappings: muscleMapping
        )
        let filtered = contributions.filter { $0.category == selectedCategory }
        let top = Array(filtered.prefix(8))

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Progress Delta")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                BrutalistSegmentedPicker(
                    title: "Progress window",
                    selection: $progressWindow,
                    options: [("4w", 4), ("8w", 8), ("12w", 12)]
                )
                .frame(width: 190)
            }

            BrutalistSegmentedPicker(
                title: "Progress category",
                selection: $selectedCategory,
                options: [
                    ("Exercises", ProgressContributionCategory.exercise),
                    ("Muscle", ProgressContributionCategory.muscleGroup),
                    ("Workout", ProgressContributionCategory.workoutType)
                ]
            )

            if top.isEmpty {
                Text("Not enough data yet.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            } else {
                Chart(top) { item in
                    BarMark(
                        x: .value("Delta", item.delta),
                        y: .value("Name", item.name)
                    )
                    .foregroundStyle(item.delta >= 0 ? item.tint : Theme.Colors.warning)
                }
                .chartXAxis { AxisMarks(position: .bottom) }
                .frame(height: CGFloat(top.count) * 28 + 40)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)

                if selectedCategory == .exercise {
                    ForEach(top) { item in
                        Button {
                            selectedExercise = ExerciseSelection(id: item.name)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Text("Change \(formatDelta(item.delta)) 1RM")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                            .padding(Theme.Spacing.lg)
                            .softCard(elevation: 1)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } else if selectedCategory == .workoutType {
                    ForEach(top) { item in
                        Button {
                            if let workout = workouts.first(where: { $0.name == item.name }) {
                                selectedWorkout = workout
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Text("\(formatDelta(item.delta)) volume")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                            .padding(Theme.Spacing.lg)
                            .softCard(elevation: 1)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    private var changeSection: some View {
        let window = WorkoutAnalytics.rollingChangeWindow(for: workouts, windowDays: changeWindow)
        let changes = window.map { WorkoutAnalytics.changeMetrics(for: workouts, window: $0) } ?? []
        let exerciseImprovements = WorkoutAnalytics.progressContributions(
            workouts: workouts,
            weeks: max(2, changeWindow / 7),
            mappings: muscleMapping
        )
        .filter { $0.category == .exercise }
        .sorted { $0.delta > $1.delta }

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Change")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                BrutalistSegmentedPicker(
                    title: "Change window",
                    selection: $changeWindow,
                    options: [("2w", 14), ("4w", 28)]
                )
                .frame(width: 160)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                ForEach(changes) { metric in
                    MetricTileButton(
                        action: {
                            selectedChangeMetric = metric
                        },
                        content: {
                            ChangeMetricCard(metric: metric)
                        }
                    )
                }
            }

            if !exerciseImprovements.isEmpty {
                Text("Top Delta")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(exerciseImprovements.prefix(5)) { item in
                    Button {
                        selectedExercise = ExerciseSelection(id: item.name)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Text("delta +\(Int(item.delta)) 1RM")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var volumeBalanceSection: some View {
        let allTimeRange: DateInterval = {
            let now = Date()
            let oldest = workouts.map { $0.date }.min() ?? now
            return DateInterval(start: oldest, end: now)
        }()

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Volume Balance")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            WeeklyMuscleVolumeChart(workouts: workouts, mappings: muscleMapping)

            WeeklyExerciseVolumeChart(workouts: workouts)

            ExerciseBreakdownView(workouts: workouts)

            MuscleHeatmapView(dataManager: dataManager, dateRange: allTimeRange)
        }
    }

    private var repRangeSection: some View {
        let repBuckets = WorkoutAnalytics.repRangeDistribution(for: workouts)
        let intensity = WorkoutAnalytics.intensityZones(for: workouts)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Rep Ranges & Intensity")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Chart(repBuckets) { bucket in
                BarMark(
                    x: .value("Share", bucket.percent),
                    y: .value("Range", bucket.label)
                )
                .foregroundStyle(bucket.tint)
            }
            .chartXScale(domain: 0...1)
            .frame(height: 180)
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)

            if !intensity.isEmpty {
                Chart(intensity) { bucket in
                    BarMark(
                        x: .value("Share", bucket.percent),
                        y: .value("Zone", bucket.label)
                    )
                    .foregroundStyle(bucket.tint)
                }
                .chartXScale(domain: 0...1)
                .frame(height: 180)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }

    private var mostImprovedSection: some View {
        let improvements = WorkoutAnalytics.progressContributions(
            workouts: workouts,
            weeks: progressWindow,
            mappings: muscleMapping
        )
        .filter { $0.category == .exercise && $0.delta > 0 }
        .sorted { $0.delta > $1.delta }

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Most improved")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if improvements.isEmpty {
                Text("No improvements yet.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            } else {
                ForEach(improvements.prefix(6)) { item in
                    Button {
                        selectedExercise = ExerciseSelection(id: item.name)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Text("Change +\(Int(item.delta)) 1RM over \(progressWindow) weeks")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private func formatDelta(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int(value))"
    }
}

private struct ChangeMetricCard: View {
    let metric: ChangeMetric

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(metric.title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Text(formatValue(metric.current))
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(changeLabel)
                .font(Theme.Typography.caption)
                .foregroundColor(metric.isPositive ? Theme.Colors.success : Theme.Colors.error)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private var changeLabel: String {
        let sign = metric.delta >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", metric.delta)) (\(String(format: "%.0f", metric.percentChange))%)"
    }

    private func formatValue(_ value: Double) -> String {
        if metric.title.contains("Volume") {
            if value >= 1000 { return String(format: "%.1fk", value / 1000) }
        }
        return String(format: "%.1f", value)
    }
}

private struct WeeklyMuscleVolumeChart: View {
    let workouts: [Workout]
    let mappings: [String: [MuscleTag]]

    private struct WeeklyPoint: Identifiable {
        let id = UUID()
        let weekStart: Date
        let group: MuscleTag
        let volume: Double
    }

    private var points: [WeeklyPoint] {
        let calendar = Calendar.current
        var buckets: [Date: [MuscleTag: Double]] = [:]

        for workout in workouts {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.date)
            guard let weekStart = calendar.date(from: components) else { continue }
            for exercise in workout.exercises {
                let tags = mappings[exercise.name] ?? []
                guard !tags.isEmpty else { continue }
                for tag in tags {
                    buckets[weekStart, default: [:]][tag, default: 0] += exercise.totalVolume
                }
            }
        }

        return buckets.flatMap { weekStart, volumes in
            volumes.map { group, volume in
                WeeklyPoint(weekStart: weekStart, group: group, volume: volume)
            }
        }
        .sorted { $0.weekStart < $1.weekStart }
    }

    var body: some View {
        if points.isEmpty {
            Text("tags 0")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
        } else {
            Chart(points) { point in
                BarMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Volume", point.volume)
                )
                .foregroundStyle(point.group.tint)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .frame(height: 200)
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
        }
    }
}

private struct WeeklyExerciseVolumeChart: View {
    let workouts: [Workout]

    private struct ExerciseWeekPoint: Identifiable {
        let id = UUID()
        let weekStart: Date
        let exercise: String
        let volume: Double
    }

    private var points: [ExerciseWeekPoint] {
        let calendar = Calendar.current
        let exerciseTotals = Dictionary(grouping: workouts.flatMap { $0.exercises }, by: { $0.name })
            .map { (name: $0.key, total: $0.value.reduce(0) { $0 + $1.totalVolume }) }
            .sorted { $0.total > $1.total }
            .prefix(3)
            .map { $0.name }

        var buckets: [Date: [String: Double]] = [:]

        for workout in workouts {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.date)
            guard let weekStart = calendar.date(from: components) else { continue }

            for exercise in workout.exercises where exerciseTotals.contains(exercise.name) {
                buckets[weekStart, default: [:]][exercise.name, default: 0] += exercise.totalVolume
            }
        }

        return buckets.flatMap { weekStart, volumes in
            volumes.map { name, volume in
                ExerciseWeekPoint(weekStart: weekStart, exercise: name, volume: volume)
            }
        }
        .sorted { $0.weekStart < $1.weekStart }
    }

    var body: some View {
        if points.isEmpty {
            Text("volume n 0")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
        } else {
            Chart(points) { point in
                LineMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Volume", point.volume)
                )
                .foregroundStyle(by: .value("Exercise", point.exercise))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .frame(height: 200)
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
        }
    }
}
