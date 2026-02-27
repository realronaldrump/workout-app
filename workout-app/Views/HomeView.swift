import SwiftUI

struct HomeView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    let annotationsManager: WorkoutAnnotationsManager
    let gymProfilesManager: GymProfilesManager
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var insightsEngine: InsightsEngine
    @EnvironmentObject var sessionManager: WorkoutSessionManager
    @Binding var selectedTab: AppTab

    @StateObject private var correlationEngine = DataCorrelationEngine()
    @AppStorage("weightIncrement") private var weightIncrement: Double = 2.5

    @State private var showingImportWizard = false
    @State private var showingHealthWizard = false
    @State private var showingQuickStart = false
    @State private var quickStartExercise: String?
    @State private var selectedExercise: ExerciseSelection?
    @State private var selectedWorkout: Workout?
    @State private var selectedWorkoutMetric: WorkoutMetricDetailSelection?
    @State private var selectedChangeMetric: ChangeMetric?
    @State private var showingMuscleBalance = false
    @State private var showRepeatWorkoutId: UUID?
    private let maxContentWidth: CGFloat = 820

    init(
        dataManager: WorkoutDataManager,
        iCloudManager: iCloudDocumentManager,
        annotationsManager: WorkoutAnnotationsManager,
        gymProfilesManager: GymProfilesManager,
        selectedTab: Binding<AppTab>
    ) {
        self.dataManager = dataManager
        self.iCloudManager = iCloudManager
        self.annotationsManager = annotationsManager
        self.gymProfilesManager = gymProfilesManager
        _selectedTab = selectedTab
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    headerSection

                    quickActionsSection

                    if dataManager.isLoading && dataManager.workouts.isEmpty {
                        LoadingCard()
                            .padding(.horizontal, Theme.Spacing.lg)
                    } else if let error = dataManager.error, dataManager.workouts.isEmpty {
                        ErrorCard(message: error) {
                            Task {
                                await dataManager.loadLatestWorkoutData(
                                    iCloudManager: iCloudManager,
                                    healthDataSnapshot: Array(healthManager.healthDataStore.values)
                                )
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                    } else if dataManager.workouts.isEmpty {
                        HomeEmptyState(
                            onStart: { startQuickSession(exercise: nil) },
                            onImport: { showingImportWizard = true }
                        )
                        .padding(.horizontal, Theme.Spacing.lg)
                    } else {
                        // Pre-Workout Briefing — the app's unique differentiator.
                        // Surfaces recovery, muscle recency, time-of-day, and sleep
                        // correlation data all in one glanceable card.
                        PreWorkoutBriefingCard(
                            recoveryReadiness: correlationEngine.recoveryReadiness,
                            muscleSuggestions: muscleSuggestions,
                            bestTimeBucket: bestPerformanceTimeBucket,
                            sleepCorrelation: sleepCorrelation,
                            onStartSession: { groupName in
                                startQuickSession(exercise: groupName)
                            },
                            onExerciseTap: { name in
                                selectedExercise = ExerciseSelection(id: name)
                            }
                        )
                        .padding(.horizontal, Theme.Spacing.lg)

                        weeklySummarySection
                            .padding(.horizontal, Theme.Spacing.lg)

                        // Change metrics — always visible (not collapsed)
                        changeSection
                            .padding(.horizontal, Theme.Spacing.lg)

                        // Highlights — always visible (not collapsed)
                        if !homeHighlights.isEmpty {
                            HighlightsSectionView(title: "Highlights", items: homeHighlights)
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        // Data Insights (plateaus, efficiency, frequency)
                        DataInsightCards(
                            plateaus: correlationEngine.plateauAlerts,
                            efficiencyTrends: correlationEngine.efficiencyTrends,
                            frequencyInsights: correlationEngine.frequencyInsights,
                            onExerciseTap: { name in
                                selectedExercise = ExerciseSelection(id: name)
                            }
                        )
                        .padding(.horizontal, Theme.Spacing.lg)

                        // Recent workouts with repeat capability
                        recentWorkoutsSection
                            .padding(.horizontal, Theme.Spacing.lg)

                        exploreSection
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
                workouts: weeklyWorkouts,
                scrollTarget: selection.scrollTarget
            )
        }
        .navigationDestination(item: $selectedChangeMetric) { metric in
            ChangeMetricDetailView(metric: metric, window: changeWindow, workouts: dataManager.workouts)
        }
        .navigationDestination(isPresented: $showingMuscleBalance) {
            MuscleBalanceDetailView(
                dataManager: dataManager,
                dateRange: weeklyDateRange,
                rangeLabel: "This Week"
            )
        }
        .sheet(isPresented: $showingImportWizard) {
            StrongImportWizard(
                isPresented: $showingImportWizard,
                dataManager: dataManager,
                iCloudManager: iCloudManager
            )
        }
        .sheet(isPresented: $showingHealthWizard) {
            HealthSyncWizard(
                isPresented: $showingHealthWizard,
                workouts: dataManager.workouts
            )
        }
        .sheet(isPresented: $showingQuickStart) {
            QuickStartView(exerciseName: quickStartExercise)
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            if dataManager.workouts.isEmpty {
                Task {
                    await dataManager.loadLatestWorkoutData(
                        iCloudManager: iCloudManager,
                        healthDataSnapshot: Array(healthManager.healthDataStore.values)
                    )
                    await insightsEngine.generateInsights()
                    await runCorrelationAnalysis()
                }
            } else {
                triggerAutoHealthSync()
                Task { await runCorrelationAnalysis() }
            }
        }
        .refreshable {
            await dataManager.loadLatestWorkoutData(
                iCloudManager: iCloudManager,
                healthDataSnapshot: Array(healthManager.healthDataStore.values)
            )
            await insightsEngine.generateInsights()
            await runCorrelationAnalysis()
        }
        .onChange(of: dataManager.workouts.count) { _, _ in
            triggerAutoHealthSync()
            Task { await runCorrelationAnalysis() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(greetingText)
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text("Dashboard")
                        .font(Theme.Typography.screenTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .tracking(1.5)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                    SyncStatusPill(text: syncStatusText, isActive: isHealthFresh)
                    Text(Date().formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            if !headerSubtitle.isEmpty {
                Text(headerSubtitle)
                    .font(Theme.Typography.microcopy)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .animateOnAppear(delay: 0)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Late night"
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Primary CTA — gradient hero button
            Button(
                action: {
                    Haptics.selection()
                    startQuickSession(exercise: nil)
                },
                label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("Start a Session")
                            .font(Theme.Typography.headline)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.lg)
                    .frame(minHeight: 60)
                    .background(Theme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge))
                    .shadow(
                        color: Theme.Colors.accent.opacity(0.3),
                        radius: 12,
                        x: 0,
                        y: 6
                    )
                    .shadow(
                        color: Theme.Colors.accent.opacity(0.15),
                        radius: 24,
                        x: 0,
                        y: 12
                    )
                }
            )
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)
            .animateOnAppear(delay: 0.05)

            // Repeat last workout
            if let lastWorkout = dataManager.workouts.first {
                Button(
                    action: {
                        Haptics.selection()
                        repeatWorkout(lastWorkout)
                    },
                    label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.accent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Repeat Last")
                                    .font(Theme.Typography.metricLabel)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                    .textCase(.uppercase)
                                    .tracking(0.6)
                                Text(lastWorkout.name)
                                    .font(Theme.Typography.bodyBold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(lastWorkout.date.formatted(date: .abbreviated, time: .omitted))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.md)
                        .softCard(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
                    }
                )
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.lg)
                .animateOnAppear(delay: 0.1)
            }

            // Secondary chips
            HStack(spacing: Theme.Spacing.md) {
                SecondaryChip(title: "Import", icon: "arrow.down.to.line") {
                    showingImportWizard = true
                }
                SecondaryChip(title: "Health", icon: "heart.fill") {
                    if healthManager.authorizationStatus == .authorized {
                        selectedTab = .health
                    } else {
                        showingHealthWizard = true
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .animateOnAppear(delay: 0.15)
        }
    }

    // MARK: - Weekly Summary

    private var weeklySummarySection: some View {
        let workouts = weeklyWorkouts
        let stats = workouts.isEmpty ? nil : dataManager.calculateStats(for: workouts)
        let sessions = stats.map { "\($0.totalWorkouts)" } ?? "0"
        let avgDuration = stats?.avgWorkoutDuration ?? "--"
        let volumeText = stats.map { SharedFormatters.volumeCompact($0.totalVolume) } ?? "--"
        let allStats = dataManager.workouts.isEmpty ? nil : dataManager.calculateStats(for: dataManager.workouts)
        let streak = allStats?.currentStreak ?? 0

        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("This Week")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .tracking(1.0)
                Spacer()
                if streak > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(streak)w streak")
                            .font(Theme.Typography.captionBold)
                    }
                    .foregroundStyle(Theme.Colors.accentSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.accentSecondary.opacity(0.1))
                    )
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    SummaryPill(title: "Sessions", value: sessions) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .sessions, scrollTarget: nil)
                    }
                    SummaryPill(title: "Avg Duration", value: avgDuration) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .avgDuration, scrollTarget: nil)
                    }
                    SummaryPill(title: "Volume", value: volumeText) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .totalVolume, scrollTarget: nil)
                    }
                }

                VStack(spacing: Theme.Spacing.sm) {
                    SummaryPill(title: "Sessions", value: sessions) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .sessions, scrollTarget: nil)
                    }
                    SummaryPill(title: "Avg Duration", value: avgDuration) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .avgDuration, scrollTarget: nil)
                    }
                    SummaryPill(title: "Volume", value: volumeText) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .totalVolume, scrollTarget: nil)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
        .animateOnAppear(delay: 0.15)
    }

    // MARK: - Change Metrics (always visible — key differentiator)

    private var changeSection: some View {
        let metrics = weeklyChangeMetrics
        return Group {
            if !metrics.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Text("vs Last Week")
                            .font(Theme.Typography.sectionHeader)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .tracking(1.0)
                        Spacer()
                        NavigationLink {
                            PerformanceLabView(dataManager: dataManager)
                        } label: {
                            Text("More")
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(Theme.Colors.accent)
                                .textCase(.uppercase)
                                .tracking(0.8)
                        }
                        .buttonStyle(.plain)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(metrics) { metric in
                                MetricTileButton(
                                    action: { selectedChangeMetric = metric },
                                    content: { CompactChangeCard(metric: metric) }
                                )
                            }
                        }

                        VStack(spacing: Theme.Spacing.sm) {
                            ForEach(metrics) { metric in
                                MetricTileButton(
                                    action: { selectedChangeMetric = metric },
                                    content: { CompactChangeCard(metric: metric) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent Workouts

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Workouts")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .tracking(1.0)
                Spacer()
                NavigationLink(destination: WorkoutHistoryView(workouts: dataManager.workouts, showsBackButton: true)) {
                    HStack(spacing: 4) {
                        Text("See All")
                            .font(Theme.Typography.captionBold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(Theme.Colors.accent)
                }
            }

            VStack(spacing: Theme.Spacing.md) {
                ForEach(Array(dataManager.workouts.prefix(3).enumerated()), id: \.element.id) { index, workout in
                    HomeWorkoutRow(
                        workout: workout,
                        onRepeat: { repeatWorkout(workout) },
                        onTap: { selectedWorkout = workout }
                    )
                    .staggeredAppear(index: index, baseDelay: 0.2)
                }
            }
        }
    }

    // MARK: - Explore

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Explore")
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.md), GridItem(.flexible(), spacing: Theme.Spacing.md)], spacing: Theme.Spacing.md) {
                NavigationLink {
                    PerformanceLabView(dataManager: dataManager)
                } label: {
                    ExploreRow(title: "Performance", subtitle: "Trends", icon: "chart.line.uptrend.xyaxis", tint: Theme.Colors.success)
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    ExerciseListView(dataManager: dataManager)
                } label: {
                    ExploreRow(title: "Exercises", subtitle: "By lift", icon: "figure.strengthtraining.traditional", tint: Theme.Colors.accentSecondary)
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    CorrelationDetailView(engine: correlationEngine)
                } label: {
                    ExploreRow(title: "Correlations", subtitle: "Health data", icon: "waveform.path.ecg", tint: Theme.Colors.accentTertiary)
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    WorkoutHistoryView(workouts: dataManager.workouts, showsBackButton: true)
                } label: {
                    ExploreRow(title: "History", subtitle: "Past sessions", icon: "clock.fill", tint: Theme.Colors.accent)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Data Helpers

    private var headerSubtitle: String {
        if let lastWorkout = dataManager.workouts.first {
            return "Last workout \(lastWorkout.date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "No workouts yet."
    }

    private var syncStatusText: String {
        if healthManager.isAutoSyncing { return "syncing" }
        switch healthManager.authorizationStatus {
        case .authorized:
            if let lastSync = healthManager.lastSyncDate {
                return "sync \(lastSync.formatted(.relative(presentation: .named)))"
            }
            return "sync ready"
        case .notDetermined: return "health off"
        case .denied: return "health denied"
        case .unavailable: return "health n/a"
        }
    }

    private var isHealthFresh: Bool {
        guard let lastSync = healthManager.lastSyncDate else { return false }
        return abs(lastSync.timeIntervalSinceNow) < 3600 * 6
    }

    private var weeklyWorkouts: [Workout] {
        guard !dataManager.workouts.isEmpty else { return [] }
        let now = Date()
        let weekStart = SharedFormatters.startOfWeekSunday(for: now)
        return dataManager.workouts.filter { $0.date >= weekStart && $0.date <= now }
    }

    private var weeklyDateRange: DateInterval {
        let now = Date()
        let weekStart = SharedFormatters.startOfWeekSunday(for: now)
        return DateInterval(start: weekStart, end: now)
    }

    private var changeWindow: ChangeMetricWindow {
        let calendar = Calendar.current
        let current = weeklyDateRange
        let previousStart = calendar.date(byAdding: .day, value: -7, to: current.start) ?? current.start
        let previousEnd = calendar.date(byAdding: .day, value: -7, to: current.end) ?? current.end
        return ChangeMetricWindow(
            label: "This week",
            current: current,
            previous: DateInterval(start: previousStart, end: previousEnd)
        )
    }

    private var weeklyChangeMetrics: [ChangeMetric] {
        let all = WorkoutAnalytics.changeMetrics(for: dataManager.workouts, window: changeWindow)
        let preferred = all.filter {
            $0.title.contains("Sessions") || $0.title.contains("Volume") || $0.title.contains("Duration")
        }
        return Array((preferred.isEmpty ? all : preferred).prefix(3))
    }

    private var homeHighlights: [HighlightItem] {
        var items: [HighlightItem] = []

        let allowedTypes: Set<InsightType> = [.personalRecord, .strengthGain, .baseline]
        let filteredInsights = insightsEngine.insights.filter { allowedTypes.contains($0.type) }

        for insight in filteredInsights.prefix(3) {
            let highlightValue = SharedFormatters.sanitizedHighlightValue(from: insight.message)
            items.append(
                HighlightItem(
                    title: insight.title,
                    value: highlightValue,
                    subtitle: insight.date.formatted(date: .abbreviated, time: .omitted),
                    icon: insight.type.iconName,
                    tint: SharedFormatters.highlightTint(for: insight.type),
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

    private var muscleSuggestions: [MuscleGroupSuggestion] {
        let workouts = dataManager.workouts
        guard !workouts.isEmpty else { return [] }

        let exerciseNames = Set(workouts.flatMap { $0.exercises.map(\.name) })
        let tagMappings = ExerciseMetadataManager.shared.resolvedMappings(for: exerciseNames)
        let groupMappings: [String: [MuscleGroup]] = tagMappings.mapValues { tags in
            tags.compactMap { $0.builtInGroup }
        }

        return MuscleRecencySuggestionEngine.suggestions(
            workouts: workouts,
            muscleGroupsByExerciseName: groupMappings
        )
    }

    private var bestPerformanceTimeBucket: TimeOfDayBucket? {
        // Only consider buckets with enough sessions to be statistically
        // meaningful, then rank by Bayesian confidence score.
        let qualifying = correlationEngine.timeOfDayAnalysis.filter { $0.meetsMinimum }
        return qualifying.max(by: { $0.confidenceScore < $1.confidenceScore })
    }

    private var sleepCorrelation: PerformanceCorrelation? {
        correlationEngine.correlations.first { $0.healthMetric == .sleep }
    }

    // MARK: - Actions

    private func startQuickSession(exercise: String?) {
        quickStartExercise = exercise
        showingQuickStart = true
    }

    private func repeatWorkout(_ workout: Workout) {
        let exercises = workout.exercises.map { $0.name }
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId

        sessionManager.startSession(
            name: workout.name,
            gymProfileId: gymId
        )

        // Add all exercises from the repeated workout with auto-prefilled weights
        let increment = weightIncrement > 0 ? weightIncrement : 2.5
        for exerciseName in exercises {
            let tags = ExerciseMetadataManager.shared.resolvedTags(for: exerciseName)
            let isCardio = tags.contains(where: { $0.builtInGroup == .cardio })

            if isCardio {
                sessionManager.addExercise(name: exerciseName)
            } else {
                let history = dataManager.getExerciseHistory(for: exerciseName)
                let rec = ExerciseRecommendationEngine.recommend(
                    exerciseName: exerciseName,
                    history: history,
                    weightIncrement: increment
                )
                let midReps = (rec.repRange.lowerBound + rec.repRange.upperBound) / 2
                sessionManager.addExercise(
                    name: exerciseName,
                    initialSetPrefill: SetPrefill(weight: rec.suggestedWeight, reps: midReps)
                )
            }
        }

        sessionManager.isPresentingSessionUI = true
        Haptics.notify(.success)
    }

    private func triggerAutoHealthSync() {
        guard healthManager.authorizationStatus == .authorized else { return }
        Task {
            await healthManager.syncRecentWorkoutsIfNeeded(dataManager.workouts)
        }
    }

    private func runCorrelationAnalysis() async {
        let exerciseNames = Set(dataManager.workouts.flatMap { $0.exercises.map(\.name) })
        let tagMappings = ExerciseMetadataManager.shared.resolvedMappings(for: exerciseNames)
        await correlationEngine.analyze(
            workouts: dataManager.workouts,
            healthStore: healthManager.healthDataStore,
            dailyHealth: healthManager.dailyHealthStore,
            muscleMappings: tagMappings
        )
    }
}

private struct HomeEmptyState: View {
    let onStart: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.accent.opacity(0.08))
                        .frame(width: 80, height: 80)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(Theme.Colors.accent)
                }

                Text("You're Ready.")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .tracking(0.8)

                Text("Start a session or import your history.\nWe'll keep it simple from there.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            VStack(spacing: Theme.Spacing.md) {
                Button(
                    action: {
                        Haptics.selection()
                        onStart()
                    },
                    label: {
                        Text("Start a Session")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.lg)
                            .frame(minHeight: 56)
                            .background(Theme.accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge))
                            .shadow(color: Theme.Colors.accent.opacity(0.25), radius: 12, x: 0, y: 6)
                    }
                )
                .buttonStyle(.plain)

                Button(
                    action: {
                        Haptics.selection()
                        onImport()
                    },
                    label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 13, weight: .bold))
                            Text("Import from Strong")
                                .font(Theme.Typography.bodyBold)
                        }
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .frame(minHeight: 48)
                        .softCard(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
                    }
                )
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 2)
    }
}

