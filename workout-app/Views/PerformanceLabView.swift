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
    @State private var isTrainingMixExpanded = false
    @State private var isRepStyleExpanded = false

    private let maxContentWidth: CGFloat = 820
    private let consistencyMinimumSessions = 3
    private let consistencyMinimumWeeks = 3
    private let consistencyMinimumCoverage = 0.5

    private var workouts: [Workout] {
        dataManager.workouts
    }

    private var muscleMapping: [String: [MuscleTag]] {
        let names = Set(workouts.flatMap { $0.exercises.map { $0.name } })
        return ExerciseMetadataManager.shared.resolvedMappings(for: names)
    }

    private var displayWeightUnit: String { "lbs" }

    private var progressMetricSubtitle: String {
        switch selectedCategory {
        case .exercise:
            return "Best lifted weight per exercise (\(displayWeightUnit))."
        case .muscleGroup:
            return "Combined best-weight changes by muscle group (\(displayWeightUnit))."
        case .workoutType:
            return "Total work change by workout type (\(displayWeightUnit))."
        }
    }

    private var progressMetricAxisHint: String {
        switch selectedCategory {
        case .exercise:
            return "X-axis = change in best lifted weight (\(displayWeightUnit))."
        case .muscleGroup:
            return "X-axis = combined best-weight change (\(displayWeightUnit))."
        case .workoutType:
            return "X-axis = change in total work (\(displayWeightUnit))."
        }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    if workouts.isEmpty {
                        emptyStateSection
                    } else {
                        readingGuideSection

                        changeSection

                        progressMapSection

                        mostImprovedSection

                        CollapsibleSection(
                            title: "Training Mix",
                            subtitle: "Where your total work is going over time",
                            isExpanded: $isTrainingMixExpanded
                        ) {
                            volumeBalanceSection
                        }

                        CollapsibleSection(
                            title: "Rep Style & Effort",
                            subtitle: "How heavy and high-rep your training has been",
                            isExpanded: $isRepStyleExpanded
                        ) {
                            repRangeSection
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
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
            Text("Performance, made simple")
                .font(Theme.Typography.screenTitle)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.5)
            Text(headerSummary)
                .font(Theme.Typography.microcopy)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private var headerSummary: String {
        guard let latestWorkoutDate = workouts.map(\.date).max() else {
            return "Log your first workout and this screen will explain your progress without technical terms."
        }
        let healthCheckIns = healthManager.healthDataStore.count
        let throughDate = latestWorkoutDate.formatted(date: .abbreviated, time: .omitted)
        return "\(workouts.count) workouts logged and \(healthCheckIns) health check-ins " +
            "recorded through \(throughDate)."
    }

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No workouts yet")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            Text("Once you log a few sessions, this page will compare recent training with earlier weeks so your progress is easy to read.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var readingGuideSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("How to read this page")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("This is a before-and-after view of your training. You only need to know these three things:")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                guideRow(
                    icon: "clock.badge.checkmark",
                    title: "Recent period",
                    detail: "Your latest \(progressWindow) weeks of workouts."
                )
                guideRow(
                    icon: "clock.arrow.circlepath",
                    title: "Earlier period",
                    detail: "The \(progressWindow) weeks right before the recent period."
                )
                guideRow(
                    icon: "arrow.up.arrow.down",
                    title: "Change",
                    detail: "Blue means higher than earlier, orange means lower."
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var progressMapSection: some View {
        let contributions = WorkoutAnalytics.progressContributions(
            workouts: workouts,
            weeks: progressWindow,
            mappings: muscleMapping
        )
        let filtered = contributions.filter { $0.category == selectedCategory }
        let top = Array(filtered.prefix(6))

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Where You Improved Most")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(progressMetricSubtitle)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    BrutalistSegmentedPicker(
                        title: "Comparison window",
                        selection: $progressWindow,
                        options: [("4 weeks", 4), ("8 weeks", 8), ("12 weeks", 12)]
                    )
                    .frame(maxWidth: 240)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Where You Improved Most")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(progressMetricSubtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                    BrutalistSegmentedPicker(
                        title: "Comparison window",
                        selection: $progressWindow,
                        options: [("4 weeks", 4), ("8 weeks", 8), ("12 weeks", 12)]
                    )
                }
            }

            BrutalistSegmentedPicker(
                title: "View by",
                selection: $selectedCategory,
                options: [
                    ("Exercise Strength", ProgressContributionCategory.exercise),
                    ("Muscle Groups", ProgressContributionCategory.muscleGroup),
                    ("Workout Volume", ProgressContributionCategory.workoutType)
                ]
            )

            if top.isEmpty {
                Text("Not enough data yet.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            } else {
                Text("\(progressMetricAxisHint) Blue bars are up from earlier, orange bars are down.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                Chart(top) { item in
                    BarMark(
                        x: .value("Change", item.delta),
                        y: .value("Item", item.name)
                    )
                    .foregroundStyle(item.delta >= 0 ? item.tint : Theme.Colors.warning)
                    .annotation(position: item.delta >= 0 ? .trailing : .leading) {
                        Text(progressDeltaLabel(value: item.delta, category: selectedCategory))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                Text(progressDeltaLabel(value: axisValue, category: selectedCategory))
                            }
                        }
                    }
                }
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
                                    Text(exerciseProgressDescription(for: item.delta))
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
                                Text(workoutVolumeProgressDescription(for: item.delta))
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
                } else {
                    ForEach(top) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Text(muscleProgressDescription(for: item.delta))
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 1)
                    }
                }
            }
        }
    }

    private var changeSection: some View {
        let window = WorkoutAnalytics.rollingChangeWindow(for: workouts, windowDays: changeWindow)
        let changes = window.map { WorkoutAnalytics.changeMetrics(for: workouts, window: $0) } ?? []

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Recent vs Earlier")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("Simple side-by-side comparison for your latest training window.")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    BrutalistSegmentedPicker(
                        title: "Window",
                        selection: $changeWindow,
                        options: [("2 weeks", 14), ("4 weeks", 28)]
                    )
                    .frame(maxWidth: 220)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Recent vs Earlier")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Simple side-by-side comparison for your latest training window.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                    BrutalistSegmentedPicker(
                        title: "Window",
                        selection: $changeWindow,
                        options: [("2 weeks", 14), ("4 weeks", 28)]
                    )
                }
            }

            if changes.isEmpty {
                Text("Not enough workouts yet to compare time periods.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.md) {
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
                }
            }
        }
    }

    private var volumeBalanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("These charts show where your weekly workload is going so you can spot over- or under-trained areas.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            WeeklyMuscleVolumeChart(workouts: workouts, mappings: muscleMapping)

            WeeklyExerciseVolumeChart(workouts: workouts)

            ExerciseBreakdownView(workouts: workouts)
        }
    }

    private var repRangeSection: some View {
        let repBuckets = WorkoutAnalytics.repRangeDistribution(for: workouts)
        let intensity = WorkoutAnalytics.intensityZones(for: workouts)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Use this to check if your program is balanced between heavy work and higher-rep work.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            if repBuckets.allSatisfy({ $0.count < 1 }) {
                Text("No rep data yet.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Rep ranges")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Chart(repBuckets) { bucket in
                        BarMark(
                            x: .value("Share", bucket.percent),
                            y: .value("Range", bucket.label)
                        )
                        .foregroundStyle(bucket.tint)
                        .annotation(position: .trailing) {
                            Text("\(Int(round(bucket.percent * 100)))%")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                    .chartXScale(domain: 0...1)
                    .frame(height: 180)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
                }
            }

            if !intensity.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Effort zones")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Compared with the heaviest set you have logged for each exercise.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                    Chart(intensity) { bucket in
                        BarMark(
                            x: .value("Share", bucket.percent),
                            y: .value("Zone", bucket.label)
                        )
                        .foregroundStyle(bucket.tint)
                        .annotation(position: .trailing) {
                            Text("\(Int(round(bucket.percent * 100)))%")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                    .chartXScale(domain: 0...1)
                    .frame(height: 180)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
                }
            }
        }
    }

    private var mostImprovedSection: some View {
        let baseImprovements = WorkoutAnalytics.progressContributions(
            workouts: workouts,
            weeks: progressWindow,
            mappings: muscleMapping
        )
        .filter { $0.category == .exercise && $0.delta > 0 }
        .sorted { $0.delta > $1.delta }

        let consistencySummaries = WorkoutAnalytics.exerciseConsistencySummaries(workouts: workouts, weeks: progressWindow)
        let consistencyByExercise = Dictionary(uniqueKeysWithValues: consistencySummaries.map { ($0.exerciseName, $0) })
        let consistentExercises = WorkoutAnalytics.consistentExerciseNames(
            workouts: workouts,
            weeks: progressWindow,
            minimumSessions: consistencyMinimumSessions,
            minimumWeeks: consistencyMinimumWeeks,
            minimumWeeklyCoverage: consistencyMinimumCoverage
        )

        let improvements = WorkoutAnalytics.progressContributions(
            workouts: workouts,
            weeks: progressWindow,
            mappings: muscleMapping
        )
        .filter { $0.category == .exercise && $0.delta > 0 && consistentExercises.contains($0.name) }
        .sorted { $0.delta > $1.delta }

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Most improved exercises")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(
                "To qualify, an exercise must be trained regularly: at least \(consistencyMinimumSessions) sessions, " +
                "in \(consistencyMinimumWeeks) different weeks, and in \(Int(consistencyMinimumCoverage * 100))% of your active weeks."
            )
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            if improvements.isEmpty {
                if baseImprovements.isEmpty {
                    Text("No improvements yet.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 2)
                } else {
                    Text("You have some improvements, but none meet the consistency rule yet.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 2)
                }
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
                                Text(exerciseProgressDescription(for: item.delta))
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                if let summary = consistencyByExercise[item.name] {
                                    Text("\(summary.sessions) sessions across \(summary.weeksPerformed) of \(summary.activeWeeks) active weeks")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textTertiary)
                                }
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

    private func guideRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundColor(Theme.Colors.accent)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private func exerciseProgressDescription(for delta: Double) -> String {
        if abs(delta) < 0.01 {
            return "About the same best lifted weight as earlier."
        }
        let direction = delta > 0 ? "Up" : "Down"
        return "\(direction) \(formatWeight(abs(delta))) in best lifted weight."
    }

    private func muscleProgressDescription(for delta: Double) -> String {
        if abs(delta) < 0.01 {
            return "About the same combined strength as earlier."
        }
        let direction = delta > 0 ? "Up" : "Down"
        return "\(direction) \(formatWeight(abs(delta))) combined best-weight change."
    }

    private func workoutVolumeProgressDescription(for delta: Double) -> String {
        if abs(delta) < 0.01 {
            return "About the same total work as earlier."
        }
        let direction = delta > 0 ? "Up" : "Down"
        return "\(direction) \(formatVolume(abs(delta))) of total work."
    }

    private func progressDeltaLabel(value: Double, category: ProgressContributionCategory) -> String {
        switch category {
        case .workoutType:
            return formatSignedVolume(value)
        case .exercise, .muscleGroup:
            return formatSignedWeight(value)
        }
    }

    private func formatWeight(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk lbs", value / 1000)
        }
        return "\(Int(round(value))) lbs"
    }

    private func formatSignedWeight(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(formatWeight(abs(value)))"
    }

    private func formatSignedVolume(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(formatVolume(abs(value)))"
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM lbs", volume / 1_000_000)
        }
        if volume >= 1000 {
            return String(format: "%.1fk lbs", volume / 1000)
        }
        return String(format: "%.0f lbs", volume)
    }
}

