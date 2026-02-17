import SwiftUI
import Charts

struct PerformanceLabView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager

    @State private var comparisonWindow = 14
    @State private var selectedWorkout: Workout?
    @State private var selectedExercise: ExerciseSelection?
    @State private var selectedChangeMetric: ChangeMetric?

    private let maxContentWidth: CGFloat = 820

    private var workouts: [Workout] {
        dataManager.workouts
    }

    private var muscleMapping: [String: [MuscleTag]] {
        let names = Set(workouts.flatMap { $0.exercises.map { $0.name } })
        return ExerciseMetadataManager.shared.resolvedMappings(for: names)
    }

    private var comparisonWindowOptions: [(label: String, value: Int)] {
        [
            ("2 Weeks", 14),
            ("4 Weeks", 28),
            ("8 Weeks", 56),
            ("12 Weeks", 84)
        ]
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    if workouts.isEmpty {
                        emptyState
                    } else {
                        atAGlanceSection

                        comparisonSection

                        strengthGainsSection

                        muscleBalanceSection

                        weeklyActivitySection
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
                label: "Last \(comparisonWindow)d",
                current: DateInterval(start: fallbackNow, end: fallbackNow),
                previous: DateInterval(start: fallbackNow, end: fallbackNow)
            )
            ChangeMetricDetailView(
                metric: metric,
                window: WorkoutAnalytics.rollingChangeWindow(for: workouts, windowDays: comparisonWindow) ?? fallbackWindow,
                workouts: workouts
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Your Performance")
                .font(Theme.Typography.screenTitle)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.5)
            Text(headerSubtitle)
                .font(Theme.Typography.microcopy)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private var headerSubtitle: String {
        guard let latest = workouts.map(\.date).max() else {
            return "Start logging workouts to track your progress."
        }
        let through = latest.formatted(date: .abbreviated, time: .omitted)
        return "\(workouts.count) workouts through \(through)"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No workouts yet")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            Text("Log a few sessions and your progress will show up here automatically.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    // MARK: - At a Glance

    private var atAGlanceSection: some View {
        let streakRuns = WorkoutAnalytics.streakRuns(for: workouts, intentionalRestDays: 2)
        let currentStreak = streakRuns.last?.workoutDayCount ?? 0
        let bestStreak = streakRuns.map(\.workoutDayCount).max() ?? 0

        let calendar = Calendar.current
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let recentCount = workouts.filter { $0.date >= fourWeeksAgo }.count

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("At a Glance")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    glanceTile(
                        value: "\(workouts.count)",
                        label: "Total Workouts",
                        icon: "figure.strengthtraining.traditional"
                    )
                    glanceTile(
                        value: "\(recentCount)",
                        label: "Last 4 Weeks",
                        icon: "calendar"
                    )
                    glanceTile(
                        value: "\(currentStreak)",
                        label: currentStreak == bestStreak && currentStreak > 0 ? "Day Streak \u{2605}" : "Day Streak",
                        icon: "flame.fill"
                    )
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                    glanceTile(
                        value: "\(workouts.count)",
                        label: "Total Workouts",
                        icon: "figure.strengthtraining.traditional"
                    )
                    glanceTile(
                        value: "\(recentCount)",
                        label: "Last 4 Weeks",
                        icon: "calendar"
                    )
                    glanceTile(
                        value: "\(currentStreak)",
                        label: currentStreak == bestStreak && currentStreak > 0 ? "Day Streak \u{2605}" : "Day Streak",
                        icon: "flame.fill"
                    )
                }
            }
        }
    }

    private func glanceTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Theme.Colors.accent)
            Text(value)
                .font(Theme.Typography.number)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.sm)
        .softCard(elevation: 2)
    }

    // MARK: - Comparison (Recent vs Before)

    private var comparisonSection: some View {
        let window = WorkoutAnalytics.rollingChangeWindow(for: workouts, windowDays: comparisonWindow)
        let changes = window.map { WorkoutAnalytics.changeMetrics(for: workouts, window: $0) } ?? []

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Trending")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            BrutalistSegmentedPicker(
                title: "Window",
                selection: $comparisonWindow,
                options: comparisonWindowOptions
            )
            .frame(maxWidth: 560, alignment: .leading)

            if changes.isEmpty {
                Text("Need more workouts to compare periods.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(changes) { metric in
                        MetricTileButton(
                            chevronPlacement: .topTrailing,
                            action: { selectedChangeMetric = metric }
                        ) {
                            PerformanceComparisonRow(metric: metric)
                                .padding(Theme.Spacing.lg)
                                .softCard(elevation: 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Strength Gains

    private var strengthGainsSection: some View {
        let contributions = WorkoutAnalytics.progressContributions(
            workouts: workouts,
            weeks: 8,
            mappings: muscleMapping
        )
        let exerciseGains = contributions
            .filter { $0.category == .exercise }
            .sorted { $0.delta > $1.delta }
        let gainers = Array(exerciseGains.filter { $0.delta > 0 }.prefix(5))
        let decliners = Array(exerciseGains.filter { $0.delta < 0 }.sorted { $0.delta < $1.delta }.prefix(3))

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Strength Trends")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Best weight per exercise \u{2014} last 8 weeks vs the 8 before")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            if gainers.isEmpty && decliners.isEmpty {
                Text("Keep training \u{2014} trends will appear after a few weeks.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            } else {
                if !gainers.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(gainers.enumerated()), id: \.element.id) { index, item in
                            Button {
                                selectedExercise = ExerciseSelection(id: item.name)
                            } label: {
                                strengthRow(item: item)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if index < gainers.count - 1 {
                                Divider()
                                    .padding(.horizontal, Theme.Spacing.lg)
                            }
                        }
                    }
                    .softCard(elevation: 2)
                }

                if !decliners.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Needs Attention")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.warning)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.top, Theme.Spacing.sm)

                        VStack(spacing: 0) {
                            ForEach(Array(decliners.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    selectedExercise = ExerciseSelection(id: item.name)
                                } label: {
                                    strengthRow(item: item)
                                }
                                .buttonStyle(PlainButtonStyle())

                                if index < decliners.count - 1 {
                                    Divider()
                                        .padding(.horizontal, Theme.Spacing.lg)
                                }
                            }
                        }
                        .softCard(elevation: 1)
                    }
                }
            }
        }
    }

    private func strengthRow(item: ProgressContribution) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            strengthTrendIcon(for: item.delta)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(strengthChangeText(item.delta))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func strengthTrendIcon(for delta: Double) -> some View {
        let (icon, color): (String, Color) = {
            if delta > 10 { return ("arrow.up.circle.fill", Theme.Colors.success) }
            if delta > 0 { return ("arrow.up.right.circle.fill", Theme.Colors.success) }
            if delta < -10 { return ("arrow.down.circle.fill", Theme.Colors.warning) }
            if delta < 0 { return ("arrow.down.right.circle.fill", Theme.Colors.warning) }
            return ("equal.circle.fill", Theme.Colors.textTertiary)
        }()

        Image(systemName: icon)
            .font(.title2)
            .foregroundColor(color)
    }

    private func strengthChangeText(_ delta: Double) -> String {
        if abs(delta) < 0.5 { return "Holding steady" }
        let direction = delta > 0 ? "Up" : "Down"
        return "\(direction) \(formatWeight(abs(delta)))"
    }

    // MARK: - Muscle Balance

    private var muscleBalanceSection: some View {
        let buckets = muscleVolumeBuckets()

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Muscle Focus")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if buckets.isEmpty {
                Text("Tag your exercises with muscle groups to see your training balance.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            } else {
                PerformanceMuscleFocusChart(buckets: buckets)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            }
        }
    }

    private func muscleVolumeBuckets() -> [PerformanceMuscleVolumeBucket] {
        let calendar = Calendar.current
        let eightWeeksAgo = calendar.date(byAdding: .day, value: -56, to: Date()) ?? Date()
        let recent = workouts.filter { $0.date >= eightWeeksAgo }

        var groupVolumes: [MuscleTag: Double] = [:]
        for workout in recent {
            for exercise in workout.exercises {
                let tags = muscleMapping[exercise.name] ?? []
                for tag in tags {
                    groupVolumes[tag, default: 0] += exercise.totalVolume
                }
            }
        }

        let total = groupVolumes.values.reduce(0, +)
        guard total > 0 else { return [] }

        let sorted = groupVolumes
            .sorted { $0.value > $1.value }

        return sorted.enumerated().map { index, entry in
            PerformanceMuscleVolumeBucket(
                name: entry.key.shortName,
                volume: entry.value,
                share: entry.value / total,
                tint: entry.key.tint,
                rank: index
            )
        }
    }

    // MARK: - Weekly Activity

    private var weeklyActivitySection: some View {
        let weeks = weeklyWorkoutCounts()

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Weekly Activity")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if weeks.isEmpty {
                Text("Your weekly training pattern will appear here.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            } else {
                PerformanceWeeklyChart(weeks: weeks)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            }
        }
    }

    private func weeklyWorkoutCounts() -> [PerformanceWeeklyCount] {
        let calendar = Calendar.current
        guard let latest = workouts.map(\.date).max() else { return [] }

        let maxWeeks = 12
        var counts: [Date: Int] = [:]

        for workout in workouts {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.date)
            guard let weekStart = calendar.date(from: comps) else { continue }
            counts[weekStart, default: 0] += 1
        }

        // Include all weeks in range, even those with zero workouts
        let earliest = calendar.date(byAdding: .day, value: -(maxWeeks * 7), to: latest) ?? latest
        let earliestComps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: earliest)
        guard var cursor = calendar.date(from: earliestComps) else {
            return counts.keys.sorted().suffix(maxWeeks).map {
                PerformanceWeeklyCount(weekStart: $0, count: counts[$0] ?? 0)
            }
        }

        let latestComps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: latest)
        guard let latestWeekStart = calendar.date(from: latestComps) else {
            return []
        }

        var result: [PerformanceWeeklyCount] = []
        while cursor <= latestWeekStart {
            result.append(PerformanceWeeklyCount(weekStart: cursor, count: counts[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }

        return Array(result.suffix(maxWeeks))
    }

    // MARK: - Helpers

    private func formatWeight(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk lbs", value / 1000)
        }
        return "\(Int(round(value))) lbs"
    }
}

