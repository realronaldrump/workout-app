import SwiftUI

struct HealthHubView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext

    @State private var showingHealthWizard = false
    @State private var timelineDensity: TimelineDensity = .compact
    @State private var selectedMetric: HealthMetric?
    @State private var cachedDailyData: [DailyHealthData] = []
    @State private var cachedSummaryCards: [HealthSummaryCardModel] = []

    private var earliestDate: Date? {
        healthManager.dailyHealthStore.keys.min()
    }

    private var currentRange: DateInterval {
        dateRangeContext.resolvedRange(earliest: earliestDate)
    }

    private var rangeLabel: String {
        dateRangeContext.rangeLabel(earliest: earliestDate)
    }

    private var timelinePresentation: TimelinePresentation {
        let sorted = cachedDailyData.sorted { $0.dayStart > $1.dayStart }
        return TimelinePresentation(days: sorted, density: timelineDensity)
    }

    private var timelineSummaryText: String? {
        guard timelinePresentation.isSampled else { return nil }

        let cadence = timelinePresentation.samplingStep == 7
            ? "Showing weekly checkpoints"
            : "Showing roughly every \(timelinePresentation.samplingStep) days"
        let hiddenDates = timelinePresentation.hiddenCount == 1 ? "1 date hidden" : "\(timelinePresentation.hiddenCount) dates hidden"
        return "\(cadence) across \(timelinePresentation.totalCount) days • \(hiddenDates)"
    }

    private var canShowMoreTimeline: Bool {
        timelineDensity == .compact && cachedDailyData.count > TimelinePresentation.expandedTargetCount
    }

    private var canShowAllTimeline: Bool {
        timelineDensity != .all && timelinePresentation.isSampled
    }

    private var canShowLessTimeline: Bool {
        timelineDensity != .compact && cachedDailyData.count > TimelinePresentation.compactTargetCount
    }

    private var headerSubtitle: String {
        let dayCount = cachedDailyData.count
        let countLabel = dayCount == 1 ? "1 day" : "\(dayCount) days"
        return "\(rangeLabel) • \(countLabel)"
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    headerSection

                    timeRangeSection

                    if healthManager.authorizationStatus == .unavailable {
                        unavailableCard
                    } else if healthManager.authorizationStatus != .authorized {
                        accessCard
                    } else {
                        categorySection

                        if cachedDailyData.isEmpty {
                            emptyState
                        } else {
                            summarySection
                            dailyTimelineSection
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(item: $selectedMetric) { metric in
            HealthMetricDetailView(metric: metric)
        }
        .sheet(isPresented: $showingHealthWizard) {
            HealthSyncWizard(
                isPresented: $showingHealthWizard,
                workouts: dataManager.workouts
            )
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            refreshCachedContent()
            triggerDailySync(force: false)
        }
        .onChange(of: dateRangeContext.selectedRange) { _, _ in
            timelineDensity = .compact
            refreshCachedContent()
            triggerDailySync(force: false)
        }
        .onChange(of: dateRangeContext.customRange) { _, _ in
            if dateRangeContext.selectedRange == .custom {
                timelineDensity = .compact
                refreshCachedContent()
                triggerDailySync(force: false)
            }
        }
        .onChange(of: healthManager.authorizationStatus) { _, newValue in
            if newValue == .authorized {
                triggerDailySync(force: false)
            }
        }
        .onReceive(healthManager.$dailyHealthStore) { _ in
            refreshCachedContent()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Health")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.5)

                    Text(headerSubtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Button {
                    triggerDailySync(force: true)
                } label: {
                    Group {
                        if healthManager.isDailySyncing {
                            ProgressView(value: healthManager.dailySyncProgress)
                                .progressViewStyle(CircularProgressViewStyle())
                                .tint(Theme.Colors.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(Theme.Typography.bodyStrong)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Theme.Colors.surfaceRaised)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.Colors.border.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    healthManager.authorizationStatus != .authorized || healthManager.isDailySyncing
                )
                .accessibilityLabel("Refresh health data")
            }

            if let lastSync = healthManager.lastDailySyncDate {
                Text("Last sync \(formatSyncDate(lastSync))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var timeRangeSection: some View {
        HealthDateRangeSection(earliestDate: earliestDate)
            .padding(.horizontal, Theme.Spacing.xs)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Overview")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(cachedSummaryCards) { card in
                        MetricTileButton(
                            action: {
                                selectedMetric = card.metric
                            },
                            content: {
                                HealthSummaryCard(model: card)
                            }
                        )
                    }
                }
            }
        }
    }

    private var dailyTimelineSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Daily Timeline")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(1.0)

                Spacer()

                if canShowLessTimeline {
                    Button("Show Less") {
                        withAnimation(Theme.Animation.smooth) {
                            timelineDensity = .compact
                        }
                    }
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.accent)
                    .textCase(.uppercase)
                    .tracking(0.8)
                }
            }

            if let timelineSummaryText {
                Text(timelineSummaryText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            VStack(spacing: Theme.Spacing.md) {
                ForEach(timelinePresentation.days) { day in
                    NavigationLink {
                        DailyHealthDetailView(day: day)
                    } label: {
                        DailyTimelineRow(day: day)
                    }
                    .buttonStyle(.plain)
                }
            }

            if canShowMoreTimeline || canShowAllTimeline {
                HStack(spacing: Theme.Spacing.md) {
                    if canShowMoreTimeline {
                        Button("Show More") {
                            withAnimation(Theme.Animation.smooth) {
                                timelineDensity = .expanded
                            }
                        }
                    }

                    if canShowAllTimeline {
                        Button("Show All") {
                            withAnimation(Theme.Animation.smooth) {
                                timelineDensity = .all
                            }
                        }
                    }
                }
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.accent)
                .textCase(.uppercase)
                .tracking(0.8)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Explore Health")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                ForEach(HealthHubCategory.allCases) { category in
                    NavigationLink {
                        if category == .sessions {
                            HealthDashboardView()
                        } else if category == .body {
                            BodyCompositionView()
                        } else {
                            HealthCategoryDetailView(category: category)
                        }
                    } label: {
                        HealthCategoryCard(category: category)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Connect Apple Health")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Allow access to view daily activity, sleep, vitals, and recovery metrics.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                showingHealthWizard = true
            } label: {
                Text("Connect Health")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.elevated)
                    .cornerRadius(Theme.CornerRadius.large)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Health Data Unavailable")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Apple Health isn’t available on this device.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No health data yet")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Sync Apple Health to see daily activity, sleep, vitals, and recovery trends.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                triggerDailySync(force: true)
            } label: {
                Text("Sync Now")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.elevated)
                    .cornerRadius(Theme.CornerRadius.large)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    private func buildSummaryCards(from dailyData: [DailyHealthData]) -> [HealthSummaryCardModel] {
        let avgSteps = average(dailyData.compactMap { $0.steps })
        let avgSleep = average(dailyData.compactMap { $0.sleepSummary?.totalHours })
        let avgRestingHR = average(dailyData.compactMap { $0.restingHeartRate })
        let avgHRV = average(dailyData.compactMap { $0.heartRateVariability })
        let avgEnergy = average(dailyData.compactMap { $0.activeEnergy })

        return [
            HealthSummaryCardModel(
                id: "avgSteps",
                metric: .steps,
                title: "Avg Steps",
                value: avgSteps.map { "\(Int($0))" } ?? "--",
                unit: "steps",
                icon: "figure.walk",
                tint: Theme.Colors.warning
            ),
            HealthSummaryCardModel(
                id: "avgSleep",
                metric: .sleep,
                title: "Avg Sleep",
                value: avgSleep.map { String(format: "%.1f", $0) } ?? "--",
                unit: "h",
                icon: "moon.zzz.fill",
                tint: Theme.Colors.accentSecondary
            ),
            HealthSummaryCardModel(
                id: "avgRestingHr",
                metric: .restingHeartRate,
                title: "Resting HR",
                value: avgRestingHR.map { "\(Int($0))" } ?? "--",
                unit: "bpm",
                icon: "heart",
                tint: Theme.Colors.error
            ),
            HealthSummaryCardModel(
                id: "avgHrv",
                metric: .heartRateVariability,
                title: "Avg HRV",
                value: avgHRV.map { "\(Int($0))" } ?? "--",
                unit: "ms",
                icon: "waveform.path.ecg",
                tint: Theme.Colors.accent
            ),
            HealthSummaryCardModel(
                id: "avgEnergy",
                metric: .activeEnergy,
                title: "Active Energy",
                value: avgEnergy.map { "\(Int($0))" } ?? "--",
                unit: "cal",
                icon: "flame.fill",
                tint: Theme.Colors.warning
            )
        ]
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func formatSyncDate(_ date: Date) -> String {
        HealthHubFormatters.mediumDateTime.string(from: date)
    }

    private func triggerDailySync(force: Bool) {
        guard healthManager.authorizationStatus == .authorized else { return }
        guard !healthManager.isDailySyncing else { return }

        Task {
            if force {
                try? await healthManager.syncDailyHealthData(range: currentRange)
            } else {
                await healthManager.ensureDailyHealthData(range: currentRange)
            }
        }
    }

    private func refreshCachedContent() {
        let filtered = healthManager.dailyHealthStore.values
            .filter { currentRange.contains($0.dayStart) }
            .sorted { $0.dayStart < $1.dayStart }
        cachedDailyData = filtered
        cachedSummaryCards = buildSummaryCards(from: filtered)
    }
}

private struct HealthSummaryCardModel: Identifiable {
    let id: String
    let metric: HealthMetric
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color
}

private enum TimelineDensity {
    case compact
    case expanded
    case all
}

enum TimelineSampling {
    static func sampledIndices(totalCount: Int, targetCount: Int) -> [Int] {
        guard totalCount > 0 else { return [] }
        guard targetCount > 1, totalCount > targetCount else {
            return Array(0..<totalCount)
        }

        let desiredCount = min(totalCount, targetCount)
        var indices: [Int] = []
        indices.reserveCapacity(desiredCount)

        for sampleIndex in 0..<desiredCount {
            let progress = Double(sampleIndex) / Double(desiredCount - 1)
            let resolvedIndex = Int((progress * Double(totalCount - 1)).rounded())
            if indices.last != resolvedIndex {
                indices.append(resolvedIndex)
            }
        }

        if indices.last != totalCount - 1 {
            indices.append(totalCount - 1)
        }

        return indices
    }

    static func approximateStep(totalCount: Int, displayedCount: Int) -> Int {
        guard displayedCount > 1, totalCount > displayedCount else { return 1 }
        return max(1, Int(round(Double(totalCount - 1) / Double(displayedCount - 1))))
    }
}

private struct TimelinePresentation {
    static let compactTargetCount = 12
    static let expandedTargetCount = 28

    let days: [DailyHealthData]
    let totalCount: Int
    let samplingStep: Int

    var isSampled: Bool {
        samplingStep > 1
    }

    var hiddenCount: Int {
        max(totalCount - days.count, 0)
    }

    init(days allDays: [DailyHealthData], density: TimelineDensity) {
        totalCount = allDays.count

        switch density {
        case .compact:
            let sampled = Self.sample(allDays, targetCount: Self.compactTargetCount)
            days = sampled.days
            samplingStep = sampled.step
        case .expanded:
            let sampled = Self.sample(allDays, targetCount: Self.expandedTargetCount)
            days = sampled.days
            samplingStep = sampled.step
        case .all:
            days = allDays
            samplingStep = 1
        }
    }

    private static func sample(_ days: [DailyHealthData], targetCount: Int) -> (days: [DailyHealthData], step: Int) {
        guard days.count > targetCount, targetCount > 1 else {
            return (days, 1)
        }

        let sampledIndices = TimelineSampling.sampledIndices(
            totalCount: days.count,
            targetCount: targetCount
        )
        let sampledDays = sampledIndices.map { days[$0] }
        let samplingStep = TimelineSampling.approximateStep(
            totalCount: days.count,
            displayedCount: sampledDays.count
        )
        return (sampledDays, samplingStep)
    }
}

private struct HealthSummaryCard: View {
    let model: HealthSummaryCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: model.icon)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(model.tint)
                Text(model.title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(model.value)
                    .font(Theme.Typography.number)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(model.unit)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(width: 160, alignment: .leading)
        .softCard(elevation: 1)
    }
}