private struct ChangeMetricCard: View {
    let metric: ChangeMetric

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(displayTitle)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Text(formatValue(metric.current))
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            Text("Earlier: \(formatValue(metric.previous))")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
            Text(changeLabel)
                .font(Theme.Typography.caption)
                .foregroundColor(changeTint)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private var displayTitle: String {
        switch metric.title {
        case "Sessions":
            return "Workouts"
        case "Total Volume":
            return "Total Work (lbs)"
        case "Avg Duration":
            return "Avg Length"
        default:
            return metric.title
        }
    }

    private var changeTint: Color {
        if abs(metric.delta) < 0.01 {
            return Theme.Colors.textSecondary
        }
        return metric.delta > 0 ? Theme.Colors.success : Theme.Colors.warning
    }

    private var changeLabel: String {
        if abs(metric.delta) < 0.01 {
            return "About the same as earlier period"
        }

        let direction = metric.delta > 0 ? "Up" : "Down"
        let amount = formatDelta(abs(metric.delta))
        let percent = abs(metric.percentChange)
        if percent >= 1 {
            return "\(direction) \(amount) (\(Int(round(percent)))%) vs earlier period"
        }
        return "\(direction) \(amount) vs earlier period"
    }

    private func formatValue(_ value: Double) -> String {
        switch metric.title {
        case "Sessions":
            return "\(Int(round(value))) workouts"
        case "Total Volume":
            return formatVolume(value)
        case "Avg Duration":
            return formatDurationMinutes(value)
        default:
            return String(format: "%.1f", value)
        }
    }

