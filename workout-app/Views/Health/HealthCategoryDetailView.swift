import Combine
import SwiftUI
import Charts

struct HealthCategoryDetailView: View {
    let category: HealthHubCategory

    @EnvironmentObject var healthManager: HealthViewStore
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext
    @State private var cachedPresentation: HealthCategoryPresentation?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let presentation = cachedPresentation {
                        categoryHeader(rangeLabel: presentation.rangeLabel)
                            .staggeredAppear(index: 0)

                        if presentation.dailyData.isEmpty || presentation.metricsWithData.isEmpty {
                            emptyState
                        } else {
                            spotlightSection(presentation.spotlight)
                                .staggeredAppear(index: 1)

                            if let insightText = generateInsight(for: presentation.spotlight) {
                                insightBanner(insightText)
                                    .staggeredAppear(index: 2)
                            }

                            if !presentation.secondaryMetrics.isEmpty {
                                secondarySection(presentation.secondaryMetrics)
                            }

                            if !presentation.unavailableMetrics.isEmpty {
                                unavailableMetricsDisclosure(presentation.unavailableMetrics)
                            }
                        }
                    } else {
                        ProgressView()
                            .tint(category.tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xxl)
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HealthDateRangeToolbarMenu(earliestDate: cachedPresentation?.earliestDate)
            }
        }
        .onAppear { refreshPresentation() }
        .onChange(of: dateRangeContext.selectedRange) { _, _ in refreshPresentation() }
        .onChange(of: dateRangeContext.customRange) { _, _ in
            if dateRangeContext.selectedRange == .custom {
                refreshPresentation()
            }
        }
        .onReceive(healthManager.$dailyHealthStore.dropFirst()) { store in
            refreshPresentation(from: store)
        }
    }

    // MARK: - Category Header

    private func categoryHeader(rangeLabel: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: category.icon)
                .font(Theme.Iconography.title2)
                .foregroundStyle(category.tint)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(category.tint.opacity(Theme.Opacity.subtleFill))
                )
                .overlay(
                    Circle()
                        .strokeBorder(category.tint.opacity(0.15), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(category.subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(rangeLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .tintedSection(category.tint)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No \(category.title.lowercased()) data in this range")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Try a longer time range or review Apple Health access for this category.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    // MARK: - Spotlight Section

    private func spotlightSection(_ snapshot: HealthCategoryMetricSnapshot) -> some View {
        let metric = snapshot.metric

        return NavigationLink {
            HealthMetricDetailView(metric: metric)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Header: icon + name + trend
                HStack {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: metric.icon)
                            .font(Theme.Iconography.medium)
                            .foregroundStyle(metric.chartColor)
                        Text(metric.title)
                            .font(Theme.Typography.sectionHeader2)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    Spacer()

                    if let trend = snapshot.trend {
                        TrendBadge(percentage: trend, color: metric.chartColor)
                    }
                }

                // Big number
                HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(snapshot.latest.map(metric.format) ?? "--")
                        .font(Theme.Typography.numberLarge)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(metric.displayUnit)
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                // Chart
                if snapshot.points.count >= 2 {
                    spotlightChart(points: snapshot.renderedPoints, metric: metric)
                }

                // Divider
                Rectangle()
                    .fill(Theme.Colors.border.opacity(0.5))
                    .frame(height: 1)

                // Stats row
                HStack(spacing: 0) {
                    SpotlightStat(
                        label: "AVG",
                        value: snapshot.average.map(metric.format) ?? "--",
                        unit: metric.displayUnit
                    )
                    Spacer()
                    SpotlightStat(
                        label: "LOW",
                        value: snapshot.minimum.map(metric.format) ?? "--",
                        unit: metric.displayUnit
                    )
                    Spacer()
                    SpotlightStat(
                        label: "HIGH",
                        value: snapshot.maximum.map(metric.format) ?? "--",
                        unit: metric.displayUnit
                    )
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: Theme.CornerRadius.large,
                    topTrailingRadius: Theme.CornerRadius.large
                )
                .fill(metric.chartColor)
                .frame(height: 3)
            }
        }
        .buttonStyle(.plain)
    }

    private func spotlightChart(points: [HealthTrendPoint], metric: HealthMetric) -> some View {
        let baseline = areaBaseline(for: points)

        return Chart(points) { point in
            AreaMark(
                x: .value("Date", point.date),
                yStart: .value("Baseline", baseline),
                yEnd: .value("Value", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        metric.chartColor.opacity(0.25),
                        metric.chartColor.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Date", point.date),
                y: .value("Value", point.value)
            )
            .foregroundStyle(metric.chartColor)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYScale(domain: chartYDomain(for: points, baseline: baseline))
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.border.opacity(0.35))
                AxisValueLabel {
                    if let axisValue = value.as(Double.self) {
                        Text(metric.format(axisValue))
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .frame(height: Theme.ChartHeight.standard)
    }

    private func unavailableMetricsDisclosure(_ unavailableMetrics: [HealthMetric]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(unavailableMetrics) { metric in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: metric.icon)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(metric.chartColor)
                            .frame(width: 24, height: 24)

                        Text(metric.title)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Spacer()
                    }
                }

                Text("These metrics are either not recorded by your devices, not shared with this app, or not present in the selected range.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Theme.Spacing.sm)
        } label: {
            Text("Unavailable Metrics")
                .font(Theme.Typography.subheadlineBold)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    // MARK: - Insight Banner

    private func insightBanner(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(Theme.Iconography.medium)
                .foregroundStyle(category.tint)

            Text(text)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .tintedSection(category.tint)
    }

    // MARK: - Secondary Section

    private func secondarySection(_ secondaryMetrics: [HealthCategoryMetricSnapshot]) -> some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("ALL METRICS")
                .sectionHeaderStyle()
                .padding(.top, Theme.Spacing.sm)

            ForEach(secondaryMetrics) { snapshot in
                let metric = snapshot.metric
                NavigationLink {
                    HealthMetricDetailView(metric: metric)
                } label: {
                    EnrichedMetricRow(
                        metric: metric,
                        points: snapshot.renderedPoints,
                        latestValue: snapshot.latest,
                        average: snapshot.average,
                        trend: snapshot.trend
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Data Helpers

    private func areaBaseline(for points: [HealthTrendPoint]) -> Double {
        let values = points.map(\.value)
        guard let minVal = values.min(), let maxVal = values.max() else { return 0 }
        let span = maxVal - minVal
        return Swift.max(0, minVal - span * 0.1)
    }

    private func chartYDomain(for points: [HealthTrendPoint], baseline: Double) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let maxVal = values.max() else { return 0...1 }
        let span = maxVal - baseline
        if span <= 0 {
            let padding = max(abs(maxVal) * 0.05, 1)
            return max(0, baseline - padding)...(maxVal + padding)
        }
        return baseline...(maxVal + span * 0.08)
    }

    private func generateInsight(for snapshot: HealthCategoryMetricSnapshot) -> String? {
        guard let trend = snapshot.trend else { return nil }
        let name = snapshot.metric.title.lowercased()
        let absT = abs(trend)
        let direction = trend > 0 ? "up" : "down"
        let pct = String(format: "%.0f%%", absT)

        if absT < 2 {
            return "Your \(name) has been holding steady over this period."
        } else if absT < 10 {
            return "Your \(name) is trending \(direction) \(pct) compared to earlier in this range."
        } else {
            return "Your \(name) is \(direction) \(pct) — a notable shift from the first half of this period."
        }
    }

    private func refreshPresentation(from emittedStore: [Date: DailyHealthData]? = nil) {
        let store = emittedStore ?? healthManager.dailyHealthStore
        let earliestDate = store.keys.min()
        let resolvedRange = dateRangeContext.resolvedRange(earliest: earliestDate)
        var dailyData = store.values.filter { resolvedRange.contains($0.dayStart) }
        dailyData.sort { $0.dayStart < $1.dayStart }

        cachedPresentation = HealthCategoryPresentation(
            category: category,
            dailyData: dailyData,
            earliestDate: earliestDate,
            rangeLabel: dateRangeContext.rangeLabel(earliest: earliestDate)
        )
    }
}

private struct HealthCategoryMetricSnapshot: Identifiable {
    let metric: HealthMetric
    let points: [HealthTrendPoint]
    let renderedPoints: [HealthTrendPoint]
    let latest: Double?
    let average: Double?
    let minimum: Double?
    let maximum: Double?
    let trend: Double?

    var id: HealthMetric { metric }

    init(metric: HealthMetric, dailyData: [DailyHealthData]) {
        self.metric = metric

        let points = dailyData.compactMap { day -> HealthTrendPoint? in
            guard let value = day.value(for: metric) else { return nil }
            return HealthTrendPoint(date: day.dayStart, value: value, label: metric.title)
        }
        self.points = points
        renderedPoints = HealthChartPointSampler.sampled(points, limit: 240)

        let values = points.map(\.value)
        latest = values.last
        average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        minimum = values.min()
        maximum = values.max()
        trend = Self.trendPercentage(values)
    }

    private static func trendPercentage(_ values: [Double]) -> Double? {
        guard values.count >= 4 else { return nil }

        let midpoint = values.count / 2
        let firstHalf = values[..<midpoint]
        let secondHalf = values[midpoint...]
        let firstAverage = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAverage = secondHalf.reduce(0, +) / Double(secondHalf.count)

        guard firstAverage != 0 else { return nil }
        return ((secondAverage - firstAverage) / abs(firstAverage)) * 100
    }
}

private struct HealthCategoryPresentation {
    let dailyData: [DailyHealthData]
    let earliestDate: Date?
    let rangeLabel: String
    let metricsWithData: [HealthCategoryMetricSnapshot]
    let unavailableMetrics: [HealthMetric]
    let spotlight: HealthCategoryMetricSnapshot
    let secondaryMetrics: [HealthCategoryMetricSnapshot]

    init(
        category: HealthHubCategory,
        dailyData: [DailyHealthData],
        earliestDate: Date?,
        rangeLabel: String
    ) {
        self.dailyData = dailyData
        self.earliestDate = earliestDate
        self.rangeLabel = rangeLabel

        let metrics = HealthMetric.metrics(for: category)
        let snapshots = metrics.map {
            HealthCategoryMetricSnapshot(metric: $0, dailyData: dailyData)
        }
        let available = snapshots.filter { !$0.points.isEmpty }
        metricsWithData = available
        unavailableMetrics = snapshots.filter(\.points.isEmpty).map(\.metric)

        let preferred = category.primaryMetric.flatMap { primary in
            available.first { $0.metric == primary }
        }
        let fallbackMetric = category.primaryMetric ?? metrics.first ?? .steps
        let spotlight = preferred ?? available.first ?? HealthCategoryMetricSnapshot(
            metric: fallbackMetric,
            dailyData: dailyData
        )
        self.spotlight = spotlight
        secondaryMetrics = available.filter { $0.metric != spotlight.metric }
    }
}

// MARK: - Trend Badge

private struct TrendBadge: View {
    let percentage: Double
    let color: Color

    private var isPositive: Bool { percentage >= 0 }
    private var icon: String { isPositive ? "arrow.up.right" : "arrow.down.right" }
    private var displayText: String { String(format: "%+.0f%%", percentage) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(Theme.Typography.caption)
            Text(displayText)
                .font(Theme.Typography.captionBold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(Theme.Opacity.subtleFill))
        )
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Spotlight Stat

private struct SpotlightStat: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(0.8)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(unit)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }
}

// MARK: - Enriched Metric Row

private struct EnrichedMetricRow: View {
    let metric: HealthMetric
    let points: [HealthTrendPoint]
    let latestValue: Double?
    let average: Double?
    let trend: Double?

    private var areaBaseline: Double {
        let values = points.map(\.value)
        guard let minVal = values.min(), let maxVal = values.max() else { return 0 }
        let span = maxVal - minVal
        return Swift.max(0, minVal - span * 0.1)
    }

    private var chartYDomain: ClosedRange<Double> {
        let baseline = areaBaseline
        let maximum = points.map(\.value).max() ?? 1
        if maximum <= baseline {
            let padding = max(abs(maximum) * 0.05, 1)
            return max(0, baseline - padding)...(maximum + padding)
        }
        return baseline...(maximum + (maximum - baseline) * 0.05)
    }

    var body: some View {
        let baseline = areaBaseline
        let chartDomain = chartYDomain

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header row
            HStack {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: metric.icon)
                        .font(Theme.Iconography.medium)
                        .foregroundStyle(metric.chartColor)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                .fill(metric.chartColor.opacity(Theme.Opacity.subtleFill))
                        )

                    Text(metric.title)
                        .font(Theme.Typography.subheadlineBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Spacer()

                if let trend {
                    TrendBadge(percentage: trend, color: metric.chartColor)
                }
            }

            // Value + average
            HStack(alignment: .lastTextBaseline) {
                if let latestValue {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(metric.format(latestValue))
                            .font(Theme.Typography.number)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(metric.displayUnit)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                } else {
                    Text("--")
                        .font(Theme.Typography.number)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                if let average {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("AVG")
                            .font(Theme.Typography.metricLabel)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .tracking(0.6)
                        Text("\(metric.format(average)) \(metric.displayUnit)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }

            // Chart
            if points.isEmpty {
                Text("No data in this range")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else {
                Chart(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Baseline", baseline),
                        yEnd: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                metric.chartColor.opacity(0.18),
                                metric.chartColor.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(metric.chartColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: chartDomain)
                .chartYAxis(.hidden)
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .frame(height: 56)
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.CornerRadius.large,
                bottomLeadingRadius: Theme.CornerRadius.large
            )
            .fill(metric.chartColor)
            .frame(width: 3)
        }
    }
}
