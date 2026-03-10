import SwiftUI
import Charts

struct MetricDetailView: View {
    let kind: WorkoutMetricDetailKind
    let workouts: [Workout]
    var scrollTarget: MetricDetailScrollTarget?

    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @EnvironmentObject var intentionalBreaksManager: IntentionalBreaksManager
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1

    @State private var hasAutoScrolled = false
    @State private var selectedStreakRunId: String?
    @State private var selectedSessionDay: Date?
    @State private var selectedVolumeWorkoutId: UUID?
    @State private var cachedSortedWorkouts: [Workout] = []

    private var sundayCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private var sortedWorkouts: [Workout] {
        cachedSortedWorkouts
    }

    var body: some View {
        ZStack {
            detailBackground

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        heroCard

                        switch kind {
                        case .sessions:
                            sessionsSection
                        case .streak:
                            streakSection
                        case .totalVolume:
                            totalVolumeSection
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.xl)
                    .frame(maxWidth: 920, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .onAppear {
                    refreshCachedWorkouts()
                    syncSelections()
                    autoScrollIfNeeded(using: proxy)
                }
                .onChange(of: workouts) { _, _ in
                    refreshCachedWorkouts()
                    syncSelections()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func refreshCachedWorkouts() {
        cachedSortedWorkouts = workouts.sorted { $0.date > $1.date }
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
                    HeroChip(title: "Active Days", value: "\(uniqueWorkoutDayCount)", tint: Theme.Colors.success)
                    HeroChip(title: "Typical Window", value: preferredSessionWindow?.compactTitle ?? "--", tint: Theme.Colors.accentSecondary)
                    HeroChip(title: "Longest Break", value: longestSessionBreakLabel, tint: Theme.Colors.warning)
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
            sectionHeader(
                title: "Session Cadence",
                subtitle: "This week reads better as rhythm and timing than stacked counts. Tap an active day to focus the feed."
            )

            sessionCadenceSummaryCard

            sessionFlowCard

            sessionTimingCard

            sessionsListCard
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var sessionCadenceSummaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cadence Snapshot")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(sessionCadenceHeadline)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(sessionCadenceNarrative)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if !workouts.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: stackedSessionDayCount == 0 ? "checkmark.circle.fill" : "square.stack.3d.up.fill")
                            .font(Theme.Typography.captionStrong)
                        Text(stackedSessionDayCount == 0 ? "One per day" : "\(stackedSessionDayCount) stacked")
                            .font(Theme.Typography.captionBold)
                    }
                    .foregroundColor(stackedSessionDayCount == 0 ? Theme.Colors.success : Theme.Colors.accentSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                stackedSessionDayCount == 0
                                    ? Theme.Colors.success.opacity(0.12)
                                    : Theme.Colors.accentSecondary.opacity(0.12)
                            )
                    )
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                spacing: Theme.Spacing.sm
            ) {
                SessionInsightTile(
                    label: "Day Coverage",
                    value: "\(uniqueWorkoutDayCount)/\(max(sessionDisplayDays.count, 1))",
                    tint: Theme.Colors.accent
                )
                SessionInsightTile(
                    label: "Rest Days",
                    value: "\(max(sessionDisplayDays.count - uniqueWorkoutDayCount, 0))",
                    tint: Theme.Colors.warning
                )
                SessionInsightTile(
                    label: "Typical Window",
                    value: preferredSessionWindow?.compactTitle ?? "--",
                    tint: Theme.Colors.success
                )
                SessionInsightTile(
                    label: "Longest Break",
                    value: longestSessionBreakLabel,
                    tint: Theme.Colors.accentSecondary
                )
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var sessionFlowCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sessionFlowTitle)
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(sessionFlowSubtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                if selectedSessionDay != nil {
                    Button {
                        withAnimation(Theme.Animation.spring) {
                            selectedSessionDay = nil
                        }
                        Haptics.selection()
                    } label: {
                        Text("Show All")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.accent)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Theme.Colors.accent.opacity(0.1))
                            )
                    }
                    .buttonStyle(AppInteractionButtonStyle())
                }
            }

            if sessionDisplayDays.count <= 7 {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(sessionDisplayDays) { day in
                        SessionDayTile(
                            day: day,
                            isSelected: selectedSessionDay == day.date,
                            allowSelection: day.hasSessions,
                            isCompact: true,
                            onTap: {
                                guard day.hasSessions else { return }
                                withAnimation(Theme.Animation.spring) {
                                    selectedSessionDay = selectedSessionDay == day.date ? nil : day.date
                                }
                                Haptics.selection()
                            }
                        )
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(sessionDisplayDays) { day in
                            SessionDayTile(
                                day: day,
                                isSelected: selectedSessionDay == day.date,
                                allowSelection: day.hasSessions,
                                isCompact: false,
                                onTap: {
                                    guard day.hasSessions else { return }
                                    withAnimation(Theme.Animation.spring) {
                                        selectedSessionDay = selectedSessionDay == day.date ? nil : day.date
                                    }
                                    Haptics.selection()
                                }
                            )
                            .frame(width: 74)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            Text(sessionSelectionHint)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var sessionTimingCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Training Window")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            if workouts.isEmpty {
                EmptyStateTile(message: "Log a session to see when you usually train.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(sessionTimeWindowStats) { stat in
                        SessionTimeWindowRow(
                            stat: stat,
                            maxCount: maxSessionTimeWindowCount,
                            isHighlighted: stat.window == preferredSessionWindow
                        )
                    }
                }

                if let preferredSessionWindow {
                    Text("Most sessions in this range started in the \(preferredSessionWindow.title.lowercased()).")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var sessionsListCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedSessionDay == nil ? "Session Feed" : "Sessions On \(selectedSessionDayLabel)")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Text("\(filteredSessionWorkouts.count)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.surface)
                    )
            }

            if filteredSessionWorkouts.isEmpty {
                EmptyStateTile(message: "No sessions match the current filter.")
            } else {
                ForEach(filteredSessionWorkouts) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        MetricWorkoutRow(
                            workout: workout,
                            subtitle: "\(workout.date.formatted(date: .abbreviated, time: .shortened)) | \(timeOfDayLabel(for: workout.date))",
                            highlight: selectedSessionDay != nil
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
            sectionHeader(title: "Streak Explorer", subtitle: "Workout-day streaks that respect your rest allowance and saved break dates.")

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
                        value: "\(volumeWorkouts.count)",
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

            if volumeListWorkouts.isEmpty {
                EmptyStateTile(message: "No sessions with chartable volume yet.")
            } else {
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
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var topExercisesByVolumeCard: some View {
        let exerciseTotals = Dictionary(grouping: volumeWorkouts.flatMap(\.volumeExercises), by: { $0.name })
            .map { name, exercises in
                (name: name, volume: exercises.reduce(0) { $0 + $1.totalVolume })
            }
            .filter { $0.volume > 0 }
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
            if workouts.isEmpty {
                return "No sessions yet"
            }
            if stackedSessionDayCount == 0 {
                return "\(uniqueWorkoutDayCount) active days"
            }
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
            if workouts.isEmpty {
                return "This view will map your training rhythm and preferred window as soon as you log a session."
            }
            if stackedSessionDayCount == 0 {
                return "Each active day held a single workout, so this screen focuses on rhythm, spacing, and timing."
            }
            return "See which days carried sessions, where they cluster, and when you usually train."
        case .streak:
            return "Streaks honor your rest allowance plus any saved intentional break dates."
        case .totalVolume:
            return "Track progression, inspect outliers, and identify top-contributing exercises."
        }
    }

    private var uniqueWorkoutDayCount: Int {
        Set(sortedWorkouts.map { sundayCalendar.startOfDay(for: $0.date) }).count
    }

    private var stackedSessionDayCount: Int {
        sessionDayBuckets.filter { $0.count > 1 }.count
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

    private var workoutsByDay: [Date: [Workout]] {
        Dictionary(grouping: sortedWorkouts) { workout in
            sundayCalendar.startOfDay(for: workout.date)
        }
    }

    private var sessionDayBuckets: [SessionDayBucket] {
        workoutsByDay
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

    private var isCurrentWeekContext: Bool {
        let now = Date()
        let weekStart = SharedFormatters.startOfWeekSunday(for: now)
        return sortedWorkouts.allSatisfy { workout in
            workout.date >= weekStart && workout.date <= now
        }
    }

    private var sessionDisplayEndDay: Date {
        if isCurrentWeekContext {
            return sundayCalendar.startOfDay(for: Date())
        }
        return sundayCalendar.startOfDay(for: sortedWorkouts.first?.date ?? Date())
    }

    private var sessionDisplayStartDay: Date {
        if isCurrentWeekContext {
            return SharedFormatters.startOfWeekSunday(for: sessionDisplayEndDay)
        }

        guard let oldestDay = sortedWorkouts.last.map({ sundayCalendar.startOfDay(for: $0.date) }) else {
            return sessionDisplayEndDay
        }

        let recentStart = sundayCalendar.date(byAdding: .day, value: -13, to: sessionDisplayEndDay) ?? oldestDay
        return max(oldestDay, recentStart)
    }

    private var sessionDisplayDays: [SessionDisplayDay] {
        continuousDays(from: sessionDisplayStartDay, to: sessionDisplayEndDay).map { day in
            let dayWorkouts = (workoutsByDay[day] ?? []).sorted { $0.date < $1.date }
            return SessionDisplayDay(date: day, workouts: dayWorkouts)
        }
    }

    private var sessionFlowTitle: String {
        isCurrentWeekContext ? "Week Flow" : "Recent Flow"
    }

    private var sessionFlowSubtitle: String {
        if isCurrentWeekContext {
            return "Tap an active day to zero in on this week's session list."
        }
        return "Showing the latest \(sessionDisplayDays.count) days from this range."
    }

    private var sessionCadenceHeadline: String {
        if workouts.isEmpty {
            return "No sessions logged in this range."
        }
        if uniqueWorkoutDayCount == sessionDisplayDays.count {
            return "You trained every day in view."
        }
        if stackedSessionDayCount == 0 {
            return "Single-session days are your normal pattern."
        }
        return "\(stackedSessionDayCount) days carried stacked sessions."
    }

    private var sessionCadenceNarrative: String {
        guard !workouts.isEmpty else {
            return "Once you log a workout, this screen will show which days were active, when sessions usually happen, and how evenly they are spaced."
        }

        var parts = ["\(uniqueWorkoutDayCount) of \(max(sessionDisplayDays.count, 1)) days were active"]

        if let preferredSessionWindow {
            parts.append("most sessions started in the \(preferredSessionWindow.title.lowercased())")
        }

        if let averageSessionSpacingDays {
            if averageSessionSpacingDays <= 1.2 {
                parts.append("workouts landed on back-to-back days")
            } else {
                parts.append("workouts landed about every \(roundedDayLabel(for: averageSessionSpacingDays))")
            }
        }

        if stackedSessionDayCount == 0 {
            parts.append("each active day held a single session")
        }

        return parts.joined(separator: " • ")
    }

    private var sessionSelectionHint: String {
        guard let selectedSessionDay,
              let selectedDay = sessionDisplayDays.first(where: { sundayCalendar.isDate($0.date, inSameDayAs: selectedSessionDay) }) else {
            return isCurrentWeekContext
                ? "Tap an active day to focus the feed without losing the shape of the week."
                : "Tap an active day to focus the feed or scan the strip for recent rhythm."
        }

        let label = selectedDay.date.formatted(Date.FormatStyle().weekday(.wide).month(.abbreviated).day())
        if let workout = selectedDay.workouts.first, selectedDay.count == 1 {
            let window = selectedDay.primaryWindow?.title.lowercased() ?? timeOfDayLabel(for: workout.date).lowercased()
            return "\(label) had 1 session: \(workout.name) in the \(window)."
        }
        return "\(label) had \(selectedDay.count) sessions."
    }

    private var activeWorkoutDaysAscending: [Date] {
        sessionDayBuckets
            .map(\.dayStart)
            .sorted()
    }

    private var sessionSpacingDays: [Int] {
        let days = activeWorkoutDaysAscending
        guard days.count > 1 else { return [] }

        return zip(days, days.dropFirst()).compactMap { previous, next in
            sundayCalendar.dateComponents([.day], from: previous, to: next).day
        }
    }

    private var averageSessionSpacingDays: Double? {
        guard !sessionSpacingDays.isEmpty else { return nil }
        let total = sessionSpacingDays.reduce(0, +)
        return Double(total) / Double(sessionSpacingDays.count)
    }

    private var longestSessionBreakDays: Int? {
        sessionSpacingDays
            .map { max($0 - 1, 0) }
            .max()
    }

    private var longestSessionBreakLabel: String {
        guard let longestSessionBreakDays else { return "--" }
        return "\(longestSessionBreakDays)d"
    }

    private var sessionTimeWindowStats: [SessionTimeWindowStat] {
        SessionTimeWindow.allCases.map { window in
            SessionTimeWindowStat(
                window: window,
                sessions: sortedWorkouts.filter { SessionTimeWindow.window(for: $0.date) == window }.count
            )
        }
    }

    private var maxSessionTimeWindowCount: Int {
        max(sessionTimeWindowStats.map(\.sessions).max() ?? 0, 1)
    }

    private var preferredSessionWindow: SessionTimeWindow? {
        sessionTimeWindowStats
            .sorted {
                if $0.sessions != $1.sessions {
                    return $0.sessions > $1.sessions
                }
                return $0.window.sortOrder < $1.window.sortOrder
            }
            .first(where: \.hasSessions)?
            .window
    }

    private func roundedDayLabel(for spacing: Double) -> String {
        let rounded = max(Int(spacing.rounded()), 1)
        return rounded == 1 ? "1 day" : "\(rounded) days"
    }

    private func continuousDays(from start: Date, to end: Date) -> [Date] {
        guard start <= end else { return [] }

        var days: [Date] = []
        var current = sundayCalendar.startOfDay(for: start)
        let endDay = sundayCalendar.startOfDay(for: end)

        while current <= endDay {
            days.append(current)
            guard let next = sundayCalendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return days
    }

    private var streakRuns: [StreakRun] {
        WorkoutAnalytics.streakRuns(
            for: dataManager.workouts,
            intentionalRestDays: intentionalRestDays,
            intentionalBreakRanges: intentionalBreaksManager.savedBreaks
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
        let workoutDays = IntentionalBreaksAnalytics.normalizedWorkoutDays(for: dataManager.workouts, calendar: sundayCalendar)
        let breakDays = intentionalBreaksManager.breakDaySet(
            excluding: workoutDays,
            within: (workoutDays.min() ?? today)...today,
            calendar: sundayCalendar
        )

        return streakRunsByRecency.first { run in
            let endDay = sundayCalendar.startOfDay(for: run.end)
            let daysSince = IntentionalBreaksAnalytics.effectiveGapDays(
                from: endDay,
                to: today,
                breakDays: breakDays,
                includeEnd: true,
                calendar: sundayCalendar
            )
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
        volumeWorkouts
            .sorted { $0.date < $1.date }
            .map { workout in
                VolumePoint(id: workout.id, date: workout.date, value: workout.totalVolume)
            }
    }

    private var topVolumeWorkouts: [Workout] {
        volumeWorkouts.sorted { $0.totalVolume > $1.totalVolume }.prefix(6).map { $0 }
    }

    private var volumeListWorkouts: [Workout] {
        if let selectedVolumeWorkoutId,
           let focused = volumeWorkouts.first(where: { $0.id == selectedVolumeWorkoutId }) {
            return [focused] + volumeWorkouts.filter { $0.id != selectedVolumeWorkoutId }
        }
        return volumeWorkouts
    }

    private var volumeWorkouts: [Workout] {
        sortedWorkouts.filter(\.hasVolume)
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
           !volumeWorkouts.contains(where: { $0.id == selectedVolumeWorkoutId }) {
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
                .font(Theme.Typography.captionBold)
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

private struct SessionInsightTile: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
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
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct SessionDayTile: View {
    let day: SessionDisplayDay
    let isSelected: Bool
    let allowSelection: Bool
    let isCompact: Bool
    let onTap: () -> Void

    private var fillStyle: AnyShapeStyle {
        if day.hasSessions {
            return isSelected
                ? AnyShapeStyle(Theme.accentGradient)
                : AnyShapeStyle(day.primaryWindow?.backgroundGradient ?? Theme.successGradient)
        }
        return AnyShapeStyle(Theme.Colors.surfaceRaised)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Theme.Spacing.sm) {
                VStack(spacing: 2) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(day.date.formatted(.dateTime.day()))
                        .font(Theme.Typography.monoSmall)
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                VStack(spacing: 4) {
                    Text(day.hasSessions ? "\(day.count)" : "0")
                        .font(day.hasSessions ? Theme.Typography.monoMedium : Theme.Typography.monoSmall)
                        .foregroundColor(day.hasSessions ? .white : Theme.Colors.textTertiary)

                    Text(day.tileSubtitle)
                        .font(isCompact ? Theme.Typography.microLabel : Theme.Typography.caption2Bold)
                        .foregroundColor(day.hasSessions ? .white.opacity(0.88) : Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
                .frame(height: isCompact ? 58 : 64)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(fillStyle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .strokeBorder(
                            isSelected
                                ? Theme.Colors.accent.opacity(0.38)
                                : (day.hasSessions ? Theme.Colors.border.opacity(0.18) : Theme.Colors.border.opacity(0.55)),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: day.hasSessions ? Theme.Colors.accent.opacity(isSelected ? 0.18 : 0.08) : .clear,
                    radius: isSelected ? 10 : 5,
                    x: 0,
                    y: isSelected ? 5 : 3
                )
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.vertical, 2)
            .opacity(allowSelection ? 1.0 : 0.92)
        }
        .buttonStyle(AppInteractionButtonStyle())
        .disabled(!allowSelection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct SessionTimeWindowRow: View {
    let stat: SessionTimeWindowStat
    let maxCount: Int
    let isHighlighted: Bool

    private var fillFraction: Double {
        guard maxCount > 0 else { return 0 }
        return min(Double(stat.sessions) / Double(maxCount), 1)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Label(stat.window.title, systemImage: stat.window.icon)
                .font(Theme.Typography.captionBold)
                .foregroundColor(isHighlighted ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: 116, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.surface)

                    Capsule()
                        .fill(isHighlighted ? AnyShapeStyle(stat.window.backgroundGradient) : AnyShapeStyle(Theme.Colors.accent.opacity(0.28)))
                        .frame(width: geometry.size.width * fillFraction)
                }
            }
            .frame(height: 12)

            Text("\(stat.sessions)")
                .font(Theme.Typography.monoSmall)
                .foregroundColor(isHighlighted ? Theme.Colors.accent : Theme.Colors.textPrimary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(isHighlighted ? Theme.Colors.accent.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(isHighlighted ? Theme.Colors.accent.opacity(0.24) : Color.clear, lineWidth: 1)
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

private struct SessionDisplayDay: Identifiable {
    let date: Date
    let workouts: [Workout]

    var id: Date { date }

    var count: Int { workouts.count }

    var hasSessions: Bool { !workouts.isEmpty }

    var primaryWindow: SessionTimeWindow? {
        let windows = workouts.map { SessionTimeWindow.window(for: $0.date) }
        return windows
            .reduce(into: [SessionTimeWindow: Int]()) { counts, window in
                counts[window, default: 0] += 1
            }
            .max {
                if $0.value != $1.value {
                    return $0.value < $1.value
                }
                return $0.key.sortOrder > $1.key.sortOrder
            }?
            .key
    }

    var tileSubtitle: String {
        if hasSessions {
            return primaryWindow?.shortTitle ?? "Logged"
        }
        return "Rest"
    }

    var accessibilityLabel: String {
        let dayLabel = date.formatted(Date.FormatStyle().weekday(.wide).month(.abbreviated).day())
        if !hasSessions {
            return "\(dayLabel), rest day"
        }
        let label = count == 1 ? "1 session" : "\(count) sessions"
        let window = primaryWindow?.title.lowercased() ?? "logged"
        return "\(dayLabel), \(label), \(window)"
    }
}

private enum SessionTimeWindow: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening
    case late

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .late: return "Late"
        }
    }

    var shortTitle: String {
        switch self {
        case .morning: return "AM"
        case .afternoon: return "Noon"
        case .evening: return "PM"
        case .late: return "Late"
        }
    }

    var compactTitle: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .late: return "Late"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .late: return "moon.stars.fill"
        }
    }

    var sortOrder: Int {
        switch self {
        case .morning: return 0
        case .afternoon: return 1
        case .evening: return 2
        case .late: return 3
        }
    }

    var backgroundGradient: LinearGradient {
        switch self {
        case .morning:
            return LinearGradient(
                colors: [
                    Theme.Colors.warning,
                    Theme.Colors.accentSecondary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .afternoon:
            return LinearGradient(
                colors: [
                    Theme.Colors.accentSecondary,
                    Theme.Colors.warning
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .evening:
            return Theme.accentGradient
        case .late:
            return LinearGradient(
                colors: [
                    Theme.Colors.accentTertiary,
                    Theme.Colors.accent
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func window(for date: Date) -> SessionTimeWindow {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<22:
            return .evening
        default:
            return .late
        }
    }
}

private struct SessionTimeWindowStat: Identifiable {
    let window: SessionTimeWindow
    let sessions: Int

    var id: SessionTimeWindow { window }
    var hasSessions: Bool { sessions > 0 }
}

private struct VolumePoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}