    private func formatDelta(_ value: Double) -> String {
        switch metric.title {
        case "Sessions":
            return "\(Int(round(value))) workouts"
        case "Total Volume":
            return formatVolume(value)
        case "Avg Duration":
            return formatDurationMinutes(value)
        default:
            return String(format: "%.1f", value)
        }
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM lbs", value / 1_000_000)
        }
        if value >= 1000 {
            return String(format: "%.1fk lbs", value / 1000)
        }
        return String(format: "%.0f lbs", value)
    }

    private func formatDurationMinutes(_ minutes: Double) -> String {
        let value = Int(round(minutes))
        if value >= 60 {
            return "\(value / 60)h \(value % 60)m"
        }
        return "\(value)m"
    }
}

private struct WeeklyMuscleVolumeChart: View {
    let workouts: [Workout]
    let mappings: [String: [MuscleTag]]
    private let maxVisibleWeeks = 12
    private let maxNamedGroups = 4

    private struct WeeklyPoint: Identifiable {
        let weekStart: Date
        let group: String
        let tint: Color
        let volume: Double

        var id: String { "\(Int(weekStart.timeIntervalSince1970))-\(group)" }
    }

    private struct LegendItem: Identifiable {
        let name: String
        let tint: Color

        var id: String { name }
    }

