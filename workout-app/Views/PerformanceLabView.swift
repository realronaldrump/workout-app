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
    @State private var selectedHabitFactor: HabitFactorKind?
    @State private var selectedCorrelation: CorrelationInsight?

    private var workouts: [Workout] {
        dataManager.workouts
    }

    private var muscleMapping: [String: MuscleGroup] {
        let names = Set(workouts.flatMap { $0.exercises.map { $0.name } })
        return names.reduce(into: [String: MuscleGroup]()) { result, name in
            if let group = ExerciseMetadataManager.shared.getMuscleGroup(for: name) {
                result[name] = group
            }
        }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    progressMapSection

                    changeSection

                    consistencySection

                    effortDensitySection

                    volumeBalanceSection

                    repRangeSection

                    habitImpactSection

                    correlationSection

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
            ChangeMetricDetailView(metric: metric, windowDays: changeWindow, workouts: workouts)
        }
        .navigationDestination(item: $selectedHabitFactor) { kind in
            HabitImpactDetailView(kind: kind, workouts: workouts, annotations: annotationsManager.annotations)
        }
        .navigationDestination(item: $selectedCorrelation) { insight in
            CorrelationDetailView(insight: insight, workouts: workouts, healthData: healthManager.healthDataStore)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Performance Analytics")
                .font(Theme.Typography.largeTitle)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(headerSummary)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private var headerSummary: String {
        "sessions \(workouts.count) | health \(healthManager.healthDataStore.count) | notes \(annotationsManager.annotations.count)"
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
                Picker("Window", selection: $progressWindow) {
                    Text("4w").tag(4)
                    Text("8w").tag(8)
                    Text("12w").tag(12)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            Picker("Category", selection: $selectedCategory) {
                Text("Exercises").tag(ProgressContributionCategory.exercise)
                Text("Muscle").tag(ProgressContributionCategory.muscleGroup)
                Text("Workout").tag(ProgressContributionCategory.workoutType)
            }
            .pickerStyle(.segmented)

            if top.isEmpty {
                Text("n < 2")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
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
                .glassBackground(elevation: 2)

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
                                    Text("delta \(formatDelta(item.delta)) 1RM")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                            .padding(Theme.Spacing.lg)
                            .glassBackground(elevation: 1)
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
                            .glassBackground(elevation: 1)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    private var changeSection: some View {
        let changes = WorkoutAnalytics.changeMetrics(for: workouts, windowDays: changeWindow)
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
                Picker("Window", selection: $changeWindow) {
                    Text("2w").tag(14)
                    Text("4w").tag(28)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                ForEach(changes) { metric in
                    MetricTileButton(action: {
                        selectedChangeMetric = metric
                    }) {
                        ChangeMetricCard(metric: metric)
                    }
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
                        .glassBackground(elevation: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var consistencySection: some View {
        let issues = WorkoutAnalytics.consistencyIssues(for: workouts)
        let grouped = Dictionary(grouping: issues, by: { $0.type })

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Consistency")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if issues.isEmpty {
                Text("issues 0")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
            } else {
                ForEach([ConsistencyIssueType.missedDay, .shortenedSession, .skippedExercises], id: \.self) { type in
                    if let bucket = grouped[type] {
                        ConsistencyIssueSection(title: typeTitle(type), issues: bucket, onWorkoutTap: { workoutId in
                            if let workoutId, let workout = workouts.first(where: { $0.id == workoutId }) {
                                selectedWorkout = workout
                            }
                        })
                    }
                }
            }
        }
    }

    private var effortDensitySection: some View {
        let series = WorkoutAnalytics.effortDensitySeries(for: workouts)
        let topWorkouts = series.sorted { $0.value > $1.value }.prefix(5)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Density")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if series.isEmpty {
                Text("density n 0")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
            } else {
                Chart(series) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Density", point.value)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Density", point.value)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                }
                .frame(height: 180)
                .padding(Theme.Spacing.lg)
                .glassBackground(elevation: 2)

                Text("Top Density")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(topWorkouts, id: \.workoutId) { point in
                    if let workout = workouts.first(where: { $0.id == point.workoutId }) {
                        Button {
                            selectedWorkout = workout
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(workout.name)
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Text("\(formatDensity(point.value)) | \(workout.duration)")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                            .padding(Theme.Spacing.lg)
                            .glassBackground(elevation: 1)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    private var volumeBalanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Volume Balance")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            WeeklyMuscleVolumeChart(workouts: workouts, mappings: muscleMapping)

            WeeklyExerciseVolumeChart(workouts: workouts)

            ExerciseBreakdownView(workouts: workouts)

            MuscleHeatmapView(dataManager: dataManager)
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
            .glassBackground(elevation: 2)

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
                .glassBackground(elevation: 2)
            }
        }
    }

    private var habitImpactSection: some View {
        let insights = WorkoutAnalytics.habitImpactInsights(
            workouts: workouts,
            annotations: annotationsManager.annotations
        )

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Habit Factors")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if insights.isEmpty {
                Text("notes 0")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
            } else {
                ForEach(insights) { insight in
                    MetricTileButton(action: {
                        selectedHabitFactor = insight.kind
                    }) {
                        HStack(spacing: Theme.Spacing.md) {
                            Circle()
                                .fill(insight.tint)
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title)
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Text(insight.detail)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Text(insight.value)
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }
                        .padding(Theme.Spacing.lg)
                        .glassBackground(elevation: 1)
                    }
                }
            }
        }
    }

    private var correlationSection: some View {
        let insights = WorkoutAnalytics.correlationInsights(
            workouts: workouts,
            healthData: healthManager.healthDataStore
        )

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Correlations")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if insights.isEmpty {
                Text("health samples 0")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
            } else {
                ForEach(insights) { insight in
                    MetricTileButton(action: {
                        selectedCorrelation = insight
                    }) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(insight.title)
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(insight.detail)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                            Text("r=\(String(format: "%.2f", insight.correlation)) | n=\(insight.supportingCount)")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .glassBackground(elevation: 1)
                    }
                }
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
            Text("Top delta")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if improvements.isEmpty {
                Text("n 0")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
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
                                Text("delta +\(Int(item.delta)) 1RM | \(progressWindow)w")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .glassBackground(elevation: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private func typeTitle(_ type: ConsistencyIssueType) -> String {
        switch type {
        case .missedDay: return "Missed Days"
        case .shortenedSession: return "Shortened Sessions"
        case .skippedExercises: return "Skipped Exercises"
        }
    }

    private func formatDensity(_ value: Double) -> String {
        String(format: "%.1f", value)
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
        .glassBackground(elevation: 1)
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

private struct ConsistencyIssueSection: View {
    let title: String
    let issues: [ConsistencyIssue]
    let onWorkoutTap: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            ForEach(issues.prefix(4)) { issue in
                Button {
                    onWorkoutTap(issue.workoutId)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.title)
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(issue.detail)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        if issue.workoutId != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 1)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

private struct WeeklyMuscleVolumeChart: View {
    let workouts: [Workout]
    let mappings: [String: MuscleGroup]

    private struct WeeklyPoint: Identifiable {
        let id = UUID()
        let weekStart: Date
        let group: MuscleGroup
        let volume: Double
    }

    private var points: [WeeklyPoint] {
        let calendar = Calendar.current
        var buckets: [Date: [MuscleGroup: Double]] = [:]

        for workout in workouts {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.date)
            guard let weekStart = calendar.date(from: components) else { continue }
            for exercise in workout.exercises {
                guard let group = mappings[exercise.name] else { continue }
                buckets[weekStart, default: [:]][group, default: 0] += exercise.totalVolume
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
                .glassBackground(elevation: 2)
        } else {
            Chart(points) { point in
                BarMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Volume", point.volume)
                )
                .foregroundStyle(point.group.color)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .frame(height: 200)
            .padding(Theme.Spacing.lg)
            .glassBackground(elevation: 2)
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
                .glassBackground(elevation: 2)
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
            .glassBackground(elevation: 2)
        }
    }
}
