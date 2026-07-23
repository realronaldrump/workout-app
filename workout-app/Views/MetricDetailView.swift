import SwiftUI
import Charts
// swiftlint:disable type_body_length file_length

struct MetricDetailView: View {
    let kind: WorkoutMetricDetailKind
    let workouts: [Workout]
    var scrollTarget: MetricDetailScrollTarget?

    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @EnvironmentObject var intentionalBreaksManager: IntentionalBreaksManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1

    @State private var hasAutoScrolled = false
    @State private var selectedStreakRunId: String?
    @State private var selectedSessionDay: Date?
    @State private var selectedVolumeWorkoutId: UUID?
    @State private var presentation = MetricDetailPresentation.empty

    private var sundayCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private var sortedWorkouts: [Workout] {
        presentation.sortedWorkouts
    }

    private var summaryGridColumns: [GridItem] {
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
            detailBackground

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
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
                    refreshPresentation()
                    autoScrollIfNeeded(using: proxy)
                }
                .onChange(of: workouts) { _, _ in
                    refreshPresentation()
                }
                .onChange(of: dataManager.workouts) { _, _ in
                    refreshPresentation()
                }
                .onChange(of: intentionalRestDays) { _, _ in
                    refreshPresentation()
                }
                .onChange(of: intentionalBreaksManager.savedBreaks) { _, _ in
                    refreshPresentation()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func refreshPresentation() {
        let nextPresentation = makePresentation()
        presentation = nextPresentation
        syncSelections(using: nextPresentation)
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.65)
                .fixedSize(horizontal: false, vertical: true)

            Text(heroSubtitle)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: summaryGridColumns,
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
                    HeroChip(
                        title: "Peak Session",
                        value: SharedFormatters.volumePrecise(peakVolumeSession.map { normalizedVolume(for: $0) } ?? 0),
                        tint: Theme.Colors.accentSecondary
                    )
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
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
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
                columns: summaryGridColumns,
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
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
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
                            exerciseCount: exerciseCount(for: workout),
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
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader(title: "Streak Explorer", subtitle: "Workout-day streaks that respect your rest allowance and saved break dates.")

            CachedLongestStreaksSection(
                runs: streakRunsByLength,
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
                                exerciseCount: exerciseCount(for: workout),
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
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .frame(height: Theme.ChartHeight.standard)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Recent streak lengths")
                .accessibilityValue("\(chartRuns.count) runs. Longest \(chartRuns.map(\.workoutDayCount).max() ?? 0) days.")
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var totalVolumeSection: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
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
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .frame(height: Theme.ChartHeight.expanded)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Volume trend")
                .accessibilityValue(
                    "\(volumePoints.count) sessions. Peak \(SharedFormatters.volumeCompact(volumePoints.map(\.value).max() ?? 0))."
                )
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
    }

    private var topVolumeSessionPicker: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
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
                            value: SharedFormatters.volumeCompact(normalizedVolume(for: workout)),
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
                            subtitle: "\(SharedFormatters.volumeCompact(normalizedVolume(for: workout))) volume | \(timeOfDayLabel(for: workout.date))",
                            exerciseCount: exerciseCount(for: workout),
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
        let exerciseTotals = topExerciseTotals

        return LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
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
        presentation.uniqueWorkoutDayCount
    }

    private var stackedSessionDayCount: Int {
        presentation.stackedSessionDayCount
    }

    private var totalVolume: Double {
        presentation.totalVolume
    }

    private var avgVolumePerSession: Double {
        presentation.averageVolumePerSession
    }

    private var peakVolumeSession: Workout? {
        presentation.peakVolumeSession
    }

    private var selectedSessionDayLabel: String {
        selectedSessionDay?.formatted(date: .abbreviated, time: .omitted) ?? "All"
    }

    private var filteredSessionWorkouts: [Workout] {
        guard let selectedSessionDay else { return sortedWorkouts }
        return presentation.workoutsByDay[sundayCalendar.startOfDay(for: selectedSessionDay)] ?? []
    }

    private var sessionDayBuckets: [SessionDayBucket] {
        presentation.sessionDayBuckets
    }

    private var isCurrentWeekContext: Bool {
        presentation.isCurrentWeekContext
    }

