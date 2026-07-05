import SwiftUI

struct HealthHubView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext

    @State private var timelineDensity: TimelineDensity = .all
    @State private var timelineSortOrder: DailyTimelineSortOrder = .newestFirst
    @State private var selectedMetric: HealthMetric?
    @State private var cachedDailyData: [DailyHealthData] = []
    @State private var cachedSummaryCards: [HealthSummaryCardModel] = []
    @State private var cachedTimelineRows: [DailyTimelineRowModel] = []
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

    private var timelinePresentation: DailyTimelinePresentation {
        DailyTimelinePresentation(rows: cachedTimelineRows, density: timelineDensity)
    }

    private var timelineSummaryText: String? {
        guard timelinePresentation.hasMore else { return nil }
        let dayLabel = timelinePresentation.totalCount == 1 ? "day" : "days"
        return "Showing \(timelinePresentation.visibleCount) of \(timelinePresentation.totalCount) \(dayLabel)"
    }

    private var canShowMoreTimeline: Bool {
        timelineDensity == .compact && cachedTimelineRows.count > DailyTimelineDisplayPolicy.compactCount
    }

    private var canShowAllTimeline: Bool {
        timelineDensity != .all && timelinePresentation.hasMore
    }

    private var canShowLessTimeline: Bool {
        timelineDensity != .compact && cachedTimelineRows.count > DailyTimelineDisplayPolicy.compactCount
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
                            if !cachedSummaryCards.isEmpty {
                                summarySection
                            }
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
            timelineDensity = .all
            refreshCachedContent()
        }
        .onChange(of: dateRangeContext.customRange) { _, _ in
            if dateRangeContext.selectedRange == .custom {
                timelineDensity = .all
                refreshCachedContent()
            }
        }
        .onChange(of: timelineSortOrder) { _, _ in
            refreshTimelineRows()
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

                timelineSortMenu

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
                ForEach(timelinePresentation.rows) { row in
                    NavigationLink {
                        DailyHealthDetailView(day: row.day)
                    } label: {
                        DailyTimelineRow(model: row)
                            .equatable()
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

    private var timelineSortMenu: some View {
        Menu {
            Picker("Timeline Sort", selection: $timelineSortOrder) {
                ForEach(DailyTimelineSortOrder.allCases) { order in
                    Label(order.title, systemImage: order.icon)
                        .tag(order)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)
                Text(timelineSortOrder.shortTitle)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(minHeight: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort daily timeline")
        .accessibilityValue(timelineSortOrder.title)
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

        var cards: [HealthSummaryCardModel] = []

        if let avgSteps {
            cards.append(
                HealthSummaryCardModel(
                    id: "avgSteps",
                    metric: .steps,
                    title: "Avg Steps",
                    value: "\(Int(avgSteps))",
                    unit: "steps",
                    icon: "figure.walk",
                    tint: Theme.Colors.warning
                )
            )
        }

        if let avgSleep {
            cards.append(
                HealthSummaryCardModel(
                    id: "avgSleep",
                    metric: .sleep,
                    title: "Avg Sleep",
                    value: String(format: "%.1f", avgSleep),
                    unit: "h",
                    icon: "moon.zzz.fill",
                    tint: Theme.Colors.accentSecondary
                )
            )
        }

        if let avgRestingHR {
            cards.append(
                HealthSummaryCardModel(
                    id: "avgRestingHr",
                    metric: .restingHeartRate,
                    title: "Resting HR",
                    value: "\(Int(avgRestingHR))",
                    unit: "bpm",
                    icon: "heart",
                    tint: Theme.Colors.error
                )
            )
        }

        if let avgHRV {
            cards.append(
                HealthSummaryCardModel(
                    id: "avgHrv",
                    metric: .heartRateVariability,
                    title: "Avg HRV",
                    value: "\(Int(avgHRV))",
                    unit: "ms",
                    icon: "waveform.path.ecg",
                    tint: Theme.Colors.accent
                )
            )
        }

        if let avgEnergy {
            cards.append(
                HealthSummaryCardModel(
                    id: "avgEnergy",
                    metric: .activeEnergy,
                    title: "Active Energy",
                    value: "\(Int(avgEnergy))",
                    unit: "cal",
                    icon: "flame.fill",
                    tint: Theme.Colors.warning
                )
            )
        }

        return cards
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
        refreshTimelineRows(from: filtered)
    }

    private func refreshTimelineRows(from dailyData: [DailyHealthData]? = nil) {
        let source = dailyData ?? cachedDailyData
        cachedTimelineRows = DailyTimelineRowModel.rows(from: source, sortOrder: timelineSortOrder)
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

enum TimelineDensity {
    case compact
    case expanded
    case all
}

enum DailyTimelineSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: return "Newest first"
        case .oldestFirst: return "Oldest first"
        }
    }

    var shortTitle: String {
        switch self {
        case .newestFirst: return "Newest"
        case .oldestFirst: return "Oldest"
        }
    }

    var icon: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        }
    }

    func sortedDays(_ days: [DailyHealthData]) -> [DailyHealthData] {
        switch self {
        case .newestFirst:
            return days.sorted { $0.dayStart > $1.dayStart }
        case .oldestFirst:
            return days.sorted { $0.dayStart < $1.dayStart }
        }
    }
}

enum DailyTimelineDisplayPolicy {
    static let compactCount = 12
    static let expandedCount = 28

    static func visibleCount(totalCount: Int, density: TimelineDensity) -> Int {
        switch density {
        case .compact:
            return min(totalCount, compactCount)
        case .expanded:
            return min(totalCount, expandedCount)
        case .all:
            return totalCount
        }
    }

    static func visibleItems<T>(from items: [T], density: TimelineDensity) -> [T] {
        Array(items.prefix(visibleCount(totalCount: items.count, density: density)))
    }
}

private struct DailyTimelinePresentation {
    let rows: [DailyTimelineRowModel]
    let totalCount: Int

    var visibleCount: Int {
        rows.count
    }

    var hasMore: Bool {
        visibleCount < totalCount
    }

    init(rows allRows: [DailyTimelineRowModel], density: TimelineDensity) {
        totalCount = allRows.count
        rows = DailyTimelineDisplayPolicy.visibleItems(from: allRows, density: density)
    }
}

private struct HealthSummaryCard: View {
    let model: HealthSummaryCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: model.icon)
                    .font(Theme.Iconography.medium)
                    .foregroundStyle(model.tint)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(model.tint.opacity(Theme.Opacity.subtleFill))
                    )
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
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.CornerRadius.large,
                topTrailingRadius: Theme.CornerRadius.large
            )
            .fill(model.tint)
            .frame(height: 3)
        }
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
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .fill(category.tint.opacity(Theme.Opacity.subtleFill))
                    )
                Spacer()

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption2Bold)
                    .foregroundStyle(Theme.Colors.textTertiary)
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