// MARK: - Sync Status Pill

private struct SyncStatusPill: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Theme.Colors.success : Theme.Colors.textTertiary.opacity(0.5))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.metricLabel)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(isActive ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Theme.Colors.surfaceRaised)
        )
        .overlay(
            Capsule()
                .strokeBorder(Theme.Colors.border.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync status: \(text)")
    }
}

// MARK: - Compact Change Card (always-visible period-over-period delta)

private struct CompactChangeCard: View {
    let metric: ChangeMetric

    private var tint: Color {
        metric.isPositive ? Theme.Colors.success : Theme.Colors.warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 5) {
                Image(systemName: metric.isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(tint)
                Text(metric.title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }

            Text(formatValue(metric))
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)

            if metric.percentChange != 0 {
                Text(String(format: "%+.0f%%", metric.percentChange))
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(tint.opacity(0.1))
                    )
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title): \(formatValue(metric)), \(metric.isPositive ? "increased" : "decreased")")
    }

    private func formatValue(_ metric: ChangeMetric) -> String {
        if metric.title.contains("Sessions") {
            return String(format: "%.0f", metric.current)
        }
        if metric.title.contains("Duration") {
            return SharedFormatters.durationMinutes(metric.current)
        }
        if metric.title.contains("Volume") {
            return SharedFormatters.volumePrecise(metric.current)
        }
        return String(format: "%.1f", metric.current)
    }
}

