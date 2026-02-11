import Charts
import SwiftUI

struct BodyCompositionView: View {
    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var dataManager: WorkoutDataManager

    @StateObject private var model = BodyCompositionViewModel()

    @State private var selectedRange: HealthTimeRange = .fourWeeks
    @State private var showingCustomRange = false
    @State private var showingHealthWizard = false
    @State private var customRange: DateInterval = {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -28, to: end) ?? end
        return DateInterval(start: start, end: end)
    }()

    @State private var metricKind: BodyCompositionMetricKind = .weight
    @State private var selectedTab: Tab = .overview
    @State private var reportGranularity: ReportGranularity = .weekly

    @State private var showMA7 = true
    @State private var showRA30 = true
    @State private var showTrend = true
    @State private var showForecast = true

    @State private var expandedDays: Set<Date> = []

    private enum Tab: String, CaseIterable, Identifiable {
        case overview
        case logbook
        case reports

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .logbook: return "Logbook"
            case .reports: return "Reports"
            }
        }
    }

    private var earliestDateForAll: Date? {
        model.earliestSampleDate ?? healthManager.dailyHealthStore.keys.min()
    }

    private var displayRange: DateInterval {
        let raw = selectedRange.interval(reference: Date(), earliest: earliestDateForAll, custom: customRange)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: raw.start)
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: raw.end) ?? raw.end
        return DateInterval(start: start, end: min(end, Date()))
    }

    private var rangeLabel: String {
        formatRange(displayRange)
    }

    private var measurementNoun: String {
        metricKind == .weight ? "weigh-ins" : "readings"
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    headerSection

                    timeRangeSection

                    metricSection

                    tabSection

                    content
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle("Body Composition")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCustomRange) {
            HealthCustomRangeSheet(range: $customRange) {
                selectedRange = .custom
            }
        }
        .sheet(isPresented: $showingHealthWizard) {
            HealthSyncWizard(isPresented: $showingHealthWizard, workouts: dataManager.workouts)
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            refreshData()
        }
        .onChange(of: selectedRange) { _, _ in
            refreshData()
        }
        .onChange(of: customRange) { _, _ in
            if selectedRange == .custom {
                refreshData()
            }
        }
        .onChange(of: metricKind) { _, _ in
            expandedDays.removeAll()
            refreshData()
        }
        .onChange(of: reportGranularity) { _, newValue in
            model.recomputeReports(granularity: newValue)
        }
        .onChange(of: model.earliestSampleDate) { _, _ in
            if selectedRange == .all {
                refreshData()
            }
        }
        .onChange(of: healthManager.authorizationStatus) { _, newValue in
            if newValue == .authorized {
                refreshData()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Body Composition")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.5)

                    Text("\(rangeLabel) • \(model.sampleCountInDisplayRange) \(measurementNoun)")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Button {
                    refreshData(force: true)
                } label: {
                    Group {
                        if model.isLoading {
                            ProgressView()
                                .tint(Theme.Colors.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                            .fill(Theme.Colors.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                            .strokeBorder(Theme.Colors.border, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(healthManager.authorizationStatus != .authorized || model.isLoading)
                .accessibilityLabel("Refresh body composition data")
            }

            if let lastUpdated = model.lastUpdatedAt {
                Text("Last updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var timeRangeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Time Range")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(HealthTimeRange.allCases) { range in
                        let isSelected = selectedRange == range
                        Button {
                            if range == .custom {
                                showingCustomRange = true
                            } else {
                                selectedRange = range
                            }
                        } label: {
                            Text(range.title)
                                .font(Theme.Typography.metricLabel)
                                .textCase(.uppercase)
                                .tracking(0.8)
                                .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .frame(minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                        .fill(isSelected ? Theme.Colors.accent : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var metricSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Metric")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            BrutalistSegmentedPicker(
                title: "Metric",
                selection: $metricKind,
                options: BodyCompositionMetricKind.allCases.map { ($0.title, $0) }
            )
        }
    }

    private var tabSection: some View {
        BrutalistSegmentedPicker(
            title: "Section",
            selection: $selectedTab,
            options: Tab.allCases.map { ($0.title, $0) }
        )
    }

    @ViewBuilder
    private var content: some View {
        if healthManager.authorizationStatus == .unavailable {
            unavailableCard
        } else if healthManager.authorizationStatus != .authorized {
            accessCard
        } else if let error = model.errorMessage {
            errorCard(message: error)
        } else if model.representativeSeries.isEmpty {
            emptyState
        } else {
            switch selectedTab {
            case .overview:
                overviewTab
            case .logbook:
                logbookTab
            case .reports:
                reportsTab
            }
        }
    }

    // MARK: - Overview

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            keyStatsSection
            intervalChangesSection
            trendForecastSection
            chartSection
        }
    }

    private var keyStatsSection: some View {
        let latest = model.representativeSeries.last?.value
        let latestMA7 = model.ma7Series.last?.value
        let latestRA30 = model.ra30Series.last?.value
        let pace: Double? = {
            guard let trend = model.trendSummary, trend.pointCount >= 6 else { return nil }
            return trend.pacePerWeek
        }()

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.md) {
                BodyStatCard(title: "Current", value: latest.map(formatValue) ?? "--", subtitle: nil)
                BodyStatCard(title: "7d MA", value: latestMA7.map(formatValue) ?? "--", subtitle: nil)
                BodyStatCard(title: "30d RA", value: latestRA30.map(formatValue) ?? "--", subtitle: nil)
                BodyStatCard(title: "Weekly Pace", value: pace.map(formatDeltaPerWeek) ?? "--", subtitle: nil)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                BodyStatCard(title: "Current", value: latest.map(formatValue) ?? "--", subtitle: nil)
                BodyStatCard(title: "7d MA", value: latestMA7.map(formatValue) ?? "--", subtitle: nil)
                BodyStatCard(title: "30d RA", value: latestRA30.map(formatValue) ?? "--", subtitle: nil)
                BodyStatCard(title: "Weekly Pace", value: pace.map(formatDeltaPerWeek) ?? "--", subtitle: nil)
            }
        }
    }

    private var intervalChangesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Changes")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            if model.intervalDeltas.isEmpty {
                Text("Not enough data to compute changes yet.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.md) {
                        ForEach(model.intervalDeltas) { delta in
                            DeltaCard(title: delta.label, delta: delta.delta, baselineDate: delta.baselineDate, unit: metricKind.unitLabel)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                        ForEach(model.intervalDeltas) { delta in
                            DeltaCard(title: delta.label, delta: delta.delta, baselineDate: delta.baselineDate, unit: metricKind.unitLabel)
                        }
                    }
                }
            }
        }
    }

    private var trendForecastSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Trend + Forecast")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            if let trend = model.trendSummary {
                TrendForecastCard(
                    trend: trend,
                    forecast: model.forecastPoints,
                    unit: metricKind.unitLabel,
                    formatValue: formatValue
                )
            } else {
                Text("Not enough data to estimate a trend yet.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            }
        }
    }

    private var chartSection: some View {
        let forecastEnd = model.forecastPoints.first(where: { $0.horizonDays == 90 })?.date
        let domainEnd = max(displayRange.end, forecastEnd ?? displayRange.end)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Trend Chart")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                overlayToggles

                BodyCompositionTrendChart(
                    points: model.representativeSeries,
                    ma7: model.ma7Series,
                    ra30: model.ra30Series,
                    trend: model.trendSummary,
                    forecast: model.forecastPoints,
                    color: Theme.Colors.accent,
                    fullDomain: displayRange.start...domainEnd,
                    showMA7: showMA7,
                    showRA30: showRA30,
                    showTrend: showTrend,
                    showForecast: showForecast,
                    headerValueText: formatValue,
                    axisValueText: { axisValue in
                        switch metricKind {
                        case .weight:
                            return "\(Int(axisValue.rounded()))"
                        case .bodyFat:
                            return String(format: "%.1f", axisValue)
                        }
                    }
                )
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
        }
    }

    private var overlayToggles: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.md) {
                overlayPill("7d MA", isOn: $showMA7, tint: Theme.Colors.accentSecondary)
                overlayPill("30d RA", isOn: $showRA30, tint: Theme.Colors.accentTertiary)
                overlayPill("Trend", isOn: $showTrend, tint: Theme.Colors.textSecondary)
                overlayPill("Forecast", isOn: $showForecast, tint: Theme.Colors.textTertiary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.md) {
                    overlayPill("7d MA", isOn: $showMA7, tint: Theme.Colors.accentSecondary)
                    overlayPill("30d RA", isOn: $showRA30, tint: Theme.Colors.accentTertiary)
                }
                HStack(spacing: Theme.Spacing.md) {
                    overlayPill("Trend", isOn: $showTrend, tint: Theme.Colors.textSecondary)
                    overlayPill("Forecast", isOn: $showForecast, tint: Theme.Colors.textTertiary)
                }
            }
        }
    }

    private func overlayPill(_ title: String, isOn: Binding<Bool>, tint: Color) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            Haptics.selection()
        } label: {
            HStack(spacing: 6) {
                if isOn.wrappedValue {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }

                Text(title)
                    .font(Theme.Typography.metricLabel)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn.wrappedValue ? Color.white : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(isOn.wrappedValue ? tint : Theme.Colors.cardBackground)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Theme.Colors.border, lineWidth: 2)
            )
            .shadow(
                color: Color.black.opacity(Theme.Colors.shadowOpacity),
                radius: 0,
                x: 2,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn.wrappedValue ? "On" : "Off"))
    }

    // MARK: - Logbook

    private var logbookTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Weigh-In Log")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(model.logbookDays) { day in
                    LogbookDayCard(
                        day: day,
                        anchorStart: displayRange.start,
                        unit: metricKind.unitLabel,
                        formatValue: formatValue,
                        formatRate: formatDeltaPerWeek,
                        isExpanded: expandedDays.contains(day.dayStart),
                        toggleExpanded: { toggleExpanded(day.dayStart) }
                    )
                }
            }
        }
    }

    private func toggleExpanded(_ dayStart: Date) {
        if expandedDays.contains(dayStart) {
            expandedDays.remove(dayStart)
        } else {
            expandedDays.insert(dayStart)
        }
    }

    // MARK: - Reports

    private var reportsTab: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Reports")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            BrutalistSegmentedPicker(
                title: "Granularity",
                selection: $reportGranularity,
                options: ReportGranularity.allCases.map { ($0.title, $0) }
            )

            reportsChart

            VStack(spacing: Theme.Spacing.md) {
                ForEach(model.reportBuckets.reversed()) { bucket in
                    ReportBucketRow(bucket: bucket, unit: metricKind.unitLabel, formatValue: formatValue, formatDelta: formatDelta)
                }
            }
        }
    }

    private var reportsChart: some View {
        let chartPoints = model.reportBuckets
            .map { TimeSeriesPoint(date: $0.keyDate, value: $0.average) }
            .sorted { $0.date < $1.date }

        return Group {
            if chartPoints.isEmpty {
                Text("No report data in this range.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                let dateRangeInDays: Int = {
                    guard let first = chartPoints.first?.date,
                          let last = chartPoints.last?.date else { return 1 }
                    let calendar = Calendar.current
                    let start = calendar.startOfDay(for: first)
                    let end = calendar.startOfDay(for: last)
                    return max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
                }()

                let xAxisComponent: Calendar.Component = {
                    switch reportGranularity {
                    case .weekly:
                        if dateRangeInDays > 730 { return .year }      // 2+ years: yearly ticks
                        if dateRangeInDays > 180 { return .month }     // 6m-2y: monthly ticks
                        return .weekOfYear                              // <= 6m: weekly ticks
                    case .monthly:
                        if dateRangeInDays > 730 { return .year }      // 2+ years: yearly ticks
                        return .month                                   // <= 2y: monthly ticks
                    case .yearly:
                        return .year
                    }
                }()

                let xAxisStride: Int = {
                    switch xAxisComponent {
                    case .year:
                        if dateRangeInDays > 3650 { return 2 }
                        return 1
                    case .month:
                        if dateRangeInDays > 365 { return 2 }
                        return 1
                    case .weekOfYear:
                        if dateRangeInDays > 90 { return 2 }
                        return 1
                    default:
                        return 1
                    }
                }()

                let xAxisDateFormat: Date.FormatStyle = {
                    switch xAxisComponent {
                    case .year:
                        return .dateTime.year()
                    case .month:
                        if dateRangeInDays > 365 {
                            return .dateTime.year().month(.abbreviated)
                        }
                        return .dateTime.month(.abbreviated)
                    default:
                        return .dateTime.month(.abbreviated).day()
                    }
                }()

                Chart(chartPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Avg", point.value)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Avg", point.value)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                    .symbolSize(24)
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .stride(by: xAxisComponent, count: xAxisStride)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: xAxisDateFormat)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                switch metricKind {
                                case .weight:
                                    Text("\(Int(axisValue.rounded()))")
                                case .bodyFat:
                                    Text(String(format: "%.1f", axisValue))
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 1)
            }
        }
    }

    // MARK: - States

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Connect Apple Health")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Allow access to view your weigh-ins, trends, and forecasts.")
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

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Couldn’t Load Data")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No data in this range")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Try a longer time range or sync Apple Health.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                refreshData(force: true)
            } label: {
                Text("Refresh")
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

    // MARK: - Helpers

    private func refreshData(force: Bool = false) {
        guard healthManager.authorizationStatus == .authorized else {
            return
        }

        model.load(
            healthManager: healthManager,
            metricKind: metricKind,
            displayRange: displayRange,
            reportGranularity: reportGranularity
        )
    }

    private func formatRange(_ interval: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let start = formatter.string(from: interval.start)
        let end = formatter.string(from: interval.end)
        return "\(start) – \(end)"
    }

    private func formatValue(_ value: Double) -> String {
        switch metricKind {
        case .weight:
            return String(format: "%.1f %@", value, metricKind.unitLabel)
        case .bodyFat:
            return String(format: "%.1f%@", value, metricKind.unitLabel)
        }
    }

    private func formatDelta(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        switch metricKind {
        case .weight:
            return "\(sign)\(String(format: "%.1f", value)) \(metricKind.unitLabel)"
        case .bodyFat:
            return "\(sign)\(String(format: "%.1f", value))\(metricKind.unitLabel)"
        }
    }

    private func formatDeltaPerWeek(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        switch metricKind {
        case .weight:
            return "\(sign)\(String(format: "%.2f", value)) \(metricKind.unitLabel)/wk"
        case .bodyFat:
            return "\(sign)\(String(format: "%.2f", value))\(metricKind.unitLabel)/wk"
        }
    }
}

