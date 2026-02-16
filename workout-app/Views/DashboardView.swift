import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    let annotationsManager: WorkoutAnnotationsManager
    let gymProfilesManager: GymProfilesManager
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var ouraManager: OuraManager
    @EnvironmentObject var programStore: ProgramStore
    @EnvironmentObject var sessionManager: WorkoutSessionManager

    @StateObject private var insightsEngine: InsightsEngine
    @State private var selectedTimeRange = TimeRange.week
    @State private var selectedExercise: ExerciseSelection?
    @State private var selectedWorkout: Workout?
    @State private var selectedWorkoutMetric: WorkoutMetricDetailSelection?
    @State private var selectedChangeMetric: ChangeMetric?
    @State private var showingMuscleBalance = false
    @State private var isTimeRangeExpanded = true
    @State private var isSummaryExpanded = true
    @State private var isProgramExpanded = true
    @State private var isTrainingExpanded = true
    @State private var isChangeExpanded = false
    @State private var isHighlightsExpanded = false
    @State private var isExploreExpanded = false
    @State private var selectedProgramDay: DashboardProgramDaySelection?
    @State private var showingProgramReplaceAlert = false
    private let maxContentWidth: CGFloat = 820

    init(
        dataManager: WorkoutDataManager,
        iCloudManager: iCloudDocumentManager,
        annotationsManager: WorkoutAnnotationsManager,
        gymProfilesManager: GymProfilesManager
    ) {
        self.dataManager = dataManager
        self.iCloudManager = iCloudManager
        self.annotationsManager = annotationsManager
        self.gymProfilesManager = gymProfilesManager
        _insightsEngine = StateObject(
            wrappedValue: InsightsEngine(
                dataManager: dataManager,
                annotationsProvider: { annotationsManager.annotations },
                gymNameProvider: { gymProfilesManager.gymNameSnapshot() }
            )
        )
    }

    enum TimeRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case threeMonths = "3 Months"
        case year = "Year"
        case allTime = "All Time"
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    headerSection

                    if dataManager.workouts.isEmpty {
                        EmptyDataView()
                            .padding(.horizontal, Theme.Spacing.lg)
                    } else {
                        timeRangeSection
                            .padding(.horizontal, Theme.Spacing.lg)
                        summarySection
                            .padding(.horizontal, Theme.Spacing.lg)

                        if let today = todayProgram {
                            programSection(today)
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        CollapsibleSection(
                            title: "Change",
                            subtitle: timeRangeDetailLabel,
                            isExpanded: $isChangeExpanded
                        ) {
                            changeSummaryContent
                        }
                        .padding(.horizontal, Theme.Spacing.lg)

                        CollapsibleSection(
                            title: "Highlights",
                            isExpanded: $isHighlightsExpanded
                        ) {
                            highlightsContent
                        }
                        .padding(.horizontal, Theme.Spacing.lg)

                        trainingSection
                            .padding(.horizontal, Theme.Spacing.lg)

                        CollapsibleSection(
                            title: "Explore",
                            isExpanded: $isExploreExpanded
                        ) {
                            exploreContent
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(item: $selectedExercise) { selection in
            ExerciseDetailView(
                exerciseName: selection.id,
                dataManager: dataManager,
                annotationsManager: annotationsManager,
                gymProfilesManager: gymProfilesManager
            )
        }
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
        .navigationDestination(item: $selectedWorkoutMetric) { selection in
            MetricDetailView(
                kind: selection.kind,
                workouts: filteredWorkouts,
                scrollTarget: selection.scrollTarget
            )
        }
        .navigationDestination(item: $selectedChangeMetric) { metric in
            ChangeMetricDetailView(metric: metric, window: changeWindow, workouts: dataManager.workouts)
        }
        .navigationDestination(item: $selectedProgramDay) { selection in
            ProgramDayDetailView(dayId: selection.id)
        }
        .alert("Replace active session?", isPresented: $showingProgramReplaceAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                startTodayPlan(forceReplace: true)
            }
        } message: {
            Text("Starting today's planned session will discard the current in-progress session.")
        }
        .navigationDestination(isPresented: $showingMuscleBalance) {
            MuscleBalanceDetailView(
                dataManager: dataManager,
                dateRange: selectedDateRange,
                rangeLabel: timeRangeDetailLabel
            )
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            Task {
                await ouraManager.autoRefreshOnForeground()
            }
            if dataManager.workouts.isEmpty {
                // Offload file reading to background to prevent main thread hitch
                Task { await loadLatestWorkoutData() }
            } else {
                // Just refresh these lightweight checks
                triggerAutoHealthSync()
                refreshInsights()
            }
        }
        .refreshable {
            await loadLatestWorkoutData()
            await ouraManager.autoRefreshOnForeground()
        }
        .onChange(of: dataManager.workouts.count) { _, _ in
            refreshInsights()
            triggerAutoHealthSync()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Progress")
                        .font(Theme.Typography.screenTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .tracking(1.5)
                    Text(headerSummary)
                        .font(Theme.Typography.microcopy)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    SyncStatusPill(text: syncStatusText, isActive: isHealthFresh)
                    Text(Date().formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var timeRangeSection: some View {
        CollapsibleSection(
            title: "Time Range",
            subtitle: timeRangeDetailLabel,
            isExpanded: $isTimeRangeExpanded
        ) {
            TimeRangePicker(selectedRange: $selectedTimeRange)
        }
    }

    private var summarySection: some View {
        CollapsibleSection(
            title: "Summary",
            subtitle: headerSummary,
            isExpanded: $isSummaryExpanded
        ) {
            if let currentStats = filteredStats {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.md) {
                        MetricTileButton(
                            action: {
                                selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .sessions, scrollTarget: nil)
                            },
                            content: {
                                SummaryMetricCard(title: "Sessions", value: "\(currentStats.totalWorkouts)")
                            }
                        )
                        MetricTileButton(
                            action: {
                                selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .avgDuration, scrollTarget: nil)
                            },
                            content: {
                                SummaryMetricCard(title: "Avg Duration", value: currentStats.avgWorkoutDuration)
                            }
                        )
                        MetricTileButton(
                            action: {
                                selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .totalVolume, scrollTarget: nil)
                            },
                            content: {
                                SummaryMetricCard(title: "Volume", value: formatVolume(currentStats.totalVolume))
                            }
                        )
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                        MetricTileButton(
                            action: {
                                selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .sessions, scrollTarget: nil)
                            },
                            content: {
                                SummaryMetricCard(title: "Sessions", value: "\(currentStats.totalWorkouts)")
                            }
                        )
                        MetricTileButton(
                            action: {
                                selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .avgDuration, scrollTarget: nil)
                            },
                            content: {
                                SummaryMetricCard(title: "Avg Duration", value: currentStats.avgWorkoutDuration)
                            }
                        )
                        MetricTileButton(
                            action: {
                                selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .totalVolume, scrollTarget: nil)
                            },
                            content: {
                                SummaryMetricCard(title: "Volume", value: formatVolume(currentStats.totalVolume))
                            }
                        )
                    }
                }
            } else {
                MetricsSkeletonView()
            }
        }
    }

    private var todayProgram: ProgramTodayPlan? {
        programStore.todayPlan(
            dailyHealthStore: healthManager.dailyHealthStore,
            ouraScores: ouraManager.dailyScoreStore
        )
    }

    private func programSection(_ today: ProgramTodayPlan) -> some View {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let scheduledStart = Calendar.current.startOfDay(for: today.day.scheduledDate)
        let isOverdue = scheduledStart < todayStart

        return CollapsibleSection(
            title: "Program",
            subtitle: "Week \(today.day.weekNumber) • Day \(today.day.dayNumber)",
            isExpanded: $isProgramExpanded
        ) {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(today.day.focusTitle)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Week \(today.day.weekNumber) • Day \(today.day.dayNumber)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if isOverdue {
                        Text("Overdue • \(today.day.scheduledDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(Theme.Typography.microcopy)
                            .foregroundStyle(Theme.Colors.warning)
                    }

                    Text("Readiness \(Int(round(today.readiness.score)))")
                        .font(Theme.Typography.microcopy)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                VStack(spacing: Theme.Spacing.xs) {
                    Button {
                        if sessionManager.activeSession != nil {
                            showingProgramReplaceAlert = true
                        } else {
                            startTodayPlan(forceReplace: false)
                        }
                    } label: {
                        Text("Start")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .brutalistButtonChrome(
                                fill: Theme.Colors.accent,
                                cornerRadius: Theme.CornerRadius.large
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedProgramDay = DashboardProgramDaySelection(id: today.day.id)
                        Haptics.selection()
                    } label: {
                        Text("Open Day")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
        }
    }

    private func startTodayPlan(forceReplace: Bool) {
        guard let today = todayProgram else { return }

        Task { @MainActor in
            if forceReplace {
                await sessionManager.discardDraft()
            }

            sessionManager.startSession(
                name: today.day.focusTitle,
                gymProfileId: gymProfilesManager.lastUsedGymProfileId,
                templateExercises: today.adjustedExercises,
                plannedProgramId: today.planId,
                plannedDayId: today.day.id,
                plannedDayDate: today.day.scheduledDate
            )
            sessionManager.isPresentingSessionUI = true
            Haptics.notify(.success)
        }
    }

    private var changeSummaryContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if changeSummaryMetrics.isEmpty {
                Text("No change data yet.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(changeSummaryMetrics) { metric in
                        MetricTileButton(
                            action: {
                                selectedChangeMetric = metric
                            },
                            content: {
                                ChangeMetricRow(metric: metric)
                            }
                        )
                    }
                }
            }

            NavigationLink {
                PerformanceLabView(dataManager: dataManager)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Open Performance Lab")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.md)
                .softCard(elevation: 1)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var highlightsContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if progressHighlights.isEmpty {
                EmptyHighlightsView()
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(progressHighlights) { item in
                        HighlightCardView(item: item)
                    }
                }
            }
        }
    }

    private var trainingSection: some View {
        CollapsibleSection(
            title: "Training",
            subtitle: timeRangeDetailLabel,
            isExpanded: $isTrainingExpanded
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Consistency shows first without header
                if let currentStats = filteredStats {
                    ConsistencyView(
                        stats: currentStats,
                        workouts: filteredWorkouts,
                        streakWorkouts: dataManager.workouts,
                        timeRange: consistencyTimeRange,
                        dateRange: selectedDateRange
                    ) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .streak, scrollTarget: nil)
                    }
                } else {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .fill(Theme.Colors.surface.opacity(0.6))
                        .frame(height: 220)
                }

                VolumeProgressChart(workouts: filteredWorkouts) {
                    selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .totalVolume, scrollTarget: nil)
                }
                MuscleHeatmapView(
                    dataManager: dataManager,
                    dateRange: selectedDateRange,
                    rangeLabel: timeRangeDetailLabel
                ) {
                    showingMuscleBalance = true
                }
                ExerciseBreakdownView(workouts: filteredWorkouts) {
                    selectedWorkoutMetric = WorkoutMetricDetailSelection(
                        kind: .totalVolume,
                        scrollTarget: .topExercisesByVolume
                    )
                }
            }
        }
    }

    private var exploreContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            NavigationLink {
                ProgramHubView()
            } label: {
                ExplorationRow(
                    title: "Program Coach",
                    subtitle: "Adaptive 8-week plans",
                    icon: "calendar.badge.clock",
                    tint: Theme.Colors.accent
                )
            }
            .buttonStyle(PlainButtonStyle())

            NavigationLink {
                PerformanceLabView(dataManager: dataManager)
            } label: {
                ExplorationRow(
                    title: "Performance Lab",
                    subtitle: "Trends and comparisons",
                    icon: "viewfinder",
                    tint: Theme.Colors.success
                )
            }
            .buttonStyle(PlainButtonStyle())

            NavigationLink {
                ExerciseListView(dataManager: dataManager)
            } label: {
                ExplorationRow(
                    title: "Exercises",
                    subtitle: "History by lift",
                    icon: "figure.strengthtraining.traditional",
                    tint: Theme.Colors.accentSecondary
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var filteredWorkouts: [Workout] {
        guard !dataManager.workouts.isEmpty else { return [] }
        return dataManager.workouts.filter { selectedDateRange.contains($0.date) }
    }

    private var selectedDateRange: DateInterval {
        let calendar = Calendar.current
        let now = Date()

        switch selectedTimeRange {
        case .week:
            let start = startOfWeekSunday(for: now)
            return DateInterval(start: start, end: now)
        case .month:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .threeMonths:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return DateInterval(start: start, end: now)
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return DateInterval(start: start, end: now)
        case .allTime:
            let oldest = dataManager.workouts.map { $0.date }.min() ?? now
            return DateInterval(start: oldest, end: now)
        }
    }

    private var timeRangeDetailLabel: String {
        formattedRange(
            selectedDateRange,
            includeWeekday: selectedTimeRange == .week,
            forceIncludeYear: selectedTimeRange == .year || selectedTimeRange == .allTime
        )
    }

    private func startOfWeekSunday(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func formattedRange(_ range: DateInterval, includeWeekday: Bool, forceIncludeYear: Bool) -> String {
        let calendar = Calendar.current
        let startYear = calendar.component(.year, from: range.start)
        let endYear = calendar.component(.year, from: range.end)
        let includeYear = forceIncludeYear || startYear != endYear

        let startText = formattedDate(range.start, includeWeekday: includeWeekday, includeYear: includeYear)
        let endText = formattedDate(range.end, includeWeekday: includeWeekday, includeYear: includeYear)
        if startText == endText { return startText }
        return "\(startText) – \(endText)"
    }

    private func formattedDate(_ date: Date, includeWeekday: Bool, includeYear: Bool) -> String {
        var style = Date.FormatStyle()
            .month(.abbreviated)
            .day()

        if includeYear {
            style = style.year()
        }
        if includeWeekday {
            style = style.weekday(.abbreviated)
        }
        return date.formatted(style)
    }

    private var filteredStats: WorkoutStats? {
        guard !filteredWorkouts.isEmpty else { return nil }
        return dataManager.calculateStats(for: filteredWorkouts)
    }

    private var headerSummary: String {
        guard let stats = filteredStats else {
            return "Sessions 0 • Avg --"
        }

        return "Sessions \(stats.totalWorkouts) • Avg \(stats.avgWorkoutDuration)"
    }

    private var syncStatusText: String {
        if healthManager.isAutoSyncing {
            return "syncing"
        }
        switch healthManager.authorizationStatus {
        case .authorized:
            if let lastSync = healthManager.lastSyncDate {
                return "sync \(lastSync.formatted(.relative(presentation: .named)))"
            }
            return "sync ready"
        case .notDetermined:
            return "health off"
        case .denied:
            return "health denied"
        case .unavailable:
            return "health n/a"
        }
    }

    private var isHealthFresh: Bool {
        guard let lastSync = healthManager.lastSyncDate else { return false }
        return abs(lastSync.timeIntervalSinceNow) < 3600 * 6
    }

    private var consistencyTimeRange: ConsistencyView.TimeRangeOption {
        switch selectedTimeRange {
        case .week: return .week
        case .month: return .month
        case .threeMonths: return .threeMonths
        case .year: return .year
        case .allTime: return .allTime
        }
    }

    private var changeWindow: ChangeMetricWindow {
        let calendar = Calendar.current
        let current = selectedDateRange

        switch selectedTimeRange {
        case .week:
            let previousStart = calendar.date(byAdding: .day, value: -7, to: current.start) ?? current.start
            let previousEnd = calendar.date(byAdding: .day, value: -7, to: current.end) ?? current.end
            return ChangeMetricWindow(
                label: "This week • \(timeRangeDetailLabel)",
                current: current,
                previous: DateInterval(start: previousStart, end: previousEnd)
            )
        case .month:
            let previousStart = calendar.date(byAdding: .month, value: -1, to: current.start) ?? current.start
            let previousEnd = calendar.date(byAdding: .month, value: -1, to: current.end) ?? current.end
            return ChangeMetricWindow(
                label: "This month • \(timeRangeDetailLabel)",
                current: current,
                previous: DateInterval(start: previousStart, end: previousEnd)
            )
        case .threeMonths:
            let previousStart = calendar.date(byAdding: .month, value: -3, to: current.start) ?? current.start
            let previousEnd = current.start.addingTimeInterval(-0.001)
            return ChangeMetricWindow(
                label: "Last 3 months • \(timeRangeDetailLabel)",
                current: current,
                previous: DateInterval(start: previousStart, end: previousEnd)
            )
        case .year:
            let previousStart = calendar.date(byAdding: .year, value: -1, to: current.start) ?? current.start
            let previousEnd = current.start.addingTimeInterval(-0.001)
            return ChangeMetricWindow(
                label: "Last year • \(timeRangeDetailLabel)",
                current: current,
                previous: DateInterval(start: previousStart, end: previousEnd)
            )
        case .allTime:
            let duration = current.duration
            let previousEnd = duration > 0 ? current.start.addingTimeInterval(-0.001) : current.start
            let previousStart = previousEnd.addingTimeInterval(-duration)
            return ChangeMetricWindow(
                label: "All time • \(timeRangeDetailLabel)",
                current: current,
                previous: DateInterval(start: previousStart, end: previousEnd)
            )
        }
    }

    private var windowChangeMetrics: [ChangeMetric] {
        WorkoutAnalytics.changeMetrics(for: dataManager.workouts, window: changeWindow)
    }

    private var changeSummaryMetrics: [ChangeMetric] {
        let preferred = windowChangeMetrics.filter {
            $0.title.contains("Sessions") || $0.title.contains("Volume") || $0.title.contains("Duration")
        }
        if !preferred.isEmpty {
            return Array(preferred.prefix(3))
        }
        return Array(windowChangeMetrics.prefix(3))
    }

    private var progressHighlights: [HighlightItem] {
        var items: [HighlightItem] = []

        if let latest = filteredWorkouts.first {
            items.append(
                HighlightItem(
                    title: "Latest",
                    value: latest.name,
                    subtitle: latest.date.formatted(date: .abbreviated, time: .omitted),
                    icon: "clock.fill",
                    tint: Theme.Colors.accentSecondary,
                    action: { selectedWorkout = latest }
                )
            )
        }

        let allowedTypes: Set<InsightType> = [.personalRecord, .strengthGain, .baseline]
        let filteredInsights = insightsEngine.insights.filter { allowedTypes.contains($0.type) }

        let remaining = max(0, 3 - items.count)
        for insight in filteredInsights.prefix(remaining) {
            let highlightValue = sanitizedHighlightValue(from: insight.message)
            items.append(
                HighlightItem(
                    title: insight.title,
                    value: highlightValue,
                    subtitle: insight.date.formatted(date: .abbreviated, time: .omitted),
                    icon: insight.type.iconName,
                    tint: highlightTint(for: insight.type),
                    action: {
                        if let exerciseName = insight.exerciseName {
                            selectedExercise = ExerciseSelection(id: exerciseName)
                        }
                    }
                )
            )
        }

        return items
    }

    @MainActor
    private func loadLatestWorkoutData() async {
        let directoryURL = iCloudManager.storageSnapshot().url
        let setsResult = await Task.detached(priority: .userInitiated) { [directoryURL] in
            do {
                guard let directoryURL else { return Result<[WorkoutSet], Error>.success([]) }

                let importFiles = iCloudDocumentManager.listStrongImportFiles(in: directoryURL)
                let files = (importFiles.isEmpty
                    ? iCloudDocumentManager.listWorkoutFiles(in: directoryURL)
                    : importFiles)
                    .sorted { url1, url2 in
                        let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                        let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                        return date1 > date2
                    }

                guard let latestFile = files.first else { return Result<[WorkoutSet], Error>.success([]) }
                let data = try Data(contentsOf: latestFile)
                let sets = try CSVParser.parseStrongWorkoutsCSV(from: data)
                return Result<[WorkoutSet], Error>.success(sets)
            } catch {
                return Result<[WorkoutSet], Error>.failure(error)
            }
        }.value

        switch setsResult {
        case .success(let sets):
            guard !sets.isEmpty else { return }
            let healthSnapshot = Array(healthManager.healthDataStore.values)
            await dataManager.processImportedWorkoutSets(sets, healthDataSnapshot: healthSnapshot)
            refreshInsights()
        case .failure(let error):
            print("Failed to load workout data: \(error)")
        }
    }

    private func refreshInsights() {
        Task {
            await insightsEngine.generateInsights()
        }
    }

    private func triggerAutoHealthSync() {
        guard healthManager.authorizationStatus == .authorized else { return }
        Task {
            await healthManager.syncRecentWorkoutsIfNeeded(dataManager.workouts)
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000000 {
            return String(format: "%.1fM", volume / 1000000)
        } else if volume >= 1000 {
            return String(format: "%.0fk", volume / 1000)
        }
        return "\(Int(volume))"
    }

    private func sanitizedHighlightValue(from message: String) -> String {
        let parts = message
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let filtered = parts.filter { part in
            let lower = part.lowercased()
            return !lower.contains("delta") && !lower.contains("n=") && !lower.contains("ratio")
        }

        if !filtered.isEmpty {
            return filtered.joined(separator: " • ")
        }
        return message
    }

    private func highlightTint(for type: InsightType) -> Color {
        switch type {
        case .personalRecord:
            return Theme.Colors.gold
        case .strengthGain:
            return Theme.Colors.success
        case .baseline:
            return Theme.Colors.accentSecondary
        }
    }
}

private struct SyncStatusPill: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isActive ? Theme.Colors.success : Theme.Colors.textTertiary)
                .frame(width: 6, height: 6)
            Text(text)
                .font(Theme.Typography.metricLabel)
                .textCase(.uppercase)
                .tracking(0.8)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .strokeBorder(Theme.Colors.border, lineWidth: 2)
        )
        .cornerRadius(Theme.CornerRadius.small)
    }
}

