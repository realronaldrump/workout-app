import SwiftUI
import Charts

struct HealthCategoryDetailView: View {
    let category: HealthHubCategory

    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext

    private var earliestDate: Date? {
        healthManager.dailyHealthStore.keys.min()
    }

    private var range: DateInterval {
        dateRangeContext.resolvedRange(earliest: earliestDate)
    }

    private var rangeLabel: String {
        dateRangeContext.rangeLabel(earliest: earliestDate)
    }

    private var dailyData: [DailyHealthData] {
        healthManager.dailyHealthStore.values
            .filter { range.contains($0.dayStart) }
            .sorted { $0.dayStart < $1.dayStart }
    }

    private var metrics: [HealthMetric] {
        HealthMetric.metrics(for: category)
    }

    private var spotlightMetric: HealthMetric {
        category.primaryMetric ?? metrics.first ?? .steps
    }

    private var secondaryMetrics: [HealthMetric] {
        metrics.filter { $0 != spotlightMetric }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    categoryHeader
                        .staggeredAppear(index: 0)

                    if dailyData.isEmpty {
                        emptyState
                    } else {
                        spotlightSection
                            .staggeredAppear(index: 1)

                        if let insightText = generateInsight() {
                            insightBanner(insightText)
                                .staggeredAppear(index: 2)
                        }

                        if !secondaryMetrics.isEmpty {
                            secondarySection
                        }
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
                HealthDateRangeToolbarMenu(earliestDate: earliestDate)
            }
        }
    }

    // MARK: - Category Header

    private var categoryHeader: some View {
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
            Text("No data yet")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Use Settings to sync Apple Health data before viewing \(category.title.lowercased()) metrics here.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    // MARK: - Spotlight Section

    private var spotlightSection: some View {
        let points = metricPoints(for: spotlightMetric)
        let latest = latestValue(for: spotlightMetric)
        let trend = trendPercentage(for: spotlightMetric)
        let avg = average(for: spotlightMetric)
        let minVal = minValue(for: spotlightMetric)
        let maxVal = maxValue(for: spotlightMetric)

        return NavigationLink {
            HealthMetricDetailView(metric: spotlightMetric)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Header: icon + name + trend
                HStack {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: spotlightMetric.icon)
                            .font(Theme.Iconography.medium)
                            .foregroundStyle(spotlightMetric.chartColor)
                        Text(spotlightMetric.title)
                            .font(Theme.Typography.sectionHeader2)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    Spacer()

                    if let trend {
                        TrendBadge(percentage: trend, color: spotlightMetric.chartColor)
                    }
                }

                // Big number
                HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(latest.map(spotlightMetric.format) ?? "--")
                        .font(Theme.Typography.numberLarge)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(spotlightMetric.displayUnit)
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                // Chart
                if points.count >= 2 {
                    spotlightChart(points: points)
                }

                // Divider
                Rectangle()
                    .fill(Theme.Colors.border.opacity(0.5))
                    .frame(height: 1)

                // Stats row
                HStack(spacing: 0) {
                    SpotlightStat(
                        label: "AVG",
                        value: avg.map(spotlightMetric.format) ?? "--",
                        unit: spotlightMetric.displayUnit
                    )
                    Spacer()
                    SpotlightStat(
                        label: "LOW",
                        value: minVal.map(spotlightMetric.format) ?? "--",
                        unit: spotlightMetric.displayUnit
                    )
                    Spacer()
                    SpotlightStat(
                        label: "HIGH",
                        value: maxVal.map(spotlightMetric.format) ?? "--",
                        unit: spotlightMetric.displayUnit
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
                .fill(spotlightMetric.chartColor)
                .frame(height: 3)
            }
        }
        .buttonStyle(.plain)
    }

    private func spotlightChart(points: [HealthTrendPoint]) -> some View {
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
                        spotlightMetric.chartColor.opacity(0.25),
                        spotlightMetric.chartColor.opacity(0.02)
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
            .foregroundStyle(spotlightMetric.chartColor)
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
        .chartYAxis(.hidden)
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .frame(height: Theme.ChartHeight.standard)
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

    private var secondarySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("ALL METRICS")
                .sectionHeaderStyle()
                .padding(.top, Theme.Spacing.sm)

            ForEach(Array(secondaryMetrics.enumerated()), id: \.element.id) { index, metric in
                NavigationLink {
                    HealthMetricDetailView(metric: metric)
                } label: {
                    EnrichedMetricRow(
                        metric: metric,
                        points: metricPoints(for: metric),
                        latestValue: latestValue(for: metric),
                        average: average(for: metric),
                        trend: trendPercentage(for: metric)
                    )
                }
                .buttonStyle(.plain)
                .staggeredAppear(index: index + 3)
            }
        }
    }

    // MARK: - Data Helpers

    private func metricPoints(for metric: HealthMetric) -> [HealthTrendPoint] {
        dailyData.compactMap { day in
            guard let value = day.value(for: metric) else { return nil }
            return HealthTrendPoint(date: day.dayStart, value: value, label: metric.title)
        }
    }

    private func latestValue(for metric: HealthMetric) -> Double? {
        for day in dailyData.reversed() {
            if let value = day.value(for: metric) {
                return value
            }
        }
        return nil
    }

    private func average(for metric: HealthMetric) -> Double? {
        let values = dailyData.compactMap { $0.value(for: metric) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func minValue(for metric: HealthMetric) -> Double? {
        dailyData.compactMap { $0.value(for: metric) }.min()
    }

    private func maxValue(for metric: HealthMetric) -> Double? {
        dailyData.compactMap { $0.value(for: metric) }.max()
    }

    private func trendPercentage(for metric: HealthMetric) -> Double? {
        let values = dailyData.compactMap { day -> (Date, Double)? in
            guard let metricValue = day.value(for: metric) else { return nil }
            return (day.dayStart, metricValue)
        }
        guard values.count >= 4 else { return nil }

        let midpoint = values.count / 2
        let firstHalf = values[..<midpoint].map(\.1)
        let secondHalf = values[midpoint...].map(\.1)

        let avgFirst = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let avgSecond = secondHalf.reduce(0, +) / Double(secondHalf.count)

        guard avgFirst != 0 else { return nil }
        return ((avgSecond - avgFirst) / abs(avgFirst)) * 100
    }

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
        let padding = span * 0.08
        return baseline...(maxVal + padding)
    }

    private func generateInsight() -> String? {
        guard let trend = trendPercentage(for: spotlightMetric) else { return nil }
        let name = spotlightMetric.title.lowercased()
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

    var body: some View {
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
                        yStart: .value("Baseline", areaBaseline),
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
                .chartYScale(domain: areaBaseline...(points.map(\.value).max() ?? 1) * 1.05)
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
