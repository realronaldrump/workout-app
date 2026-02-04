import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    let annotationsManager: WorkoutAnnotationsManager
    let gymProfilesManager: GymProfilesManager
    @EnvironmentObject var healthManager: HealthKitManager

    @StateObject private var insightsEngine: InsightsEngine
    @State private var selectedTimeRange = TimeRange.week
    @State private var selectedExercise: ExerciseSelection?
    @State private var selectedWorkout: Workout?
    @State private var stats: WorkoutStats?
    @State private var isTrainingExpanded = false
    @State private var showingImportWizard = false
    @State private var showingHealthWizard = false
    @State private var showingHealthDashboard = false
    @State private var showingQuickStart = false
    @State private var quickStartExercise: String?
    @State private var showingHistory = false
    @State private var selectedMetric: MetricDrilldown?

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
                        EmptyDataView(
                            onImport: { showingImportWizard = true },
                            onConnectHealth: { showingHealthWizard = true }
                        )
                        .padding(.horizontal, Theme.Spacing.lg)
                    } else {
                        timeRangeSection

                        if let currentStats = filteredStats {
                            KeyMetricsSection(
                                stats: currentStats,
                                readiness: readinessSnapshot,
                                streakDelta: streakDelta,
                                onMetricTap: { metric in
                                    selectedMetric = metric
                                }
                            )
                            .padding(.horizontal, Theme.Spacing.lg)
                        } else {
                            MetricsSkeletonView()
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        windowDeltaSection
                            .padding(.horizontal, Theme.Spacing.lg)

                        InsightsStreamView(
                            insights: insightsEngine.insights,
                            moments: insightMoments,
                            onInsightTap: { insight in
                                if let exerciseName = insight.exerciseName {
                                    selectedExercise = ExerciseSelection(id: exerciseName)
                                }
                            }
                        )
                        .padding(.horizontal, Theme.Spacing.lg)

                        if let snapshot = healthSnapshot {
                            HealthPulseSection(snapshot: snapshot) {
                                showingHealthDashboard = true
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                        }

                        trainingSection
                            .padding(.horizontal, Theme.Spacing.lg)

                        explorationSection
                            .padding(.horizontal, Theme.Spacing.lg)

                        RecentWorkoutsView(workouts: Array(filteredWorkouts.prefix(4)))
                            .padding(.horizontal, Theme.Spacing.lg)
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showingHistory) {
            WorkoutHistoryView(workouts: dataManager.workouts)
        }
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
        .navigationDestination(item: $selectedMetric) { metric in
            MetricDetailView(type: metric, workouts: filteredWorkouts)
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
        .sheet(isPresented: $showingHealthDashboard) {
            HealthDashboardView()
        }
        .sheet(isPresented: $showingQuickStart) {
            QuickStartView(exerciseName: quickStartExercise)
        }
        .onAppear {
            if dataManager.workouts.isEmpty {
                // Offload file reading to background to prevent main thread hitch
                loadLatestWorkoutData()
            } else {
                // Just refresh these lightweight checks
                healthManager.refreshAuthorizationStatus()
                triggerAutoHealthSync()
            }
        }
        .refreshable {
            loadLatestWorkoutData()
        }
        .onChange(of: dataManager.workouts.count) { _, _ in
            refreshStats()
            triggerAutoHealthSync()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Analytics")
                        .font(Theme.Typography.largeTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
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

            HStack(spacing: Theme.Spacing.md) {
                ActionButton(
                    title: "Import",
                    icon: "arrow.down.to.line",
                    tint: Theme.Colors.accent
                ) {
                    showingImportWizard = true
                }

                ActionButton(
                    title: "Health",
                    icon: "heart.fill",
                    tint: .red
                ) {
                    if healthManager.authorizationStatus == .authorized {
                        showingHealthDashboard = true
                    } else {
                        showingHealthWizard = true
                    }
                }

                ActionButton(
                    title: "Start",
                    icon: "bolt.fill",
                    tint: Theme.Colors.accentSecondary
                ) {
                    quickStartExercise = nil
                    showingQuickStart = true
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var timeRangeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Window")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.lg)

            TimeRangePicker(selectedRange: $selectedTimeRange)
        }
    }

    private var windowDeltaSection: some View {
        WindowDeltaCard(
            metrics: windowChangeMetrics,
            windowLabel: selectedTimeRange.rawValue,
            windowDays: windowDays
        )
    }

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Training Load")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button(action: {
                    withAnimation(Theme.Animation.spring) {
                        isTrainingExpanded.toggle()
                    }
                    Haptics.selection()
                }) {
                    Text(isTrainingExpanded ? "Collapse" : "Expand")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.accent)
                }
            }

            VStack(spacing: Theme.Spacing.lg) {
                if let currentStats = filteredStats {
                    ConsistencyView(stats: currentStats, workouts: filteredWorkouts)
                } else {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .fill(Theme.Colors.surface.opacity(0.6))
                        .frame(height: 220)
                        .redacted(reason: .placeholder)
                }

                if isTrainingExpanded {
                    VolumeProgressChart(workouts: filteredWorkouts)
                    MuscleHeatmapView(dataManager: dataManager)
                    ExerciseBreakdownView(workouts: filteredWorkouts)
                }
            }
        }
    }

    private var explorationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Drilldowns")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.md) {
                NavigationLink {
                    PerformanceLabView(dataManager: dataManager)
                } label: {
                    ExplorationRow(
                        title: "Performance",
                        subtitle: "Deltas | ratios | r",
                        icon: "viewfinder",
                        tint: Theme.Colors.success
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    WorkoutHistoryView(workouts: dataManager.workouts)
                } label: {
                    ExplorationRow(
                        title: "History",
                        subtitle: "Sessions | filters",
                        icon: "clock.fill",
                        tint: Theme.Colors.accent
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    ExerciseListView(dataManager: dataManager)
                } label: {
                    ExplorationRow(
                        title: "Exercises",
                        subtitle: "PR | volume | freq",
                        icon: "figure.strengthtraining.traditional",
                        tint: Theme.Colors.accentSecondary
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    ProfileView(dataManager: dataManager, iCloudManager: iCloudManager)
                } label: {
                    ExplorationRow(
                        title: "Profile",
                        subtitle: "Stats | links | prefs",
                        icon: "person.crop.circle",
                        tint: Theme.Colors.accent
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    SettingsView(dataManager: dataManager, iCloudManager: iCloudManager)
                } label: {
                    ExplorationRow(
                        title: "Settings",
                        subtitle: "Sync | units | tags",
                        icon: "gearshape.fill",
                        tint: Theme.Colors.textSecondary
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var filteredWorkouts: [Workout] {
        guard !dataManager.workouts.isEmpty else { return [] }

        let calendar = Calendar.current
        let now = Date()

        switch selectedTimeRange {
        case .week:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return dataManager.workouts.filter { $0.date >= weekAgo }
        case .month:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return dataManager.workouts.filter { $0.date >= monthAgo }
        case .threeMonths:
            let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return dataManager.workouts.filter { $0.date >= threeMonthsAgo }
        case .year:
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return dataManager.workouts.filter { $0.date >= yearAgo }
        case .allTime:
            return dataManager.workouts
        }
    }

    private var filteredStats: WorkoutStats? {
        guard !filteredWorkouts.isEmpty else { return nil }
        return dataManager.calculateStats(for: filteredWorkouts)
    }

    private var headerSummary: String {
        guard let stats = filteredStats else {
            return "sessions 0 | volume 0 | density 0"
        }

        let densities = filteredWorkouts.map { WorkoutAnalytics.effortDensity(for: $0) }
        let avgDensity = average(densities) ?? 0
        return "sessions \(stats.totalWorkouts) | volume \(formatVolume(stats.totalVolume)) | density \(String(format: "%.1f", avgDensity))"
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

    private var readinessSnapshot: ReadinessSnapshot? {
        guard let snapshot = healthSnapshot else { return nil }
        return snapshot.readiness
    }

    private var healthSnapshot: HealthSnapshot? {
        let values = healthManager.healthDataStore.values
        guard !values.isEmpty else { return nil }

        let recent = values.sorted { $0.workoutDate > $1.workoutDate }.prefix(5)
        let avgHRV = average(recent.compactMap { $0.avgHRV })
        let avgResting = average(recent.compactMap { $0.restingHeartRate })
        let avgHR = average(recent.compactMap { $0.avgHeartRate })
        let lastSynced = values.compactMap { $0.syncedAt }.max()

        return HealthSnapshot(
            avgHRV: avgHRV,
            avgRestingHR: avgResting,
            avgWorkoutHR: avgHR,
            lastSynced: lastSynced,
            isConnected: healthManager.authorizationStatus == .authorized
        )
    }

    private var streakDelta: String? {
        guard let stats = stats else { return nil }
        return "best \(stats.longestStreak)"
    }

    private var insightMoments: [InsightMoment] {
        var items: [InsightMoment] = []

        if let stats = stats {
            let densities = filteredWorkouts.map { WorkoutAnalytics.effortDensity(for: $0) }
            let avgDensity = average(densities) ?? 0
            items.append(
                InsightMoment(
                    title: "Sessions",
                    message: "window \(selectedTimeRange.rawValue)",
                    icon: "flag.checkered",
                    tint: Theme.Colors.accent,
                    value: "\(stats.totalWorkouts)"
                )
            )
            items.append(
                InsightMoment(
                    title: "Density",
                    message: "avg",
                    icon: "chart.line.uptrend.xyaxis",
                    tint: Theme.Colors.accentSecondary,
                    value: String(format: "%.1f", avgDensity)
                )
            )
        }

        if let readiness = readinessSnapshot {
            items.append(
                InsightMoment(
                    title: readiness.label,
                    message: readiness.detail,
                    icon: readiness.icon,
                    tint: readiness.tint,
                    value: readiness.score
                )
            )
        }

        if let recentWorkout = filteredWorkouts.first {
            items.append(
                InsightMoment(
                    title: "Latest",
                    message: recentWorkout.name,
                    icon: "clock.fill",
                    tint: Theme.Colors.accentSecondary,
                    value: recentWorkout.duration
                )
            )
        }

        return items
    }

    private var windowDays: Int {
        switch selectedTimeRange {
        case .week:
            return 7
        case .month:
            return 30
        case .threeMonths:
            return 90
        case .year:
            return 365
        case .allTime:
            guard let oldest = dataManager.workouts.map({ $0.date }).min(),
                  let newest = dataManager.workouts.map({ $0.date }).max() else { return 30 }
            let days = Calendar.current.dateComponents([.day], from: oldest, to: newest).day ?? 30
            return max(days, 30)
        }
    }

    private var windowChangeMetrics: [ChangeMetric] {
        WorkoutAnalytics.changeMetrics(for: dataManager.workouts, windowDays: windowDays)
    }

    private func loadLatestWorkoutData() {
        Task.detached(priority: .userInitiated) {
            let files = await iCloudManager.listWorkoutFiles()
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }

            if let latestFile = files.first {
                do {
                    let data = try Data(contentsOf: latestFile)
                    let sets = try CSVParser.parseStrongWorkoutsCSV(from: data)

                    let healthSnapshot = await MainActor.run {
                        Array(healthManager.healthDataStore.values)
                    }

                    await dataManager.processWorkoutSets(sets, healthDataSnapshot: healthSnapshot)
                    await MainActor.run {
                        refreshStats()
                    }
                } catch {
                    print("Failed to load workout data: \(error)")
                }
            }
        }
    }

    private func refreshStats() {
        if dataManager.workouts.isEmpty {
            stats = nil
        } else {
            stats = dataManager.calculateStats()
        }
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

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000000 {
            return String(format: "%.1fM", volume / 1000000)
        } else if volume >= 1000 {
            return String(format: "%.0fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
}

private struct HealthSnapshot {
    let avgHRV: Double?
    let avgRestingHR: Double?
    let avgWorkoutHR: Double?
    let lastSynced: Date?
    let isConnected: Bool

    var readiness: ReadinessSnapshot? {
        guard let hrv = avgHRV, let resting = avgRestingHR else { return nil }
        let ratio = hrv / max(resting, 1)
        let scoreValue = max(0, min(100, Int(ratio * 12)))
        let isCaution = scoreValue < 60
        let tint: Color = isCaution ? Theme.Colors.warning : Theme.Colors.success
        let label = "Readiness"
        let detail = "hrv \(Int(hrv)) ms | rhr \(Int(resting)) bpm | r \(String(format: "%.2f", ratio))"

        return ReadinessSnapshot(
            score: "\(scoreValue)",
            label: label,
            detail: detail,
            icon: isCaution ? "bed.double.fill" : "figure.strengthtraining.traditional",
            tint: tint,
            isCaution: isCaution,
            ratioLabel: "r \(String(format: "%.2f", ratio))"
        )
    }
}

private struct ReadinessSnapshot {
    let score: String
    let label: String
    let detail: String
    let icon: String
    let tint: Color
    let isCaution: Bool
    let ratioLabel: String
}

private struct SyncStatusPill: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(isActive ? Theme.Colors.success : Theme.Colors.textTertiary)
                .frame(width: 6, height: 6)
            Text(text)
                .font(Theme.Typography.caption)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surface.opacity(0.7))
        .cornerRadius(14)
    }
}

private struct ActionButton: View {
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
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(tint)
            .cornerRadius(Theme.CornerRadius.large)
        }
    }
}

private struct TimeRangePicker: View {
    @Binding var selectedRange: DashboardView.TimeRange

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(DashboardView.TimeRange.allCases, id: \.self) { range in
                    Button {
                        selectedRange = range
                        Haptics.selection()
                    } label: {
                        Text(range.rawValue)
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(selectedRange == range ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                    .fill(selectedRange == range ? Theme.Colors.elevated : Theme.Colors.surface.opacity(0.4))
                            )
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let direction = value.translation.width
                    guard abs(direction) > 40 else { return }
                    let all = DashboardView.TimeRange.allCases
                    guard let index = all.firstIndex(of: selectedRange) else { return }
                    let nextIndex = direction < 0 ? min(index + 1, all.count - 1) : max(index - 1, 0)
                    if nextIndex != index {
                        selectedRange = all[nextIndex]
                        Haptics.selection()
                    }
                }
        )
    }
}

private struct KeyMetricsSection: View {
    let stats: WorkoutStats
    let readiness: ReadinessSnapshot?
    let streakDelta: String?
    let onMetricTap: (MetricDrilldown) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Key Metrics")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                Button(action: {
                    Haptics.selection()
                    onMetricTap(.sessions)
                }) {
                    MetricCard(
                        title: "Sessions",
                        value: "\(stats.totalWorkouts)",
                        subtitle: "window",
                        icon: "flag.checkered",
                        accent: Theme.Colors.accent,
                        badge: nil
                    )
                }
                .buttonStyle(ScaleButtonStyle())

                Button(action: {
                    Haptics.selection()
                    onMetricTap(.streak)
                }) {
                    MetricCard(
                        title: "Streak",
                        value: "\(stats.currentStreak)",
                        subtitle: "days",
                        icon: "flame.fill",
                        accent: Theme.Colors.warning,
                        badge: streakDelta
                    )
                }
                .buttonStyle(ScaleButtonStyle())

                Button(action: {
                    Haptics.selection()
                    onMetricTap(.volume)
                }) {
                    MetricCard(
                        title: "Volume",
                        value: formatVolume(stats.totalVolume),
                        subtitle: "total",
                        icon: "scalemass.fill",
                        accent: Theme.Colors.success,
                        badge: nil
                    )
                }
                .buttonStyle(ScaleButtonStyle())

                Button(action: {
                    Haptics.selection()
                    onMetricTap(.readiness)
                }) {
                    MetricCard(
                        title: "Readiness",
                        value: readiness?.score ?? "--",
                        subtitle: readiness?.ratioLabel ?? "ratio --",
                        icon: "waveform.path.ecg",
                        accent: readiness?.tint ?? Theme.Colors.accentSecondary,
                        badge: nil
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
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
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let accent: Color
    let badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(accent)
                Spacer()
                if let badge = badge {
                    Text(badge)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.surface.opacity(0.6))
                        .cornerRadius(10)
                }
            }

            Text(value)
                .font(Theme.Typography.metric)
                .foregroundColor(Theme.Colors.textPrimary)

            Text([title, subtitle].compactMap { $0 }.joined(separator: " "))
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(elevation: 3)
    }
}

