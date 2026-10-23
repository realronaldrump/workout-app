import Combine
import SwiftUI
// swiftlint:disable type_body_length file_length

struct HomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    let annotationsManager: WorkoutAnnotationsManager
    let gymProfilesManager: GymProfilesManager
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var insightsEngine: InsightsEngine
    @EnvironmentObject var intentionalBreaksManager: IntentionalBreaksManager
    @EnvironmentObject var sessionManager: WorkoutSessionManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var relationshipManager = ExerciseRelationshipManager.shared
    @Binding var selectedTab: AppTab

    @StateObject private var recoveryCoverageEngine = RecoveryCoverageEngine()
    @AppStorage("weightIncrement") private var weightIncrement: Double = 2.5
    @AppStorage("sessionsPerWeekGoal") private var sessionsPerWeekGoal: Int = 4
    @AppStorage("profileName") private var profileName = ""

    @State private var showingImportWizard = false
    @State private var showingQuickStart = false
    @State private var quickStartExercise: String?
    @State private var selectedExercise: ExerciseSelection?
    @State private var selectedWorkout: Workout?
    @State private var selectedWorkoutMetric: WorkoutMetricDetailSelection?
    @State private var showingMuscleBalance = false
    @State private var showingMuscleRecency = false
    @State private var showingConsistencyDetail = false
    @State private var pendingRepeatWorkout: Workout?
    @State private var cachedWeekBuckets: [HomeWeekBucket] = []
    @State private var cachedExerciseCounts: [UUID: Int] = [:]
    @State private var cachedCurrentWeekStreak = 0
    @State private var cachedMuscleSuggestions: [MuscleGroupSuggestion] = []
    @State private var cachedUntaggedExerciseNames: [String] = []
    @State private var cachedHomeHighlights: [HighlightItem] = []
    @State private var cachedPlateCategories: [UUID: PlateCategory] = [:]
    @State private var cachedRackWeeks: [RackWeek] = []
    @State private var hasDerivedLoadedHistory = false
    @State private var selectedWeekBucketStart: Date?
    @State private var derivedStateTask: Task<Void, Never>?
    @State private var recoveryCoverageTask: Task<Void, Never>?
    @State private var homeDerivedCacheKey: Int?
    @State private var hasScheduledInitialWorkoutRefresh = false
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
                VStack(alignment: .leading, spacing: 0) {
                    if isAwaitingInitialHistory || (dataManager.isLoading && dataManager.workouts.isEmpty) {
                        TodayLoadingHero(weeklyGoal: min(max(sessionsPerWeekGoal, 1), 14))
                    } else if let error = dataManager.error, dataManager.workouts.isEmpty {
                        ErrorCard(message: error) {
                            Task {
                                await dataManager.loadLatestWorkoutData(
                                    iCloudManager: iCloudManager,
                                    healthIdentitySnapshot: healthIdentitySnapshot
                                )
                            }
                        }
                    } else if dataManager.workouts.isEmpty {
                        emptySection
                    } else {
                        heroSection

                        if shouldShowUntaggedBanner {
                            untaggedExercisesBanner
                                .padding(.top, Theme.Spacing.section)
                        }

                        // Recovery signals and the muscle groups that are due.
                        PreWorkoutBriefingCard(
                            recoverySignals: recoveryCoverageEngine.recoverySignals,
                            muscleSuggestions: cachedMuscleSuggestions,
                            onStartSession: { exerciseName in
                                startQuickSession(exercise: exerciseName)
                            },
                            onExerciseTap: { name in
                                selectedExercise = ExerciseSelection(id: name)
                            },
                            onViewAllMuscleRecency: {
                                showingMuscleRecency = true
                            }
                        )
                        .padding(.top, Theme.Spacing.section)

                        weekSection
                            .padding(.top, Theme.Spacing.section)

                        // Today surfaces one result worth noticing. Deeper analysis stays
                        // one tap away instead of turning the home screen into a report.
                        if !cachedHomeHighlights.isEmpty {
                            HighlightsSectionView(
                                title: "Latest result",
                                items: Array(cachedHomeHighlights.prefix(1))
                            )
                            .padding(.top, Theme.Spacing.section)
                        }

                        recentWorkoutsSection
                            .padding(.top, Theme.Spacing.section)

                        exploreSection
                            .padding(.top, Theme.Spacing.section)
                    }
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Today")
        .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            AppToolbarItem(placement: .topBarTrailing) {
                healthStatusButton
            }
        }
        .analyticsScreen("Home")
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
                workouts: selectedWeekBucket?.workouts ?? weeklyWorkouts
            )
        }
        .navigationDestination(isPresented: $showingConsistencyDetail) {
            ConsistencyDetailView(workouts: dataManager.workouts)
        }
        .navigationDestination(isPresented: $showingMuscleBalance) {
            MuscleBalanceDetailView(
                dataManager: dataManager,
                dateRange: weeklyDateRange,
                rangeLabel: "This week"
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
                iCloudManager: iCloudManager,
                source: "home"
            )
        }
        .sheet(isPresented: $showingQuickStart) {
            QuickStartView(exerciseName: quickStartExercise)
        }
        .alert(
            "Replace active session?",
            isPresented: repeatReplacementAlertBinding,
            presenting: pendingRepeatWorkout
        ) { workout in
            Button("Cancel", role: .cancel) {
                pendingRepeatWorkout = nil
            }
            Button("Replace", role: .destructive) {
                pendingRepeatWorkout = nil
                replaceActiveSessionAndRepeat(workout)
            }
        } message: { _ in
            Text("This will discard your current in-progress session and repeat the selected workout.")
        }
        .onAppear {
            refreshHomeDerivedState()
            rebuildHomeHighlights()
            if !isAnalyticsUITestFixture {
                healthManager.refreshAuthorizationStatus()
            }
            if !dataManager.workouts.isEmpty {
                triggerAutoHealthSync()
                scheduleRecoveryCoverageRefresh()
            }
            scheduleInitialWorkoutRefreshIfNeeded()
        }
        .refreshable {
            await dataManager.loadLatestWorkoutData(
                iCloudManager: iCloudManager,
                healthIdentitySnapshot: healthIdentitySnapshot
            )
            await insightsEngine.generateInsights()
            rebuildHomeHighlights()
            await refreshRecoveryCoverage()
        }
        .onChange(of: dataManager.hasLoadedImportedHistory) { _, _ in
            scheduleHomeDerivedStateRefresh(debounceNs: 0)
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
        .onChange(of: relationshipManager.relationships) { _, _ in
            dataManager.refreshExerciseIdentityDerivedState()
            scheduleHomeDerivedStateRefresh()
            scheduleRecoveryCoverageRefresh()
        }
        .onReceive(insightsEngine.$insights) { _ in
            rebuildHomeHighlights()
        }
    }

    // MARK: - Header

    private var healthStatusButton: some View {
        Button {
            selectedTab = .health
        } label: {
            SyncStatusPill(
                text: syncStatusText,
                isActive: isHealthFresh,
                isSyncing: healthManager.isAutoSyncing
            )
            .padding(.horizontal, Theme.Spacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Health")
    }

    // MARK: - Untagged Exercises Banner

    private var untaggedExerciseNames: [String] {
        cachedUntaggedExerciseNames
    }

    private var shouldShowUntaggedBanner: Bool {
        let count = untaggedExerciseNames.count
        return count > 0 && count != dismissedUntaggedCount
    }

    private var healthIdentitySnapshot: [WorkoutHealthIdentitySnapshot] {
        healthManager.healthDataStore.values.map {
            WorkoutHealthIdentitySnapshot(
                workoutId: $0.workoutId,
                workoutDate: $0.workoutDate
            )
        }
    }

    private var untaggedExercisesBanner: some View {
        let count = untaggedExerciseNames.count
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text("\(count)")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(
                    count == 1
                        ? "exercise has no muscle roles yet, so it can't color your plates or count toward muscle recency."
                        : "exercises have no muscle roles yet, so they can't color your plates or count toward muscle recency."
                )
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Theme.Spacing.sm) {
                AppPillButton(title: "Tag exercises", variant: .accent) {
                    Haptics.selection()
                    showingTagging = true
                }
                .accessibilityLabel("Tag exercises with muscle roles")

                AppPillButton(title: "Not now", variant: .subtle) {
                    withAnimation(reduceMotion ? nil : Theme.Animation.spring) {
                        dismissedUntaggedCount = count
                    }
                }
                .accessibilityLabel("Dismiss tagging reminder")
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
        .transition(.opacity)
    }

    // MARK: - Hero

    private var heroSection: some View {
        TodayHero(
            sessionsThisWeek: currentWeekBucket?.stats.totalWorkouts ?? 0,
            weeklyGoal: min(max(sessionsPerWeekGoal, 1), 14),
            streakWeeks: cachedCurrentWeekStreak,
            plates: currentWeekPlates,
            activeSession: sessionManager.activeSession,
            lastWorkout: dataManager.workouts.first,
            onPrimaryAction: {
                Haptics.selection()
                if sessionManager.activeSession != nil {
                    sessionManager.isPresentingSessionUI = true
                } else {
                    startQuickSession(exercise: nil)
                }
            },
            onRepeatLast: { workout in
                repeatWorkout(workout)
            },
            onOpenWeek: {
                Haptics.selection()
                showingConsistencyDetail = true
            }
        )
    }

    private var emptySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HomeEmptyState(weeklyGoal: min(max(sessionsPerWeekGoal, 1), 14))

            VStack(spacing: Theme.Spacing.sm) {
                AppPrimaryButton(title: "Start workout") {
                    Haptics.selection()
                    startQuickSession(exercise: nil)
                }

                // New users are the ones who need a path in; returning users
                // still have import in Settings.
                Button {
                    Haptics.selection()
                    showingImportWizard = true
                } label: {
                    Text("Import history from Strong")
                        .font(Theme.Typography.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(BrandSecondaryButtonStyle())
            }
        }
    }

    private var currentWeekBucket: HomeWeekBucket? {
        cachedWeekBuckets.first { $0.isCurrentWeek }
    }

    private var currentWeekPlates: [LoadedPlate] {
        cachedRackWeeks.last?.plates ?? []
    }

    // MARK: - Week

    private var weekSection: some View {
        let bucket = selectedWeekBucket
        let selectedStart = selectedWeekBucketStart ?? cachedWeekBuckets.first?.weekStart
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(
                title: bucket?.title ?? selectedStart.map(Self.weekTitle(for:)) ?? "This week",
                subtitle: bucket.map { "\($0.rangeLabel), \($0.statusLabel.lowercased())" }
            ) {
                Button {
                    Haptics.selection()
                    showingConsistencyDetail = true
                } label: {
                    TextLinkLabel(title: "Consistency")
                }
                .buttonStyle(.plain)
            }

            if cachedRackWeeks.count > 1 {
                WeekRackChart(
                    weeks: cachedRackWeeks,
                    goal: min(max(sessionsPerWeekGoal, 1), 14),
                    selectedWeekStart: selectedStart,
                    onSelect: { weekStart in
                        withAnimation(reduceMotion ? nil : Theme.Animation.quick) {
                            selectedWeekBucketStart = weekStart
                        }
                    }
                )
                .padding(.horizontal, -Theme.Layout.screenGutter)
                .accessibilityLabel("Weekly sessions")
            }

            WeekStatsRow(bucket: bucket) { kind in
                selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: kind)
            }
        }
    }

    private static func weekTitle(for weekStart: Date) -> String {
        "Week of \(weekStart.formatted(Date.FormatStyle().month(.abbreviated).day()))"
    }

    // MARK: - Recent Workouts

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(title: "Recent") {
                NavigationLink(destination: WorkoutHistoryView(workouts: dataManager.workouts, showsBackButton: true)) {
                    TextLinkLabel(title: "All history")
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(Array(dataManager.workouts.prefix(3).enumerated()), id: \.element.id) { index, workout in
                    HomeWorkoutRow(
                        workout: workout,
                        exerciseCount: cachedExerciseCounts[workout.id] ?? workout.exercises.count,
                        category: cachedPlateCategories[workout.id],
                        showsRule: index > 0,
                        onRepeat: { repeatWorkout(workout) },
                        onTap: { selectedWorkout = workout }
                    )
                }
            }
        }
    }

    // MARK: - Explore

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(title: "Training")

            VStack(spacing: 0) {
                NavigationLink {
                    PerformanceLabView(
                        dataManager: dataManager,
                        annotationsManager: annotationsManager,
                        gymProfilesManager: gymProfilesManager
                    )
                } label: {
                    ExploreRow(title: "Performance", subtitle: "Strength and volume trends", showsRule: false)
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityIdentifier("explore-performance")

                NavigationLink {
                    ExerciseListView(dataManager: dataManager)
                } label: {
                    ExploreRow(title: "Exercises", subtitle: "Every lift, its records and history")
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityIdentifier("explore-exercises")

                Button {
                    showingConsistencyDetail = true
                } label: {
                    ExploreRow(title: "Consistency", subtitle: "Weekly goals and streaks")
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityIdentifier("explore-consistency")

                NavigationLink {
                    MuscleRecencyView(dataManager: dataManager)
                } label: {
                    ExploreRow(title: "Muscles", subtitle: "When each group was last trained")
                }
                .buttonStyle(PressableCardButtonStyle())

                NavigationLink {
                    RecoveryCoverageDetailView(engine: recoveryCoverageEngine)
                } label: {
                    ExploreRow(title: "Recovery", subtitle: "Sleep, heart rate, and muscle coverage")
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityIdentifier("explore-signals")

                NavigationLink {
                    WorkoutVariantReviewView()
                } label: {
                    ExploreRow(title: "Variants", subtitle: "How repeat workouts have changed")
                }
                .buttonStyle(PressableCardButtonStyle())
            }
        }
    }

    // MARK: - Data Helpers

    private var syncStatusText: String {
        if healthManager.isAutoSyncing { return "Syncing Health" }
        switch healthManager.authorizationStatus {
        case .authorized:
            if let lastSync = healthManager.lastSyncDate {
                return "Health updated \(lastSync.formatted(.relative(presentation: .named)))"
            }
            return "Health connected"
        case .notDetermined: return "Connect Health"
        case .denied: return "Review Health access"
        case .unavailable: return "Health unavailable"
        }
    }

    private var isHealthFresh: Bool {
        guard healthManager.authorizationStatus == .authorized,
              let lastSync = healthManager.lastSyncDate else { return false }
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

    private var weeklyDateRange: DateInterval {
        let now = Date()
        let weekStart = SharedFormatters.startOfWeekSunday(for: now)
        return DateInterval(start: weekStart, end: now)
    }

    private func buildHomeHighlights() -> [HighlightItem] {
        var items: [HighlightItem] = []

        let allowedTypes: Set<InsightType> = [.personalRecord, .strengthGain, .baseline]
        let filteredInsights = insightsEngine.insights.filter { allowedTypes.contains($0.type) }

        for insight in filteredInsights.prefix(3) {
            let highlightValue = SharedFormatters.sanitizedHighlightValue(from: insight.message)
            let action: (() -> Void)? = insight.exerciseName.map { exerciseName in
                { selectedExercise = ExerciseSelection(id: exerciseName) }
            }
            items.append(
                HighlightItem(
                    id: "\(insight.title)-\(insight.exerciseName ?? "none")-\(Int(insight.date.timeIntervalSince1970))",
                    title: insight.title,
                    value: highlightValue,
                    subtitle: insight.date.formatted(date: .abbreviated, time: .omitted),
                    icon: insight.type.iconName,
                    tint: SharedFormatters.highlightTint(for: insight.type),
                    action: action,
                    isRecord: insight.type == .personalRecord
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
        let outcome = WorkoutRepeatHelper.repeatWorkout(
            workout,
            gymProfileId: annotationsManager.annotation(for: workout.id)?.gymProfileId,
            weightIncrement: weightIncrement,
            sessionManager: sessionManager,
            dataManager: dataManager
        )
        if outcome == .requiresActiveSessionReplacement {
            pendingRepeatWorkout = workout
        }
    }

    private var repeatReplacementAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingRepeatWorkout != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRepeatWorkout = nil
                }
            }
        )
    }

    private func replaceActiveSessionAndRepeat(_ workout: Workout) {
        Task { @MainActor in
            await WorkoutRepeatHelper.replaceActiveSessionAndRepeat(
                workout,
                gymProfileId: annotationsManager.annotation(for: workout.id)?.gymProfileId,
                weightIncrement: weightIncrement,
                sessionManager: sessionManager,
                dataManager: dataManager
            )
        }
    }

    private func triggerAutoHealthSync() {
        guard !isAnalyticsUITestFixture else { return }
        guard healthManager.authorizationStatus == .authorized else { return }
        Task {
            await healthManager.syncRecentWorkoutsIfNeeded(dataManager.workouts)
        }
    }

    private var homeDerivedFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(dataManager.datasetRevision)
        hasher.combine(intentionalBreaksManager.revision)
        hasher.combine(metadataManager.revision)
        hasher.combine(relationshipManager.revision)
        hasher.combine(Calendar.current.startOfDay(for: Date()))
        return hasher.finalize()
    }

    private func refreshHomeDerivedState() {
        let fingerprint = homeDerivedFingerprint
        defer {
            if dataManager.hasLoadedImportedHistory {
                hasDerivedLoadedHistory = true
            }
        }
        guard fingerprint != homeDerivedCacheKey else { return }

        let workouts = dataManager.workouts
        let breaks = intentionalBreaksManager.savedBreaks
        let resolver = relationshipManager.resolverSnapshot()
        let weekBuckets = buildWeekBuckets(
            workouts: workouts,
            intentionalBreakRanges: breaks,
            resolver: resolver
        )

        cachedWeekBuckets = weekBuckets
        cachedExerciseCounts = weekBuckets.reduce(into: [:]) { result, bucket in
            result.merge(bucket.exerciseCounts) { current, _ in current }
        }
        cachedCurrentWeekStreak = WorkoutAnalytics.currentWeeklyStreak(
            for: workouts,
            intentionalBreakRanges: breaks
        )
        let allExerciseNames = dataManager.allExerciseNames()
        let exerciseNames = Set(allExerciseNames)
        let assignmentMappings = metadataManager.resolvedAssignmentMappings(
            for: exerciseNames,
            resolver: resolver
        )
        cachedUntaggedExerciseNames = allExerciseNames.filter { assignmentMappings[$0]?.isEmpty ?? true }

        let rackWeeks = buildRackWeeks(
            workouts: workouts,
            buckets: weekBuckets,
            assignments: assignmentMappings
        )
        cachedRackWeeks = rackWeeks.weeks
        cachedPlateCategories = rackWeeks.categories

        guard !workouts.isEmpty else {
            cachedMuscleSuggestions = []
            syncSelectedWeekBucket()
            homeDerivedCacheKey = fingerprint
            return
        }

        cachedMuscleSuggestions = MuscleRecencySuggestionEngine.suggestions(
            workouts: workouts,
            muscleAssignmentsByExerciseName: assignmentMappings,
            resolver: resolver
        )
        syncSelectedWeekBucket()
        homeDerivedCacheKey = fingerprint
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
        let exerciseNames = Set(dataManager.allExerciseNames())
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()
        let assignmentMappings = ExerciseMetadataManager.shared.resolvedAssignmentMappings(
            for: exerciseNames,
            resolver: resolver
        )
        await recoveryCoverageEngine.analyze(
            workouts: dataManager.workouts,
            healthStore: healthManager.healthDataStore,
            dailyHealth: healthManager.dailyHealthStore,
            muscleMappings: assignmentMappings,
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

    private func scheduleInitialWorkoutRefreshIfNeeded() {
        guard !hasScheduledInitialWorkoutRefresh else { return }
        hasScheduledInitialWorkoutRefresh = true
        guard !isAnalyticsUITestFixture else { return }

        Task {
            await dataManager.loadLatestWorkoutData(
                iCloudManager: iCloudManager,
                healthIdentitySnapshot: healthIdentitySnapshot
            )
            guard !Task.isCancelled else { return }

            await insightsEngine.generateInsights()
            guard !Task.isCancelled else { return }

            rebuildHomeHighlights()
            await refreshRecoveryCoverage()
        }
    }

    /// Holds the screen on the loading state until the saved import has arrived and this
    /// screen has summarized it, so the week never renders from partial data and then jumps.
    private var isAwaitingInitialHistory: Bool {
        !hasDerivedLoadedHistory && dataManager.error == nil && !isAnalyticsUITestFixture
    }

    private var isAnalyticsUITestFixture: Bool {
#if DEBUG
        AnalyticsUITestFixture.isEnabled
#else
        false
#endif
    }

    private func rebuildHomeHighlights() {
        cachedHomeHighlights = buildHomeHighlights()
    }

    private func buildWeekBuckets(
        workouts: [Workout],
        intentionalBreakRanges: [IntentionalBreakRange],
        resolver: ExerciseIdentityResolver
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
                    exerciseCounts: [:],
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
                    exerciseCounts: Dictionary(uniqueKeysWithValues: weekWorkouts.map {
                        ($0.id, ExerciseAggregation.exerciseCount(for: $0, resolver: resolver))
                    }),
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

    /// Weeks for the rack chart, oldest first: up to half a year back, never before the
    /// first workout. Also returns each recent session's plate category.
    private func buildRackWeeks(
        workouts: [Workout],
        buckets: [HomeWeekBucket],
        assignments: [String: [ExerciseMuscleAssignment]]
    ) -> (weeks: [RackWeek], categories: [UUID: PlateCategory]) {
        let calendar = Calendar.current
        let currentWeekStart = SharedFormatters.startOfWeekSunday(for: Date())
        guard let earliest = workouts.last else {
            return ([RackWeek(weekStart: currentWeekStart, plates: [], isBreak: false)], [:])
        }
        let earliestWeekStart = SharedFormatters.startOfWeekSunday(for: earliest.date)
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -25, to: currentWeekStart) ?? currentWeekStart
        let firstWeek = max(earliestWeekStart, windowStart)

        let recentWorkouts = workouts.filter { $0.date >= firstWeek }
        var categories: [UUID: PlateCategory] = [:]
        for workout in recentWorkouts {
            categories[workout.id] = PlateCategory.classify(workout, assignments: assignments)
        }
        let grouped = Dictionary(grouping: recentWorkouts) { SharedFormatters.startOfWeekSunday(for: $0.date) }
        let breakWeeks = Set(buckets.filter(\.isSavedBreakWeek).map(\.weekStart))

        var weeks: [RackWeek] = []
        var cursor = firstWeek
        while cursor <= currentWeekStart {
            let plates = (grouped[cursor] ?? [])
                .sorted { $0.date < $1.date }
                .map { LoadedPlate(id: $0.id, date: $0.date, category: categories[$0.id] ?? .fullBody) }
            weeks.append(RackWeek(weekStart: cursor, plates: plates, isBreak: breakWeeks.contains(cursor)))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return (weeks, categories)
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

}

// swiftlint:enable type_body_length file_length