private struct DashboardProgramDaySelection: Hashable, Identifiable {
    let id: UUID
}

private struct TimeRangePicker: View {
    @Binding var selectedRange: DashboardView.TimeRange

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(DashboardView.TimeRange.allCases, id: \.self) { range in
                    let isSelected = selectedRange == range
                    Button {
                        selectedRange = range
                        Haptics.selection()
                    } label: {
                        Text(range.rawValue)
                            .font(Theme.Typography.metricLabel)
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .fill(isSelected ? Theme.Colors.accent : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .strokeBorder(Theme.Colors.border, lineWidth: 2)
                            )
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }
}

private struct SummaryMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)

            Text(value)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(elevation: 2)
    }
}

private struct ChangeMetricRow: View {
    let metric: ChangeMetric

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: metric.isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.caption.weight(.bold))
                .foregroundColor(metric.isPositive ? Theme.Colors.success : Theme.Colors.warning)
                .frame(width: 24, height: 24)
                .background((metric.isPositive ? Theme.Colors.success : Theme.Colors.warning).opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                        .strokeBorder(metric.isPositive ? Theme.Colors.success : Theme.Colors.warning, lineWidth: 2)
                )
                .cornerRadius(Theme.CornerRadius.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(formatValue(metric))
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }

    private func formatValue(_ metric: ChangeMetric) -> String {
        if metric.title.contains("Sessions") {
            return String(format: "%.0f", metric.current)
        }
        if metric.title.contains("Duration") {
            return formatDurationMinutes(metric.current)
        }
        if metric.title.contains("Volume") {
            return formatVolume(metric.current)
        }
        return String(format: "%.1f", metric.current)
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000000 {
            return String(format: "%.1fM", volume / 1000000)
        }
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }

    private func formatDurationMinutes(_ minutes: Double) -> String {
        let value = Int(round(minutes))
        if value >= 60 {
            return "\(value / 60)h \(value % 60)m"
        }
        return "\(value)m"
    }
}

private struct ExplorationRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                        .strokeBorder(tint, lineWidth: 2)
                )
                .cornerRadius(Theme.CornerRadius.small)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
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
}

private struct EmptyDataView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("No sessions yet")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Your progress view will fill in after your first workout.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 2)
    }
}

private struct MetricsSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surface.opacity(0.6))
                .frame(height: 24)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Theme.Colors.surface.opacity(0.6))
                        .frame(height: 120)
                }
            }
        }
    }
}