private struct HealthCategoryCard: View {
    let category: HealthHubCategory

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: category.icon)
                    .font(Theme.Iconography.title3)
                    .foregroundStyle(category.tint)
                Spacer()
            }

            Text(category.title)
                .font(Theme.Typography.cardHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(category.subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

private struct DailyTimelineRow: View {
    let day: DailyHealthData

    private var title: String {
        HealthHubFormatters.weekday.string(from: day.dayStart)
    }

    private var subtitle: String {
        if Calendar.current.isDateInToday(day.dayStart) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(day.dayStart) {
            return "Yesterday"
        }
        return HealthHubFormatters.mediumDate.string(from: day.dayStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    DailyTimelineStat(label: "Sleep", value: day.sleepSummary.map { String(format: "%.1f", $0.totalHours) } ?? "--", unit: "h")
                    DailyTimelineStat(label: "Steps", value: day.steps.map { "\(Int($0))" } ?? "--", unit: "")
                    DailyTimelineStat(label: "Energy", value: day.activeEnergy.map { "\(Int($0))" } ?? "--", unit: "cal")
                    DailyTimelineStat(label: "Resting", value: day.restingHeartRate.map { "\(Int($0))" } ?? "--", unit: "bpm")
                }

                VStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        DailyTimelineStat(label: "Sleep", value: day.sleepSummary.map { String(format: "%.1f", $0.totalHours) } ?? "--", unit: "h")
                        DailyTimelineStat(label: "Steps", value: day.steps.map { "\(Int($0))" } ?? "--", unit: "")
                    }
                    HStack(spacing: Theme.Spacing.md) {
                        DailyTimelineStat(label: "Energy", value: day.activeEnergy.map { "\(Int($0))" } ?? "--", unit: "cal")
                        DailyTimelineStat(label: "Resting", value: day.restingHeartRate.map { "\(Int($0))" } ?? "--", unit: "bpm")
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

private enum HealthHubFormatters {
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let mediumDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

private struct DailyTimelineStat: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
