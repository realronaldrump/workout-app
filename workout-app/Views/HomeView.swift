import Combine
import SwiftUI

struct HomeView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    let annotationsManager: WorkoutAnnotationsManager
    let gymProfilesManager: GymProfilesManager
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var insightsEngine: InsightsEngine
    @EnvironmentObject var intentionalBreaksManager: IntentionalBreaksManager
    @EnvironmentObject var sessionManager: WorkoutSessionManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @Binding var selectedTab: AppTab

    @StateObject private var recoveryCoverageEngine = RecoveryCoverageEngine()
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
    @State private var showingMuscleRecency = false
    @State private var showingConsistencyDetail = false
    @State private var showRepeatWorkoutId: UUID?
    @State private var cachedWeeklyStats: WorkoutStats?
    @State private var cachedOverallStats: WorkoutStats?
    @State private var cachedWeeklyChangeMetrics: [ChangeMetric] = []
    @State private var cachedMuscleSuggestions: [MuscleGroupSuggestion] = []
    @State private var cachedHomeHighlights: [HighlightItem] = []
    @State private var derivedStateTask: Task<Void, Never>?
    @State private var recoveryCoverageTask: Task<Void, Never>?
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
                        // Pre-workout briefing with recovery signals and muscle recency cues.
                        PreWorkoutBriefingCard(
                            recoverySignals: recoveryCoverageEngine.recoverySignals,
                            muscleSuggestions: cachedMuscleSuggestions,
                            onStartSession: { groupName in
                                startQuickSession(exercise: groupName)
                            },
                            onExerciseTap: { name in
                                selectedExercise = ExerciseSelection(id: name)
                            },
                            onViewAllMuscleRecency: {
                                showingMuscleRecency = true
                            }
                        )
                        .padding(.horizontal, Theme.Spacing.lg)

                        weeklySummarySection
                            .padding(.horizontal, Theme.Spacing.lg)

                        consistencySection
                            .padding(.horizontal, Theme.Spacing.lg)

                        // Change metrics — always visible (not collapsed)
                        changeSection
                            .padding(.horizontal, Theme.Spacing.lg)

                        // Highlights — always visible (not collapsed)
                        if !cachedHomeHighlights.isEmpty {
                            HighlightsSectionView(title: "Highlights", items: cachedHomeHighlights)
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        // Data Insights (frequency snapshots)
                        DataInsightCards(
                            frequencyInsightsProvider: { window in
                                recoveryCoverageEngine.frequencyInsights(for: window)
                            },
                            hasHistoricalFrequencyData: recoveryCoverageEngine.hasHistoricalFrequencyData
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
        .navigationDestination(isPresented: $showingConsistencyDetail) {
            ConsistencyDetailView(workouts: dataManager.workouts)
        }
        .navigationDestination(isPresented: $showingMuscleBalance) {
            MuscleBalanceDetailView(
                dataManager: dataManager,
                dateRange: weeklyDateRange,
                rangeLabel: "This Week"
            )
        }
        .navigationDestination(isPresented: $showingMuscleRecency) {
            MuscleRecencyView(dataManager: dataManager)
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
            refreshHomeDerivedState()
            rebuildHomeHighlights()
            healthManager.refreshAuthorizationStatus()
            if dataManager.workouts.isEmpty {
                Task {
                    await dataManager.loadLatestWorkoutData(
                        iCloudManager: iCloudManager,
                        healthDataSnapshot: Array(healthManager.healthDataStore.values)
                    )
                    await insightsEngine.generateInsights()
                    rebuildHomeHighlights()
                    await refreshRecoveryCoverage()
                }
            } else {
                triggerAutoHealthSync()
                scheduleRecoveryCoverageRefresh()
            }
        }
        .refreshable {
            await dataManager.loadLatestWorkoutData(
                iCloudManager: iCloudManager,
                healthDataSnapshot: Array(healthManager.healthDataStore.values)
            )
            await insightsEngine.generateInsights()
            rebuildHomeHighlights()
            await refreshRecoveryCoverage()
        }
        .onChange(of: dataManager.workouts) { _, _ in
            scheduleHomeDerivedStateRefresh()
            triggerAutoHealthSync()
            scheduleRecoveryCoverageRefresh()
        }
        .onChange(of: intentionalBreaksManager.savedBreaks) { _, _ in
            scheduleHomeDerivedStateRefresh()
            scheduleRecoveryCoverageRefresh()
        }
        .onReceive(metadataManager.objectWillChange) { _ in
            scheduleHomeDerivedStateRefresh()
        }
        .onReceive(insightsEngine.$insights) { _ in
            rebuildHomeHighlights()
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
                    Text("Today")
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
                            .font(Theme.Typography.title4Bold)
                        Text("Start a Session")
                            .font(Theme.Typography.headline)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(Theme.Typography.subheadlineBold)
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
                                .font(Theme.Typography.footnoteBold)
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
                                .font(Theme.Typography.caption2Bold)
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
        let sessions = cachedWeeklyStats.map { "\($0.totalWorkouts)" } ?? "0"
        let volumeText = cachedWeeklyStats.map { SharedFormatters.volumeCompact($0.totalVolume) } ?? "--"
        let streak = cachedOverallStats?.currentStreak ?? 0

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
                            .font(Theme.Typography.caption2Bold)
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
                    SummaryPill(title: "Volume", value: volumeText) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .totalVolume, scrollTarget: nil)
                    }
                }

                VStack(spacing: Theme.Spacing.sm) {
                    SummaryPill(title: "Sessions", value: sessions) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .sessions, scrollTarget: nil)
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

    private var consistencySection: some View {
        return ConsistencyView(
            stats: cachedOverallStats ?? emptyStats,
            workouts: dataManager.workouts,
            timeRange: .allTime,
            onTap: {
                showingConsistencyDetail = true
            }
        )
        .animateOnAppear(delay: 0.2)
    }

    // MARK: - Change Metrics (always visible — key differentiator)

    private var changeSection: some View {
        let metrics = cachedWeeklyChangeMetrics
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
                            .font(Theme.Typography.microLabel)
                    }
                    .foregroundColor(Theme.Colors.accent)
                }
            }

            VStack(spacing: Theme.Spacing.md) {
                ForEach(Array(dataManager.workouts.prefix(3).enumerated()), id: \.element.id) { _, workout in
                    HomeWorkoutRow(
                        workout: workout,
                        onRepeat: { repeatWorkout(workout) },
                        onTap: { selectedWorkout = workout }
                    )
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

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.md),
                    GridItem(.flexible(), spacing: Theme.Spacing.md)
                ],
                spacing: Theme.Spacing.md
            ) {
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
                    RecoveryCoverageDetailView(engine: recoveryCoverageEngine)
                } label: {
                    ExploreRow(title: "Signals", subtitle: "Recovery + coverage", icon: "waveform.path.ecg", tint: Theme.Colors.accentTertiary)
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    WorkoutHistoryView(workouts: dataManager.workouts, showsBackButton: true)
                } label: {
                    ExploreRow(title: "History", subtitle: "Past sessions", icon: "clock.fill", tint: Theme.Colors.accent)
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    MuscleRecencyView(dataManager: dataManager)
                } label: {
                    ExploreRow(
                        title: "Muscles",
                        subtitle: "Last worked",
                        icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        tint: Theme.Colors.accentSecondary
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    WorkoutVariantReviewView()
                } label: {
                    ExploreRow(
                        title: "Variants",
                        subtitle: "What changed",
                        icon: "square.3.layers.3d",
                        tint: Theme.Colors.accent
                    )
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

    private func buildHomeHighlights() -> [HighlightItem] {
        var items: [HighlightItem] = []

        let allowedTypes: Set<InsightType> = [.personalRecord, .strengthGain, .baseline]
        let filteredInsights = insightsEngine.insights.filter { allowedTypes.contains($0.type) }

        for insight in filteredInsights.prefix(3) {
            let highlightValue = SharedFormatters.sanitizedHighlightValue(from: insight.message)
            items.append(
                HighlightItem(
                    id: "\(insight.title)-\(insight.exerciseName ?? "none")-\(Int(insight.date.timeIntervalSince1970))",
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

    private var emptyStats: WorkoutStats {
        WorkoutStats(
            totalWorkouts: 0,
            totalExercises: 0,
            totalVolume: 0,
            totalSets: 0,
            favoriteExercise: nil,
            strongestExercise: nil,
            mostImprovedExercise: nil,
            currentStreak: 0,
            longestStreak: 0,
            workoutsPerWeek: 0,
            lastWorkoutDate: nil
        )
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

    private func refreshHomeDerivedState() {
        let workouts = dataManager.workouts
        let breaks = intentionalBreaksManager.savedBreaks
        let weekly = weeklyWorkouts

        cachedWeeklyStats = weekly.isEmpty
            ? nil
            : dataManager.calculateStats(for: weekly, intentionalBreakRanges: breaks)
        cachedOverallStats = workouts.isEmpty
            ? nil
            : dataManager.calculateStats(for: workouts, intentionalBreakRanges: breaks)

        let allMetrics = WorkoutAnalytics.changeMetrics(for: workouts, window: changeWindow)
        let preferredMetrics = allMetrics.filter {
            $0.title.contains("Sessions") || $0.title.contains("Volume")
        }
        cachedWeeklyChangeMetrics = Array((preferredMetrics.isEmpty ? allMetrics : preferredMetrics).prefix(3))

        guard !workouts.isEmpty else {
            cachedMuscleSuggestions = []
            return
        }

        let exerciseNames = Set(dataManager.allExerciseNames())
        let tagMappings = metadataManager.resolvedMappings(for: exerciseNames)
        let groupMappings: [String: [MuscleGroup]] = tagMappings.mapValues { tags in
            tags.compactMap(\.builtInGroup)
        }
        cachedMuscleSuggestions = MuscleRecencySuggestionEngine.suggestions(
            workouts: workouts,
            muscleGroupsByExerciseName: groupMappings
        )
    }

    private func scheduleHomeDerivedStateRefresh(debounceNs: UInt64 = 150_000_000) {
        derivedStateTask?.cancel()
        derivedStateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            refreshHomeDerivedState()
        }
    }

    private func refreshRecoveryCoverage() async {
        let exerciseNames = Set(dataManager.workouts.flatMap { $0.exercises.map(\.name) })
        let tagMappings = ExerciseMetadataManager.shared.resolvedMappings(for: exerciseNames)
        await recoveryCoverageEngine.analyze(
            workouts: dataManager.workouts,
            healthStore: healthManager.healthDataStore,
            dailyHealth: healthManager.dailyHealthStore,
            muscleMappings: tagMappings,
            intentionalBreakRanges: intentionalBreaksManager.savedBreaks
        )
    }

    private func scheduleRecoveryCoverageRefresh(debounceNs: UInt64 = 250_000_000) {
        recoveryCoverageTask?.cancel()
        recoveryCoverageTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await refreshRecoveryCoverage()
        }
    }

    private func rebuildHomeHighlights() {
        cachedHomeHighlights = buildHomeHighlights()
    }
}
