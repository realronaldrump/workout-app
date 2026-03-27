import SwiftUI

struct HealthHubView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext

    @State private var timelineDensity: TimelineDensity = .compact
    @State private var selectedMetric: HealthMetric?
    @State private var cachedDailyData: [DailyHealthData] = []
    @State private var cachedSummaryCards: [HealthSummaryCardModel] = []
    @State private var isCatchUpSyncing = false

    private var earliestDate: Date? {
        healthManager.dailyHealthStore.keys.min()
    }

    private var currentRange: DateInterval {
        dateRangeContext.resolvedRange(earliest: earliestDate)
    }

    private var rangeLabel: String {
        dateRangeContext.rangeLabel(earliest: earliestDate)
    }

    private var timelineSourceDays: [DailyHealthData] {
        DailyTimelineRangePolicy.displayedDays(
            from: cachedDailyData,
            selectedRange: dateRangeContext.selectedRange,
            range: currentRange
        )
    }

    private var timelineUsesRecentWindow: Bool {
        DailyTimelineRangePolicy.shouldLimitTimeline(
            selectedRange: dateRangeContext.selectedRange,
            range: currentRange
        )
    }

    private var timelinePresentation: TimelinePresentation {
        let sorted = timelineSourceDays.sorted { $0.dayStart > $1.dayStart }
        return TimelinePresentation(days: sorted, density: timelineDensity)
    }

    private var timelineSummaryText: String? {
        var segments: [String] = []

        if timelineUsesRecentWindow {
            segments.append("Latest \(DailyTimelineRangePolicy.recentWindowDays) days of daily entries")
        }

        if timelinePresentation.isSampled {
            let cadence = timelinePresentation.samplingStep == 7
                ? "Showing weekly checkpoints"
                : "Showing roughly every \(timelinePresentation.samplingStep) days"
            let hiddenDates = timelinePresentation.hiddenCount == 1 ? "1 date hidden" : "\(timelinePresentation.hiddenCount) dates hidden"
            segments.append("\(cadence) across \(timelinePresentation.totalCount) days")
            segments.append(hiddenDates)
        }

        guard !segments.isEmpty else { return nil }
        return segments.joined(separator: " • ")
    }

    private var canShowMoreTimeline: Bool {
        timelineDensity == .compact && timelineSourceDays.count > TimelinePresentation.expandedTargetCount
    }

    private var canShowAllTimeline: Bool {
        timelineDensity != .all && timelinePresentation.isSampled
    }

    private var canShowLessTimeline: Bool {
        timelineDensity != .compact && timelineSourceDays.count > TimelinePresentation.compactTargetCount
    }

    private var headerSubtitle: String {
        let dayCount = cachedDailyData.count
        let countLabel = dayCount == 1 ? "1 day with data" : "\(dayCount) days with data"
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
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            refreshCachedContent()
        }
        .task {
            await catchUpRecentHealthData()
        }
        .onChange(of: dateRangeContext.selectedRange) { _, _ in
            timelineDensity = .compact
            refreshCachedContent()
        }
        .onChange(of: dateRangeContext.customRange) { _, _ in
            if dateRangeContext.selectedRange == .custom {
                timelineDensity = .compact
                refreshCachedContent()
            }
        }
        .onReceive(healthManager.$dailyHealthStore) { _ in
            refreshCachedContent()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Health")
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(1.5)

                Text(headerSubtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if healthManager.authorizationStatus == .authorized {
                syncStatusRow
            }
        }
    }

    private var syncStatusRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if isCatchUpSyncing || healthManager.isDailySyncing {
                ProgressView()
                    .controlSize(.mini)
                Text("Syncing…")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else if let lastSync = healthManager.lastDailySyncDate {
                Text("Last sync \(formatSyncDate(lastSync))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)

                Button {
                    Task { await catchUpRecentHealthData(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.accent)
                }
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

            LazyVStack(spacing: Theme.Spacing.md) {
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

            Text("View daily activity, sleep, vitals, and recovery metrics by connecting Apple Health.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                Task { await connectAndSync() }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "heart.fill")
                    Text("Connect")
                        .tracking(0.8)
                }
                .font(Theme.Typography.metricLabel)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.background)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
            }
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

            Text("Sync recent Apple Health data to see daily activity, sleep, vitals, and recovery trends.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                Task { await catchUpRecentHealthData(force: true) }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                        .tracking(0.8)
                }
                .font(Theme.Typography.metricLabel)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.accent)
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    private func connectAndSync() async {
        do {
            try await healthManager.requestAuthorization()
        } catch {
            return
        }
        guard healthManager.authorizationStatus == .authorized else { return }
        await catchUpRecentHealthData(force: true)
    }

    private func catchUpRecentHealthData(force: Bool = false) async {
        guard healthManager.authorizationStatus == .authorized else { return }
        guard !isCatchUpSyncing, !healthManager.isDailySyncing else { return }

        let calendar = Calendar.current
        let now = Date()

        // Determine how far back to sync: since last sync or last 7 days, whichever is shorter
        let defaultLookback = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let syncStart: Date
        if let lastSync = healthManager.lastDailySyncDate, !force {
            // Sync from the day before last sync to catch any late-arriving data
            syncStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: lastSync) ?? lastSync)
        } else {
            syncStart = calendar.startOfDay(for: defaultLookback)
        }

        let syncEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        guard syncStart < syncEnd else { return }

        let range = DateInterval(start: syncStart, end: syncEnd)

        isCatchUpSyncing = true
        defer { isCatchUpSyncing = false }

        do {
            try await healthManager.syncDailyHealthData(range: range)
        } catch {
            // Silently fail — this is a background convenience sync
        }
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

enum DailyTimelineRangePolicy {
    static let recentWindowDays = 90
    static let longRangeThresholdDays = 366

    static func shouldLimitTimeline(
        selectedRange: AppTimeRange,
        range: DateInterval
    ) -> Bool {
        selectedRange == .allTime || range.duration > TimeInterval(longRangeThresholdDays * 24 * 60 * 60)
    }

    static func displayedDays(
        from days: [DailyHealthData],
        selectedRange: AppTimeRange,
        range: DateInterval,
        calendar: Calendar = .current
    ) -> [DailyHealthData] {
        let sortedDays = days.sorted { $0.dayStart < $1.dayStart }
        guard shouldLimitTimeline(selectedRange: selectedRange, range: range) else {
            return sortedDays
        }

        let cutoffReference = calendar.date(byAdding: .day, value: -(recentWindowDays - 1), to: range.end) ?? range.start
        let cutoff = max(calendar.startOfDay(for: cutoffReference), calendar.startOfDay(for: range.start))
        return sortedDays.filter { $0.dayStart >= cutoff }
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
