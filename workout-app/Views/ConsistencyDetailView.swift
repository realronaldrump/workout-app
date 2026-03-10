import SwiftUI
import Charts

struct ConsistencyDetailView: View {
    let workouts: [Workout]

    @EnvironmentObject private var intentionalBreaksManager: IntentionalBreaksManager
    @AppStorage("sessionsPerWeekGoal") private var sessionsPerWeekGoal: Int = 4
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1

    @State private var selectedRange: ConsistencyRange = .sixMonths
    @State private var selectedWeekStart: Date?
    @State private var selectedStreakRunId: String?
    @State private var selectedWeekday: Int?

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private var sortedWorkouts: [Workout] {
        workouts.sorted { $0.date < $1.date }
    }

    private var targetSessionsPerWeek: Int {
        min(max(sessionsPerWeekGoal, 1), 14)
    }

    var body: some View {
        ZStack {
            consistencyBackground

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    heroCard
                        .animateOnAppear(delay: 0)

                    rangePicker
                        .animateOnAppear(delay: 0.04)

                    weeklyExplorerSection
                        .animateOnAppear(delay: 0.08)

                    weekdayPatternSection
                        .animateOnAppear(delay: 0.12)

                    streakExplorerSection
                        .animateOnAppear(delay: 0.16)
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
            syncSelections()
        }
        .onChange(of: selectedRange) { _, _ in
            syncSelections()
        }
        .onChange(of: workouts.count) { _, _ in
            syncSelections()
        }
    }