    private var sessionDisplayDays: [SessionDisplayDay] {
        presentation.sessionDisplayDays
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

    private var averageSessionSpacingDays: Double? {
        presentation.averageSessionSpacingDays
    }

    private var longestSessionBreakDays: Int? {
        presentation.longestSessionBreakDays
    }

    private var longestSessionBreakLabel: String {
        guard let longestSessionBreakDays else { return "--" }
        return "\(longestSessionBreakDays)d"
    }

    private var sessionTimeWindowStats: [SessionTimeWindowStat] {
        presentation.sessionTimeWindowStats
    }

    private var maxSessionTimeWindowCount: Int {
        presentation.maxSessionTimeWindowCount
    }

    private var preferredSessionWindow: SessionTimeWindow? {
        presentation.preferredSessionWindow
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

    /// Builds every expensive, data-driven value once per source mutation instead of
    /// repeatedly while SwiftUI evaluates the view hierarchy.
    private func makePresentation() -> MetricDetailPresentation {
        let calendar = sundayCalendar
        let sortedWorkouts = workouts.sorted { $0.date > $1.date }
        let workoutsByDay = Dictionary(grouping: sortedWorkouts) { workout in
            calendar.startOfDay(for: workout.date)
        }
        let sessionDayBuckets = workoutsByDay
            .map { day, dayWorkouts in
                SessionDayBucket(dayStart: day, count: dayWorkouts.count)
            }
            .sorted { $0.dayStart > $1.dayStart }
        let uniqueWorkoutDayCount = sessionDayBuckets.count
        let stackedSessionDayCount = sessionDayBuckets.lazy.filter { $0.count > 1 }.count

        let activeDays = sessionDayBuckets.map(\.dayStart).sorted()
        let spacingDays: [Int]
        if activeDays.count > 1 {
            spacingDays = zip(activeDays, activeDays.dropFirst()).compactMap { previous, next in
                calendar.dateComponents([.day], from: previous, to: next).day
            }
        } else {
            spacingDays = []
        }
        let averageSessionSpacingDays = spacingDays.isEmpty
            ? nil
            : Double(spacingDays.reduce(0, +)) / Double(spacingDays.count)
        let longestSessionBreakDays = spacingDays.map { max($0 - 1, 0) }.max()

        let now = Date()
        let currentWeekStart = SharedFormatters.startOfWeekSunday(for: now)
        let isCurrentWeekContext = sortedWorkouts.allSatisfy { workout in
            workout.date >= currentWeekStart && workout.date <= now
        }
        let sessionDisplayEndDay = isCurrentWeekContext
            ? calendar.startOfDay(for: now)
            : calendar.startOfDay(for: sortedWorkouts.first?.date ?? now)
        let sessionDisplayStartDay: Date
        if isCurrentWeekContext {
            sessionDisplayStartDay = SharedFormatters.startOfWeekSunday(for: sessionDisplayEndDay)
        } else if let oldestWorkout = sortedWorkouts.last {
            let oldestDay = calendar.startOfDay(for: oldestWorkout.date)
            let recentStart = calendar.date(byAdding: .day, value: -13, to: sessionDisplayEndDay) ?? oldestDay
            sessionDisplayStartDay = max(oldestDay, recentStart)
        } else {
            sessionDisplayStartDay = sessionDisplayEndDay
        }
        let sessionDisplayDays = continuousDays(from: sessionDisplayStartDay, to: sessionDisplayEndDay).map { day in
            SessionDisplayDay(
                date: day,
                workouts: (workoutsByDay[day] ?? []).sorted { $0.date < $1.date }
            )
        }

        let timeWindowCounts = sortedWorkouts.reduce(into: [SessionTimeWindow: Int]()) { counts, workout in
            counts[SessionTimeWindow.window(for: workout.date), default: 0] += 1
        }
        let sessionTimeWindowStats = SessionTimeWindow.allCases.map { window in
            SessionTimeWindowStat(window: window, sessions: timeWindowCounts[window, default: 0])
        }
        let maxSessionTimeWindowCount = max(sessionTimeWindowStats.map(\.sessions).max() ?? 0, 1)
        let preferredSessionWindow = sessionTimeWindowStats
            .sorted {
                if $0.sessions != $1.sessions {
                    return $0.sessions > $1.sessions
                }
                return $0.window.sortOrder < $1.window.sortOrder
            }
            .first(where: \.hasSessions)?
            .window

        let allWorkouts = dataManager.workouts
        let savedBreaks = intentionalBreaksManager.savedBreaks
        let resolver = ExerciseIdentityResolver.current
        var exerciseCountByWorkoutID: [UUID: Int] = [:]
        exerciseCountByWorkoutID.reserveCapacity(max(allWorkouts.count, workouts.count))
        for workout in allWorkouts + workouts where exerciseCountByWorkoutID[workout.id] == nil {
            exerciseCountByWorkoutID[workout.id] = ExerciseAggregation.exerciseCount(
                for: workout,
                resolver: resolver
            )
        }
        let streakRuns = WorkoutAnalytics.streakRuns(
            for: allWorkouts,
            intentionalRestDays: intentionalRestDays,
            intentionalBreakRanges: savedBreaks
        )
        let streakRunsByLength = streakRuns.sorted {
            if $0.workoutDayCount != $1.workoutDayCount {
                return $0.workoutDayCount > $1.workoutDayCount
            }
            return $0.end > $1.end
        }
        let streakRunsByRecency = streakRuns.sorted { $0.end > $1.end }

        let today = calendar.startOfDay(for: now)
        let allowedGapDays = max(0, intentionalRestDays) + 1
        let workoutDays = IntentionalBreaksAnalytics.normalizedWorkoutDays(for: allWorkouts, calendar: calendar)
        let breakDays = IntentionalBreaksAnalytics.breakDaySet(
            from: savedBreaks,
            excluding: workoutDays,
            within: (workoutDays.min() ?? today)...today,
            calendar: calendar
        )
        let currentStreakRun = streakRunsByRecency.first { run in
            let daysSince = IntentionalBreaksAnalytics.effectiveGapDays(
                from: calendar.startOfDay(for: run.end),
                to: today,
                breakDays: breakDays,
                includeEnd: true,
                calendar: calendar
            )
            return daysSince <= allowedGapDays
        }

        let allWorkoutsNewestFirst = allWorkouts.sorted { $0.date > $1.date }
        var streakWorkoutsByRunID: [String: [Workout]] = [:]
        for run in streakRuns {
            let startDay = calendar.startOfDay(for: run.start)
            let endDay = calendar.startOfDay(for: run.end)
            streakWorkoutsByRunID[run.id] = allWorkoutsNewestFirst.filter { workout in
                let day = calendar.startOfDay(for: workout.date)
                return day >= startDay && day <= endDay
            }
        }

        var volumeByWorkoutID: [UUID: Double] = [:]
        volumeByWorkoutID.reserveCapacity(workouts.count)
        for workout in workouts {
            volumeByWorkoutID[workout.id] = ExerciseAggregation.totalVolume(for: workout, resolver: resolver)
        }
        let totalVolume = ExerciseAggregation.totalVolume(for: workouts, resolver: resolver)
        let averageVolumePerSession = workouts.isEmpty ? 0 : totalVolume / Double(workouts.count)
        let peakVolumeSession = workouts.max {
            volumeByWorkoutID[$0.id, default: 0] < volumeByWorkoutID[$1.id, default: 0]
        }
        let volumeWorkouts = sortedWorkouts.filter(\.hasVolume)
        let volumePoints = volumeWorkouts
            .sorted { $0.date < $1.date }
            .map { workout in
                VolumePoint(id: workout.id, date: workout.date, value: volumeByWorkoutID[workout.id, default: 0])
            }
        let topVolumeWorkouts = volumeWorkouts
            .sorted { volumeByWorkoutID[$0.id, default: 0] > volumeByWorkoutID[$1.id, default: 0] }
            .prefix(6)
            .map { $0 }
        let exercises = volumeWorkouts.flatMap { workout in
            ExerciseAggregation.aggregateExercises(in: workout, resolver: resolver).filter(\.hasVolume)
        }
        let topExerciseTotals = Dictionary(grouping: exercises, by: \.name)
            .map { name, matchingExercises in
                ExerciseVolumeTotal(
                    name: name,
                    volume: matchingExercises.reduce(0) { $0 + $1.totalVolume }
                )
            }
            .filter { $0.volume > 0 }
            .sorted { $0.volume > $1.volume }

        return MetricDetailPresentation(
            sortedWorkouts: sortedWorkouts,
            workoutsByDay: workoutsByDay,
            sessionDayBuckets: sessionDayBuckets,
            uniqueWorkoutDayCount: uniqueWorkoutDayCount,
            stackedSessionDayCount: stackedSessionDayCount,
            isCurrentWeekContext: isCurrentWeekContext,
            sessionDisplayDays: sessionDisplayDays,
            averageSessionSpacingDays: averageSessionSpacingDays,
            longestSessionBreakDays: longestSessionBreakDays,
            sessionTimeWindowStats: sessionTimeWindowStats,
            maxSessionTimeWindowCount: maxSessionTimeWindowCount,
            preferredSessionWindow: preferredSessionWindow,
            exerciseCountByWorkoutID: exerciseCountByWorkoutID,
            streakRuns: streakRuns,
            streakRunsByLength: streakRunsByLength,
            streakRunsByRecency: streakRunsByRecency,
            currentStreakRun: currentStreakRun,
            streakWorkoutsByRunID: streakWorkoutsByRunID,
            volumeByWorkoutID: volumeByWorkoutID,
            totalVolume: totalVolume,
            averageVolumePerSession: averageVolumePerSession,
            peakVolumeSession: peakVolumeSession,
            volumeWorkouts: volumeWorkouts,
            volumePoints: volumePoints,
            topVolumeWorkouts: topVolumeWorkouts,
            topExerciseTotals: topExerciseTotals
        )
    }

    private var streakRuns: [StreakRun] {
        presentation.streakRuns
    }

    private var streakRunsByLength: [StreakRun] {
        presentation.streakRunsByLength
    }

    private var streakRunsByRecency: [StreakRun] {
        presentation.streakRunsByRecency
    }

    private var currentStreakRun: StreakRun? {
        presentation.currentStreakRun
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
        return presentation.streakWorkoutsByRunID[run.id] ?? []
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
        presentation.volumePoints
    }

    private var topVolumeWorkouts: [Workout] {
        presentation.topVolumeWorkouts
    }

    private var topExerciseTotals: [ExerciseVolumeTotal] {
        presentation.topExerciseTotals
    }

    private func normalizedVolume(for workout: Workout) -> Double {
        presentation.volumeByWorkoutID[workout.id] ?? 0
    }

    private func exerciseCount(for workout: Workout) -> Int {
        presentation.exerciseCountByWorkoutID[workout.id] ?? 0
    }

    private var volumeListWorkouts: [Workout] {
        if let selectedVolumeWorkoutId,
           let focused = volumeWorkouts.first(where: { $0.id == selectedVolumeWorkoutId }) {
            return [focused] + volumeWorkouts.filter { $0.id != selectedVolumeWorkoutId }
        }
        return volumeWorkouts
    }

    private var volumeWorkouts: [Workout] {
        presentation.volumeWorkouts
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
        Task { @MainActor in
            await Task.yield()
            withAnimation(Theme.Animation.smooth) {
                proxy.scrollTo(scrollTarget, anchor: .top)
            }
        }
    }

    private func syncSelections(using nextPresentation: MetricDetailPresentation) {
        if let selectedSessionDay,
           !nextPresentation.sessionDayBuckets.contains(where: {
               sundayCalendar.isDate($0.dayStart, inSameDayAs: selectedSessionDay)
           }) {
            self.selectedSessionDay = nil
        }

        if let selectedVolumeWorkoutId,
           !nextPresentation.volumeWorkouts.contains(where: { $0.id == selectedVolumeWorkoutId }) {
            self.selectedVolumeWorkoutId = nil
        }

        let fallbackStreakRunID = nextPresentation.currentStreakRun?.id
            ?? nextPresentation.streakRunsByLength.first?.id
        if let selectedStreakRunId,
           !nextPresentation.streakRuns.contains(where: { $0.id == selectedStreakRunId }) {
            self.selectedStreakRunId = fallbackStreakRunID
        } else if self.selectedStreakRunId == nil {
            self.selectedStreakRunId = fallbackStreakRunID
        }
    }
}

private struct MetricDetailPresentation {
    let sortedWorkouts: [Workout]
    let workoutsByDay: [Date: [Workout]]
    let sessionDayBuckets: [SessionDayBucket]
    let uniqueWorkoutDayCount: Int
    let stackedSessionDayCount: Int
    let isCurrentWeekContext: Bool
    let sessionDisplayDays: [SessionDisplayDay]
    let averageSessionSpacingDays: Double?
    let longestSessionBreakDays: Int?
    let sessionTimeWindowStats: [SessionTimeWindowStat]
    let maxSessionTimeWindowCount: Int
    let preferredSessionWindow: SessionTimeWindow?
    let exerciseCountByWorkoutID: [UUID: Int]
    let streakRuns: [StreakRun]
    let streakRunsByLength: [StreakRun]
    let streakRunsByRecency: [StreakRun]
    let currentStreakRun: StreakRun?
    let streakWorkoutsByRunID: [String: [Workout]]
    let volumeByWorkoutID: [UUID: Double]
    let totalVolume: Double
    let averageVolumePerSession: Double
    let peakVolumeSession: Workout?
    let volumeWorkouts: [Workout]
    let volumePoints: [VolumePoint]
    let topVolumeWorkouts: [Workout]
    let topExerciseTotals: [ExerciseVolumeTotal]

    static let empty = MetricDetailPresentation(
        sortedWorkouts: [],
        workoutsByDay: [:],
        sessionDayBuckets: [],
        uniqueWorkoutDayCount: 0,
        stackedSessionDayCount: 0,
        isCurrentWeekContext: true,
        sessionDisplayDays: [],
        averageSessionSpacingDays: nil,
        longestSessionBreakDays: nil,
        sessionTimeWindowStats: [],
        maxSessionTimeWindowCount: 1,
        preferredSessionWindow: nil,
        exerciseCountByWorkoutID: [:],
        streakRuns: [],
        streakRunsByLength: [],
        streakRunsByRecency: [],
        currentStreakRun: nil,
        streakWorkoutsByRunID: [:],
        volumeByWorkoutID: [:],
        totalVolume: 0,
        averageVolumePerSession: 0,
        peakVolumeSession: nil,
        volumeWorkouts: [],
        volumePoints: [],
        topVolumeWorkouts: [],
        topExerciseTotals: []
    )
}

private struct ExerciseVolumeTotal {
    let name: String
    let volume: Double
}

/// The shared streak component derives runs from raw workouts during every body
/// evaluation. This variant accepts the already-cached ordering for this screen.
private struct CachedLongestStreaksSection: View {
    let runs: [StreakRun]
    let collapsedCount: Int
    let maxExpandedCount: Int
    let selectedRunId: String?
    let onSelectRun: (StreakRun) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            if runs.isEmpty {
                Text("No streaks yet")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            } else {
                Text("Tap a streak to inspect it below")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(displayRuns.enumerated()), id: \.element.id) { index, run in
                        Button {
                            Haptics.selection()
                            onSelectRun(run)
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                Text("\(index + 1)")
                                    .font(Theme.Typography.captionBold)
                                    .foregroundColor(Theme.Colors.textTertiary)
                                    .frame(width: 18, alignment: .leading)

                                Text("\(run.workoutDayCount) day\(run.workoutDayCount == 1 ? "" : "s")")
                                    .font(Theme.Typography.subheadline)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                Spacer()

                                Text(dateLabel(for: run))
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, Theme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .fill(
                                        selectedRunId == run.id
                                            ? Theme.Colors.accent.opacity(0.12)
                                            : Theme.Colors.surface.opacity(0.55)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .strokeBorder(
                                        selectedRunId == run.id ? Theme.Colors.accent : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text("Longest Streaks")
                .font(Theme.Typography.cardHeader)
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            if runs.count > collapsedCount {
                Button {
                    withAnimation(Theme.Animation.spring) {
                        isExpanded.toggle()
                    }
                    Haptics.selection()
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(isExpanded ? "Less" : "More")
                            .font(Theme.Typography.metricLabel)
                            .foregroundColor(Theme.Colors.accent)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.accent)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var displayRuns: [StreakRun] {
        guard runs.count > collapsedCount else { return runs }
        return isExpanded
            ? Array(runs.prefix(maxExpandedCount))
            : Array(runs.prefix(collapsedCount))
    }

    private func dateLabel(for run: StreakRun) -> String {
        let calendar = Calendar.current
        if calendar.isDate(run.start, equalTo: run.end, toGranularity: .day) {
            return run.start.formatted(date: .abbreviated, time: .omitted)
        }

        let startYear = calendar.component(.year, from: run.start)
        let endYear = calendar.component(.year, from: run.end)
        if startYear == endYear {
            let start = run.start.formatted(Date.FormatStyle().month(.abbreviated).day())
            let end = run.end.formatted(Date.FormatStyle().month(.abbreviated).day().year())
            return "\(start) - \(end)"
        }

        let start = run.start.formatted(Date.FormatStyle().month(.abbreviated).day().year())
        let end = run.end.formatted(Date.FormatStyle().month(.abbreviated).day().year())
        return "\(start) - \(end)"
    }
}

private struct HeroChip: View {
    let title: String
    let value: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                .fixedSize(horizontal: false, vertical: true)
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
    let exerciseCount: Int
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
                Text("\(exerciseCount) exercises")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .tracking(0.7)

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

// swiftlint:enable type_body_length file_length
