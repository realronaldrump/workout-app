import SwiftUI
import Charts

struct PerformanceLabView: View {
    private enum TimeFilter: String, CaseIterable {
        case twoWeeks = "2 Weeks"
        case fourWeeks = "4 Weeks"
        case eightWeeks = "8 Weeks"
        case twelveWeeks = "12 Weeks"
        case custom = "Custom"

        var days: Int? {
            switch self {
            case .twoWeeks: return 14
            case .fourWeeks: return 28
            case .eightWeeks: return 56
            case .twelveWeeks: return 84
            case .custom: return nil
            }
        }
    }

    @ObservedObject var dataManager: WorkoutDataManager
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager

    @State private var selectedTimeFilter: TimeFilter = .twoWeeks
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var didInitializeCustomRange = false
    @State private var selectedWorkout: Workout?
    @State private var selectedExercise: ExerciseSelection?
    @State private var selectedChangeMetric: ChangeMetric?

    private let maxContentWidth: CGFloat = 820

    private struct MuscleWorkChange: Identifiable {
        let tag: MuscleTag
        let currentEffort: Double
        let previousEffort: Double
        let currentShare: Double
        let previousShare: Double

        var id: String { tag.id }
        var deltaEffort: Double { currentEffort - previousEffort }
        var deltaShare: Double { currentShare - previousShare }
    }

    private var workouts: [Workout] {
        dataManager.workouts
    }

    private var muscleMapping: [String: [MuscleTag]] {
        let names = Set(workouts.flatMap { $0.exercises.map { $0.name } })
        return ExerciseMetadataManager.shared.resolvedMappings(for: names)
    }

    private var timeFilterOptions: [(label: String, value: TimeFilter)] {
        TimeFilter.allCases.map { (label: $0.rawValue, value: $0) }
    }

    private var earliestWorkoutDate: Date? {
        workouts.map(\.date).min()
    }

    private var latestWorkoutDate: Date? {
        workouts.map(\.date).max()
    }

    private var latestSelectableDate: Date {
        latestWorkoutDate ?? Date()
    }

    private var selectedWindowLabel: String {
        selectedTimeFilter.rawValue
    }

    private var selectedWindowContextLabel: String {
        selectedTimeFilter == .custom ? "Custom Range" : selectedWindowLabel
    }

    private var selectedRangeDetailLabel: String {
        guard let selectedRangeInterval else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        let start = formatter.string(from: selectedRangeInterval.start)
        let end = formatter.string(from: selectedRangeInterval.end)
        return start == end ? start : "\(start) - \(end)"
    }

    private var selectedRangeDayCount: Int {
        guard let selectedRangeInterval else { return 1 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedRangeInterval.start)
        let end = calendar.startOfDay(for: selectedRangeInterval.end)
        let days = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return max(1, days)
    }

    private var selectedWindowWeeks: Int {
        max(1, Int(ceil(Double(selectedRangeDayCount) / 7.0)))
    }

    private var selectedWindowTrendSubtitle: String {
        if selectedTimeFilter == .custom {
            return "selected range vs previous \(selectedRangeDayCount)-day span"
        }
        return "last \(selectedWindowWeeks) weeks vs the \(selectedWindowWeeks) before"
    }