    private var weeklyBuckets: [Date: [MuscleTag: Double]] {
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

        return buckets
    }

    private var visibleWeeks: [Date] {
        Array(weeklyBuckets.keys.sorted().suffix(maxVisibleWeeks))
    }

    private var namedGroups: [MuscleTag] {
        var totals: [MuscleTag: Double] = [:]
        for week in visibleWeeks {
            let volumes = weeklyBuckets[week] ?? [:]
            for (tag, volume) in volumes {
                totals[tag, default: 0] += volume
            }
        }
        return totals
            .sorted { $0.value > $1.value }
            .prefix(maxNamedGroups)
            .map(\.key)
    }

    private var points: [WeeklyPoint] {
        let topGroups = namedGroups
        let topGroupSet = Set(topGroups)

        return visibleWeeks.flatMap { weekStart in
            let volumes = weeklyBuckets[weekStart] ?? [:]
            var weekPoints: [WeeklyPoint] = []

            for group in topGroups {
                let volume = volumes[group, default: 0]
                guard volume > 0 else { continue }
                weekPoints.append(
                    WeeklyPoint(
                        weekStart: weekStart,
                        group: group.shortName,
                        tint: group.tint,
                        volume: volume
                    )
                )
            }

            let otherVolume = volumes
                .filter { !topGroupSet.contains($0.key) }
                .reduce(0) { $0 + $1.value }
            if otherVolume > 0 {
                weekPoints.append(
                    WeeklyPoint(
                        weekStart: weekStart,
                        group: "Other",
                        tint: Theme.Colors.textTertiary,
                        volume: otherVolume
                    )
                )
            }

            return weekPoints
        }
    }

    private var legendItems: [LegendItem] {
        var items = namedGroups.map { LegendItem(name: $0.shortName, tint: $0.tint) }
        if points.contains(where: { $0.group == "Other" }) {
            items.append(LegendItem(name: "Other", tint: Theme.Colors.textTertiary))
        }
        return items
    }

    var body: some View {
        if points.isEmpty {
            Text("No tagged muscle volume data yet.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Weekly muscle balance")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("Showing the top muscle groups from the last \(visibleWeeks.count) weeks. Smaller groups are combined as Other.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                Chart(points) { point in
                    BarMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Volume", point.volume)
                    )
                    .foregroundStyle(point.tint)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                Text(formatVolume(axisValue))
                            }
                        }
                    }
                }
                .frame(height: 220)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)

                if !legendItems.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.xs) {
                        ForEach(legendItems) { item in
                            HStack(spacing: Theme.Spacing.xs) {
                                Circle()
                                    .fill(item.tint)
                                    .frame(width: 8, height: 8)
                                Text(item.name)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM lbs", value / 1_000_000)
        }
        if value >= 1000 {
            return String(format: "%.0fk lbs", value / 1000)
        }
        return String(format: "%.0f lbs", value)
    }
}

