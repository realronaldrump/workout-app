import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
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

    init(dataManager: WorkoutDataManager, iCloudManager: iCloudDocumentManager) {
        self.dataManager = dataManager
        self.iCloudManager = iCloudManager
        _insightsEngine = StateObject(wrappedValue: InsightsEngine(dataManager: dataManager))
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
                        EmptyMissionView(
                            onImport: { showingImportWizard = true },
                            onConnectHealth: { showingHealthWizard = true }
                        )
                        .padding(.horizontal, Theme.Spacing.lg)
                    } else {
                        timeRangeSection

                        if let currentStats = filteredStats {
                            MissionMetricsSection(
                                stats: currentStats,
                                readiness: readinessSnapshot,
                                streakDelta: streakDelta
                            )
                            .padding(.horizontal, Theme.Spacing.lg)
                        } else {
                            MetricsSkeletonView()
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        briefingSection
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
            ExerciseDetailView(exerciseName: selection.id, dataManager: dataManager)
        }
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailView(workout: workout)
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
                    Text(greeting)
                        .font(Theme.Typography.microcopy)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text("Mission Control")
                        .font(Theme.Typography.largeTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
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
                MissionActionButton(
                    title: "Import",
                    icon: "arrow.down.to.line",
                    tint: Theme.Colors.accent
                ) {
                    showingImportWizard = true
                }

                MissionActionButton(
                    title: healthManager.authorizationStatus == .authorized ? "Health" : "Connect",
                    icon: "heart.fill",
                    tint: .red
                ) {
                    if healthManager.authorizationStatus == .authorized {
                        showingHealthDashboard = true
                    } else {
                        showingHealthWizard = true
                    }
                }

                MissionActionButton(
                    title: "Quick Start",
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
            Text("Focus Window")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.lg)

            TimeRangePicker(selectedRange: $selectedTimeRange)
        }
    }

    private var briefingSection: some View {
        let briefing = contextualBriefing

        return ContextualBriefingCard(
            title: briefing.title,
            message: briefing.message,
            accent: briefing.tint,
            icon: briefing.icon,
            actionLabel: briefing.actionLabel,
            action: {
                handleBriefingAction(briefing.action)
            }
        )
    }

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Training Pulse")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button(action: {
                    withAnimation(Theme.Animation.spring) {
                        isTrainingExpanded.toggle()
                    }
                    Haptics.selection()
                }) {
                    Text(isTrainingExpanded ? "Less" : "More")
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
            Text("Explore")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.md) {
                NavigationLink {
                    WorkoutHistoryView(workouts: dataManager.workouts)
                } label: {
                    ExplorationRow(
                        title: "Workout History",
                        subtitle: "Every session, filtered",
                        icon: "clock.fill",
                        tint: Theme.Colors.accent
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    ExerciseListView(dataManager: dataManager)
                } label: {
                    ExplorationRow(
                        title: "Exercise Library",
                        subtitle: "Trends, PRs, plateaus",
                        icon: "figure.strengthtraining.traditional",
                        tint: Theme.Colors.accentSecondary
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink {
                    SettingsView(dataManager: dataManager, iCloudManager: iCloudManager)
                } label: {
                    ExplorationRow(
                        title: "Settings",
                        subtitle: "Sync, units, and tags",
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

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<22:
            return "Good evening"
        default:
            return "Welcome back"
        }
    }

    private var syncStatusText: String {
        if healthManager.isAutoSyncing {
            return "Refreshing health data"
        }
        switch healthManager.authorizationStatus {
        case .authorized:
            if let lastSync = healthManager.lastSyncDate {
                return "Health updated \(lastSync.formatted(.relative(presentation: .named)))"
            }
            return "Health connected"
        case .notDetermined:
            return "Health not connected"
        case .denied:
            return "Health permission denied"
        case .unavailable:
            return "Health unavailable"
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
        if stats.currentStreak >= stats.longestStreak {
            return "New best"
        }
        if stats.currentStreak >= 3 {
            return "On a roll"
        }
        return nil
    }

    private var insightMoments: [InsightMoment] {
        var items: [InsightMoment] = []

        if let stats = stats {
            items.append(
                InsightMoment(
                    title: "Momentum",
                    message: "\(stats.totalWorkouts) sessions logged this window.",
                    icon: "sparkles",
                    tint: Theme.Colors.accent,
                    value: "\(stats.currentStreak) day streak"
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
                    title: "Latest Session",
                    message: recentWorkout.name,
                    icon: "clock.fill",
                    tint: Theme.Colors.accentSecondary,
                    value: recentWorkout.duration
                )
            )
        }

        return items
    }

    private var contextualBriefing: DashboardBriefing {
        let now = Date()
        let weekday = Calendar.current.component(.weekday, from: now)
        let hour = Calendar.current.component(.hour, from: now)
        let lastWorkout = stats?.lastWorkoutDate

        if let lastWorkout, now.timeIntervalSince(lastWorkout) < 3600 * 6 {
            return DashboardBriefing(
                title: "Recovery first",
                message: "Your last session was just \(lastWorkout.formatted(.relative(presentation: .named))). Keep intensity low or focus on mobility.",
                icon: "waveform.path.ecg",
                tint: Theme.Colors.warning,
                actionLabel: "Check recovery",
                action: .health
            )
        }

        if weekday == 2 && hour < 12 {
            return DashboardBriefing(
                title: "Set the week",
                message: "Monday morning focus. Map your training windows based on your strongest sessions.",
                icon: "calendar.badge.clock",
                tint: Theme.Colors.accent,
                actionLabel: "View history",
                action: .history
            )
        }

        if let readiness = readinessSnapshot, readiness.isCaution {
            return DashboardBriefing(
                title: "Dial it back",
                message: readiness.detail,
                icon: readiness.icon,
                tint: readiness.tint,
                actionLabel: "Recovery",
                action: .health
            )
        }

        return DashboardBriefing(
            title: "Ready to push",
            message: "Your consistency is building. Plan a focused session to keep momentum.",
            icon: "bolt.fill",
            tint: Theme.Colors.success,
            actionLabel: "Quick start",
            action: .quickStart
        )
    }

    private func handleBriefingAction(_ action: DashboardBriefing.Action) {
        Haptics.selection()
        switch action {
        case .history:
            showingHistory = true
        case .health:
            if healthManager.authorizationStatus == .authorized {
                showingHealthDashboard = true
            } else {
                showingHealthWizard = true
            }
        case .quickStart:
            quickStartExercise = nil
            showingQuickStart = true
        case .importData:
            showingImportWizard = true
        }
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
                    
                    // Switch back to MainActor to update the view model
                    _ = await MainActor.run {
                        // We will make processWorkoutSets async next, but for now calling it inside a Task structure
                        // If processWorkoutSets becomes async, we'll await it.
                        // For this step, we are assuming it might still be synchronous or we will update it shortly.
                        // Actually, looking at the plan, we are making processWorkoutSets async next.
                        // So let's prepare for that.
                        
                        Task {
                             await dataManager.processWorkoutSets(sets)
                             refreshStats()
                        }
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
}

private struct DashboardBriefing {
    enum Action {
        case history
        case health
        case quickStart
        case importData
    }

    let title: String
    let message: String
    let icon: String
    let tint: Color
    let actionLabel: String
    let action: Action
}

private struct HealthSnapshot {
    let avgHRV: Double?
    let avgRestingHR: Double?
    let avgWorkoutHR: Double?
    let lastSynced: Date?
    let isConnected: Bool

    var readiness: ReadinessSnapshot? {
        guard let hrv = avgHRV, let resting = avgRestingHR else { return nil }
        let scoreValue = max(0, min(100, Int((hrv / max(resting, 1)) * 12)))
        let isCaution = scoreValue < 60
        let tint: Color = isCaution ? Theme.Colors.warning : Theme.Colors.success
        let label = isCaution ? "Recovery" : "Ready"
        let detail = isCaution
            ? "HRV and resting HR suggest a lighter session today."
            : "HRV and resting HR look strong. You can push intensity."

        return ReadinessSnapshot(
            score: "\(scoreValue)",
            label: label,
            detail: detail,
            icon: isCaution ? "bed.double.fill" : "figure.strengthtraining.traditional",
            tint: tint,
            isCaution: isCaution
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

private struct MissionActionButton: View {
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

private struct MissionMetricsSection: View {
    let stats: WorkoutStats
    let readiness: ReadinessSnapshot?
    let streakDelta: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Critical Metrics")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                MetricCard(
                    title: "Sessions",
                    value: "\(stats.totalWorkouts)",
                    subtitle: "this window",
                    icon: "flag.checkered",
                    accent: Theme.Colors.accent,
                    badge: nil
                )

                MetricCard(
                    title: "Streak",
                    value: "\(stats.currentStreak)",
                    subtitle: "days",
                    icon: "flame.fill",
                    accent: Theme.Colors.warning,
                    badge: streakDelta
                )

                MetricCard(
                    title: "Total Volume",
                    value: formatVolume(stats.totalVolume),
                    subtitle: "lifted",
                    icon: "scalemass.fill",
                    accent: Theme.Colors.success,
                    badge: nil
                )

                MetricCard(
                    title: readiness?.label ?? "Readiness",
                    value: readiness?.score ?? "--",
                    subtitle: readiness?.isCaution == true ? "recover" : "ready",
                    icon: readiness?.icon ?? "heart.circle.fill",
                    accent: readiness?.tint ?? Theme.Colors.accentSecondary,
                    badge: nil
                )
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

private struct ContextualBriefingCard: View {
    let title: String
    let message: String
    let accent: Color
    let icon: String
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(accent)
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
            }

            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            Button(action: action) {
                Text(actionLabel)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(accent)
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 2)
    }
}

private struct HealthPulseSection: View {
    let snapshot: HealthSnapshot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text("Health Pulse")
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
                    Text("Updated \(lastSynced.formatted(.relative(presentation: .named)))")
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

private struct EmptyMissionView: View {
    let onImport: () -> Void
    let onConnectHealth: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundColor(Theme.Colors.textTertiary)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Your mission control is waiting")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Import your Strong history to unlock insights, recovery guidance, and adaptive recommendations.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
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
                    Text("Connect Health")
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