private struct DailyTimelineStatModel: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let unit: String
}

private struct DailyTimelineRowModel: Identifiable, Equatable {
    let id: Date
    let day: DailyHealthData
    let title: String
    let subtitle: String
    let dayNumber: String
    let monthAbbrev: String
    let isToday: Bool
    let stats: [DailyTimelineStatModel]

    static func rows(from days: [DailyHealthData], sortOrder: DailyTimelineSortOrder) -> [DailyTimelineRowModel] {
        sortOrder.sortedDays(days).map { day in
            DailyTimelineRowModel(day: day)
        }
    }

    init(day: DailyHealthData, calendar: Calendar = .current) {
        self.id = day.id
        self.day = day
        self.title = HealthHubFormatters.weekday.string(from: day.dayStart)
        if calendar.isDateInToday(day.dayStart) {
            self.subtitle = "Today"
        } else if calendar.isDateInYesterday(day.dayStart) {
            self.subtitle = "Yesterday"
        } else {
            self.subtitle = HealthHubFormatters.mediumDate.string(from: day.dayStart)
        }

        self.dayNumber = HealthHubFormatters.dayNumber.string(from: day.dayStart)
        self.monthAbbrev = HealthHubFormatters.monthAbbrev.string(from: day.dayStart).uppercased()
        self.isToday = calendar.isDateInToday(day.dayStart)
        self.stats = Self.makeStats(for: day)
    }

    private static func makeStats(for day: DailyHealthData) -> [DailyTimelineStatModel] {
        var items: [DailyTimelineStatModel] = []

        if let sleep = day.sleepSummary?.totalHours {
            items.append(
                DailyTimelineStatModel(
                    id: "sleep",
                    label: "Sleep",
                    value: String(format: "%.1f", sleep),
                    unit: "h"
                )
            )
        }

        if let steps = day.steps {
            items.append(
                DailyTimelineStatModel(
                    id: "steps",
                    label: "Steps",
                    value: "\(Int(steps))",
                    unit: ""
                )
            )
        }

        if let activeEnergy = day.activeEnergy {
            items.append(
                DailyTimelineStatModel(
                    id: "energy",
                    label: "Energy",
                    value: "\(Int(activeEnergy))",
                    unit: "cal"
                )
            )
        }

        if let restingHeartRate = day.restingHeartRate {
            items.append(
                DailyTimelineStatModel(
                    id: "resting",
                    label: "Resting",
                    value: "\(Int(restingHeartRate))",
                    unit: "bpm"
                )
            )
        }

        return items
    }

    static func == (lhs: DailyTimelineRowModel, rhs: DailyTimelineRowModel) -> Bool {
        lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.subtitle == rhs.subtitle &&
            lhs.dayNumber == rhs.dayNumber &&
            lhs.monthAbbrev == rhs.monthAbbrev &&
            lhs.isToday == rhs.isToday &&
            lhs.stats == rhs.stats
    }
}

private struct DailyTimelineRow: View, Equatable {
    let model: DailyTimelineRowModel

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            // Date badge
            VStack(spacing: 1) {
                Text(model.monthAbbrev)
                    .font(Theme.Typography.microLabel)
                    .foregroundStyle(model.isToday ? .white : Theme.Colors.textTertiary)
                Text(model.dayNumber)
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(model.isToday ? .white : Theme.Colors.textPrimary)
            }
            .frame(width: 42, height: 42)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .fill(model.isToday ? Theme.Colors.accent : Theme.Colors.accent.opacity(Theme.Opacity.subtleFill))
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.title)
                            .font(Theme.Typography.subheadlineBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(model.subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption2Bold)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                if model.stats.isEmpty {
                    Text("No key metrics recorded for this day.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(model.stats) { stat in
                                DailyTimelineStat(label: stat.label, value: stat.value, unit: stat.unit)
                            }
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                            ForEach(model.stats) { stat in
                                DailyTimelineStat(label: stat.label, value: stat.value, unit: stat.unit)
                            }
                        }
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

    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    static let monthAbbrev: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
}

private struct DailyTimelineStat: View {
    let label: String
    let value: String
    let unit: String

    private var statColor: Color {
        switch label {
        case "Sleep": return Theme.Colors.accentTertiary
        case "Steps": return Theme.Colors.success
        case "Energy": return Theme.Colors.accentSecondary
        case "Resting": return Theme.Colors.error
        default: return Theme.Colors.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(statColor)
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
        .padding(.vertical, 6)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .fill(statColor.opacity(0.04))
        )
    }
}