private struct WindowDeltaCard: View {
    let metrics: [ChangeMetric]
    let windowLabel: String
    let windowDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Window Delta")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("\(windowLabel) | \(windowDays)d")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            if metrics.isEmpty {
                Text("metrics 0")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                    ForEach(metrics) { metric in
                        DeltaMetricCard(metric: metric)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 2)
    }
}

private struct DeltaMetricCard: View {
    let metric: ChangeMetric

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(metric.title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Text(formatValue(metric.current))
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(deltaLabel)
                .font(Theme.Typography.caption)
                .foregroundColor(metric.isPositive ? Theme.Colors.success : Theme.Colors.error)
        }
        .padding(Theme.Spacing.md)
        .glassBackground(elevation: 1)
    }

    private var deltaLabel: String {
        let sign = metric.delta >= 0 ? "+" : "-"
        let percentSign = metric.percentChange >= 0 ? "+" : ""
        return "delta \(sign)\(formatDelta(abs(metric.delta))) | \(percentSign)\(String(format: "%.0f", metric.percentChange))%"
    }

    private func formatValue(_ value: Double) -> String {
        if metric.title.contains("Sessions") {
            return String(format: "%.0f", value)
        }
        if metric.title.contains("Duration") {
            return formatDurationMinutes(value)
        }
        if metric.title.contains("Volume") {
            return formatVolume(value)
        }
        if metric.title.contains("Density") {
            return String(format: "%.1f", value)
        }
        return String(format: "%.1f", value)
    }

    private func formatDelta(_ value: Double) -> String {
        if metric.title.contains("Sessions") {
            return String(format: "%.0f", value)
        }
        if metric.title.contains("Duration") {
            return String(format: "%.0f m", value)
        }
        if metric.title.contains("Volume") {
            return formatVolume(value)
        }
        if metric.title.contains("Density") {
            return String(format: "%.1f", value)
        }
        return String(format: "%.1f", value)
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

private struct HealthPulseSection: View {
    let snapshot: HealthSnapshot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text("Health Snapshot")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                HStack(spacing: Theme.Spacing.lg) {
                    HealthMetricPill(title: "Avg HRV", value: snapshot.avgHRV, unit: "ms")
                    HealthMetricPill(title: "Resting HR", value: snapshot.avgRestingHR, unit: "bpm")
                    HealthMetricPill(title: "Workout HR", value: snapshot.avgWorkoutHR, unit: "bpm")
                }

                if let lastSynced = snapshot.lastSynced {
                    Text("sync \(lastSynced.formatted(.relative(presentation: .named)))")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .padding(Theme.Spacing.lg)
            .glassBackground(elevation: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct HealthMetricPill: View {
    let title: String
    let value: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value.map { "\(Int($0))" } ?? "--")
                    .font(Theme.Typography.numberSmall)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(unit)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surface.opacity(0.5))
        .cornerRadius(Theme.CornerRadius.medium)
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
        .glassBackground(elevation: 1)
    }
}

private struct EmptyDataView: View {
    let onImport: () -> Void
    let onConnectHealth: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 44))
                .foregroundColor(Theme.Colors.textTertiary)

            VStack(spacing: Theme.Spacing.sm) {
                Text("workouts 0")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("exercises 0 | volume 0 | streak 0")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button(action: onImport) {
                    Text("Import CSV")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accent)
                        .cornerRadius(Theme.CornerRadius.large)
                }

                Button(action: onConnectHealth) {
                    Text("Health")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.surface.opacity(0.7))
                        .cornerRadius(Theme.CornerRadius.large)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .glassBackground(elevation: 2)
    }
}

private struct MetricsSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surface.opacity(0.6))
                .frame(height: 24)
                .redacted(reason: .placeholder)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Theme.Colors.surface.opacity(0.6))
                        .frame(height: 120)
                        .redacted(reason: .placeholder)
                }
            }
        }
    }
}
