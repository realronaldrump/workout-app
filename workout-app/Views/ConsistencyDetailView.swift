import SwiftUI
import Charts

struct ConsistencyDetailView: View {
    let workouts: [Workout]

    @EnvironmentObject private var intentionalBreaksManager: IntentionalBreaksManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("sessionsPerWeekGoal") private var sessionsPerWeekGoal: Int = 4
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1

    @State private var selectedRange: ConsistencyRange = .sixMonths
    @State private var selectedWeekStart: Date?
    @State private var selectedStreakRunId: String?
    @State private var selectedWeekday: Int?
    @State private var presentation = ConsistencyPresentation.empty
    @State private var hasBuiltPresentation = false

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private var targetSessionsPerWeek: Int {
        min(max(sessionsPerWeekGoal, 1), 14)
    }

    private var metricGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: Theme.Spacing.sm),
            GridItem(.flexible(), spacing: Theme.Spacing.sm)
        ]
    }

    var body: some View {
        ZStack {
            consistencyBackground

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    // The window scopes the headline numbers too, so it leads the page.
                    rangePicker

                    heroCard

                    weeklyExplorerSection

                    weekdayPatternSection

                    streakExplorerSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xl)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Consistency")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasBuiltPresentation else { return }
            refreshPresentation()
            syncSelections()
        }
        .onChange(of: selectedRange) { _, _ in
            refreshPresentation()
            syncSelections()
        }
        .onChange(of: workouts) { _, _ in
            refreshPresentation()
            syncSelections()
        }
        .onChange(of: intentionalBreaksManager.savedBreaks) { _, _ in
            refreshPresentation()
            syncSelections()
        }
        .onChange(of: sessionsPerWeekGoal) { _, _ in
            refreshPresentation()
            syncSelections()
        }
        .onChange(of: intentionalRestDays) { _, _ in
            refreshPresentation()
            syncSelections()
        }
    }

    @MainActor
    private func refreshPresentation() {
        let calendar = calendar
        let sortedWorkouts = workouts.sorted { $0.date < $1.date }
        let bounds = makeRangeBounds(sortedWorkouts: sortedWorkouts, calendar: calendar)
        let workoutsInRange = sortedWorkouts.filter { workout in
            let day = calendar.startOfDay(for: workout.date)
            return day >= bounds.start && day <= bounds.end
        }
        let workoutDaysInRange = IntentionalBreaksAnalytics.normalizedWorkoutDays(
            for: workoutsInRange,
            calendar: calendar
        )
        let breakDaysInRange = intentionalBreaksManager.breakDaySet(
            excluding: workoutDaysInRange,
            within: bounds.start...bounds.end,
            calendar: calendar
        )
        let volumeByWorkoutID = workoutsInRange.reduce(into: [UUID: Double]()) { result, workout in
            result[workout.id] = ExerciseAggregation.totalVolume(
                for: workout,
                resolver: ExerciseIdentityResolver.current
            )
        }
        let weeklyBuckets = workouts.isEmpty
            ? []
            : buildWeeklyBuckets(
                workoutsInRange: workoutsInRange,
                volumeByWorkoutID: volumeByWorkoutID,
                rangeBounds: bounds,
                breakDaysInRange: breakDaysInRange,
                calendar: calendar
            )
        let workoutsByWeekStart = Dictionary(grouping: workoutsInRange) { workout in
            SharedFormatters.startOfWeekSunday(for: workout.date)
        }
        .mapValues { workouts in
            Array(workouts.reversed())
        }

        let chronologicalStreakRuns = WorkoutAnalytics.streakRuns(
            for: workoutsInRange,
            intentionalRestDays: max(0, intentionalRestDays),
            intentionalBreakRanges: intentionalBreaksManager.savedBreaks
        )
        let streakRuns = chronologicalStreakRuns
            .sorted {
                if $0.workoutDayCount != $1.workoutDayCount {
                    return $0.workoutDayCount > $1.workoutDayCount
                }
                return $0.end > $1.end
            }
        let streakRunsByID = streakRuns.reduce(into: [String: StreakRun]()) { result, run in
            result[run.id] = run
        }
        let allowedGapDays = max(0, intentionalRestDays) + 1
        let today = calendar.startOfDay(for: Date())
        let currentStreakRun = streakRuns.first { run in
            let end = calendar.startOfDay(for: run.end)
            let daysSince = IntentionalBreaksAnalytics.effectiveGapDays(
                from: end,
                to: today,
                breakDays: breakDaysInRange,
                includeEnd: true,
                calendar: calendar
            )
            return daysSince <= allowedGapDays
        }
        var workoutsByStreakRunID: [String: [Workout]] = [:]
        var runIndex = 0
        for workout in workoutsInRange {
            let day = calendar.startOfDay(for: workout.date)
            while runIndex < chronologicalStreakRuns.count,
                  day > calendar.startOfDay(for: chronologicalStreakRuns[runIndex].end) {
                runIndex += 1
            }
            guard runIndex < chronologicalStreakRuns.count else { break }
            let run = chronologicalStreakRuns[runIndex]
            if day >= calendar.startOfDay(for: run.start) {
                workoutsByStreakRunID[run.id, default: []].append(workout)
            }
        }
        workoutsByStreakRunID = workoutsByStreakRunID.mapValues { Array($0.reversed()) }

        let workoutsByWeekday = Dictionary(grouping: workoutsInRange) { workout in
            calendar.component(.weekday, from: workout.date)
        }
        .mapValues { workouts in
            Array(workouts.reversed())
        }
        let weekdayStats = (1...7).map { weekday in
            let dayWorkouts = workoutsByWeekday[weekday] ?? []
            return WeekdayConsistencyStat(
                weekday: weekday,
                label: weekdayName(for: weekday) ?? "-",
                sessions: dayWorkouts.count,
                totalVolume: dayWorkouts.reduce(0) { $0 + (volumeByWorkoutID[$1.id] ?? 0) }
            )
        }

        let activeGoalWeeks = weeklyBuckets.filter { !$0.isFullyExcused }.count
        let goalHitWeeks = weeklyBuckets.filter {
            let required = $0.requiredSessions(targetSessionsPerWeek: targetSessionsPerWeek)
            return required > 0 && $0.sessions >= required
        }.count
        let totalSessions = weeklyBuckets.reduce(0) { $0 + $1.sessions }
        let effectiveWeeks = weeklyBuckets.reduce(0.0) { $0 + $1.activeWeekEquivalent }

        presentation = ConsistencyPresentation(
            sortedWorkouts: sortedWorkouts,
            rangeBounds: bounds,
            workoutsInRange: workoutsInRange,
            workoutDaysInRange: workoutDaysInRange,
            breakDaysInRange: breakDaysInRange,
            weeklyBuckets: weeklyBuckets,
            weeklyBucketsByStart: Dictionary(uniqueKeysWithValues: weeklyBuckets.map { ($0.weekStart, $0) }),
            workoutsByWeekStart: workoutsByWeekStart,
            streakRuns: streakRuns,
            streakRunsByID: streakRunsByID,
            currentStreakRun: currentStreakRun,
            bestStreakLength: streakRuns.map(\.workoutDayCount).max() ?? 0,
            workoutsByStreakRunID: workoutsByStreakRunID,
            weekdayStats: weekdayStats,
            workoutsByWeekday: workoutsByWeekday,
            weekdayMaxCount: max(weekdayStats.map(\.sessions).max() ?? 1, 1),
            goalHitWeeks: goalHitWeeks,
            activeGoalWeeks: activeGoalWeeks,
            goalHitRate: activeGoalWeeks > 0 ? Double(goalHitWeeks) / Double(activeGoalWeeks) : 0,
            averageSessionsPerWeek: effectiveWeeks > 0 ? Double(totalSessions) / effectiveWeeks : 0,
            maxSessionsInRange: max(
                targetSessionsPerWeek,
                weeklyBuckets.map(\.sessions).max() ?? targetSessionsPerWeek
            )
        )
        hasBuiltPresentation = true
    }

    private var consistencyBackground: some View {
        Theme.Colors.background.ignoresSafeArea()
    }

    private var heroCard: some View {
        ConsistencySummaryView(
            average: averageSessionsPerWeek,
            weeks: weeklyBuckets.map { TimeSeriesPoint(date: $0.weekStart, value: Double($0.sessions)) },
            goalWeeks: goalHitWeeks,
            totalWeeks: activeGoalWeeks,
            currentStreak: currentStreakRun?.workoutDayCount ?? 0,
            bestStreak: bestStreakLength
        )
    }

    private var rangePicker: some View {
        TimeRangePillPicker(
            options: ConsistencyRange.allCases,
            selected: $selectedRange,
            label: { $0.label },
            expandsToFill: true
        )
    }

    private var weeklyExplorerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader(title: "Weekly workouts")

            if weeklyBuckets.isEmpty {
                emptyCard(message: "No workouts in this range yet.")
            } else {
                selectedWeekSummary

                weekStrip

                selectedWeekBreakdown
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var selectedWeekSummary: some View {
        let bucket = selectedWeek
        let requiredSessions = bucket.requiredSessions(targetSessionsPerWeek: targetSessionsPerWeek)

        return HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(bucket.weekStart.formatted(Date.FormatStyle().month(.abbreviated).day()))
                .font(Theme.Typography.sectionHeader2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("to")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)

            Text(bucket.weekEnd.formatted(Date.FormatStyle().month(.abbreviated).day().year()))
                .font(Theme.Typography.sectionHeader2)
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            Group {
                if bucket.isFullyExcused {
                    Text("Break week")
                        .foregroundColor(Theme.Colors.textSecondary)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.textTertiary.opacity(0.12))
                        )
                } else {
                    let goalHit = bucket.sessions >= requiredSessions
                    Text(goalHit ? "Goal hit" : "Needs \(max(requiredSessions - bucket.sessions, 0))")
                        .foregroundColor(goalHit ? Theme.Colors.success : Theme.Colors.warning)
                        .background(
                            Capsule()
                                .fill((goalHit ? Theme.Colors.success : Theme.Colors.warning).opacity(0.12))
                        )
                }
            }
            .font(Theme.Typography.captionBold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private var weekStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                    ForEach(weeklyBuckets) { bucket in
                        ConsistencyWeekPillar(
                            bucket: bucket,
                            targetSessionsPerWeek: targetSessionsPerWeek,
                            maxSessions: maxSessionsInRange,
                            isSelected: selectedWeekStart == bucket.weekStart,
                            label: weekAxisLabel(for: bucket),
                            onTap: {
                                withAnimation(Theme.Animation.spring) {
                                    selectedWeekStart = bucket.weekStart
                                }
                                Haptics.selection()
                            }
                        )
                        .id(bucket.weekStart)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .onAppear {
                guard let selectedWeekStart else { return }
                DispatchQueue.main.async {
                    withAnimation(Theme.Animation.smooth) {
                        proxy.scrollTo(selectedWeekStart, anchor: .center)
                    }
                }
            }
            .onChange(of: selectedWeekStart) { _, newValue in
                guard let newValue else { return }
                withAnimation(Theme.Animation.smooth) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var selectedWeekBreakdown: some View {
        let bucket = selectedWeek

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            LazyVGrid(
                columns: metricGridColumns,
                spacing: Theme.Spacing.sm
            ) {
                DetailMetricTile(
                    label: "Sessions",
                    value: "\(bucket.sessions)",
                    tint: Theme.Colors.accent
                )
                DetailMetricTile(
                    label: "Workout days",
                    value: "\(bucket.uniqueWorkoutDays)",
                    tint: Theme.Colors.success
                )
                DetailMetricTile(
                    label: "Volume",
                    value: SharedFormatters.volumePrecise(bucket.totalVolume),
                    tint: Theme.Colors.accentSecondary
                )
                DetailMetricTile(
                    label: "Minutes",
                    value: "\(bucket.totalMinutes)",
                    tint: Theme.Colors.warning
                )
                DetailMetricTile(
                    label: "Excused days",
                    value: "\(bucket.excludedDayCount)",
                    tint: Theme.Colors.textTertiary
                )
            }

            if !selectedWeekWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Week sessions")
                        .font(Theme.Typography.metricLabel)
                        .foregroundColor(Theme.Colors.textTertiary)

                    ForEach(selectedWeekWorkouts.prefix(4)) { workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            HStack(spacing: Theme.Spacing.md) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.name)
                                        .font(Theme.Typography.bodyBold)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Text(workout.duration)
                                    .font(Theme.Typography.captionBold)
                                    .foregroundColor(Theme.Colors.textTertiary)
                                Image(systemName: "chevron.right")
                                    .font(Theme.Typography.captionBold)
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .fill(Theme.Colors.surfaceRaised)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var weekdayPatternSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader(title: "By day of week")

            if weekdayStats.allSatisfy({ $0.sessions == 0 }) {
                emptyCard(message: "No workouts in this range.")
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(weekdayStats) { stat in
                        WeekdayPatternRow(
                            stat: stat,
                            maxCount: weekdayMaxCount,
                            isSelected: selectedWeekday == stat.weekday,
                            onTap: {
                                withAnimation(Theme.Animation.spring) {
                                    selectedWeekday = stat.weekday
                                }
                                Haptics.selection()
                            }
                        )
                    }
                }

                if let selectedWeekday,
                   let dayName = weekdayName(for: selectedWeekday),
                   let dayStat = weekdayStats.first(where: { $0.weekday == selectedWeekday }) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("\(dayName) workouts")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text("\(dayStat.sessions) sessions, \(SharedFormatters.volumePrecise(dayStat.totalVolume)) total volume")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)

                        ForEach(workoutsForWeekday(selectedWeekday).prefix(3)) { workout in
                            NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                HStack {
                                    Text(workout.name)
                                        .font(Theme.Typography.subheadline)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Spacer()
                                    Text(workout.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textTertiary)
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                        .fill(Theme.Colors.surfaceRaised)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var streakExplorerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader(title: "Streaks")

            if streakRuns.isEmpty {
                emptyCard(message: "No streaks in this range.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(streakRuns.prefix(10)) { run in
                            StreakRunChip(
                                run: run,
                                isSelected: selectedStreakRun?.id == run.id,
                                onTap: {
                                    withAnimation(Theme.Animation.spring) {
                                        selectedStreakRunId = run.id
                                    }
                                    Haptics.selection()
                                }
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }

                if let selectedStreakRun {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Text("\(selectedStreakRun.workoutDayCount)-day streak")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Spacer()
                            Text(streakRangeLabel(selectedStreakRun))
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        CalendarHeatmap(
                            workouts: selectedStreakWorkouts,
                            anchorDate: selectedStreakRun.end
                        )
                    }
                    .padding(Theme.Spacing.md)
                    .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Workouts in streak")
                            .font(Theme.Typography.metricLabel)
                            .foregroundColor(Theme.Colors.textTertiary)

                        ForEach(selectedStreakWorkouts.prefix(6)) { workout in
                            NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(workout.name)
                                            .font(Theme.Typography.subheadline)
                                            .foregroundColor(Theme.Colors.textPrimary)
                                        Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(Theme.Typography.captionBold)
                                        .foregroundColor(Theme.Colors.textTertiary)
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                        .fill(Theme.Colors.surfaceRaised)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func sectionHeader(title: String) -> some View {
        SectionHeading(title: title)
    }

    private func emptyCard(message: String) -> some View {
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

    private func weekAxisLabel(for bucket: ConsistencyWeekBucket) -> String {
        let monthDay = bucket.weekStart.formatted(Date.FormatStyle().month(.abbreviated).day())
        if bucket.sessions == 0 {
            return monthDay
        }
        return monthDay
    }

    private var goalHitWeeks: Int {
        presentation.goalHitWeeks
    }

    private var activeGoalWeeks: Int {
        presentation.activeGoalWeeks
    }

    private var goalHitRate: Double {
        presentation.goalHitRate
    }

    private var averageSessionsPerWeek: Double {
        presentation.averageSessionsPerWeek
    }

    private var maxSessionsInRange: Int {
        presentation.maxSessionsInRange
    }

    private func makeRangeBounds(
        sortedWorkouts: [Workout],
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let now = Date()
        let end = calendar.startOfDay(for: now)

        let start: Date = {
            switch selectedRange {
            case .fourWeeks:
                return calendar.date(byAdding: .day, value: -27, to: end) ?? end
            case .twelveWeeks:
                return calendar.date(byAdding: .day, value: -(12 * 7 - 1), to: end) ?? end
            case .sixMonths:
                return calendar.date(byAdding: .month, value: -6, to: end) ?? end
            case .year:
                return calendar.date(byAdding: .year, value: -1, to: end) ?? end
            case .allTime:
                return calendar.startOfDay(for: sortedWorkouts.first?.date ?? end)
            }
        }()

        return (start: min(start, end), end: end)
    }

    private var weeklyBuckets: [ConsistencyWeekBucket] {
        presentation.weeklyBuckets
    }

    private func buildWeeklyBuckets(
        workoutsInRange: [Workout],
        volumeByWorkoutID: [UUID: Double],
        rangeBounds: (start: Date, end: Date),
        breakDaysInRange: Set<Date>,
        calendar: Calendar
    ) -> [ConsistencyWeekBucket] {
        let firstWeekStart = SharedFormatters.startOfWeekSunday(for: rangeBounds.start)
        let lastWeekStart = SharedFormatters.startOfWeekSunday(for: rangeBounds.end)

        struct WeekAccumulator {
            var sessions: Int = 0
            var totalVolume: Double = 0
            var totalMinutes: Int = 0
            var uniqueDays: Set<Date> = []
        }

        let aggregates = workoutsInRange.reduce(into: [Date: WeekAccumulator]()) { partialResult, workout in
            let weekStart = SharedFormatters.startOfWeekSunday(for: workout.date)
            var accumulator = partialResult[weekStart, default: WeekAccumulator()]
            accumulator.sessions += 1
            accumulator.totalVolume += volumeByWorkoutID[workout.id] ?? 0
            accumulator.totalMinutes += workout.estimatedDurationMinutes(defaultMinutes: 60)
            accumulator.uniqueDays.insert(calendar.startOfDay(for: workout.date))
            partialResult[weekStart] = accumulator
        }

        var buckets: [ConsistencyWeekBucket] = []
        var cursor = firstWeekStart

        while cursor <= lastWeekStart {
            let weekEnd = min(calendar.date(byAdding: .day, value: 6, to: cursor) ?? cursor, rangeBounds.end)
            let aggregate = aggregates[cursor] ?? WeekAccumulator()
            let trackedStart = max(cursor, rangeBounds.start)
            let trackedEnd = min(
                calendar.date(byAdding: .day, value: 6, to: cursor) ?? cursor,
                rangeBounds.end
            )
            let trackedDays = max((calendar.dateComponents([.day], from: trackedStart, to: trackedEnd).day ?? 0) + 1, 0)
            let excludedDays = IntentionalBreaksAnalytics.dayCount(
                from: trackedStart,
                to: trackedEnd,
                breakDays: breakDaysInRange,
                includeStart: true,
                includeEnd: true,
                calendar: calendar
            )
            buckets.append(
                ConsistencyWeekBucket(
                    weekStart: cursor,
                    weekEnd: weekEnd,
                    sessions: aggregate.sessions,
                    totalVolume: aggregate.totalVolume,
                    totalMinutes: aggregate.totalMinutes,
                    uniqueWorkoutDays: aggregate.uniqueDays.count,
                    trackedDayCount: trackedDays,
                    excludedDayCount: excludedDays
                )
            )

            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }

        return buckets
    }

    private var selectedWeek: ConsistencyWeekBucket {
        guard !weeklyBuckets.isEmpty else {
            return ConsistencyWeekBucket(
                weekStart: Date(),
                weekEnd: Date(),
                sessions: 0,
                totalVolume: 0,
                totalMinutes: 0,
                uniqueWorkoutDays: 0,
                trackedDayCount: 0,
                excludedDayCount: 0
            )
        }

        if let selectedWeekStart,
           let bucket = presentation.weeklyBucketsByStart[selectedWeekStart] {
            return bucket
        }

        return weeklyBuckets.last ?? ConsistencyWeekBucket(
            weekStart: Date(),
            weekEnd: Date(),
            sessions: 0,
            totalVolume: 0,
            totalMinutes: 0,
            uniqueWorkoutDays: 0,
            trackedDayCount: 0,
            excludedDayCount: 0
        )
    }

    private var selectedWeekWorkouts: [Workout] {
        presentation.workoutsByWeekStart[selectedWeek.weekStart] ?? []
    }

    private var streakRuns: [StreakRun] {
        presentation.streakRuns
    }

    private var currentStreakRun: StreakRun? {
        presentation.currentStreakRun
    }

    private var bestStreakLength: Int {
        presentation.bestStreakLength
    }

    private var selectedStreakRun: StreakRun? {
        if let selectedStreakRunId,
           let run = presentation.streakRunsByID[selectedStreakRunId] {
            return run
        }
        return currentStreakRun ?? streakRuns.first
    }

    private var selectedStreakWorkouts: [Workout] {
        guard let run = selectedStreakRun else { return [] }
        return presentation.workoutsByStreakRunID[run.id] ?? []
    }

    private func streakRangeLabel(_ run: StreakRun) -> String {
        if calendar.isDate(run.start, inSameDayAs: run.end) {
            return run.start.formatted(date: .abbreviated, time: .omitted)
        }
        let start = run.start.formatted(Date.FormatStyle().month(.abbreviated).day())
        let end = run.end.formatted(Date.FormatStyle().month(.abbreviated).day().year())
        return "\(start) - \(end)"
    }

    private var weekdayStats: [WeekdayConsistencyStat] {
        presentation.weekdayStats
    }

    private var weekdayMaxCount: Int {
        presentation.weekdayMaxCount
    }

    private func workoutsForWeekday(_ weekday: Int) -> [Workout] {
        presentation.workoutsByWeekday[weekday] ?? []
    }

    private func weekdayName(for weekday: Int) -> String? {
        let symbols = calendar.weekdaySymbols
        guard weekday >= 1 && weekday <= symbols.count else { return nil }
        return symbols[weekday - 1]
    }

    private func syncSelections() {
        if let selectedWeekStart {
            if presentation.weeklyBucketsByStart[selectedWeekStart] == nil {
                self.selectedWeekStart = weeklyBuckets.last?.weekStart
            }
        } else {
            selectedWeekStart = weeklyBuckets.last?.weekStart
        }

        if let selectedStreakRunId,
           presentation.streakRunsByID[selectedStreakRunId] == nil {
            self.selectedStreakRunId = currentStreakRun?.id ?? streakRuns.first?.id
        } else if selectedStreakRunId == nil {
            selectedStreakRunId = currentStreakRun?.id ?? streakRuns.first?.id
        }

        if let selectedWeekday,
           !weekdayStats.contains(where: { $0.weekday == selectedWeekday }) {
            self.selectedWeekday = weekdayStats.max(by: { $0.sessions < $1.sessions })?.weekday
        } else if selectedWeekday == nil {
            selectedWeekday = weekdayStats.max(by: { $0.sessions < $1.sessions })?.weekday
        }
    }
}

private enum ConsistencyRange: String, CaseIterable, Identifiable {
    case fourWeeks
    case twelveWeeks
    case sixMonths
    case year
    case allTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fourWeeks: return "4W"
        case .twelveWeeks: return "12W"
        case .sixMonths: return "6M"
        case .year: return "1Y"
        case .allTime: return "All"
        }
    }
}

private struct ConsistencyWeekBucket: Identifiable {
    let weekStart: Date
    let weekEnd: Date
    let sessions: Int
    let totalVolume: Double
    let totalMinutes: Int
    let uniqueWorkoutDays: Int
    let trackedDayCount: Int
    let excludedDayCount: Int

    var id: Date { weekStart }

    var eligibleDayCount: Int {
        max(trackedDayCount - excludedDayCount, 0)
    }

    var activeWeekEquivalent: Double {
        Double(eligibleDayCount) / 7.0
    }

    var isFullyExcused: Bool {
        eligibleDayCount == 0
    }

    func requiredSessions(targetSessionsPerWeek: Int) -> Int {
        IntentionalBreaksAnalytics.requiredSessionsForWeek(
            targetSessionsPerWeek: targetSessionsPerWeek,
            trackedDays: trackedDayCount,
            excludedDays: excludedDayCount
        )
    }
}

private struct WeekdayConsistencyStat: Identifiable {
    let weekday: Int
    let label: String
    let sessions: Int
    let totalVolume: Double

    var id: Int { weekday }
}

/// A single, main-actor snapshot of every history-derived value rendered by the screen.
/// Selection changes only read this snapshot; the full history is revisited when one of
/// the source inputs observed by `ConsistencyDetailView` changes.
private struct ConsistencyPresentation {
    let sortedWorkouts: [Workout]
    let rangeBounds: (start: Date, end: Date)
    let workoutsInRange: [Workout]
    let workoutDaysInRange: Set<Date>
    let breakDaysInRange: Set<Date>
    let weeklyBuckets: [ConsistencyWeekBucket]
    let weeklyBucketsByStart: [Date: ConsistencyWeekBucket]
    let workoutsByWeekStart: [Date: [Workout]]
    let streakRuns: [StreakRun]
    let streakRunsByID: [String: StreakRun]
    let currentStreakRun: StreakRun?
    let bestStreakLength: Int
    let workoutsByStreakRunID: [String: [Workout]]
    let weekdayStats: [WeekdayConsistencyStat]
    let workoutsByWeekday: [Int: [Workout]]
    let weekdayMaxCount: Int
    let goalHitWeeks: Int
    let activeGoalWeeks: Int
    let goalHitRate: Double
    let averageSessionsPerWeek: Double
    let maxSessionsInRange: Int

    static let empty = ConsistencyPresentation(
        sortedWorkouts: [],
        rangeBounds: (start: .distantPast, end: .distantPast),
        workoutsInRange: [],
        workoutDaysInRange: [],
        breakDaysInRange: [],
        weeklyBuckets: [],
        weeklyBucketsByStart: [:],
        workoutsByWeekStart: [:],
        streakRuns: [],
        streakRunsByID: [:],
        currentStreakRun: nil,
        bestStreakLength: 0,
        workoutsByStreakRunID: [:],
        weekdayStats: [],
        workoutsByWeekday: [:],
        weekdayMaxCount: 1,
        goalHitWeeks: 0,
        activeGoalWeeks: 0,
        goalHitRate: 0,
        averageSessionsPerWeek: 0,
        maxSessionsInRange: 1
    )
}

private struct ConsistencyWeekPillar: View {
    let bucket: ConsistencyWeekBucket
    let targetSessionsPerWeek: Int
    let maxSessions: Int
    let isSelected: Bool
    let label: String
    let onTap: () -> Void

    private let barHeight: CGFloat = 132

    private var normalizedMax: CGFloat {
        CGFloat(max(maxSessions, 1))
    }

    private var fillHeight: CGFloat {
        let count = max(bucket.sessions, 0)
        return max(6, (CGFloat(count) / normalizedMax) * barHeight)
    }

    private var targetOffset: CGFloat {
        let adjustedTarget = Double(bucket.requiredSessions(targetSessionsPerWeek: targetSessionsPerWeek))
        guard adjustedTarget > 0 else { return 0 }
        return min(barHeight, (CGFloat(adjustedTarget) / normalizedMax) * barHeight)
    }

    private var fillStyle: AnyShapeStyle {
        if bucket.isFullyExcused {
            return AnyShapeStyle(Theme.Colors.textTertiary.opacity(0.18))
        }

        if bucket.sessions >= bucket.requiredSessions(targetSessionsPerWeek: targetSessionsPerWeek) {
            return AnyShapeStyle(Theme.successGradient)
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Theme.Colors.ink,
                    Theme.Colors.ink
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Theme.Spacing.xs) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                        .fill(Theme.Colors.surface.opacity(0.7))
                        .frame(width: 24, height: barHeight)

                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .fill(fillStyle)
                    .frame(width: 24, height: fillHeight)

                    if targetOffset > 0 {
                        Rectangle()
                            .fill(Theme.Colors.accentSecondary)
                            .frame(width: 30, height: 1)
                            .offset(y: -(targetOffset - 0.5))
                    }
                }

                Text("\(bucket.sessions)")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(isSelected ? Theme.Colors.accent : Theme.Colors.textPrimary)

                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 44)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(isSelected ? Theme.Colors.accent.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(isSelected ? Theme.Colors.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(AppInteractionButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityLabel: String {
        let start = bucket.weekStart.formatted(Date.FormatStyle().month(.abbreviated).day())
        let end = bucket.weekEnd.formatted(Date.FormatStyle().month(.abbreviated).day().year())
        if bucket.isFullyExcused {
            return "Week \(start) to \(end), intentional break week"
        }
        return "Week \(start) to \(end), \(bucket.sessions) sessions"
    }
}

private struct DetailMetricTile: View {
    let label: String
    let value: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.monoMedium)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .statChipChrome(tint: tint)
        .accessibilityElement(children: .combine)
    }
}

private struct WeekdayPatternRow: View {
    let stat: WeekdayConsistencyStat
    let maxCount: Int
    let isSelected: Bool
    let onTap: () -> Void

    private var fillFraction: Double {
        guard maxCount > 0 else { return 0 }
        return min(Double(stat.sessions) / Double(maxCount), 1)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                Text(stat.label.prefix(3))
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 32, alignment: .leading)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Colors.surface)
                        Capsule()
                            .fill(
                                isSelected
                                    ? AnyShapeStyle(Theme.accentGradient)
                                    : AnyShapeStyle(Theme.Colors.accent.opacity(0.55))
                            )
                            .frame(width: geometry.size.width * fillFraction)
                    }
                }
                .frame(height: 12)

                Text("\(stat.sessions)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundColor(isSelected ? Theme.Colors.accent : Theme.Colors.textPrimary)
                    .frame(width: 28, alignment: .trailing)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(isSelected ? Theme.Colors.accent.opacity(0.09) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(isSelected ? Theme.Colors.accent.opacity(0.28) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(AppInteractionButtonStyle())
    }
}

private struct StreakRunChip: View {
    let run: StreakRun
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("\(run.workoutDayCount)d")
                    .font(Theme.Typography.monoMedium)
                    .foregroundColor(isSelected ? .white : Theme.Colors.textPrimary)

                Text(run.start.formatted(Date.FormatStyle().month(.abbreviated).day()))
                    .font(Theme.Typography.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.85) : Theme.Colors.textSecondary)

                Text(run.end.formatted(Date.FormatStyle().month(.abbreviated).day().year()))
                    .font(Theme.Typography.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.85) : Theme.Colors.textSecondary)
            }
            .frame(width: 112, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.Colors.surfaceRaised))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(isSelected ? Theme.Colors.accent.opacity(0.35) : Theme.Colors.border.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(AppInteractionButtonStyle())
    }
}
