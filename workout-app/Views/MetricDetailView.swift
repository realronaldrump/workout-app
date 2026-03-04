import SwiftUI
import Charts

struct MetricDetailView: View {
    let kind: WorkoutMetricDetailKind
    let workouts: [Workout]
    var scrollTarget: MetricDetailScrollTarget?

    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1

    @State private var hasAutoScrolled = false
    @State private var selectedStreakRunId: String?
    @State private var selectedSessionDay: Date?
    @State private var selectedVolumeWorkoutId: UUID?
    @State private var sessionsGranularity: SessionsGranularity = .daily

    enum SessionsGranularity: String, CaseIterable, Identifiable {
        case daily = "Daily"
        case weekly = "Weekly"

        var id: String { rawValue }
    }

    private var sundayCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private var sortedWorkouts: [Workout] {
        workouts.sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            detailBackground

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        heroCard
                            .animateOnAppear(delay: 0)

                        switch kind {
                        case .sessions:
                            sessionsSection
                                .animateOnAppear(delay: 0.05)
                        case .streak:
                            streakSection
                                .animateOnAppear(delay: 0.05)
                        case .totalVolume:
                            totalVolumeSection
                                .animateOnAppear(delay: 0.05)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.xl)
                    .frame(maxWidth: 920, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .onAppear {
                    syncSelections()
                    autoScrollIfNeeded(using: proxy)
                }
                .onChange(of: workouts.count) { _, _ in
                    syncSelections()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailBackground: some View {
        ZStack {
            AdaptiveBackground()

            LinearGradient(
                colors: [
                    Theme.Colors.accent.opacity(0.11),
                    Theme.Colors.accentSecondary.opacity(0.07),
                    Theme.Colors.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Theme.Colors.accent.opacity(0.08))
                .frame(width: 280, height: 280)
                .offset(x: 180, y: -260)
                .blur(radius: 4)

            Circle()
                .fill(Theme.Colors.accentSecondary.opacity(0.07))
                .frame(width: 220, height: 220)
                .offset(x: -170, y: -130)
                .blur(radius: 3)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title.uppercased())
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .tracking(1.0)

            Text(heroHeadline)
                .font(Theme.Typography.metric)
                .foregroundStyle(Theme.accentGradient)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(heroSubtitle)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                spacing: Theme.Spacing.sm
            ) {
                switch kind {
                case .sessions:
                    HeroChip(title: "Sessions", value: "\(workouts.count)", tint: Theme.Colors.accent)
                    HeroChip(title: "Workout Days", value: "\(uniqueWorkoutDayCount)", tint: Theme.Colors.success)
                    HeroChip(title: "Avg / Day", value: String(format: "%.1f", avgSessionsPerWorkoutDay), tint: Theme.Colors.accentSecondary)
                    HeroChip(title: "Week Span", value: "\(sessionWeekBuckets.count)", tint: Theme.Colors.warning)
                case .streak:
                    HeroChip(title: "Current", value: "\(currentStreakRun?.workoutDayCount ?? 0)d", tint: Theme.Colors.accent)
                    HeroChip(title: "Best", value: "\(streakRunsByLength.first?.workoutDayCount ?? 0)d", tint: Theme.Colors.success)
                    HeroChip(title: "Runs", value: "\(streakRuns.count)", tint: Theme.Colors.accentSecondary)
                    HeroChip(title: "Break Allowance", value: "\(max(0, intentionalRestDays))d", tint: Theme.Colors.warning)
                case .totalVolume:
                    HeroChip(title: "Total", value: SharedFormatters.volumeCompact(totalVolume), tint: Theme.Colors.accent)
                    HeroChip(title: "Avg / Session", value: SharedFormatters.volumePrecise(avgVolumePerSession), tint: Theme.Colors.success)
                    HeroChip(title: "Peak Session", value: SharedFormatters.volumePrecise(peakVolumeSession?.totalVolume ?? 0), tint: Theme.Colors.accentSecondary)
                    HeroChip(title: "Sessions", value: "\(workouts.count)", tint: Theme.Colors.warning)
                }
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
        .shadow(color: Theme.Colors.accent.opacity(0.08), radius: 18, x: 0, y: 8)
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader(title: "Session Explorer", subtitle: "Switch granularity and filter to inspect rhythm in detail.")

            sessionsControls

            sessionsChartCard

            sessionsListCard
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var sessionsControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(SessionsGranularity.allCases) { option in
                    Button {
                        withAnimation(Theme.Animation.spring) {
                            sessionsGranularity = option
                        }
                        Haptics.selection()
                    } label: {
                        Text(option.rawValue)
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(sessionsGranularity == option ? .white : Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(
                                        sessionsGranularity == option
                                            ? AnyShapeStyle(Theme.accentGradient)
                                            : AnyShapeStyle(Theme.Colors.surfaceRaised)
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        sessionsGranularity == option ? Theme.Colors.accent.opacity(0.25) : Theme.Colors.border.opacity(0.55),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(AppInteractionButtonStyle())
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    SessionDayFilterChip(
                        label: "All",
                        secondaryText: "\(workouts.count)",
                        isSelected: selectedSessionDay == nil,
                        onTap: {
                            withAnimation(Theme.Animation.spring) {
                                selectedSessionDay = nil
                            }
                            Haptics.selection()
                        }
                    )

                    ForEach(sessionDayBuckets.prefix(14)) { bucket in
                        SessionDayFilterChip(
                            label: bucket.dayStart.formatted(Date.FormatStyle().month(.abbreviated).day()),
                            secondaryText: "\(bucket.count)",
                            isSelected: selectedSessionDay == bucket.dayStart,
                            onTap: {
                                withAnimation(Theme.Animation.spring) {
                                    selectedSessionDay = bucket.dayStart
                                }
                                Haptics.selection()
                            }
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var sessionsChartCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(sessionsGranularity == .daily ? "Daily Session Count" : "Weekly Session Count")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Group {
                if sessionsGranularity == .daily {
                    if sessionDayBuckets.isEmpty {
                        EmptyStateTile(message: "No sessions available yet.")
                    } else {
                        Chart(sessionDayBuckets) { bucket in
                            BarMark(
                                x: .value("Day", bucket.dayStart),
                                y: .value("Sessions", bucket.count)
                            )
                            .foregroundStyle(Theme.Colors.accent.opacity(0.78))
                            .cornerRadius(5)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: min(6, max(sessionDayBuckets.count, 1)))) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3]))
                                    .foregroundStyle(Theme.Colors.border.opacity(0.45))
                                AxisValueLabel {
                                    if let count = value.as(Int.self) {
                                        Text("\(count)")
                                    }
                                }
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                        .frame(height: 210)
                    }
                } else {
                    if sessionWeekBuckets.isEmpty {
                        EmptyStateTile(message: "No weeks available yet.")
                    } else {
                        Chart(sessionWeekBuckets) { bucket in
                            BarMark(
                                x: .value("Week", bucket.weekStart),
                                y: .value("Sessions", bucket.count)
                            )
                            .foregroundStyle(bucket.count >= 4 ? Theme.successGradient : Theme.accentGradient)
                            .cornerRadius(5)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .weekOfYear, count: max(1, sessionWeekBuckets.count / 6))) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3]))
                                    .foregroundStyle(Theme.Colors.border.opacity(0.45))
                                AxisValueLabel {
                                    if let count = value.as(Int.self) {
                                        Text("\(count)")
                                    }
                                }
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                        .frame(height: 210)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var sessionsListCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(selectedSessionDay == nil ? "All Sessions" : "Sessions On \(selectedSessionDayLabel)")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            if filteredSessionWorkouts.isEmpty {
                EmptyStateTile(message: "No sessions match the current filter.")
            } else {
                ForEach(filteredSessionWorkouts) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        MetricWorkoutRow(
                            workout: workout,
                            subtitle: "\(workout.date.formatted(date: .abbreviated, time: .shortened)) | \(timeOfDayLabel(for: workout.date))",
                            highlight: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader(title: "Streak Explorer", subtitle: "Workout-day streaks that respect your intentional break allowance.")

            LongestStreaksSection(
                workouts: dataManager.workouts,
                collapsedCount: 4,
                maxExpandedCount: 12,
                selectedRunId: selectedStreakRun?.id
            ) { run in
                withAnimation(Theme.Animation.spring) {
                    selectedStreakRunId = run.id
                }
                Haptics.selection()
            }
            .padding(Theme.Spacing.md)
            .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)

            streakTimelineCard

            if let run = selectedStreakRun {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("\(run.workoutDayCount)-day selected run")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text(streakDateLabel(run))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    CalendarHeatmap(
                        workouts: selectedStreakWorkouts,
                        anchorDate: selectedStreakRun?.end
                    )
                }
                .padding(Theme.Spacing.md)
                .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Sessions In Selected Run")
                        .font(Theme.Typography.metricLabel)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .tracking(0.8)

                    ForEach(selectedStreakWorkouts.prefix(8)) { workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            MetricWorkoutRow(
                                workout: workout,
                                subtitle: "\(workout.date.formatted(date: .abbreviated, time: .shortened)) | \(timeOfDayLabel(for: workout.date))",
                                highlight: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.md)
                .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var streakTimelineCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Recent Run Lengths")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            if streakRunsByRecency.isEmpty {
                EmptyStateTile(message: "No streak runs to visualize yet.")
            } else {
                let chartRuns = Array(streakRunsByRecency.prefix(12).reversed())
                Chart(chartRuns) { run in
                    BarMark(
                        x: .value("Run End", run.end),
                        y: .value("Length", run.workoutDayCount)
                    )
                    .foregroundStyle(run.id == selectedStreakRun?.id ? Theme.successGradient : Theme.accentGradient)
                    .cornerRadius(5)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(6, max(streakRunsByRecency.count, 1)))) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3]))
                            .foregroundStyle(Theme.Colors.border.opacity(0.45))
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text("\(count)")
                            }
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .frame(height: 190)
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var totalVolumeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader(title: "Volume Explorer", subtitle: "Inspect trend, spotlight top sessions, and drill into top exercises.")

            volumeChartCard

            topVolumeSessionPicker

            volumeSessionList

            topExercisesByVolumeCard
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var volumeChartCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Volume Trend")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            if volumePoints.isEmpty {
                EmptyStateTile(message: "Not enough volume data to chart yet.")
            } else {
                Chart(volumePoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Volume", point.value)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Volume", point.value)
                    )
                    .foregroundStyle(Theme.Colors.accent.opacity(0.16))
                    .interpolationMethod(.catmullRom)

                    if point.id == selectedVolumeWorkoutId {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Volume", point.value)
                        )
                        .foregroundStyle(Theme.Colors.success)
                        .symbolSize(90)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(6, max(volumePoints.count, 1)))) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3]))
                            .foregroundStyle(Theme.Colors.border.opacity(0.45))
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                Text(SharedFormatters.volumeCompact(axisValue))
                            }
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .frame(height: 220)
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var topVolumeSessionPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Peak Sessions")
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    VolumeSessionChip(
                        title: "All",
                        value: "\(workouts.count)",
                        isSelected: selectedVolumeWorkoutId == nil,
                        onTap: {
                            withAnimation(Theme.Animation.spring) {
                                selectedVolumeWorkoutId = nil
                            }
                            Haptics.selection()
                        }
                    )

                    ForEach(topVolumeWorkouts) { workout in
                        VolumeSessionChip(
                            title: workout.name,
                            value: SharedFormatters.volumeCompact(workout.totalVolume),
                            isSelected: selectedVolumeWorkoutId == workout.id,
                            onTap: {
                                withAnimation(Theme.Animation.spring) {
                                    selectedVolumeWorkoutId = workout.id
                                }
                                Haptics.selection()
                            }
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var volumeSessionList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(selectedVolumeWorkoutId == nil ? "All Sessions" : "Focused Session")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            ForEach(volumeListWorkouts.prefix(10)) { workout in
                NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                    MetricWorkoutRow(
                        workout: workout,
                        subtitle: "\(SharedFormatters.volumeCompact(workout.totalVolume)) volume | \(timeOfDayLabel(for: workout.date))",
                        highlight: selectedVolumeWorkoutId == workout.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var topExercisesByVolumeCard: some View {
        let exerciseTotals = Dictionary(grouping: workouts.flatMap { $0.exercises }, by: { $0.name })
            .map { name, exercises in
                (name: name, volume: exercises.reduce(0) { $0 + $1.totalVolume })
            }
            .sorted { $0.volume > $1.volume }

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Top Exercises By Volume")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
                .id(MetricDetailScrollTarget.topExercisesByVolume)

            if exerciseTotals.isEmpty {
                EmptyStateTile(message: "No exercises available.")
            } else {
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
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercise.name)
                                    .font(Theme.Typography.bodyBold)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Text("\(SharedFormatters.volumeCompact(exercise.volume)) volume")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
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
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
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

    private var title: String {
        switch kind {
        case .sessions: return "Sessions"
        case .streak: return "Streak"
        case .totalVolume: return "Total Volume"
        }
    }

    private var heroHeadline: String {
        switch kind {
        case .sessions:
            return "\(workouts.count) sessions"
        case .streak:
            return "\(currentStreakRun?.workoutDayCount ?? 0) day streak"
        case .totalVolume:
            return "\(SharedFormatters.volumeCompact(totalVolume))"
        }
    }

    private var heroSubtitle: String {
        switch kind {
        case .sessions:
            return "Daily + weekly cadence from this range."
        case .streak:
            return "Streaks treat up to \(max(0, intentionalRestDays)) day\(max(0, intentionalRestDays) == 1 ? "" : "s") off as intentional breaks."
        case .totalVolume:
            return "Track progression, inspect outliers, and identify top-contributing exercises."
        }
    }

    private var uniqueWorkoutDayCount: Int {
        Set(sortedWorkouts.map { sundayCalendar.startOfDay(for: $0.date) }).count
    }

    private var avgSessionsPerWorkoutDay: Double {
        guard uniqueWorkoutDayCount > 0 else { return 0 }
        return Double(workouts.count) / Double(uniqueWorkoutDayCount)
    }

    private var totalVolume: Double {
        workouts.reduce(0) { $0 + $1.totalVolume }
    }

    private var avgVolumePerSession: Double {
        guard !workouts.isEmpty else { return 0 }
        return totalVolume / Double(workouts.count)
    }

    private var peakVolumeSession: Workout? {
        workouts.max(by: { $0.totalVolume < $1.totalVolume })
    }

    private var selectedSessionDayLabel: String {
        selectedSessionDay?.formatted(date: .abbreviated, time: .omitted) ?? "All"
    }

    private var filteredSessionWorkouts: [Workout] {
        guard let selectedSessionDay else { return sortedWorkouts }
        return sortedWorkouts.filter { workout in
            sundayCalendar.isDate(workout.date, inSameDayAs: selectedSessionDay)
        }
    }

    private var sessionDayBuckets: [SessionDayBucket] {
        let grouped = Dictionary(grouping: sortedWorkouts) { workout in
            sundayCalendar.startOfDay(for: workout.date)
        }

        return grouped
            .map { day, dayWorkouts in
                SessionDayBucket(dayStart: day, count: dayWorkouts.count)
            }
            .sorted { $0.dayStart > $1.dayStart }
    }

    private var sessionWeekBuckets: [SessionWeekBucket] {
        let grouped = Dictionary(grouping: sortedWorkouts) { workout in
            weekStart(for: workout.date)
        }

        return grouped
            .map { weekStart, weekWorkouts in
                SessionWeekBucket(weekStart: weekStart, count: weekWorkouts.count)
            }
            .sorted { $0.weekStart < $1.weekStart }
    }

    private func weekStart(for date: Date) -> Date {
        sundayCalendar.dateInterval(of: .weekOfYear, for: date)?.start ?? sundayCalendar.startOfDay(for: date)
    }

    private var streakRuns: [StreakRun] {
        WorkoutAnalytics.streakRuns(
            for: dataManager.workouts,
            intentionalRestDays: intentionalRestDays
        )
    }

    private var streakRunsByLength: [StreakRun] {
        streakRuns.sorted {
            if $0.workoutDayCount != $1.workoutDayCount {
                return $0.workoutDayCount > $1.workoutDayCount
            }
            return $0.end > $1.end
        }
    }

    private var streakRunsByRecency: [StreakRun] {
        streakRuns.sorted { $0.end > $1.end }
    }

    private var currentStreakRun: StreakRun? {
        let allowedGapDays = max(0, intentionalRestDays) + 1
        let today = sundayCalendar.startOfDay(for: Date())

        return streakRunsByRecency.first { run in
            let endDay = sundayCalendar.startOfDay(for: run.end)
            let daysSince = sundayCalendar.dateComponents([.day], from: endDay, to: today).day ?? Int.max
            return daysSince <= allowedGapDays
        }
    }

    private var selectedStreakRun: StreakRun? {
        if let selectedStreakRunId,
           let matched = streakRuns.first(where: { $0.id == selectedStreakRunId }) {
            return matched
        }
        return currentStreakRun ?? streakRunsByLength.first ?? streakRunsByRecency.first
    }

    private var selectedStreakWorkouts: [Workout] {
        guard let run = selectedStreakRun else { return sortedWorkouts }
        let startDay = sundayCalendar.startOfDay(for: run.start)
        let endDay = sundayCalendar.startOfDay(for: run.end)

        return dataManager.workouts
            .filter { workout in
                let day = sundayCalendar.startOfDay(for: workout.date)
                return day >= startDay && day <= endDay
            }
            .sorted { $0.date > $1.date }
    }

    private func streakDateLabel(_ run: StreakRun) -> String {
        if sundayCalendar.isDate(run.start, inSameDayAs: run.end) {
            return run.start.formatted(date: .abbreviated, time: .omitted)
        }
        let start = run.start.formatted(Date.FormatStyle().month(.abbreviated).day())
        let end = run.end.formatted(Date.FormatStyle().month(.abbreviated).day().year())
        return "\(start) - \(end)"
    }

    private var volumePoints: [VolumePoint] {
        sortedWorkouts
            .sorted { $0.date < $1.date }
            .map { workout in
                VolumePoint(id: workout.id, date: workout.date, value: workout.totalVolume)
            }
    }

    private var topVolumeWorkouts: [Workout] {
        sortedWorkouts.sorted { $0.totalVolume > $1.totalVolume }.prefix(6).map { $0 }
    }

    private var volumeListWorkouts: [Workout] {
        if let selectedVolumeWorkoutId,
           let focused = sortedWorkouts.first(where: { $0.id == selectedVolumeWorkoutId }) {
            return [focused] + sortedWorkouts.filter { $0.id != selectedVolumeWorkoutId }
        }
        return sortedWorkouts
    }

    private func timeOfDayLabel(for date: Date) -> String {
        let hour = sundayCalendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        case 17..<22:
            return "Evening"
        default:
            return "Late"
        }
    }

    private func autoScrollIfNeeded(using proxy: ScrollViewProxy) {
        guard !hasAutoScrolled else { return }
        guard let scrollTarget else { return }
        hasAutoScrolled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(Theme.Animation.smooth) {
                proxy.scrollTo(scrollTarget, anchor: .top)
            }
        }
    }

    private func syncSelections() {
        if let selectedSessionDay,
           !sessionDayBuckets.contains(where: { sundayCalendar.isDate($0.dayStart, inSameDayAs: selectedSessionDay) }) {
            self.selectedSessionDay = nil
        }

        if let selectedVolumeWorkoutId,
           !sortedWorkouts.contains(where: { $0.id == selectedVolumeWorkoutId }) {
            self.selectedVolumeWorkoutId = nil
        }

        if let selectedStreakRunId,
           !streakRuns.contains(where: { $0.id == selectedStreakRunId }) {
            self.selectedStreakRunId = currentStreakRun?.id ?? streakRunsByLength.first?.id
        } else if self.selectedStreakRunId == nil {
            self.selectedStreakRunId = currentStreakRun?.id ?? streakRunsByLength.first?.id
        }
    }
}

private struct HeroChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.7)

            Text(value)
                .font(Theme.Typography.monoSmall)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                .strokeBorder(tint.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct SessionDayFilterChip: View {
    let label: String
    let secondaryText: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(label)
                    .font(Theme.Typography.captionBold)
                Text(secondaryText)
                    .font(Theme.Typography.caption)
            }
            .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(Theme.accentGradient)
                            : AnyShapeStyle(Theme.Colors.surfaceRaised)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(
                        isSelected ? Theme.Colors.accent.opacity(0.3) : Theme.Colors.border.opacity(0.55),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(AppInteractionButtonStyle())
    }
}

private struct VolumeSessionChip: View {
    let title: String
    let value: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.captionBold)
                    .lineLimit(1)
                Text(value)
                    .font(Theme.Typography.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.88) : Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 132, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .foregroundColor(isSelected ? .white : Theme.Colors.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(Theme.accentGradient)
                            : AnyShapeStyle(Theme.Colors.surfaceRaised)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(
                        isSelected ? Theme.Colors.accent.opacity(0.3) : Theme.Colors.border.opacity(0.55),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(AppInteractionButtonStyle())
    }
}

private struct MetricWorkoutRow: View {
    let workout: Workout
    let subtitle: String
    var highlight: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(workout.duration)
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("\(workout.exercises.count) exercises")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(highlight ? Theme.Colors.accent.opacity(0.1) : Theme.Colors.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(highlight ? Theme.Colors.accent.opacity(0.3) : Theme.Colors.border.opacity(0.35), lineWidth: 1)
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

private struct SessionDayBucket: Identifiable {
    let dayStart: Date
    let count: Int

    var id: Date { dayStart }
}

private struct SessionWeekBucket: Identifiable {
    let weekStart: Date
    let count: Int

    var id: Date { weekStart }
}

private struct VolumePoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}
