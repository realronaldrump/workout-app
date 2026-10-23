import Combine
import SwiftUI

struct HealthHubView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var healthManager: HealthViewStore
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext
    @EnvironmentObject private var bodyStore: BodyStore

    @State private var timelineDensity: TimelineDensity = .compact
    @State private var timelineSortOrder: DailyTimelineSortOrder = .newestFirst
    @State private var selectedMetric: HealthMetric?
    @State private var cachedDailyData: [DailyHealthData] = []
    @State private var cachedSummaryCards: [HealthSummaryCardModel] = []
    @State private var cachedTimelineRows: [DailyTimelineRowModel] = []
    @State private var isCatchUpSyncing = false
    @State private var operationError: String?

    private var earliestDate: Date? {
        healthManager.dailySnapshot.earliestDate
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
        let countLabel = dayCount == 1 ? "1 day of data" : "\(dayCount) days of data"
        return "\(rangeLabel). \(countLabel)."
    }

    private var headlineInsight: String? {
        guard let card = cachedSummaryCards
            .filter({ $0.delta != nil })
            .max(by: {
                abs($0.delta?.percentChange ?? 0) < abs($1.delta?.percentChange ?? 0)
            }),
            let delta = card.delta else { return nil }
        let change = Int(abs(delta.percentChange).rounded())
        let unit = card.unit.isEmpty ? "" : " \(card.unit)"
        let comparison = delta.isFlat
            ? "level with the prior period"
            : "\(change)% \(delta.percentChange > 0 ? "higher" : "lower") than the prior period"
        return "Biggest change: \(card.metric.narrativeNoun) averaged \(card.value)\(unit), \(comparison)."
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    if healthManager.authorizationStatus == .unavailable {
                        unavailableCard
                    } else if healthManager.authorizationStatus != .authorized {
                        accessCard
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            timeRangeSection
                            headerSection
                        }

                        if let error = operationError ?? healthManager.syncError {
                            syncErrorCard(error)
                        }

                        if cachedDailyData.isEmpty {
                            emptyState
                        } else {
                            if !cachedSummaryCards.isEmpty {
                                summarySection
                            }
                        }

                        categorySection

                        if !cachedDailyData.isEmpty {
                            dailyTimelineSection
                        }
                    }
                }
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Layout.screenGutter)
                .contentColumn()
            }
        }
        .refreshable {
            await catchUpRecentHealthData(force: true)
        }
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedMetric) { metric in
            HealthMetricDetailView(metric: metric)
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            refreshCachedContent()
            if !bodyStore.hasLoaded { bodyStore.refresh(from: healthManager) }
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
        .onChange(of: healthManager.dailyDataRevision) { _, _ in
            refreshCachedContent()
        }
        .onChange(of: timelineSortOrder) { _, _ in
            refreshTimelineRows()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headerSubtitle)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            syncStatusRow
        }
    }

    private var syncStatusRow: some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))) {
            syncStatusContent
        }
    }

    @ViewBuilder
    private var syncStatusContent: some View {
        if isCatchUpSyncing || healthManager.isDailySyncing {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Syncing recent Health data")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(minHeight: Theme.Layout.minimumTapTarget)
        } else {
            if let lastSync = healthManager.lastDailySyncDate {
                Text("Synced \(formatSyncDate(lastSync))")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await catchUpRecentHealthData(force: true) }
            } label: {
                TextLinkLabel(title: "Sync now", showsChevron: false)
                    .underline()
            }
            .buttonStyle(.plain)
        }
    }

    private var timeRangeSection: some View {
        HealthDateRangeSection(earliestDate: earliestDate, showsResolvedLabel: false)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(title: "Readings", subtitle: "Daily averages for the range")

            if let headlineInsight {
                Text(headlineInsight)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Theme.Spacing.xs)
            }

            VStack(spacing: 0) {
                ForEach(Array(cachedSummaryCards.enumerated()), id: \.element.id) { index, card in
                    Button {
                        Haptics.selection()
                        selectedMetric = card.metric
                    } label: {
                        HealthReadingRow(model: card, showsRule: index > 0 || headlineInsight != nil)
                    }
                    .buttonStyle(PressableCardButtonStyle())
                    .accessibilityIdentifier("health-summary-\(card.metric.rawValue)")
                }
            }
        }
    }

    private var dailyTimelineSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(title: "Day by day", subtitle: timelineSummaryText) {
                timelineSortMenu
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(timelinePresentation.rows.enumerated()), id: \.element.id) { index, row in
                    NavigationLink {
                        DailyHealthDetailView(day: row.day)
                    } label: {
                        DailyTimelineRow(model: row, showsRule: index > 0)
                            .equatable()
                    }
                    .buttonStyle(PressableCardButtonStyle())
                }
            }

            if canShowMoreTimeline || canShowAllTimeline || canShowLessTimeline {
                HStack(spacing: Theme.Spacing.sm) {
                    if canShowMoreTimeline {
                        AppPillButton(title: "Show more") {
                            withAnimation(reduceMotion ? nil : Theme.Animation.smooth) {
                                timelineDensity = .expanded
                            }
                        }
                    }

                    if canShowAllTimeline {
                        AppPillButton(title: "Show all") {
                            withAnimation(reduceMotion ? nil : Theme.Animation.smooth) {
                                timelineDensity = .all
                            }
                        }
                    }

                    if canShowLessTimeline {
                        AppPillButton(title: "Show less", variant: .subtle) {
                            withAnimation(reduceMotion ? nil : Theme.Animation.smooth) {
                                timelineDensity = .compact
                            }
                        }
                    }
                }
                .padding(.top, Theme.Spacing.sm)
            }
        }
    }

    private var timelineSortMenu: some View {
        Menu {
            Picker("Timeline sort", selection: $timelineSortOrder) {
                ForEach(DailyTimelineSortOrder.allCases) { order in
                    Label(order.title, systemImage: order.icon)
                        .tag(order)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(timelineSortOrder.shortTitle)
                    .font(Theme.Typography.subheadlineStrong)
                Image(systemName: "chevron.up.chevron.down")
                    .font(Theme.Typography.microLabel)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort daily timeline")
        .accessibilityValue(timelineSortOrder.title)
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(title: "Categories")

            VStack(spacing: 0) {
                ForEach(Array(HealthHubCategory.allCases.enumerated()), id: \.element.id) { index, category in
                    NavigationLink {
                        if category == .sessions {
                            HealthDashboardView()
                        } else if category == .body {
                            BodyView()
                        } else {
                            HealthCategoryDetailView(category: category)
                        }
                    } label: {
                        HealthCategoryRow(
                            category: category,
                            value: category == .body ? bodyStore.weight.latest.map { BodyFormat.weight($0.trend) } : nil,
                            showsRule: index > 0
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())
                    .accessibilityIdentifier("health-category-\(category.rawValue)")
                }
            }
        }
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(healthManager.authorizationStatus == .denied ? "Health access is off." : "Apple Health isn't connected.")
                    .font(Theme.Typography.displayHeroCompact)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(accessDescription)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if healthManager.authorizationStatus == .denied {
                AppPrimaryButton(title: "Open Settings", systemImage: "gear") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }

                Button {
                    Task { await connectAndSync() }
                } label: {
                    Text("Request access again")
                        .font(Theme.Typography.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(BrandSecondaryButtonStyle())
            } else {
                AppPrimaryButton(
                    title: dynamicTypeSize.isAccessibilitySize ? "Connect Health" : "Connect Apple Health"
                ) {
                    Task { await connectAndSync() }
                }
            }
        }
        .padding(.top, Theme.Spacing.lg)
    }

    private var accessDescription: String {
        if healthManager.authorizationStatus == .denied {
            return dynamicTypeSize.isAccessibilitySize
                ? "Review this app’s Health permissions in Settings, then try again."
                : "Health access couldn’t be completed. Review this app’s permissions in Settings, then try again."
        }

        return dynamicTypeSize.isAccessibilitySize
            ? "See sleep, heart, and body trends next to your training. Your data stays on device."
            : "See sleep, heart, activity, and body trends next to your training. Your Health data stays on your devices."
    }

    private var unavailableCard: some View {
        EmptyStateCard(
            title: "Apple Health isn't available here",
            message: "This device doesn't support Apple Health, so sleep, heart, and body readings can't appear."
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(healthManager.dailyHealthStore.isEmpty ? "No readings yet" : "No readings in this range")
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(healthManager.dailyHealthStore.isEmpty
                 ? "Sync Apple Health to see daily activity, sleep, vitals, and recovery. Only data you allow appears."
                 : "Your saved Health data falls outside these dates. View all time or pick another range.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AppPillButton(
                title: healthManager.dailyHealthStore.isEmpty ? "Sync now" : "View all time",
                systemImage: healthManager.dailyHealthStore.isEmpty ? "arrow.clockwise" : "calendar",
                variant: .accent
            ) {
                if healthManager.dailyHealthStore.isEmpty {
                    Task { await catchUpRecentHealthData(force: true) }
                } else {
                    dateRangeContext.selectedRange = .allTime
                }
            }
            .disabled(isCatchUpSyncing || healthManager.isDailySyncing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .softCard()
    }

    private func connectAndSync() async {
        operationError = nil
        do {
            try await healthManager.requestAuthorization()
        } catch {
            operationError = error.localizedDescription
            return
        }
        guard healthManager.authorizationStatus == .authorized else { return }
        await catchUpRecentHealthData(force: true)
    }

    private func catchUpRecentHealthData(force: Bool = false) async {
#if DEBUG
        guard !AnalyticsUITestFixture.isEnabled else { return }
#endif
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
            operationError = error.localizedDescription
        }
    }

    private func syncErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Health sync stopped")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.error)

            Text(message)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.sm) {
                AppPillButton(title: "Try again", systemImage: "arrow.clockwise", variant: .accent) {
                    operationError = nil
                    healthManager.clearSyncError()
                    Task { await catchUpRecentHealthData(force: true) }
                }

                AppPillButton(title: "Dismiss", variant: .subtle) {
                    operationError = nil
                    healthManager.clearSyncError()
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedSection(Theme.Colors.error)
    }

    private func buildSummaryCards(
        from comparisonData: [DailyHealthData],
        fallbackData: [DailyHealthData],
        previousData: [DailyHealthData]
    ) -> [HealthSummaryCardModel] {
        // Tints come from the metric so a card here matches the same metric's detail
        // screen. Hardcoding them meant sleep read orange on this screen and violet on
        // its own.
        let configurations: [HealthSummaryConfiguration] = [
            HealthSummaryConfiguration(metric: .sleep, title: "Sleep", tint: HealthMetric.sleep.accentColor, higherIsBetter: true),
            HealthSummaryConfiguration(metric: .restingHeartRate, title: "Resting heart rate", tint: HealthMetric.restingHeartRate.accentColor, higherIsBetter: false),
            HealthSummaryConfiguration(metric: .heartRateVariability, title: "HRV", tint: HealthMetric.heartRateVariability.accentColor, higherIsBetter: true),
            HealthSummaryConfiguration(metric: .steps, title: "Steps", tint: HealthMetric.steps.accentColor, higherIsBetter: true),
            HealthSummaryConfiguration(metric: .activeEnergy, title: "Active energy", tint: HealthMetric.activeEnergy.accentColor, higherIsBetter: true)
        ]

        return configurations.compactMap { configuration in
            let metric = configuration.metric
            let comparisonValues = comparisonData.compactMap { $0.value(for: metric) }
            let usesFallback = comparisonValues.isEmpty
            let values = usesFallback
                ? fallbackData.compactMap { $0.value(for: metric) }
                : comparisonValues
            guard let currentAverage = average(values) else { return nil }
            let previousAverage = usesFallback
                ? nil
                : average(previousData.compactMap { $0.value(for: metric) })
            return HealthSummaryCardModel(
                id: metric.id,
                metric: metric,
                title: configuration.title,
                value: metric.format(currentAverage),
                unit: metric.displayUnit,
                icon: metric.icon,
                tint: configuration.tint,
                average: currentAverage,
                delta: previousAverage.flatMap {
                    TrendDelta(
                        current: currentAverage,
                        previous: $0,
                        higherIsBetter: configuration.higherIsBetter
                    )
                },
                sparklineValues: values
            )
        }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func formatSyncDate(_ date: Date) -> String {
        HealthHubFormatters.mediumDateTime.string(from: date)
    }

    private func refreshCachedContent() {
        let snapshot = healthManager.dailySnapshot
        let resolvedRange = dateRangeContext.resolvedRange(earliest: snapshot.earliestDate)
        let ranges = HealthDayComparisonRanges(
            resolvedRange: resolvedRange,
            comparesPreviousPeriod: dateRangeContext.selectedRange != .allTime
        )
        // The shared index already orders the cache. A one-week selection now
        // visits only those days instead of sorting and normalizing all history.
        let filtered = Array(snapshot.days(in: ranges.display))
        let currentComparison = ranges.currentComparison.map { Array(snapshot.days(in: $0)) } ?? []
        let previous = ranges.previousComparison.map { Array(snapshot.days(in: $0)) } ?? []
        cachedDailyData = filtered
        cachedSummaryCards = buildSummaryCards(
            from: currentComparison,
            fallbackData: filtered,
            previousData: previous
        )
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
    let average: Double
    let delta: TrendDelta?
    let sparklineValues: [Double]
}

private struct HealthSummaryConfiguration {
    let metric: HealthMetric
    let title: String
    let tint: Color
    let higherIsBetter: Bool
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

/// One reading on the board: its name and change on the left, the period's shape in
/// its own hue, and the average at poster scale on the right.
private struct HealthReadingRow: View {
    let model: HealthSummaryCardModel
    var showsRule = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.md))
        layout {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Theme.Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(model.tint)
                        .frame(width: 4, height: 16)
                        .accessibilityHidden(true)
                    Text(model.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                }
                if let delta = model.delta {
                    DeltaTag(delta: delta, suffix: "vs prior")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize {
                Sparkline(values: model.sparklineValues, tint: model.tint, areaFill: false)
                    .frame(width: 72, height: 30)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(model.value)
                    .font(Theme.Typography.number)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(model.unit)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(minWidth: 96, alignment: .trailing)
        }
        .ledgerRow(showsRule: showsRule)
        .accessibilityElement(children: .combine)
    }
}

/// A Health category in the index: its name in the display face and what it holds.
private struct HealthCategoryRow: View {
    let category: HealthHubCategory
    /// A live reading shown at the trailing edge, such as trend weight on the Body row.
    var value: String?
    var showsRule = true

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(category.tint)
                .frame(width: 4, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(Theme.Typography.cardHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(category.subtitle)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.sm)

            if let value {
                Text(value)
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            Image(systemName: "chevron.right")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .ledgerRow(showsRule: showsRule)
        .accessibilityElement(children: .combine)
    }
}

private struct DailyTimelineStatModel: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
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
        self.monthAbbrev = HealthHubFormatters.monthAbbrev.string(from: day.dayStart)
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
                    icon: "moon.zzz.fill",
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
                    icon: "figure.walk",
                    value: Int(steps).formatted(),
                    unit: "steps"
                )
            )
        }

        if let activeEnergy = day.activeEnergy {
            items.append(
                DailyTimelineStatModel(
                    id: "energy",
                    label: "Energy",
                    icon: "flame.fill",
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
                    icon: "heart.fill",
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
    var showsRule = true

    static func == (lhs: DailyTimelineRow, rhs: DailyTimelineRow) -> Bool {
        lhs.model == rhs.model && lhs.showsRule == rhs.showsRule
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(spacing: -2) {
                Text(model.monthAbbrev)
                    .font(Theme.Typography.caption2Bold)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(model.dayNumber)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(model.isToday ? Theme.Colors.success : Theme.Colors.textPrimary)
            }
            .frame(minWidth: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.isToday ? "Today" : model.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if model.stats.isEmpty {
                    Text("No key readings this day")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Spacing.md) {
                            ForEach(model.stats) { stat in
                                timelineStat(stat)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 92), alignment: .leading)],
                            alignment: .leading,
                            spacing: Theme.Spacing.sm
                        ) {
                            ForEach(model.stats) { stat in
                                timelineStat(stat)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .ledgerRow(showsRule: showsRule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.title), \(model.subtitle)")
    }

    private func timelineStat(_ stat: DailyTimelineStatModel) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(statTint(for: stat.id))
                .frame(width: 3, height: 12)
                .accessibilityHidden(true)
            Text(stat.unit.isEmpty || stat.unit == "h" ? stat.value + stat.unit : "\(stat.value) \(stat.unit)")
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stat.label) \(stat.value) \(stat.unit)")
    }

    private func statTint(for id: String) -> Color {
        switch id {
        case "sleep": return HealthMetric.sleep.accentColor
        case "steps": return HealthMetric.steps.accentColor
        case "energy": return HealthMetric.activeEnergy.accentColor
        case "resting": return HealthMetric.restingHeartRate.accentColor
        default: return Theme.Colors.textPrimary
        }
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