private struct WeeklyExerciseVolumeChart: View {
    let workouts: [Workout]

    private let maxVisibleWeeks = 12
    private let trackedExerciseCount = 3
    private let palette: [Color] = [Theme.Colors.accent, Theme.Colors.success, Theme.Colors.accentSecondary]

    private struct ExerciseLegendItem: Identifiable {
        let name: String
        let displayName: String
        let tint: Color

        var id: String { name }
    }

    private struct ExerciseWeekPoint: Identifiable {
        let weekStart: Date
        let exerciseName: String
        let displayName: String
        let tint: Color
        let volume: Double

        var id: String { "\(Int(weekStart.timeIntervalSince1970))-\(exerciseName)" }
    }

    private var recentWorkouts: [Workout] {
        guard let latestDate = workouts.map(\.date).max() else { return [] }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(maxVisibleWeeks * 7), to: latestDate) ?? latestDate
        return workouts.filter { $0.date >= start && $0.date <= latestDate }
    }

    private var trackedExercises: [ExerciseLegendItem] {
        let totals = Dictionary(grouping: recentWorkouts.flatMap { $0.exercises }, by: { $0.name })
            .map { (name: $0.key, total: $0.value.reduce(0) { $0 + $1.totalVolume }) }
            .sorted { $0.total > $1.total }
            .prefix(trackedExerciseCount)
            .map(\.name)

        return totals.enumerated().map { index, name in
            ExerciseLegendItem(
                name: name,
                displayName: shortExerciseName(name),
                tint: palette[index % palette.count]
            )
        }
    }

    private var weekStarts: [Date] {
        let calendar = Calendar.current
        let starts = Set(
            recentWorkouts.compactMap { workout in
                let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.date)
                return calendar.date(from: components)
            }
        )
        return starts.sorted()
    }

    private var points: [ExerciseWeekPoint] {
        guard !trackedExercises.isEmpty else { return [] }
        let calendar = Calendar.current
        let exerciseNames = Set(trackedExercises.map(\.name))
        var volumeByExerciseAndWeek: [String: [Date: Double]] = [:]

        for workout in recentWorkouts {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.date)
            guard let weekStart = calendar.date(from: components) else { continue }
            for exercise in workout.exercises where exerciseNames.contains(exercise.name) {
                volumeByExerciseAndWeek[exercise.name, default: [:]][weekStart, default: 0] += exercise.totalVolume
            }
        }

        return trackedExercises.flatMap { exercise in
            weekStarts.map { weekStart in
                ExerciseWeekPoint(
                    weekStart: weekStart,
                    exerciseName: exercise.name,
                    displayName: exercise.displayName,
                    tint: exercise.tint,
                    volume: volumeByExerciseAndWeek[exercise.name]?[weekStart] ?? 0
                )
            }
        }
    }

    var body: some View {
        if points.isEmpty {
            Text("No exercise volume trends yet.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Top exercise trends")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("Tracking your top \(trackedExercises.count) exercises by weekly volume over the last \(weekStarts.count) weeks.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                Chart(points) { point in
                    LineMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Volume", point.volume)
                    )
                    .foregroundStyle(point.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Volume", point.volume)
                    )
                    .foregroundStyle(point.tint)
                    .symbolSize(18)
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                Text(formatVolume(axisValue))
                            }
                        }
                    }
                }
                .frame(height: 220)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.xs) {
                    ForEach(trackedExercises) { exercise in
                        HStack(spacing: Theme.Spacing.xs) {
                            Circle()
                                .fill(exercise.tint)
                                .frame(width: 8, height: 8)
                            Text(exercise.displayName)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func shortExerciseName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: " (Machine)", with: "")
        if cleaned.count > 24 {
            return "\(cleaned.prefix(24))…"
        }
        return cleaned
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM lbs", value / 1_000_000)
        }
        if value >= 1000 {
            return String(format: "%.0fk lbs", value / 1000)
        }
        return String(format: "%.0f lbs", value)
    }
}
