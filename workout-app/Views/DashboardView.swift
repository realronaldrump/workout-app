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
    @State private var isTrainingExpanded = false

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
                        summarySection
                            .padding(.horizontal, Theme.Spacing.lg)

                        changeSummarySection
                            .padding(.horizontal, Theme.Spacing.lg)

                        highlightsSection
                            .padding(.horizontal, Theme.Spacing.lg)

                        trainingSection
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
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            if dataManager.workouts.isEmpty {
                // Offload file reading to background to prevent main thread hitch
                loadLatestWorkoutData()
            } else {
                // Just refresh these lightweight checks
                triggerAutoHealthSync()
                refreshInsights()
            }
        }
        .refreshable {
            loadLatestWorkoutData()
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
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var timeRangeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Time Range")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.lg)

            TimeRangePicker(selectedRange: $selectedTimeRange)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Summary")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            if let currentStats = filteredStats {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.md) {
                        SummaryMetricCard(title: "Sessions", value: "\(currentStats.totalWorkouts)")
                        SummaryMetricCard(title: "Avg Duration", value: currentStats.avgWorkoutDuration)
                        SummaryMetricCard(title: "Volume", value: formatVolume(currentStats.totalVolume))
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                        SummaryMetricCard(title: "Sessions", value: "\(currentStats.totalWorkouts)")
                        SummaryMetricCard(title: "Avg Duration", value: currentStats.avgWorkoutDuration)
                        SummaryMetricCard(title: "Volume", value: formatVolume(currentStats.totalVolume))
                    }
                }
            } else {
                MetricsSkeletonView()
            }
        }
    }

    private var changeSummarySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Change")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(selectedTimeRange.rawValue)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            if changeSummaryMetrics.isEmpty {
                Text("No change data")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 1)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(changeSummaryMetrics) { metric in
                        ChangeMetricRow(metric: metric)
                    }
                }
            }

            NavigationLink {
                PerformanceLabView(dataManager: dataManager)
            } label: {
                HStack {
                    Text("See Performance Lab")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.md)
                .glassBackground(elevation: 1)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 2)
    }

    private var highlightsSection: some View {
        HighlightsSectionView(title: "Highlights", items: progressHighlights)
    }

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Training")
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

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Explore")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.md) {
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
                        refreshInsights()
                    }
                } catch {
                    print("Failed to load workout data: \(error)")
                }
            }
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
        default:
            return Theme.Colors.accent
        }
    }
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

private struct SummaryMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            Text(value)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(elevation: 2)
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
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                Text(formatValue(metric))
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .glassBackground(elevation: 1)
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
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Theme.Colors.surface.opacity(0.6))
                        .frame(height: 120)
                        .redacted(reason: .placeholder)
                }
            }
        }
    }
}
