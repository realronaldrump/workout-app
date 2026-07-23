import Charts
import Combine
import SwiftUI

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
    let annotationsManager: WorkoutAnnotationsManager
    let gymProfilesManager: GymProfilesManager
    @EnvironmentObject var intentionalBreaksManager: IntentionalBreaksManager
    @EnvironmentObject var variantEngine: WorkoutVariantEngine
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var relationshipManager = ExerciseRelationshipManager.shared
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1

    @State private var selectedTimeFilter: TimeFilter = .twoWeeks
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var didInitializeCustomRange = false
    @State private var selectedWorkout: Workout?
    @State private var selectedExercise: ExerciseSelection?
    @State private var selectedChangeMetric: ChangeMetric?
    @State private var derivedAnalytics = DerivedAnalytics()
    @State private var derivedRefreshTask: Task<Void, Never>?

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

    private struct DerivedAnalytics {
        var selectedRangeWorkouts: [Workout] = []
        var averageWorkoutsPerWeek = 0.0
        var currentStreak = 0
        var bestStreak = 0
        var changeMetrics: [ChangeMetric] = []
        var strengthContributions: [ProgressContribution] = []
        var muscleBuckets: [PerformanceMuscleVolumeBucket] = []
        var muscleWorkChanges: [MuscleWorkChange] = []
        var weeklyCounts: [PerformanceWeeklyCount] = []
    }

    init(
        dataManager: WorkoutDataManager,
        annotationsManager: WorkoutAnnotationsManager,
        gymProfilesManager: GymProfilesManager
    ) {
        self.dataManager = dataManager
        self.annotationsManager = annotationsManager
        self.gymProfilesManager = gymProfilesManager
    }

    private var workouts: [Workout] {
        dataManager.workouts
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
        Date()
    }

    private var selectedWindowLabel: String {
        selectedTimeFilter.rawValue
    }

    private var selectedWindowContextLabel: String {
        selectedTimeFilter == .custom ? "Custom Range" : selectedWindowLabel
    }

    private var selectedRangeDetailLabel: String {
        guard let selectedRangeInterval else { return "--" }
        let start = PerformanceLabFormatters.rangeDate.string(from: selectedRangeInterval.start)
        let end = PerformanceLabFormatters.rangeDate.string(from: selectedRangeInterval.end)
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
        if let days = selectedTimeFilter.days {
            return max(days / 7, 1)
        }
        return max(1, Int(ceil(Double(selectedRangeDayCount) / 7.0)))
    }

    private var selectedWindowTrendSubtitle: String {
        if selectedTimeFilter == .custom {
            return "selected range vs previous \(selectedRangeDayCount)-day span"
        }
        return "last \(selectedWindowWeeks) weeks vs the \(selectedWindowWeeks) before"
    }

    private var selectedRangeInterval: DateInterval? {
        guard earliestWorkoutDate != nil else { return nil }
        let calendar = Calendar.current
        let today = Date()

        if let days = selectedTimeFilter.days {
            let todayStart = calendar.startOfDay(for: today)
            let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: todayStart) ?? todayStart
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: todayStart) ?? today
            return DateInterval(start: start, end: end)
        }

        let earliest = earliestWorkoutDate ?? today
        let clampedStart = max(calendar.startOfDay(for: customStartDate), calendar.startOfDay(for: earliest))
        let clampedEndDay = calendar.startOfDay(for: customEndDate)
        let clampedEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: clampedEndDay) ?? clampedEndDay
        return DateInterval(start: min(clampedStart, clampedEnd), end: max(clampedStart, clampedEnd))
    }

    private var selectedRangeWorkouts: [Workout] {
        derivedAnalytics.selectedRangeWorkouts
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
        derivedAnalytics.muscleWorkChanges
    }

    private var glanceGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 140, maximum: 240), spacing: Theme.Spacing.md)]
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

                        PerformanceLabVariantSection(
                            patterns: Array(variantEngine.library.standoutPatterns.prefix(2)),
                            onSelectWorkout: { selectedWorkout = $0 }
                        )

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
            refreshDerivedAnalytics()
        }
        .onReceive(dataManager.$workouts.dropFirst()) { _ in
            scheduleDerivedAnalyticsRefresh(synchronizesCustomRange: true)
        }
        .onChange(of: selectedTimeFilter) { _, _ in
            scheduleDerivedAnalyticsRefresh()
        }
        .onChange(of: customStartDate) { _, _ in
            guard selectedTimeFilter == .custom else { return }
            scheduleDerivedAnalyticsRefresh()
        }
        .onChange(of: customEndDate) { _, _ in
            guard selectedTimeFilter == .custom else { return }
            scheduleDerivedAnalyticsRefresh()
        }
        .onChange(of: intentionalRestDays) { _, _ in
            scheduleDerivedAnalyticsRefresh()
        }
        .onReceive(intentionalBreaksManager.$savedBreaks.dropFirst()) { _ in
            scheduleDerivedAnalyticsRefresh()
        }
        .onReceive(metadataManager.$muscleTagOverrides.dropFirst()) { _ in
            scheduleDerivedAnalyticsRefresh()
        }
        .onReceive(relationshipManager.$relationships.dropFirst()) { _ in
            scheduleDerivedAnalyticsRefresh()
        }
        .onDisappear {
            derivedRefreshTask?.cancel()
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

            timeRangePicker

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

    @ViewBuilder
    private var timeRangePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Time Range", selection: $selectedTimeFilter) {
                ForEach(timeFilterOptions.indices, id: \.self) { index in
                    let option = timeFilterOptions[index]
                    Text(option.label)
                        .tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 1)
            )
            .onChange(of: selectedTimeFilter) { _, _ in
                Haptics.toggle()
            }
        } else {
            AppSegmentedPicker(
                title: "Time Range",
                selection: $selectedTimeFilter,
                options: timeFilterOptions
            )
        }
    }

    // MARK: - At a Glance

    private var atAGlanceSection: some View {
        let currentStreak = derivedAnalytics.currentStreak
        let bestStreak = derivedAnalytics.bestStreak
        let avgPerWeekText = String(format: "%.1f", derivedAnalytics.averageWorkoutsPerWeek)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("At a Glance")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: glanceGridColumns, spacing: Theme.Spacing.md) {
                    glanceTiles(currentStreak: currentStreak, bestStreak: bestStreak, avgPerWeekText: avgPerWeekText)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.md) {
                        glanceTiles(currentStreak: currentStreak, bestStreak: bestStreak, avgPerWeekText: avgPerWeekText)
                    }

                    LazyVGrid(columns: glanceGridColumns, spacing: Theme.Spacing.md) {
                        glanceTiles(currentStreak: currentStreak, bestStreak: bestStreak, avgPerWeekText: avgPerWeekText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func glanceTiles(currentStreak: Int, bestStreak: Int, avgPerWeekText: String) -> some View {
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

    private func glanceTile(value: String, label: String, icon: String) -> some View {
        let tileColor: Color = {
            switch icon {
            case "flame.fill": return Theme.Colors.accentSecondary
            case "chart.bar.fill": return Theme.Colors.success
            default: return Theme.Colors.accent
            }
        }()

        return VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Iconography.title3)
                .foregroundColor(tileColor)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(tileColor.opacity(Theme.Opacity.subtleFill))
                )
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
        let changes = derivedAnalytics.changeMetrics

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
        let exerciseGains = derivedAnalytics.strengthContributions
            .filter { $0.category == .exercise }
            .sorted { $0.delta > $1.delta }
        let gainers = Array(exerciseGains.filter { $0.delta > 0 }.prefix(5))
        let decliners = Array(exerciseGains.filter { $0.delta < 0 }.sorted { $0.delta < $1.delta }.prefix(3))

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Strength Trends")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Best load per exercise \u{2014} \(selectedWindowTrendSubtitle)")
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
                .font(Theme.Typography.caption)
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
            .font(Theme.Iconography.title2)
            .foregroundColor(color)
    }

    private func strengthChangeText(_ delta: Double) -> String {
        if abs(delta) < 0.5 { return "Holding steady" }
        let direction = delta > 0 ? "Up" : "Down"
        return "\(direction) \(formatWeight(abs(delta)))"
    }

    // MARK: - Muscle Balance

    private var muscleBalanceSection: some View {
        let buckets = derivedAnalytics.muscleBuckets
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

    private func muscleVolumeBuckets(
        from groupVolumes: [MuscleTag: Double]
    ) -> [PerformanceMuscleVolumeBucket] {
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

    private func muscleEffortTotals(
        for sourceWorkouts: [Workout],
        mappings: [String: [MuscleTag]],
        resolver: ExerciseIdentityResolver
    ) -> [MuscleTag: Double] {
        var totals: [MuscleTag: Double] = [:]
        for workout in sourceWorkouts {
            for exercise in ExerciseAggregation.aggregateExercises(in: workout, resolver: resolver) {
                let tags = mappings[exercise.name]
                    ?? metadataManager.resolvedTags(for: exercise.name)
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

    private func makeMuscleWorkChanges(
        currentTotals: [MuscleTag: Double],
        previousTotals: [MuscleTag: Double]
    ) -> [MuscleWorkChange] {
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
        let weeks = derivedAnalytics.weeklyCounts

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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Weekly activity")
                    .accessibilityValue(
                        "\(weeks.reduce(0) { $0 + $1.count }) workouts across \(weeks.count) weeks."
                    )
            }
        }
    }

    private func weeklyWorkoutCounts(
        workouts: [Workout],
        range: DateInterval
    ) -> [PerformanceWeeklyCount] {
        let calendar = Calendar.current

        var counts: [Date: Int] = [:]

        for workout in workouts {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workout.date)
            guard let weekStart = calendar.date(from: comps) else { continue }
            counts[weekStart, default: 0] += 1
        }

        let rangeStartComps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: range.start)
        let rangeEndComps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: range.end)
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

    private func scheduleDerivedAnalyticsRefresh(
        synchronizesCustomRange: Bool = false
    ) {
        derivedRefreshTask?.cancel()
        derivedRefreshTask = Task { @MainActor in
            // @Published sends before its stored value changes. Yield once so a burst of
            // related manager publications collapses into one snapshot of committed state.
            await Task.yield()
            guard !Task.isCancelled else { return }
            if synchronizesCustomRange {
                synchronizeCustomRange()
            }
            refreshDerivedAnalytics()
        }
    }

    private func refreshDerivedAnalytics() {
        guard let range = selectedRangeInterval,
              let window = selectedChangeWindow else {
            derivedAnalytics = DerivedAnalytics()
            return
        }

        var currentWorkouts: [Workout] = []
        var previousWorkouts: [Workout] = []
        currentWorkouts.reserveCapacity(workouts.count)
        previousWorkouts.reserveCapacity(workouts.count)

        for workout in workouts {
            if range.contains(workout.date) {
                currentWorkouts.append(workout)
            } else if window.previous.contains(workout.date) {
                previousWorkouts.append(workout)
            }
        }

        let resolver = relationshipManager.resolverSnapshot()
        let exerciseNames = Set(
            (currentWorkouts + previousWorkouts).flatMap { workout in
                workout.exercises.map(\.name)
            }
        )
        let mappings = metadataManager.resolvedMappings(for: exerciseNames)
        let streakRuns = WorkoutAnalytics.streakRuns(
            for: currentWorkouts,
            intentionalRestDays: intentionalRestDays,
            intentionalBreakRanges: intentionalBreaksManager.savedBreaks
        )
        let currentMuscleTotals = muscleEffortTotals(
            for: currentWorkouts,
            mappings: mappings,
            resolver: resolver
        )
        let previousMuscleTotals = muscleEffortTotals(
            for: previousWorkouts,
            mappings: mappings,
            resolver: resolver
        )

        derivedAnalytics = DerivedAnalytics(
            selectedRangeWorkouts: currentWorkouts,
            averageWorkoutsPerWeek: WorkoutAnalytics.workoutsPerWeek(
                for: currentWorkouts,
                in: range,
                intentionalBreakRanges: intentionalBreaksManager.savedBreaks
            ),
            currentStreak: WorkoutAnalytics.currentDayStreak(
                for: currentWorkouts,
                intentionalRestDays: intentionalRestDays,
                intentionalBreakRanges: intentionalBreaksManager.savedBreaks,
                referenceDate: min(range.end, Date())
            ),
            bestStreak: streakRuns.map(\.workoutDayCount).max() ?? 0,
            changeMetrics: WorkoutAnalytics.changeMetrics(
                current: currentWorkouts,
                previous: previousWorkouts,
                resolver: resolver
            ),
            strengthContributions: WorkoutAnalytics.progressContributions(
                current: currentWorkouts,
                previous: previousWorkouts,
                mappings: mappings,
                resolver: resolver
            ),
            muscleBuckets: muscleVolumeBuckets(from: currentMuscleTotals),
            muscleWorkChanges: makeMuscleWorkChanges(
                currentTotals: currentMuscleTotals,
                previousTotals: previousMuscleTotals
            ),
            weeklyCounts: weeklyWorkoutCounts(workouts: currentWorkouts, range: range)
        )
    }

    // MARK: - Helpers

    private func exerciseEffortScore(_ exercise: Exercise) -> Double {
        let weightedVolume = exercise.totalVolume
        if weightedVolume > 0 {
            return weightedVolume
        }

        let count = exercise.sets.reduce(0) { $0 + max($1.reps, 0) }
        let distance = exercise.sets.reduce(0.0) { $0 + max($1.distance, 0) }

        // Cardio and bodyweight sets can be recorded as count/distance with zero weight.
        // Convert those metrics into effort points so tagged groups (e.g. Cardio/Floors) contribute.
        let countPoints = Double(count) * 10.0
        let distancePoints = distance * 100.0
        let fallbackSetPoints = Double(exercise.sets.count) * 25.0

        return max(fallbackSetPoints, countPoints + distancePoints)
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
        let calendar = Calendar.current
        let currentStartDay = calendar.startOfDay(for: current.start)
        let currentEndDay = calendar.startOfDay(for: current.end)
        let dayCount = max(
            (calendar.dateComponents([.day], from: currentStartDay, to: currentEndDay).day ?? 0) + 1,
            1
        )
        let previousEndDay = calendar.date(byAdding: .day, value: -1, to: currentStartDay) ?? currentStartDay
        let previousStart = calendar.date(
            byAdding: .day,
            value: -(dayCount - 1),
            to: previousEndDay
        ) ?? previousEndDay
        let previousEnd = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: previousEndDay
        ) ?? previousEndDay
        return DateInterval(start: previousStart, end: previousEnd)
    }

    private func synchronizeCustomRange() {
        let today = Date()
        let earliest = earliestWorkoutDate ?? today
        let calendar = Calendar.current

        if !didInitializeCustomRange {
            customEndDate = calendar.startOfDay(for: today)
            let suggestedStart = calendar.date(byAdding: .day, value: -27, to: customEndDate) ?? earliest
            customStartDate = max(calendar.startOfDay(for: earliest), calendar.startOfDay(for: suggestedStart))
            didInitializeCustomRange = true
            return
        }

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

private enum PerformanceLabFormatters {
    static let rangeDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
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
            return SharedFormatters.volumeWithUnit(value)
        default:
            return String(format: "%.0f", value)
        }
    }

    private func formatDelta(_ value: Double) -> String {
        switch metric.title {
        case "Sessions": return "\(Int(round(value)))"
        case "Total Volume": return SharedFormatters.volumeWithUnit(value)
        default: return String(format: "%.1f", value)
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var legendColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

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
            .frame(height: Theme.ChartHeight.standard)
            .chartLegend(.hidden)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Muscle focus distribution")
            .accessibilityValue(accessibilitySummary)

            LazyVGrid(
                columns: legendColumns,
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
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
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
        if percent < 1 { return String(format: percent < 0.1 ? "<0.1%%" : "%.1f%%", percent) }
        return "\(Int(round(percent)))%"
    }

    private var accessibilitySummary: String {
        buckets.prefix(5)
            .map { "\($0.name), \(percentLabel(for: $0.share))" }
            .joined(separator: "; ")
    }
}