// MARK: - Home Workout Row (with repeat button)

private struct HomeWorkoutRow: View {
    let workout: Workout
    let onRepeat: () -> Void
    let onTap: () -> Void
    @EnvironmentObject var healthManager: HealthKitManager

    var body: some View {
        Button(action: { onTap() }, label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .center) {
                        Text(workout.name)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Spacer()

                        Button {
                            Haptics.selection()
                            onRepeat()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.Colors.accent)
                                .frame(width: 28, height: 28)
                                .background(Theme.Colors.accent.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Repeat \(workout.name)")
                    }

                    Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)

                    HStack(spacing: Theme.Spacing.md) {
                        Label(workout.duration, systemImage: "clock")
                        Label("\(workout.exercises.count) exercises", systemImage: "figure.strengthtraining.traditional")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                    if let data = healthManager.getHealthData(for: workout.id) {
                        HealthDataSummaryView(healthData: data)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
        })
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workout.name), \(workout.date.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityHint("Double tap for details, or use the repeat button")
    }
}

// MARK: - Reusable Components

private struct SecondaryChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(
            action: {
                Haptics.selection()
                action()
            },
            label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                    Text(title)
                        .font(Theme.Typography.captionBold)
                        .textCase(.uppercase)
                        .tracking(0.6)
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .frame(minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .fill(Theme.Colors.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .strokeBorder(Theme.Colors.border.opacity(0.4), lineWidth: 1)
                )
            }
        )
        .buttonStyle(.plain)
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String
    var onTap: (() -> Void)?

    var body: some View {
        Group {
            if let onTap {
                MetricTileButton(action: onTap, content: { content })
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)

            Text(value)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(Theme.Colors.border.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }
}

private struct ExploreRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(tint.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}