// MARK: - Comparison Row

private struct PerformanceComparisonRow: View {
    let metric: ChangeMetric

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayTitle)
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Text(changeLabel)
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(changeTint)
            }

            // Visual progress bar comparing the two periods
            GeometryReader { geo in
                let maxVal = max(metric.current, metric.previous, 1)
                let barSpace = geo.size.width - 100
                let currentWidth = max((metric.current / maxVal) * barSpace, 4)
                let previousWidth = max((metric.previous / maxVal) * barSpace, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Now")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(width: 42, alignment: .trailing)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.Colors.accent.opacity(0.12))
                                .frame(height: 14)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.Colors.accent)
                                .frame(width: currentWidth, height: 14)
                        }
                        Text(formatValue(metric.current))
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .frame(minWidth: 40, alignment: .leading)
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Before")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(width: 42, alignment: .trailing)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.Colors.textTertiary.opacity(0.12))
                                .frame(height: 14)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.Colors.textTertiary.opacity(0.4))
                                .frame(width: previousWidth, height: 14)
                        }
                        Text(formatValue(metric.previous))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(minWidth: 40, alignment: .leading)
                    }
                }
            }
            .frame(height: 40)
        }
    }

    private var displayTitle: String {
        switch metric.title {
        case "Sessions": return "Workouts"
        case "Total Volume": return "Weight Lifted"
        case "Avg Duration": return "Avg Workout Length"
        default: return metric.title
        }
    }

    private var changeTint: Color {
        if abs(metric.delta) < 0.01 { return Theme.Colors.textSecondary }
        return metric.delta > 0 ? Theme.Colors.success : Theme.Colors.warning
    }

    private var changeLabel: String {
        if abs(metric.delta) < 0.01 { return "Same" }
        let direction = metric.delta > 0 ? "\u{2191}" : "\u{2193}"
        let percent = abs(metric.percentChange)
        if percent >= 1 {
            return "\(direction) \(Int(round(percent)))%"
        }
        return "\(direction) \(formatDelta(abs(metric.delta)))"
    }

    private func formatValue(_ value: Double) -> String {
        switch metric.title {
        case "Sessions":
            return "\(Int(round(value)))"
        case "Total Volume":
            return formatVolume(value)
        case "Avg Duration":
            return formatDuration(value)
        default:
            return String(format: "%.0f", value)
        }
    }

    private func formatDelta(_ value: Double) -> String {
        switch metric.title {
        case "Sessions": return "\(Int(round(value)))"
        case "Total Volume": return formatVolume(value)
        case "Avg Duration": return formatDuration(value)
        default: return String(format: "%.1f", value)
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

    private func formatDuration(_ minutes: Double) -> String {
        let value = Int(round(minutes))
        if value >= 60 { return "\(value / 60)h \(value % 60)m" }
        return "\(value)m"
    }
}

// MARK: - Muscle Donut Chart

struct PerformanceMuscleVolumeBucket: Identifiable {
    let name: String
    let volume: Double
    let share: Double
    let tint: Color
    let rank: Int
    var id: String { name }
}

private struct PerformanceMuscleFocusChart: View {
    let buckets: [PerformanceMuscleVolumeBucket]

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Chart(buckets) { bucket in
                SectorMark(
                    angle: .value("Volume", bucket.volume),
                    innerRadius: .ratio(0.55),
                    angularInset: 2
                )
                .foregroundStyle(bucket.tint)
                .cornerRadius(4)
            }
            .frame(height: 200)
            .chartLegend(.hidden)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Theme.Spacing.sm
            ) {
                ForEach(buckets) { bucket in
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(bucket.tint)
                            .frame(width: 10, height: 10)
                        Text(bucket.name)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(round(bucket.share * 100)))%")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Weekly Activity Chart

struct PerformanceWeeklyCount: Identifiable {
    let weekStart: Date
    let count: Int
    var id: Date { weekStart }
}

private struct PerformanceWeeklyChart: View {
    let weeks: [PerformanceWeeklyCount]

    private var average: Double {
        guard !weeks.isEmpty else { return 0 }
        return Double(weeks.map(\.count).reduce(0, +)) / Double(weeks.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last \(weeks.count) weeks")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Text("Avg \(String(format: "%.1f", average))/wk")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.accent)
            }

            Chart {
                ForEach(weeks) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Workouts", week.count)
                    )
                    .foregroundStyle(
                        week.count >= Int(ceil(average))
                            ? Theme.Colors.accent
                            : Theme.Colors.accent.opacity(0.35)
                    )
                    .cornerRadius(3)
                }

                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                        }
                    }
                }
            }
            .frame(height: 180)
        }
    }
}