    private var consistencyBackground: some View {
        ZStack {
            AdaptiveBackground()

            LinearGradient(
                colors: [
                    Theme.Colors.accent.opacity(0.14),
                    Theme.Colors.accentSecondary.opacity(0.08),
                    Theme.Colors.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Theme.Colors.accent.opacity(0.08))
                .frame(width: 320, height: 320)
                .offset(x: 170, y: -260)
                .blur(radius: 4)

            Circle()
                .fill(Theme.Colors.accentSecondary.opacity(0.07))
                .frame(width: 240, height: 240)
                .offset(x: -180, y: -150)
                .blur(radius: 2)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("CONSISTENCY ENGINE")
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .tracking(1.0)

                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    Text(String(format: "%.1f", averageSessionsPerWeek))
                        .font(Theme.Typography.metricLarge)
                        .foregroundStyle(Theme.accentGradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("sessions/week")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Text("Sunday-start calendar weeks. Saved break dates scale weekly goals down and keep excused gaps from breaking streaks.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !weeklyBuckets.isEmpty {
                Chart(weeklyBuckets) { bucket in
                    LineMark(
                        x: .value("Week", bucket.weekStart),
                        y: .value("Sessions", bucket.sessions)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.Colors.accent)

                    AreaMark(
                        x: .value("Week", bucket.weekStart),
                        y: .value("Sessions", bucket.sessions)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.Colors.accent.opacity(0.18))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3]))
                            .foregroundStyle(Theme.Colors.border.opacity(0.5))
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text("\(count)")
                            }
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 120)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                spacing: Theme.Spacing.sm
            ) {
                HeroMetricChip(
                    title: "Goal Weeks",
                    value: activeGoalWeeks > 0 ? "\(goalHitWeeks)/\(activeGoalWeeks)" : "--",
                    tint: Theme.Colors.success
                )
                HeroMetricChip(
                    title: "Hit Rate",
                    value: String(format: "%.0f%%", goalHitRate * 100),
                    tint: Theme.Colors.accentSecondary
                )
                HeroMetricChip(
                    title: "Current Streak",
                    value: "\(currentStreakRun?.workoutDayCount ?? 0)d",
                    tint: Theme.Colors.accent
                )
                HeroMetricChip(
                    title: "Best Streak",
                    value: "\(bestStreakLength)d",
                    tint: Theme.Colors.warning
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.Colors.surface,
                            Theme.Colors.surfaceRaised
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .strokeBorder(Theme.Colors.border.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Theme.Colors.accent.opacity(0.08), radius: 20, x: 0, y: 10)
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Window")
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(ConsistencyRange.allCases) { option in
                        Button {
                            withAnimation(Theme.Animation.spring) {
                                selectedRange = option
                            }
                            Haptics.selection()
                        } label: {
                            Text(option.label)
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(selectedRange == option ? .white : Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(selectedRange == option ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.Colors.surface))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            selectedRange == option ? Theme.Colors.accent.opacity(0.25) : Theme.Colors.border.opacity(0.55),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(AppInteractionButtonStyle())
                    }
                }
                .padding(1)
            }
        }
    }

    private var weeklyExplorerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader(
                title: "Weekly Explorer",
                subtitle: "Tap any week to inspect sessions, volume, and time load."
            )

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
                    Text("Break Week")
                        .foregroundColor(Theme.Colors.textSecondary)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.textTertiary.opacity(0.12))
                        )
                } else {
                    let goalHit = bucket.sessions >= requiredSessions
                    Text(goalHit ? "Goal Hit" : "Needs \(max(requiredSessions - bucket.sessions, 0))")
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
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                spacing: Theme.Spacing.sm
            ) {
                DetailMetricTile(
                    label: "Sessions",
                    value: "\(bucket.sessions)",
                    tint: Theme.Colors.accent
                )
                DetailMetricTile(
                    label: "Workout Days",
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
                    label: "Excused Days",
                    value: "\(bucket.excludedDayCount)",
                    tint: Theme.Colors.textTertiary
                )
            }

            if !selectedWeekWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Week Sessions")
                        .font(Theme.Typography.metricLabel)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .tracking(0.8)

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
            sectionHeader(
                title: "Weekday Pattern",
                subtitle: "See where your training rhythm is strongest."
            )

            if weekdayStats.allSatisfy({ $0.sessions == 0 }) {
                emptyCard(message: "Weekday pattern appears once you have sessions in this range.")
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
                        Text("\(dayName) Snapshot")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text("\(dayStat.sessions) sessions · \(SharedFormatters.volumePrecise(dayStat.totalVolume)) total volume")
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
            sectionHeader(
                title: "Streak Explorer",
                subtitle: "Runs honor your rest allowance plus saved intentional break dates. Tap a run to inspect it."
            )

            if streakRuns.isEmpty {
                emptyCard(message: "No streak runs available in this range.")
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
                            Text("\(selectedStreakRun.workoutDayCount)-day run")
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
                        Text("Sessions In Run")
                            .font(Theme.Typography.metricLabel)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .tracking(0.8)

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
        weeklyBuckets.filter {
            let required = $0.requiredSessions(targetSessionsPerWeek: targetSessionsPerWeek)
            return required > 0 && $0.sessions >= required
        }.count
    }

    private var activeGoalWeeks: Int {
        weeklyBuckets.filter { !$0.isFullyExcused }.count
    }

    private var goalHitRate: Double {
        guard activeGoalWeeks > 0 else { return 0 }
        return Double(goalHitWeeks) / Double(activeGoalWeeks)
    }

    private var averageSessionsPerWeek: Double {
        guard !weeklyBuckets.isEmpty else { return 0 }
        let total = weeklyBuckets.reduce(0) { partialResult, bucket in
            partialResult + bucket.sessions
        }
        let effectiveWeeks = weeklyBuckets.reduce(0.0) { partialResult, bucket in
            partialResult + bucket.activeWeekEquivalent
        }
        guard effectiveWeeks > 0 else { return 0 }
        return Double(total) / effectiveWeeks
    }

    private var maxSessionsInRange: Int {
        max(targetSessionsPerWeek, weeklyBuckets.map(\.sessions).max() ?? targetSessionsPerWeek)
    }

    private var rangeBounds: (start: Date, end: Date) {
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

    private var workoutsInRange: [Workout] {
        let bounds = rangeBounds
        return workouts.filter { workout in
            let day = calendar.startOfDay(for: workout.date)
            return day >= bounds.start && day <= bounds.end
        }
    }

    private var workoutDaysInRange: Set<Date> {
        IntentionalBreaksAnalytics.normalizedWorkoutDays(for: workoutsInRange, calendar: calendar)
    }

    private var breakDaysInRange: Set<Date> {
        intentionalBreaksManager.breakDaySet(
            excluding: workoutDaysInRange,
            within: rangeBounds.start...rangeBounds.end,
            calendar: calendar
        )
    }

    private var weeklyBuckets: [ConsistencyWeekBucket] {
        guard !workouts.isEmpty else { return [] }

        let bounds = rangeBounds
        let firstWeekStart = SharedFormatters.startOfWeekSunday(for: bounds.start)
        let lastWeekStart = SharedFormatters.startOfWeekSunday(for: bounds.end)

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
            accumulator.totalVolume += workout.totalVolume
            accumulator.totalMinutes += workout.estimatedDurationMinutes(defaultMinutes: 60)
            accumulator.uniqueDays.insert(calendar.startOfDay(for: workout.date))
            partialResult[weekStart] = accumulator
        }

        var buckets: [ConsistencyWeekBucket] = []
        var cursor = firstWeekStart

        while cursor <= lastWeekStart {
            let weekEnd = min(calendar.date(byAdding: .day, value: 6, to: cursor) ?? cursor, bounds.end)
            let aggregate = aggregates[cursor] ?? WeekAccumulator()
            let trackedStart = max(cursor, bounds.start)
            let trackedEnd = min(calendar.date(byAdding: .day, value: 6, to: cursor) ?? cursor, bounds.end)
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
           let bucket = weeklyBuckets.first(where: { calendar.isDate($0.weekStart, inSameDayAs: selectedWeekStart) }) {
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
        let bucket = selectedWeek
        let start = calendar.startOfDay(for: bucket.weekStart)
        let end = calendar.startOfDay(for: bucket.weekEnd)

        return workoutsInRange
            .filter { workout in
                let day = calendar.startOfDay(for: workout.date)
                return day >= start && day <= end
            }
            .sorted { $0.date > $1.date }
    }

    private var streakRuns: [StreakRun] {
        WorkoutAnalytics
            .streakRuns(
                for: workoutsInRange,
                intentionalRestDays: max(0, intentionalRestDays),
                intentionalBreakRanges: intentionalBreaksManager.savedBreaks
            )
            .sorted {
                if $0.workoutDayCount != $1.workoutDayCount {
                    return $0.workoutDayCount > $1.workoutDayCount
                }
                return $0.end > $1.end
            }
    }

    private var currentStreakRun: StreakRun? {
        guard !streakRuns.isEmpty else { return nil }

        let allowedGapDays = max(0, intentionalRestDays) + 1
        let today = calendar.startOfDay(for: Date())

        return streakRuns.first { run in
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
    }

    private var bestStreakLength: Int {
        streakRuns.map(\.workoutDayCount).max() ?? 0
    }

    private var selectedStreakRun: StreakRun? {
        if let selectedStreakRunId,
           let run = streakRuns.first(where: { $0.id == selectedStreakRunId }) {
            return run
        }
        return currentStreakRun ?? streakRuns.first
    }

    private var selectedStreakWorkouts: [Workout] {
        guard let run = selectedStreakRun else { return [] }
        let start = calendar.startOfDay(for: run.start)
        let end = calendar.startOfDay(for: run.end)

        return workoutsInRange
            .filter { workout in
                let day = calendar.startOfDay(for: workout.date)
                return day >= start && day <= end
            }
            .sorted { $0.date > $1.date }
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
        let grouped = Dictionary(grouping: workoutsInRange) { workout in
            calendar.component(.weekday, from: workout.date)
        }

        return (1...7).map { weekday in
            let dayWorkouts = grouped[weekday] ?? []
            let sessions = dayWorkouts.count
            let volume = dayWorkouts.reduce(0) { partialResult, workout in
                partialResult + workout.totalVolume
            }

            return WeekdayConsistencyStat(
                weekday: weekday,
                label: weekdayName(for: weekday) ?? "-",
                sessions: sessions,
                totalVolume: volume
            )
        }
    }

    private var weekdayMaxCount: Int {
        max(weekdayStats.map(\.sessions).max() ?? 1, 1)
    }

    private func workoutsForWeekday(_ weekday: Int) -> [Workout] {
        workoutsInRange
            .filter { calendar.component(.weekday, from: $0.date) == weekday }
            .sorted { $0.date > $1.date }
    }

    private func weekdayName(for weekday: Int) -> String? {
        let symbols = calendar.weekdaySymbols
        guard weekday >= 1 && weekday <= symbols.count else { return nil }
        return symbols[weekday - 1]
    }

    private func syncSelections() {
        if let selectedWeekStart {
            let exists = weeklyBuckets.contains { bucket in
                calendar.isDate(bucket.weekStart, inSameDayAs: selectedWeekStart)
            }
            if !exists {
                self.selectedWeekStart = weeklyBuckets.last?.weekStart
            }
        } else {
            selectedWeekStart = weeklyBuckets.last?.weekStart
        }

        if let selectedStreakRunId,
           !streakRuns.contains(where: { $0.id == selectedStreakRunId }) {
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

private struct HeroMetricChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(value)
                .font(Theme.Typography.monoMedium)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }
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
                    Theme.Colors.accent.opacity(0.8),
                    Theme.Colors.accent.opacity(0.5)
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
                    .shadow(color: Theme.Colors.accent.opacity(0.2), radius: 6, x: 0, y: 3)

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
                    .monospacedDigit()

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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.7)
            Text(value)
                .font(Theme.Typography.monoMedium)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
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
            .shadow(color: isSelected ? Theme.Colors.accent.opacity(0.22) : .clear, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(AppInteractionButtonStyle())
    }
}