private struct BodyStatCard: View {
    let title: String
    let value: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer(minLength: 0)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Text(value)
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(elevation: 1)
    }
}

private struct DeltaCard: View {
    let title: String
    let delta: Double
    let baselineDate: Date?
    let unit: String

    private var sign: String { delta >= 0 ? "+" : "" }

    private var deltaText: String {
        "\(sign)\(String(format: "%.1f", delta)) \(unit)"
    }

    private var subtitle: String? {
        baselineDate.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
    }

    private var tint: Color {
        if abs(delta) < 0.0001 { return Theme.Colors.textTertiary }
        return delta < 0 ? Theme.Colors.success : Theme.Colors.warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer(minLength: 0)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Text(deltaText)
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(tint)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(elevation: 1)
    }
}

private struct TrendForecastCard: View {
    let trend: TrendSummary
    let forecast: [ForecastPoint]
    let unit: String
    let formatValue: (Double) -> String

    private var paceText: String {
        let sign = trend.pacePerWeek >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", trend.pacePerWeek)) \(unit)/wk"
    }

    private var r2Text: String? {
        guard let r2 = trend.rSquared else { return nil }
        return "R² \(String(format: "%.2f", r2))"
    }

    private var sigmaText: String? {
        guard let sigma = trend.residualStdDev else { return nil }
        return "±\(String(format: "%.1f", sigma)) \(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("30d Regression")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("\(trend.pointCount) pts")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                HStack(spacing: Theme.Spacing.sm) {
                    if let r2Text {
                        Text(r2Text)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    if let sigmaText {
                        Text(sigmaText)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(paceText)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.accent)
                Text("pace")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(forecast) { point in
                    HStack {
                        Text("+\(point.horizonDays)d")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: 56, alignment: .leading)

                        Text(point.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)

                        Spacer()

                        Text(formatValue(point.predicted))
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

private struct LogbookDayCard: View {
    let day: BodyLogbookDay
    let anchorStart: Date
    let unit: String

    let formatValue: (Double) -> String
    let formatRate: (Double) -> String

    let isExpanded: Bool
    let toggleExpanded: () -> Void

    private var dayTitle: String {
        day.dayStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var badgeText: String? {
        let anchorLabel = anchorStart.formatted(.dateTime.month(.abbreviated).day().year())
        if day.isNewLow { return "LOW since \(anchorLabel)" }
        if day.isNewHigh { return "HIGH since \(anchorLabel)" }
        return nil
    }

    private var badgeTint: Color {
        if day.isNewLow { return Theme.Colors.success }
        if day.isNewHigh { return Theme.Colors.warning }
        return Theme.Colors.textTertiary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            if !day.samples.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Raw Samples")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    let shown = isExpanded ? day.samples : Array(day.samples.prefix(5))
                    ForEach(shown) { sample in
                        HStack {
                            Text(sample.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Spacer()
                            Text(formatValue(sample.value))
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }

                    if day.samples.count > 5 {
                        Button {
                            toggleExpanded()
                        } label: {
                            Text(isExpanded ? "Show less" : "Show all (\(day.samples.count))")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.accent)
                                .textCase(.uppercase)
                                .tracking(0.8)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Theme.Spacing.xs)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayTitle)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text(formatValue(day.representative))
                        .font(Theme.Typography.number)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    if let badgeText {
                        Text(badgeText)
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(badgeTint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    StatLine(label: "7d MA", value: day.movingAverage7d.map(formatValue) ?? "--")
                    StatLine(label: "30d RA", value: day.rollingAverage30d.map(formatValue) ?? "--")
                    StatLine(label: "Rate", value: day.weeklyRate.map(formatRate) ?? "--")
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dayTitle)
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(formatValue(day.representative))
                            .font(Theme.Typography.number)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Spacer()
                    if let badgeText {
                        Text(badgeText)
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(badgeTint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }

                HStack(spacing: Theme.Spacing.md) {
                    StatBlock(label: "7d MA", value: day.movingAverage7d.map(formatValue) ?? "--")
                    StatBlock(label: "30d RA", value: day.rollingAverage30d.map(formatValue) ?? "--")
                    StatBlock(label: "Rate", value: day.weeklyRate.map(formatRate) ?? "--")
                }
            }
        }
    }

    private struct StatLine: View {
        let label: String
        let value: String

        var body: some View {
            HStack(spacing: 6) {
                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(value)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }

    private struct StatBlock: View {
        let label: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(value)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ReportBucketRow: View {
    let bucket: ReportBucket
    let unit: String
    let formatValue: (Double) -> String
    let formatDelta: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(bucket.label)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(formatValue(bucket.average))
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    smallStat(label: "Start", value: formatValue(bucket.start))
                    smallStat(label: "End", value: formatValue(bucket.end))
                    smallStat(label: "Chg", value: formatDelta(bucket.change))
                    smallStat(label: "Min", value: formatValue(bucket.min))
                    smallStat(label: "Max", value: formatValue(bucket.max))
                    smallStat(label: "N", value: "\(bucket.count)")
                }

                VStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        smallStat(label: "Start", value: formatValue(bucket.start))
                        smallStat(label: "End", value: formatValue(bucket.end))
                        smallStat(label: "Chg", value: formatDelta(bucket.change))
                    }
                    HStack(spacing: Theme.Spacing.md) {
                        smallStat(label: "Min", value: formatValue(bucket.min))
                        smallStat(label: "Max", value: formatValue(bucket.max))
                        smallStat(label: "N", value: "\(bucket.count)")
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func smallStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
