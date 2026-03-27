import SwiftUI
import Charts
// swiftlint:disable type_body_length file_length

struct ChangeMetricDetailView: View {
    let metric: ChangeMetric
    let window: ChangeMetricWindow
    let workouts: [Workout]

    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager

    private enum WindowBucket: String {
        case previous
        case current
    }

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let window: WindowBucket
    }

    fileprivate struct SessionWindowSummary {
        let title: String
        let rangeLabel: String
        let workouts: [Workout]
        let sessionCount: Int
        let activeDays: Int
        let totalDurationMinutes: Int
        let averageDurationMinutes: Double
        let totalExercises: Int
        let averageExercisesPerSession: Double
        let totalSets: Int
        let averageSetsPerSession: Double
        let totalVolume: Double
        let averageVolumePerSession: Double
        let topWorkoutName: String?
        let busiestDayLabel: String?
    }

    fileprivate struct SessionDayComparison: Identifiable {
        let id: Int
        let label: String
        let dateLabel: String
        let currentCount: Int
        let previousCount: Int
    }

    fileprivate struct SessionTypeComparison: Identifiable {
        let name: String
        let currentCount: Int
        let previousCount: Int
        let currentVolume: Double

        var id: String { name }
        var delta: Int { currentCount - previousCount }
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private var currentWorkouts: [Workout] {
        workouts.filter { window.current.contains($0.date) }
    }

    private var previousWorkouts: [Workout] {
        workouts.filter { window.previous.contains($0.date) }
    }

    private var windowLabel: String {
        window.label
    }

    private var currentWindowTitle: String {
        if window.label.localizedCaseInsensitiveContains("week") {
            return "This Week"
        }
        return "Current Window"
    }

    private var previousWindowTitle: String {
        if window.label.localizedCaseInsensitiveContains("week") {
            return "Last Week"
        }
        return "Previous Window"
    }

    private var currentSessionSummary: SessionWindowSummary {
        buildSessionSummary(title: currentWindowTitle, workouts: currentWorkouts, interval: window.current)
    }

    private var previousSessionSummary: SessionWindowSummary {
        buildSessionSummary(title: previousWindowTitle, workouts: previousWorkouts, interval: window.previous)
    }

    private var sessionDayComparisons: [SessionDayComparison] {
        let currentStart = calendar.startOfDay(for: window.current.start)
        let previousStart = calendar.startOfDay(for: window.previous.start)
        let dayCount = max(dayCount(for: window.current), dayCount(for: window.previous))
        let currentCounts = dayCounts(for: currentWorkouts)
        let previousCounts = dayCounts(for: previousWorkouts)

        return (0..<dayCount).compactMap { offset in
            guard let currentDay = calendar.date(byAdding: .day, value: offset, to: currentStart),
                  let previousDay = calendar.date(byAdding: .day, value: offset, to: previousStart) else {
                return nil
            }

            let label: String
            if dayCount <= 7 {
                label = currentDay.formatted(.dateTime.weekday(.abbreviated))
            } else {
                label = currentDay.formatted(.dateTime.month(.abbreviated).day())
            }

            return SessionDayComparison(
                id: offset,
                label: label,
                dateLabel: "\(previousDay.formatted(.dateTime.month(.abbreviated).day())) vs \(currentDay.formatted(.dateTime.month(.abbreviated).day()))",
                currentCount: currentCounts[currentDay, default: 0],
                previousCount: previousCounts[previousDay, default: 0]
            )
        }
    }

    private var sessionTypeComparisons: [SessionTypeComparison] {
        let currentCounts = Dictionary(grouping: currentWorkouts, by: \.name).mapValues(\.count)
        let previousCounts = Dictionary(grouping: previousWorkouts, by: \.name).mapValues(\.count)
        let currentVolume = Dictionary(grouping: currentWorkouts, by: \.name).mapValues { items in
            items.reduce(0) { partialResult, workout in
                partialResult + workout.totalVolume
            }
        }

        let names = Set(currentCounts.keys).union(previousCounts.keys)
        return names.map { name in
            SessionTypeComparison(
                name: name,
                currentCount: currentCounts[name, default: 0],
                previousCount: previousCounts[name, default: 0],
                currentVolume: currentVolume[name, default: 0]
            )
        }
        .sorted { lhs, rhs in
            if lhs.currentCount != rhs.currentCount { return lhs.currentCount > rhs.currentCount }
            if lhs.previousCount != rhs.previousCount { return lhs.previousCount > rhs.previousCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var maxDailySessionCount: Int {
        max(1, sessionDayComparisons.map { max($0.currentCount, $0.previousCount) }.max() ?? 1)
    }

    private var sessionsHeroHeadline: String {
        if metric.delta > 0 {
            return "Session load is up."
        }
        if metric.delta < 0 {
            return "This week is lighter."
        }
        return "Same count, different shape."
    }

    private var sessionsHeroNarrative: String {
        let current = currentSessionSummary
        let previous = previousSessionSummary
        let activeDayLabel = "day\(current.activeDays == 1 ? "" : "s")"

        if current.sessionCount == 0 && previous.sessionCount == 0 {
            return "There are no sessions in either comparison window yet, so this screen will populate as soon as you log a workout."
        }

        if metric.delta > 0 {
            let delta = Int(metric.delta)
            let sessionLabel = "session\(delta == 1 ? "" : "s")"
            return "You trained on \(current.activeDays) \(activeDayLabel) and logged \(delta) more \(sessionLabel) than the previous window."
        }

        if metric.delta < 0 {
            let decrease = abs(Int(metric.delta))
            let sessionLabel = "session\(decrease == 1 ? "" : "s")"
            return "You trained on \(current.activeDays) \(activeDayLabel), which is \(decrease) fewer \(sessionLabel) than the previous window."
        }

        if current.activeDays != previous.activeDays {
            return "The session count held steady, but the training days shifted from \(previous.activeDays) to \(current.activeDays), so the rhythm changed."
        }

        return "Session count and active days stayed even, so the differences below come from timing, session mix, and per-session density."
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    if metric.title == "Sessions" {
                        sessionsDetailContent
                    } else {
                        defaultDetailContent
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sessionsDetailContent: some View {
        Group {
            sessionsHeroSection
            sessionsMetricGridSection
            sessionsRhythmSection
            sessionsMixSection
            sessionsFeedSection
        }
    }

    private var defaultDetailContent: some View {
        Group {
            headerSection
            chartSection
            supportingSection
        }
    }

    private var sessionsHeroSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("VS LAST WEEK")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(1.0)

                    Text(sessionsHeroHeadline)
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(0.8)

                    Text("\(previousSessionSummary.rangeLabel) vs \(currentSessionSummary.rangeLabel)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: Theme.Spacing.md)

                SessionDeltaBadge(delta: Int(metric.delta), isPositive: metric.isPositive)
            }

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(formatValue(metric.current))
                    .font(Theme.Typography.metricLarge)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("sessions")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Text(sessionsHeroNarrative)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    SessionWindowSummaryCard(summary: previousSessionSummary, tint: Theme.Colors.textTertiary)
                    SessionWindowSummaryCard(summary: currentSessionSummary, tint: Theme.Colors.accent)
                }

                VStack(spacing: Theme.Spacing.md) {
                    SessionWindowSummaryCard(summary: currentSessionSummary, tint: Theme.Colors.accent)
                    SessionWindowSummaryCard(summary: previousSessionSummary, tint: Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.Colors.accent.opacity(0.14),
                            Theme.Colors.surface,
                            Theme.Colors.accentSecondary.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .strokeBorder(Theme.Colors.border.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Theme.Colors.accent.opacity(0.08), radius: 16, x: 0, y: 8)
    }

    private var sessionsMetricGridSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(
                title: "Window Breakdown",
                subtitle: "A better read on how those sessions actually changed, beyond the raw count."
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: Theme.Spacing.md)],
                spacing: Theme.Spacing.md
            ) {
                SessionMetricTile(
                    title: "Active Days",
                    value: "\(currentSessionSummary.activeDays)",
                    footnote: countDeltaFootnote(
                        current: currentSessionSummary.activeDays,
                        previous: previousSessionSummary.activeDays,
                        noun: "day"
                    ),
                    icon: "calendar",
                    tint: Theme.Colors.accent
                )
                SessionMetricTile(
                    title: "Avg Duration",
                    value: durationLabel(minutes: currentSessionSummary.averageDurationMinutes),
                    footnote: formattedDeltaFootnote(
                        current: currentSessionSummary.averageDurationMinutes,
                        previous: previousSessionSummary.averageDurationMinutes,
                        formatter: { durationLabel(minutes: $0) }
                    ),
                    icon: "clock.fill",
                    tint: Theme.Colors.success
                )
                SessionMetricTile(
                    title: "Exercises / Session",
                    value: decimalText(currentSessionSummary.averageExercisesPerSession),
                    footnote: formattedDeltaFootnote(
                        current: currentSessionSummary.averageExercisesPerSession,
                        previous: previousSessionSummary.averageExercisesPerSession,
                        formatter: { decimalText($0) }
                    ),
                    icon: "figure.strengthtraining.traditional",
                    tint: Theme.Colors.accentSecondary
                )
                SessionMetricTile(
                    title: "Sets / Session",
                    value: decimalText(currentSessionSummary.averageSetsPerSession),
                    footnote: formattedDeltaFootnote(
                        current: currentSessionSummary.averageSetsPerSession,
                        previous: previousSessionSummary.averageSetsPerSession,
                        formatter: { decimalText($0) }
                    ),
                    icon: "number.square.fill",
                    tint: Theme.Colors.accentTertiary
                )
                SessionMetricTile(
                    title: "Volume / Session",
                    value: SharedFormatters.volumeCompact(currentSessionSummary.averageVolumePerSession),
                    footnote: formattedDeltaFootnote(
                        current: currentSessionSummary.averageVolumePerSession,
                        previous: previousSessionSummary.averageVolumePerSession,
                        formatter: { SharedFormatters.volumeCompact($0) }
                    ),
                    icon: "scalemass.fill",
                    tint: Theme.Colors.warning
                )
            }
        }
    }

    private var sessionsRhythmSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(
                title: "Training Rhythm",
                subtitle: "Day-by-day alignment shows where this week gained, lost, or redistributed sessions."
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    legendPill(title: previousWindowTitle, tint: Theme.Colors.textTertiary)
                    legendPill(title: currentWindowTitle, tint: Theme.Colors.accent)
                }

                if sessionDayComparisons.isEmpty {
                    EmptyStateTile(message: "Not enough session data to compare timing yet.")
                } else {
                    ForEach(sessionDayComparisons) { comparison in
                        SessionRhythmComparisonRow(
                            comparison: comparison,
                            maxCount: maxDailySessionCount
                        )
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
        }
    }

    private var sessionsMixSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(
                title: "Workout Mix",
                subtitle: "Which session types actually filled the window, and whether they showed up more or less than last week."
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if sessionTypeComparisons.isEmpty {
                    EmptyStateTile(message: "Log a few named workouts to compare the mix across weeks.")
                } else {
                    ForEach(Array(sessionTypeComparisons.prefix(6))) { item in
                        SessionMixRow(item: item)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
        }
    }

    private var sessionsFeedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(
                title: "Session Feed",
                subtitle: "Each workout gets enough context to be useful: timing, duration, density, volume, and location."
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sessionFeedCard(
                    title: currentWindowTitle,
                    summary: currentSessionSummary,
                    tint: Theme.Colors.accent,
                    workouts: currentWorkouts.sorted { $0.date > $1.date }
                )

                sessionFeedCard(
                    title: previousWindowTitle,
                    summary: previousSessionSummary,
                    tint: Theme.Colors.textTertiary,
                    workouts: previousWorkouts.sorted { $0.date > $1.date }
                )
            }
        }
    }

    private func sessionFeedCard(
        title: String,
        summary: SessionWindowSummary,
        tint: Color,
        workouts: [Workout]
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(summary.rangeLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Text("\(summary.sessionCount)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(tint.opacity(0.12))
                    )
            }

            if workouts.isEmpty {
                EmptyStateTile(message: "No sessions recorded in this window.")
            } else {
                ForEach(workouts) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        SessionWorkoutCard(
                            workout: workout,
                            exercisePreview: exercisePreview(for: workout),
                            gymLabel: gymLabel(for: workout),
                            gymStyle: gymBadgeStyle(for: workout),
                            tint: tint
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(windowLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(formatValue(metric.current))
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Previous")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(formatValue(metric.previous))
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(deltaLabel)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(metric.isPositive ? Theme.Colors.success : Theme.Colors.error)
                    Text(percentLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Trend")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if chartPoints.isEmpty {
                Text("Not enough data to chart.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                Chart {
                    if metric.title == "Sessions" {
                        ForEach(chartPoints) { point in
                            BarMark(
                                x: .value("Date", point.date),
                                y: .value("Count", point.value)
                            )
                            .foregroundStyle(point.window == .current ? Theme.Colors.accent : Theme.Colors.elevated)
                            .cornerRadius(3)
                        }
                    } else {
                        ForEach(chartPoints.filter { $0.window == .previous }) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(Theme.Colors.textTertiary)
                        }

                        ForEach(chartPoints.filter { $0.window == .current }) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(Theme.Colors.accent)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(Theme.Colors.accent)
                        }
                    }

                    RuleMark(x: .value("Current start", window.current.start))
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                Text(axisLabel(axisValue))
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .frame(height: 220)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }

    private var supportingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Supporting")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            switch metric.title {
            case "Sessions":
                sessionsSupporting
            case "Total Volume":
                volumeSupporting
            default:
                Text("No supporting view for this metric.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            }
        }
    }

    private var sessionsSupporting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if currentWorkouts.isEmpty {
                Text("No sessions in this window.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                ForEach(currentWorkouts.sorted { $0.date > $1.date }) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(workout.date.formatted(date: .abbreviated, time: .omitted))
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

    private var volumeSupporting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            let topWorkouts = currentWorkouts
                .filter(\.hasVolume)
                .sorted { $0.totalVolume > $1.totalVolume }
                .prefix(8)

            if topWorkouts.isEmpty {
                Text("No volume data in this window.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                Text("Top Workouts")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                ForEach(Array(topWorkouts), id: \.id) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("\(SharedFormatters.volumePrecise(workout.totalVolume)) volume")
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

                let exerciseTotals = Dictionary(grouping: currentWorkouts.flatMap(\.volumeExercises), by: { $0.name })
                    .map { name, exercises in
                        (name: name, volume: exercises.reduce(0) { $0 + $1.totalVolume })
                    }
                    .filter { $0.volume > 0 }
                    .sorted { $0.volume > $1.volume }

                if !exerciseTotals.isEmpty {
                    Text("Top Exercises")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.top, Theme.Spacing.sm)

                    ForEach(exerciseTotals.prefix(8), id: \.name) { exercise in
                        NavigationLink(
                            destination: ExerciseDetailView(
                                exerciseName: exercise.name,
                                dataManager: dataManager,
                                annotationsManager: annotationsManager,
                                gymProfilesManager: gymProfilesManager
                            )
                        ) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(Theme.Typography.headline)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(SharedFormatters.volumePrecise(exercise.volume))
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

    private var chartPoints: [ChartPoint] {
        switch metric.title {
        case "Sessions":
            return sessionChartPoints
        case "Total Volume":
            return seriesPoints(from: workouts, value: { $0.totalVolume })
        default:
            return []
        }
    }

    private func seriesPoints(from workouts: [Workout], value: (Workout) -> Double) -> [ChartPoint] {
        let sorted = workouts.sorted { $0.date < $1.date }
        return sorted.compactMap { workout in
            let workoutValue = value(workout)
            guard workoutValue > 0 else { return nil }
            guard window.current.contains(workout.date) || window.previous.contains(workout.date) else { return nil }
            let bucket: WindowBucket = window.current.contains(workout.date) ? .current : .previous
            return ChartPoint(date: workout.date, value: workoutValue, window: bucket)
        }
    }

    private var sessionChartPoints: [ChartPoint] {
        let filtered = workouts.filter { window.current.contains($0.date) || window.previous.contains($0.date) }
        let buckets: [Date: (count: Int, window: WindowBucket)] = filtered.reduce(into: [:]) { result, workout in
            let day = calendar.startOfDay(for: workout.date)
            let bucket: WindowBucket = window.current.contains(workout.date) ? .current : .previous
            let current = result[day] ?? (0, bucket)
            result[day] = (current.count + 1, bucket)
        }

        return buckets
            .map { ChartPoint(date: $0.key, value: Double($0.value.count), window: $0.value.window) }
            .sorted { $0.date < $1.date }
    }

    private var deltaLabel: String {
        let sign = metric.delta >= 0 ? "+" : ""
        switch metric.title {
        case "Sessions":
            return "\(sign)\(Int(metric.delta))"
        case "Total Volume":
            return "\(sign)\(SharedFormatters.volumePrecise(abs(metric.delta)))"
        default:
            return "\(sign)\(String(format: "%.1f", metric.delta))"
        }
    }

    private var percentLabel: String {
        "\(String(format: "%.0f", metric.percentChange))%"
    }

    private func formatValue(_ value: Double) -> String {
        switch metric.title {
        case "Sessions":
            return "\(Int(value))"
        case "Total Volume":
            return SharedFormatters.volumePrecise(value)
        default:
            return String(format: "%.1f", value)
        }
    }

    private func axisLabel(_ value: Double) -> String {
        switch metric.title {
        case "Sessions":
            return "\(Int(value))"
        case "Total Volume":
            return SharedFormatters.volumePrecise(value)
        default:
            return String(format: "%.1f", value)
        }
    }

    private func buildSessionSummary(
        title: String,
        workouts: [Workout],
        interval: DateInterval
    ) -> SessionWindowSummary {
        let activeDays = Set(workouts.map { calendar.startOfDay(for: $0.date) }).count
        let totalDurationMinutes = workouts.reduce(0) { partialResult, workout in
            partialResult + workout.estimatedDurationMinutes(defaultMinutes: 0)
        }
        let totalExercises = workouts.reduce(0) { partialResult, workout in
            partialResult + workout.exercises.count
        }
        let totalSets = workouts.reduce(0) { partialResult, workout in
            partialResult + workout.totalSets
        }
        let totalVolume = workouts.reduce(0) { partialResult, workout in
            partialResult + workout.totalVolume
        }
        let workoutCount = max(workouts.count, 1)
        let busiestDay = Dictionary(grouping: workouts, by: { calendar.startOfDay(for: $0.date) })
            .max { lhs, rhs in
                if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
                return lhs.key < rhs.key
            }

        let topWorkout = Dictionary(grouping: workouts, by: \.name)
            .map { (name: $0.key, count: $0.value.count) }
            .max(by: { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            })?.name

        return SessionWindowSummary(
            title: title,
            rangeLabel: intervalLabel(interval),
            workouts: workouts,
            sessionCount: workouts.count,
            activeDays: activeDays,
            totalDurationMinutes: totalDurationMinutes,
            averageDurationMinutes: Double(totalDurationMinutes) / Double(workoutCount),
            totalExercises: totalExercises,
            averageExercisesPerSession: Double(totalExercises) / Double(workoutCount),
            totalSets: totalSets,
            averageSetsPerSession: Double(totalSets) / Double(workoutCount),
            totalVolume: totalVolume,
            averageVolumePerSession: totalVolume / Double(workoutCount),
            topWorkoutName: topWorkout,
            busiestDayLabel: busiestDay.map { "\($0.key.formatted(.dateTime.weekday(.abbreviated))) • \($0.value.count)" }
        )
    }

    private func dayCount(for interval: DateInterval) -> Int {
        let start = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        let span = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return max(span, 1)
    }

    private func dayCounts(for workouts: [Workout]) -> [Date: Int] {
        workouts.reduce(into: [Date: Int]()) { result, workout in
            let key = calendar.startOfDay(for: workout.date)
            result[key, default: 0] += 1
        }
    }

    private func intervalLabel(_ interval: DateInterval) -> String {
        let start = interval.start.formatted(.dateTime.month(.abbreviated).day())
        let end = interval.end.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) - \(end)"
    }

    private func durationLabel(minutes: Double) -> String {
        guard minutes > 0 else { return "--" }
        return SharedFormatters.durationMinutes(minutes)
    }

    private func decimalText(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private func countDeltaFootnote(current: Int, previous: Int, noun: String) -> String {
        let delta = current - previous
        if delta == 0 {
            return "Flat vs last week"
        }
        let signed = delta > 0 ? "+\(delta)" : "\(delta)"
        let suffix = abs(delta) == 1 ? noun : "\(noun)s"
        return "\(signed) \(suffix) from \(previous)"
    }

    private func formattedDeltaFootnote(
        current: Double,
        previous: Double,
        formatter: (Double) -> String
    ) -> String {
        let delta = current - previous
        if abs(delta) < 0.05 {
            return "Flat vs last week"
        }
        let comparison = formatter(previous)
        let prefix = delta > 0 ? "+" : "-"
        return "\(prefix)\(formatter(abs(delta))) from \(comparison)"
    }

    private func exercisePreview(for workout: Workout) -> String {
        let names = workout.exercises.map(\.name)
        guard !names.isEmpty else { return "No exercises logged" }
        let visible = Array(names.prefix(3))
        let suffix = names.count > visible.count ? " +\(names.count - visible.count)" : ""
        return visible.joined(separator: " • ") + suffix
    }

    private func gymLabel(for workout: Workout) -> String? {
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
        if let name = gymProfilesManager.gymName(for: gymId) {
            return name
        }
        if gymId != nil {
            return "Deleted gym"
        }
        return nil
    }

    private func gymBadgeStyle(for workout: Workout) -> GymBadgeStyle {
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
        if gymId == nil {
            return .unassigned
        }
        return gymProfilesManager.gymName(for: gymId) == nil ? .deleted : .assigned
    }

    private func legendPill(title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Theme.Colors.surfaceRaised)
        )
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Typography.sectionHeader2)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(0.8)
            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }
}

private struct SessionDeltaBadge: View {
    let delta: Int
    let isPositive: Bool

    private var tint: Color {
        if delta == 0 { return Theme.Colors.textSecondary }
        return isPositive ? Theme.Colors.success : Theme.Colors.warning
    }

    private var title: String {
        if delta == 0 { return "No Change" }
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(title)
                .font(Theme.Typography.monoMedium)
                .foregroundStyle(tint)
            Text(delta == 0 ? "vs last week" : "sessions")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textSecondary)
                .tracking(0.7)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct SessionWindowSummaryCard: View {
    let summary: ChangeMetricDetailView.SessionWindowSummary
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(summary.rangeLabel)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Text("\(summary.sessionCount)")
                    .font(Theme.Typography.monoMedium)
                    .foregroundStyle(tint)
            }

            HStack(spacing: Theme.Spacing.md) {
                summaryMetric(label: "Days", value: "\(summary.activeDays)")
                summaryMetric(label: "Avg", value: summary.averageDurationMinutes > 0 ? SharedFormatters.durationMinutes(summary.averageDurationMinutes) : "--")
                summaryMetric(label: "Top", value: summary.topWorkoutName ?? "--")
            }

            if let busiestDayLabel = summary.busiestDayLabel {
                Text("Busiest: \(busiestDayLabel)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surface.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }

    private func summaryMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(0.6)
            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SessionMetricTile: View {
    let title: String
    let value: String
    let footnote: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Iconography.title3Strong)
                .foregroundStyle(tint)

            Text(value)
                .font(Theme.Typography.metric)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)

            Text(footnote)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(minHeight: 138, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Theme.Colors.shadowOpacity > 0 ? Color.black.opacity(Theme.Colors.shadowOpacity) : .clear, radius: 8, x: 0, y: 4)
    }
}

private struct SessionRhythmComparisonRow: View {
    let comparison: ChangeMetricDetailView.SessionDayComparison
    let maxCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(comparison.label)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(comparison.dateLabel)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                HStack(spacing: Theme.Spacing.md) {
                    countChip(title: "Prev", value: comparison.previousCount, tint: Theme.Colors.textTertiary)
                    countChip(title: "Now", value: comparison.currentCount, tint: Theme.Colors.accent)
                }
            }

            VStack(spacing: 8) {
                comparisonBar(value: comparison.previousCount, maxCount: maxCount, tint: Theme.Colors.textTertiary.opacity(0.65))
                comparisonBar(value: comparison.currentCount, maxCount: maxCount, tint: Theme.Colors.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private func countChip(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(Theme.Typography.metricLabel)
            Text("\(value)")
                .font(Theme.Typography.monoSmall)
        }
        .foregroundStyle(value == 0 ? Theme.Colors.textSecondary : tint)
    }

    private func comparisonBar(value: Int, maxCount: Int, tint: Color) -> some View {
        GeometryReader { geometry in
            let fraction = maxCount > 0 ? CGFloat(value) / CGFloat(maxCount) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.surfaceRaised)

                Capsule()
                    .fill(tint)
                    .frame(width: max(10, geometry.size.width * fraction))
                    .opacity(value == 0 ? 0.18 : 1)
            }
        }
        .frame(height: 10)
    }
}

private struct SessionMixRow: View {
    let item: ChangeMetricDetailView.SessionTypeComparison

    private var deltaTint: Color {
        if item.delta == 0 { return Theme.Colors.textSecondary }
        return item.delta > 0 ? Theme.Colors.success : Theme.Colors.warning
    }

    private var deltaLabel: String {
        if item.delta == 0 { return "Flat" }
        return item.delta > 0 ? "+\(item.delta)" : "\(item.delta)"
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                Text(item.currentVolume > 0 ? "\(SharedFormatters.volumeCompact(item.currentVolume)) volume this week" : "No volume recorded this week")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: Theme.Spacing.md)

            HStack(spacing: Theme.Spacing.sm) {
                compactCount(value: item.previousCount, label: "Prev", tint: Theme.Colors.textTertiary)
                compactCount(value: item.currentCount, label: "Now", tint: Theme.Colors.accent)
                Text(deltaLabel)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(deltaTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(deltaTint.opacity(0.10))
                    )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surfaceRaised)
        )
    }

    private func compactCount(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("\(value)")
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(value == 0 ? Theme.Colors.textSecondary : tint)
        }
        .frame(minWidth: 38)
    }
}

private struct SessionWorkoutCard: View {
    let workout: Workout
    let exercisePreview: String
    let gymLabel: String?
    let gymStyle: GymBadgeStyle
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: Theme.Spacing.md)

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            HStack(spacing: Theme.Spacing.sm) {
                WorkoutMetricPill(label: workout.duration, icon: "clock")
                WorkoutMetricPill(label: "\(workout.exercises.count) ex", icon: "figure.strengthtraining.traditional")
                WorkoutMetricPill(label: "\(workout.totalSets) sets", icon: "number.square")
                WorkoutMetricPill(label: SharedFormatters.volumeCompact(workout.totalVolume), icon: "scalemass")
            }

            Text(exercisePreview)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)

            if let gymLabel {
                GymBadge(text: gymLabel, style: gymStyle)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct WorkoutMetricPill: View {
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(Theme.Typography.microLabel)
            Text(label)
                .font(Theme.Typography.captionBold)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Theme.Colors.surface)
        )
    }
}

private struct EmptyStateTile: View {
    let message: String

    var body: some View {
        Text(message)
            .font(Theme.Typography.body)
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Theme.Colors.surfaceRaised)
            )
    }
}

// swiftlint:enable type_body_length file_length
