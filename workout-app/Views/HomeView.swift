import SwiftUI

struct HomeView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    let annotationsManager: WorkoutAnnotationsManager
    let gymProfilesManager: GymProfilesManager
    @EnvironmentObject var healthManager: HealthKitManager
    @Binding var selectedTab: AppTab

    @StateObject private var insightsEngine: InsightsEngine
    @State private var showingImportWizard = false
    @State private var showingHealthWizard = false
    @State private var showingQuickStart = false
    @State private var quickStartExercise: String?
    @State private var selectedExercise: ExerciseSelection?
    @State private var selectedWorkout: Workout?
    @State private var selectedWorkoutMetric: WorkoutMetricDetailSelection?

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
        _insightsEngine = StateObject(
            wrappedValue: InsightsEngine(
                dataManager: dataManager,
                annotationsProvider: { annotationsManager.annotations },
                gymNameProvider: { gymProfilesManager.gymNameSnapshot() }
            )
        )
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    headerSection

                    quickActionsSection

                    if dataManager.workouts.isEmpty {
                        HomeEmptyState(
                            onStart: {
                                quickStartExercise = nil
                                showingQuickStart = true
                            },
                            onImport: {
                                showingImportWizard = true
                            }
                        )
                            .padding(.horizontal, Theme.Spacing.lg)
                    } else {
                        weeklySummarySection
                            .padding(.horizontal, Theme.Spacing.lg)

                        spotlightSection
                            .padding(.horizontal, Theme.Spacing.lg)

                        recentWorkoutsSection
                            .padding(.horizontal, Theme.Spacing.lg)

                        exploreSection
                            .padding(.horizontal, Theme.Spacing.lg)
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
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
                Task { await loadLatestWorkoutData() }
            } else {
                triggerAutoHealthSync()
                refreshInsights()
            }
        }
        .refreshable {
            await loadLatestWorkoutData()
        }
        .onChange(of: dataManager.workouts.count) { _, _ in
            refreshInsights()
            triggerAutoHealthSync()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Home")
                .font(Theme.Typography.largeTitle)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(headerSubtitle)
                .font(Theme.Typography.microcopy)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var quickActionsSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button(action: {
                Haptics.selection()
                quickStartExercise = nil
                showingQuickStart = true
            }) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "bolt.fill")
                    Text("Start a session")
                        .font(Theme.Typography.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .frame(minHeight: 56)
                .background(Theme.Colors.accent)
                .cornerRadius(Theme.CornerRadius.xlarge)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.sm) {
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

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
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
            }
        }
    }

    private var weeklySummarySection: some View {
        let workouts = weeklyWorkouts
        let stats = workouts.isEmpty ? nil : dataManager.calculateStats(for: workouts)
        let sessions = stats.map { "\($0.totalWorkouts)" } ?? "0"
        let avgDuration = stats?.avgWorkoutDuration ?? "--"
        let favorite = stats?.favoriteExercise ?? "--"
        let favoriteName = stats?.favoriteExercise

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("This Week")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    SummaryPill(title: "Sessions", value: sessions) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .sessions, scrollTarget: nil)
                    }
                    SummaryPill(title: "Avg Duration", value: avgDuration) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .avgDuration, scrollTarget: nil)
                    }
                    SummaryPill(title: "Favorite", value: favorite, onTap: favoriteName.map { name in
                        { selectedExercise = ExerciseSelection(id: name) }
                    })
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                    SummaryPill(title: "Sessions", value: sessions) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .sessions, scrollTarget: nil)
                    }
                    SummaryPill(title: "Avg Duration", value: avgDuration) {
                        selectedWorkoutMetric = WorkoutMetricDetailSelection(kind: .avgDuration, scrollTarget: nil)
                    }
                    SummaryPill(title: "Favorite", value: favorite, onTap: favoriteName.map { name in
                        { selectedExercise = ExerciseSelection(id: name) }
                    })
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var spotlightSection: some View {
        HighlightsSectionView(title: "Spotlight", items: Array(homeHighlights.prefix(1)))
    }

    private var recentWorkoutsSection: some View {
        RecentWorkoutsView(
            workouts: Array(dataManager.workouts.prefix(3)),
            allWorkouts: dataManager.workouts
        )
    }

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Explore")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.md) {
                NavigationLink {
                    PerformanceLabView(dataManager: dataManager)
                } label: {
                    ExploreRow(
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
                    ExploreRow(
                        title: "Exercises",
                        subtitle: "History by lift",
                        icon: "figure.strengthtraining.traditional",
                        tint: Theme.Colors.accentSecondary
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    WorkoutHistoryView(workouts: dataManager.workouts)
                } label: {
                    ExploreRow(
                        title: "History",
                        subtitle: "Past sessions",
                        icon: "clock.fill",
                        tint: Theme.Colors.accent
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var headerSubtitle: String {
        if let lastWorkout = dataManager.workouts.first {
            return "Last workout \(lastWorkout.date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "No workouts yet."
    }

    private var weeklyWorkouts: [Workout] {
        guard !dataManager.workouts.isEmpty else { return [] }
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return dataManager.workouts.filter { $0.date >= weekAgo }
    }

    private var homeHighlights: [HighlightItem] {
        var items: [HighlightItem] = []

        if let latest = dataManager.workouts.first {
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

                let files = iCloudDocumentManager.listWorkoutFiles(in: directoryURL)
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
            await dataManager.processWorkoutSets(sets, healthDataSnapshot: healthSnapshot)
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
        default:
            return Theme.Colors.accent
        }
    }
}

private struct HomeEmptyState: View {
    let onStart: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 40))
                    .foregroundColor(Theme.Colors.textTertiary)

                Text("You're ready.")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Start a session or import your history. We'll keep it simple from there.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Button(action: {
                    Haptics.selection()
                    onStart()
                }) {
                    Text("Start a session")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .frame(minHeight: 52)
                        .background(Theme.Colors.accent)
                        .cornerRadius(Theme.CornerRadius.xlarge)
                }
                .buttonStyle(.plain)

                Button(action: {
                    Haptics.selection()
                    onImport()
                }) {
                    Text("Import from Strong")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .frame(minHeight: 44)
                        .softCard(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 2)
    }
}

private struct SecondaryChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                Text(title)
                    .font(Theme.Typography.subheadline)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: 44)
            .softCard(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct ActionChip: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                Text(title)
                    .font(Theme.Typography.subheadline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: 44)
            .background(tint)
            .cornerRadius(Theme.CornerRadius.large)
        }
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        Group {
            if let onTap {
                MetricTileButton(action: onTap) {
                    content
                }
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            Text(value)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(elevation: 1)
    }
}

private struct ExploreRow: View {
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
                .cornerRadius(12)

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
