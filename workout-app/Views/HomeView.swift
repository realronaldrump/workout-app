import Combine
import SwiftUI
// swiftlint:disable type_body_length file_length

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
    @State private var cachedWeekBuckets: [HomeWeekBucket] = []
    @State private var cachedOverallStats: WorkoutStats?
    @State private var cachedWeeklyChangeMetrics: [ChangeMetric] = []
    @State private var cachedMuscleSuggestions: [MuscleGroupSuggestion] = []
    @State private var cachedHomeHighlights: [HighlightItem] = []
    @State private var selectedWeekBucketStart: Date?
    @State private var derivedStateTask: Task<Void, Never>?
    @State private var recoveryCoverageTask: Task<Void, Never>?
    @State private var showingTagging = false
    @AppStorage("dismissedUntaggedCount") private var dismissedUntaggedCount: Int = -1
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
                                    healthIdentitySnapshot: healthManager.healthDataStore.values.map {
                                        WorkoutHealthIdentitySnapshot(
                                            workoutId: $0.workoutId,
                                            workoutDate: $0.workoutDate
                                        )
                                    }
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

                        if shouldShowUntaggedBanner {
                            untaggedExercisesBanner
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

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
                workouts: selectedWeekBucket?.workouts ?? weeklyWorkouts,
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
        .navigationDestination(isPresented: $showingTagging) {
            ExerciseTaggingView(dataManager: dataManager)
        }
        .sheet(isPresented: $showingImportWizard) {
            StrongImportWizard(
                isPresented: $showingImportWizard,
                dataManager: dataManager,
                iCloudManager: iCloudManager
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
                        healthIdentitySnapshot: healthManager.healthDataStore.values.map {
                            WorkoutHealthIdentitySnapshot(
                                workoutId: $0.workoutId,
                                workoutDate: $0.workoutDate
                            )
                        }
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
                healthIdentitySnapshot: healthManager.healthDataStore.values.map {
                    WorkoutHealthIdentitySnapshot(
                        workoutId: $0.workoutId,
                        workoutDate: $0.workoutDate
                    )
                }
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

    // MARK: - Untagged Exercises Banner

    private var untaggedExerciseNames: [String] {
        let allNames = Set(dataManager.workouts.flatMap { $0.exercises.map(\.name) })
        return allNames.filter { metadataManager.resolvedTags(for: $0).isEmpty }.sorted()
    }

    private var shouldShowUntaggedBanner: Bool {
        let count = untaggedExerciseNames.count
        return count > 0 && count != dismissedUntaggedCount
    }

    private var untaggedExercisesBanner: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "tag")
                .font(Theme.Typography.footnoteBold)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 32, height: 32)
                .background(Theme.Colors.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(untaggedExerciseNames.count) exercise\(untaggedExerciseNames.count == 1 ? "" : "s") without tags")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Tag them for muscle tracking")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()

            Button {
                Haptics.selection()
                showingTagging = true
            } label: {
                Text("Tag")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(Theme.Animation.spring) {
                    dismissedUntaggedCount = untaggedExerciseNames.count
                }
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.Typography.caption2Bold)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .glassBackground(opacity: 0.1, cornerRadius: Theme.CornerRadius.large, elevation: 1)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
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
            .accessibilityLabel("Start a Session")
            .accessibilityHint("Begin a new workout session")
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
                        .glassBackground(opacity: 0.1, cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
                    }
                )
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.lg)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Repeat last workout: \(lastWorkout.name)")
                .accessibilityHint("Double tap to start this workout again")
                .animateOnAppear(delay: 0.1)
            }

            // Secondary chips
            HStack(spacing: Theme.Spacing.md) {
                SecondaryChip(title: "Import", icon: "arrow.down.to.line") {
                    showingImportWizard = true
                }
                SecondaryChip(title: "Health", icon: "heart.fill") {
                    selectedTab = .health
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .animateOnAppear(delay: 0.15)
        }
    }

    // MARK: - Weekly Summary

    private var weeklySummarySection: some View {
        let streak = cachedOverallStats?.currentStreak ?? 0
        let buckets = cachedWeekBuckets
        let selectedBucket = selectedWeekBucket ?? buckets.first

        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week View")
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

            if let selectedBucket {
                TabView(selection: selectedWeekSelection) {
                    ForEach(buckets) { bucket in
                        WeeklySummaryCarouselCard(
                            bucket: bucket,
                            onMetricTap: { kind in
                                selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: kind, scrollTarget: nil)
                            },
                            onWorkoutTap: { workout in
                                selectedWorkout = workout
                            }
                        )
                        .tag(Optional(bucket.weekStart))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: weeklySummaryCardHeight(for: selectedBucket))
                .animation(Theme.Animation.gentleSpring, value: selectedWeekBucketStart)

                if buckets.count > 1 {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(visibleWeekIndicatorBuckets(from: buckets)) { bucket in
                            Capsule()
                                .fill(isSelectedWeekBucket(bucket) ? Theme.Colors.accent : Theme.Colors.border.opacity(0.5))
                                .frame(width: isSelectedWeekBucket(bucket) ? 20 : 8, height: 8)
                                .animation(Theme.Animation.spring, value: selectedWeekBucketStart)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(opacity: 0.1, cornerRadius: Theme.CornerRadius.large, elevation: 2)
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

    private var selectedWeekBucket: HomeWeekBucket? {
        if let selectedWeekBucketStart {
            return cachedWeekBuckets.first { Calendar.current.isDate($0.weekStart, inSameDayAs: selectedWeekBucketStart) }
        }
        return cachedWeekBuckets.first
    }

    private var selectedWeekSelection: Binding<Date?> {
        Binding(
            get: { selectedWeekBucketStart ?? cachedWeekBuckets.first?.weekStart },
            set: { selectedWeekBucketStart = $0 }
        )
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
        let weekBuckets = buildWeekBuckets(workouts: workouts, intentionalBreakRanges: breaks)

        cachedWeekBuckets = weekBuckets
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
        syncSelectedWeekBucket()
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

    private func buildWeekBuckets(
        workouts: [Workout],
        intentionalBreakRanges: [IntentionalBreakRange]
    ) -> [HomeWeekBucket] {
        let now = Date()
        let calendar = Calendar.current
        let currentWeekStart = SharedFormatters.startOfWeekSunday(for: now)
        let boundsEnd = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: workouts) { workout in
            SharedFormatters.startOfWeekSunday(for: workout.date)
        }
        let workoutDays = IntentionalBreaksAnalytics.normalizedWorkoutDays(for: workouts, calendar: calendar)

        guard let earliestWorkout = workouts.last else {
            return [
                HomeWeekBucket(
                    weekStart: currentWeekStart,
                    referenceDate: now,
                    workouts: [],
                    stats: emptyStats,
                    trackedDayCount: max((calendar.dateComponents([.day], from: currentWeekStart, to: boundsEnd).day ?? 0) + 1, 0),
                    excludedDayCount: 0
                )
            ]
        }

        let boundsStart = calendar.startOfDay(for: earliestWorkout.date)
        let breakDays = IntentionalBreaksAnalytics.breakDaySet(
            from: intentionalBreakRanges,
            excluding: workoutDays,
            within: boundsStart...boundsEnd,
            calendar: calendar
        )
        let earliestWeekStart = SharedFormatters.startOfWeekSunday(for: earliestWorkout.date)
        var buckets: [HomeWeekBucket] = []
        var cursor = currentWeekStart

        while cursor >= earliestWeekStart {
            let weekWorkouts = (grouped[cursor] ?? []).sorted { $0.date > $1.date }
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: cursor) ?? cursor
            let trackedStart = max(cursor, boundsStart)
            let trackedEnd = min(weekEnd, boundsEnd)
            let trackedDays = trackedStart <= trackedEnd
                ? max((calendar.dateComponents([.day], from: trackedStart, to: trackedEnd).day ?? 0) + 1, 0)
                : 0
            let excludedDays = trackedStart <= trackedEnd
                ? IntentionalBreaksAnalytics.dayCount(
                    from: trackedStart,
                    to: trackedEnd,
                    breakDays: breakDays,
                    includeStart: true,
                    includeEnd: true,
                    calendar: calendar
                )
                : 0
            let eligibleDays = max(trackedDays - excludedDays, 0)
            let shouldInclude = cursor == currentWeekStart || !weekWorkouts.isEmpty || eligibleDays == 0

            guard shouldInclude else {
                guard let previousWeek = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
                cursor = previousWeek
                continue
            }

            let stats = weekWorkouts.isEmpty
                ? emptyStats
                : dataManager.calculateStats(for: weekWorkouts, intentionalBreakRanges: intentionalBreakRanges)
            buckets.append(
                HomeWeekBucket(
                    weekStart: cursor,
                    referenceDate: now,
                    workouts: weekWorkouts,
                    stats: stats,
                    trackedDayCount: trackedDays,
                    excludedDayCount: excludedDays
                )
            )

            guard let previousWeek = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
            cursor = previousWeek
        }

        return buckets
    }

    private func syncSelectedWeekBucket() {
        guard !cachedWeekBuckets.isEmpty else {
            selectedWeekBucketStart = nil
            return
        }

        if let selectedWeekBucketStart,
           cachedWeekBuckets.contains(where: { Calendar.current.isDate($0.weekStart, inSameDayAs: selectedWeekBucketStart) }) {
            return
        }

        selectedWeekBucketStart = cachedWeekBuckets.first?.weekStart
    }

    private func isSelectedWeekBucket(_ bucket: HomeWeekBucket) -> Bool {
        guard let selectedWeekBucketStart else {
            return Calendar.current.isDate(bucket.weekStart, inSameDayAs: cachedWeekBuckets.first?.weekStart ?? bucket.weekStart)
        }
        return Calendar.current.isDate(bucket.weekStart, inSameDayAs: selectedWeekBucketStart)
    }

    private func weeklySummaryCardHeight(for bucket: HomeWeekBucket) -> CGFloat {
        let visibleSessionCount = min(bucket.workouts.count, 3)
        let baseHeight: CGFloat = bucket.workouts.isEmpty ? 188 : 188 + (CGFloat(visibleSessionCount) * 76)
        return min(baseHeight, 416)
    }

    private func visibleWeekIndicatorBuckets(from buckets: [HomeWeekBucket]) -> [HomeWeekBucket] {
        let maxVisibleIndicators = 7
        guard buckets.count > maxVisibleIndicators else {
            return buckets
        }

        let selectedIndex = buckets.firstIndex(where: { isSelectedWeekBucket($0) }) ?? 0
        let halfWindow = maxVisibleIndicators / 2
        let lowerBound = max(0, min(selectedIndex - halfWindow, buckets.count - maxVisibleIndicators))
        let upperBound = min(lowerBound + maxVisibleIndicators, buckets.count)

        return Array(buckets[lowerBound..<upperBound])
    }
}

// swiftlint:enable type_body_length file_length