    private var selectedRangeInterval: DateInterval? {
        guard let latestWorkoutDate else { return nil }
        let calendar = Calendar.current

        if let days = selectedTimeFilter.days {
            let start = calendar.date(byAdding: .day, value: -days, to: latestWorkoutDate) ?? latestWorkoutDate
            return DateInterval(start: start, end: latestWorkoutDate)
        }

        let earliest = earliestWorkoutDate ?? latestWorkoutDate
        let clampedStart = max(calendar.startOfDay(for: customStartDate), calendar.startOfDay(for: earliest))
        let clampedEndDay = min(calendar.startOfDay(for: customEndDate), calendar.startOfDay(for: latestWorkoutDate))
        let clampedEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: clampedEndDay) ?? clampedEndDay
        return DateInterval(start: min(clampedStart, clampedEnd), end: max(clampedStart, clampedEnd))
    }

    private var selectedRangeWorkouts: [Workout] {
        guard let selectedRangeInterval else { return [] }
        return workouts.filter { selectedRangeInterval.contains($0.date) }
    }

    private var workoutsThroughRangeEnd: [Workout] {
        guard let selectedRangeInterval else { return workouts }
        return workouts.filter { $0.date <= selectedRangeInterval.end }
    }

    private var selectedChangeWindow: ChangeMetricWindow? {
        guard let current = selectedRangeInterval else { return nil }
        let previous = previousInterval(matching: current)
        let label: String = selectedTimeFilter == .custom
            ? "Custom range vs previous \(selectedRangeDayCount)-day span"
            : "\(selectedWindowLabel) vs previous \(selectedWindowLabel.lowercased())"
        return ChangeMetricWindow(label: label, current: current, previous: previous)
    }

    private var muscleWorkChanges: [MuscleWorkChange] {
        guard let selectedChangeWindow else { return [] }

        let currentWorkouts = workouts.filter { selectedChangeWindow.current.contains($0.date) }
        let previousWorkouts = workouts.filter { selectedChangeWindow.previous.contains($0.date) }

        let currentTotals = muscleEffortTotals(for: currentWorkouts)
        let previousTotals = muscleEffortTotals(for: previousWorkouts)
        let currentTotalEffort = max(1, currentTotals.values.reduce(0, +))
        let previousTotalEffort = max(1, previousTotals.values.reduce(0, +))

        let allTags = Set(currentTotals.keys).union(previousTotals.keys)
        return allTags.compactMap { tag in
            let currentEffort = currentTotals[tag] ?? 0
            let previousEffort = previousTotals[tag] ?? 0
            guard currentEffort > 0 || previousEffort > 0 else { return nil }
            return MuscleWorkChange(
                tag: tag,
                currentEffort: currentEffort,
                previousEffort: previousEffort,
                currentShare: currentEffort / currentTotalEffort,
                previousShare: previousEffort / previousTotalEffort
            )
        }
        .sorted { abs($0.deltaEffort) > abs($1.deltaEffort) }
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
                        timeRangeSection

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
                label: "Selected range",
                current: DateInterval(start: fallbackNow, end: fallbackNow),
                previous: DateInterval(start: fallbackNow, end: fallbackNow)
            )
            ChangeMetricDetailView(
                metric: metric,
                window: selectedChangeWindow ?? fallbackWindow,
                workouts: workouts
            )
        }
        .onAppear {
            synchronizeCustomRange()
        }
        .onChange(of: latestWorkoutDate) { _, _ in
            synchronizeCustomRange()
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
        guard let latest = latestWorkoutDate else {
            return "Start logging workouts to track your progress."
        }
        let through = latest.formatted(date: .abbreviated, time: .omitted)
        return "\(selectedRangeWorkouts.count) workouts in \(selectedWindowContextLabel) • \(workouts.count) total through \(through)"
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

    // MARK: - Time Range

    private var timeRangeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Time Range")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(selectedRangeDetailLabel)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            BrutalistSegmentedPicker(
                title: "Time Range",
                selection: $selectedTimeFilter,
                options: timeFilterOptions
            )

            if selectedTimeFilter == .custom {
                BrutalistDateRangePickerRow(
                    title: "Custom Range",
                    startDate: $customStartDate,
                    endDate: $customEndDate,
                    earliestSelectableDate: earliestWorkoutDate,
                    latestSelectableDate: latestSelectableDate
                )
            }
        }
    }

    // MARK: - At a Glance

    private var atAGlanceSection: some View {
        let streakRuns = WorkoutAnalytics.streakRuns(for: selectedRangeWorkouts, intentionalRestDays: 2)
        let currentStreak = streakRuns.last?.workoutDayCount ?? 0
        let bestStreak = streakRuns.map(\.workoutDayCount).max() ?? 0
        let avgPerWeek = Double(selectedRangeWorkouts.count) / Double(selectedWindowWeeks)
        let avgPerWeekText = String(format: "%.1f", avgPerWeek)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("At a Glance")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    glanceTile(
                        value: "\(selectedRangeWorkouts.count)",
                        label: "In \(selectedWindowContextLabel)",
                        icon: "calendar"
                    )
                    glanceTile(
                        value: avgPerWeekText,
                        label: "Avg / Week",
                        icon: "chart.bar.fill"
                    )
                    glanceTile(
                        value: "\(currentStreak)",
                        label: currentStreak == bestStreak && currentStreak > 0 ? "Day Streak \u{2605}" : "Day Streak",
                        icon: "flame.fill"
                    )
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                    glanceTile(
                        value: "\(selectedRangeWorkouts.count)",
                        label: "In \(selectedWindowContextLabel)",
                        icon: "calendar"
                    )
                    glanceTile(
                        value: avgPerWeekText,
                        label: "Avg / Week",
                        icon: "chart.bar.fill"
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
        let window = selectedChangeWindow
        let changes = window.map { WorkoutAnalytics.changeMetrics(for: workouts, window: $0) } ?? []

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Trending")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if let window {
                Text(window.label)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

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
                            action: { selectedChangeMetric = metric },
                            content: {
                                PerformanceComparisonRow(metric: metric)
                                    .padding(Theme.Spacing.lg)
                                    .softCard(elevation: 1)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Strength Gains

    private var strengthGainsSection: some View {
        let contributions = WorkoutAnalytics.progressContributions(
            workouts: workoutsThroughRangeEnd,
            weeks: selectedWindowWeeks,
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

            Text("Best weight per exercise \u{2014} \(selectedWindowTrendSubtitle)")
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
        let changes = muscleWorkChanges

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Muscle Focus")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Distribution across tagged groups in \(selectedRangeDetailLabel).")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

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

            if !changes.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Change by Muscle Group")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    if let selectedChangeWindow {
                        Text(selectedChangeWindow.label)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                            muscleChangeRow(change)
                            if index < changes.count - 1 {
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

    private func muscleVolumeBuckets() -> [PerformanceMuscleVolumeBucket] {
        let groupVolumes = muscleEffortTotals(for: selectedRangeWorkouts)

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

    private func muscleEffortTotals(for sourceWorkouts: [Workout]) -> [MuscleTag: Double] {
        var totals: [MuscleTag: Double] = [:]
        for workout in sourceWorkouts {
            for exercise in workout.exercises {
                let tags = muscleMapping[exercise.name] ?? []
                guard !tags.isEmpty else { continue }
                let effort = exerciseEffortScore(exercise)
                guard effort > 0 else { continue }
                for tag in tags {
                    totals[tag, default: 0] += effort
                }
            }
        }
        return totals
    }

    private func muscleChangeRow(_ change: MuscleWorkChange) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(change.tag.tint)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(change.tag.shortName)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("Now \(percentLabel(for: change.currentShare)) • Before \(percentLabel(for: change.previousShare))")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(shareDeltaLabel(for: change.deltaShare))
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(deltaTint(for: change.deltaEffort))
                Text(relativeEffortChangeLabel(current: change.currentEffort, previous: change.previousEffort))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
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
        guard let selectedRangeInterval else { return [] }

        var counts: [Date: Int] = [:]

        for workout in selectedRangeWorkouts {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.date)
            guard let weekStart = calendar.date(from: comps) else { continue }
            counts[weekStart, default: 0] += 1
        }

        let rangeStartComps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedRangeInterval.start)
        let rangeEndComps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedRangeInterval.end)
        guard var cursor = calendar.date(from: rangeStartComps),
              let latestWeekStart = calendar.date(from: rangeEndComps) else { return [] }

        var result: [PerformanceWeeklyCount] = []
        while cursor <= latestWeekStart {
            result.append(PerformanceWeeklyCount(weekStart: cursor, count: counts[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }

        return result
    }

    // MARK: - Helpers

    private func exerciseEffortScore(_ exercise: Exercise) -> Double {
        let weightedVolume = exercise.totalVolume
        if weightedVolume > 0 {
            return weightedVolume
        }

        let count = exercise.sets.reduce(0) { $0 + max($1.reps, 0) }
        let distance = exercise.sets.reduce(0.0) { $0 + max($1.distance, 0) }
        let seconds = exercise.sets.reduce(0.0) { $0 + max($1.seconds, 0) }

        // Cardio and bodyweight sets can be recorded as count/distance/time with zero weight.
        // Convert those metrics into effort points so tagged groups (e.g. Cardio/Floors) contribute.
        let countPoints = Double(count) * 10.0
        let distancePoints = distance * 100.0
        let durationPoints = seconds / 60.0
        let fallbackSetPoints = Double(exercise.sets.count) * 25.0

        return max(fallbackSetPoints, countPoints + distancePoints + durationPoints)
    }

    private func percentLabel(for share: Double) -> String {
        let percent = share * 100
        if percent <= 0 { return "0%" }
        if percent < 0.1 { return "<0.1%" }
        if percent < 1 { return String(format: "%.1f%%", percent) }
        return "\(Int(round(percent)))%"
    }

    private func shareDeltaLabel(for deltaShare: Double) -> String {
        let points = deltaShare * 100
        if abs(points) < 0.05 { return "0.0 pts" }
        return String(format: "%+.1f pts", points)
    }

    private func relativeEffortChangeLabel(current: Double, previous: Double) -> String {
        if previous <= 0 {
            return current > 0 ? "new activity" : "no change"
        }
        let percent = ((current - previous) / previous) * 100
        return String(format: "%+.0f%% effort", percent)
    }

    private func deltaTint(for delta: Double) -> Color {
        if abs(delta) < 0.001 { return Theme.Colors.textSecondary }
        return delta > 0 ? Theme.Colors.success : Theme.Colors.warning
    }

    private func previousInterval(matching current: DateInterval) -> DateInterval {
        let previousEnd = current.start.addingTimeInterval(-0.001)
        let previousStart = previousEnd.addingTimeInterval(-max(current.duration, 1))
        return DateInterval(start: previousStart, end: previousEnd)
    }

    private func synchronizeCustomRange() {
        guard let latestWorkoutDate else { return }
        let earliest = earliestWorkoutDate ?? latestWorkoutDate
        let calendar = Calendar.current

        if !didInitializeCustomRange {
            customEndDate = calendar.startOfDay(for: latestWorkoutDate)
            let suggestedStart = calendar.date(byAdding: .day, value: -27, to: customEndDate) ?? earliest
            customStartDate = max(calendar.startOfDay(for: earliest), calendar.startOfDay(for: suggestedStart))
            didInitializeCustomRange = true
            return
        }

        customEndDate = min(calendar.startOfDay(for: customEndDate), calendar.startOfDay(for: latestWorkoutDate))
        customStartDate = max(calendar.startOfDay(for: customStartDate), calendar.startOfDay(for: earliest))
        if customStartDate > customEndDate {
            customStartDate = customEndDate
        }
    }

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
                        Text(percentLabel(for: bucket.share))
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }
        }
    }

    private func percentLabel(for share: Double) -> String {
        let percent = share * 100
        if percent <= 0 { return "0%" }
        if percent < 0.1 { return "<0.1%" }
        if percent < 1 { return String(format: "%.1f%%", percent) }
        return "\(Int(round(percent)))%"
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
                        if let countValue = value.as(Int.self) {
                            Text("\(countValue)")
                        }
                    }
                }
            }
            .frame(height: 180)
        }
    }
}
