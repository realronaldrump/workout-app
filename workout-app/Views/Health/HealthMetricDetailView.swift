import SwiftUI

struct HealthMetricDetailView: View {
    let metric: HealthMetric

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

    private var points: [HealthTrendPoint] {
        dailyData.compactMap { day in
            guard let value = day.value(for: metric) else { return nil }
            return HealthTrendPoint(date: day.dayStart, value: value, label: metric.title)
        }
    }

    private var chartPoints: [HealthTrendPoint] {
        points.map { point in
            HealthTrendPoint(
                date: point.date,
                value: metric.displayValue(from: point.value),
                label: point.label
            )
        }
    }

    private var values: [Double] {
        points.map { $0.value }
    }

    private var averageValue: Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var minValue: Double? {
        values.min()
    }

    private var maxValue: Double? {
        values.max()
    }

    private var minPoint: HealthTrendPoint? {
        guard let minValue else { return nil }
        // If multiple days share the same min, prefer the most recent occurrence.
        return points
            .filter { $0.value == minValue }
            .max(by: { $0.date < $1.date })
    }

    private var maxPoint: HealthTrendPoint? {
        guard let maxValue else { return nil }
        // If multiple days share the same max, prefer the most recent occurrence.
        return points
            .filter { $0.value == maxValue }
            .max(by: { $0.date < $1.date })
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    headerSection

                    if points.isEmpty {
                        emptyState
                    } else {
                        dailyChartSection
                        statsSection
                    }

                    if metric == .sleep {
                        sleepBreakdownSection
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HealthDateRangeToolbarMenu(earliestDate: earliestDate)
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: metric.icon)
                .font(Theme.Iconography.title3)
                .foregroundStyle(metric.chartColor)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(metric.chartColor.opacity(Theme.Opacity.subtleFill))
                )
                .overlay(
                    Circle()
                        .strokeBorder(metric.chartColor.opacity(0.15), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let latest = values.last {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(metric.format(latest))
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(metric.displayUnit)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                Text(rangeLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .tintedSection(metric.chartColor)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No data in this range")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Try a longer time range or use Settings to sync more Apple Health data.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    private var dailyChartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Daily Trend")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            InteractiveTimeSeriesChart(
                points: chartPoints,
                color: metric.chartColor,
                areaFill: true,
                height: 180,
                fullDomain: range.start...range.end,
                valueText: { tooltipValueText(displayValue: $0) }
            )
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

	    private var statsSection: some View {
	        let includeDayForExtremes = metric == .bodyMass

	        return ViewThatFits(in: .horizontal) {
	            HStack(spacing: Theme.Spacing.md) {
                MetricStatCard(
                    title: "Average",
                    value: averageValue.map(metric.format) ?? "--",
                    unit: metric.displayUnit,
                    tint: metric.chartColor,
                    icon: "equal.circle"
                )
	                MetricStatCard(
	                    title: "Min",
                    value: minValue.map(metric.format) ?? "--",
                    unit: metric.displayUnit,
                    tint: Theme.Colors.accent,
                    icon: "arrow.down.circle",
                    subtitle: includeDayForExtremes ? minPoint.map { formatDay($0.date) } : nil
                )
                MetricStatCard(
                    title: "Max",
                    value: maxValue.map(metric.format) ?? "--",
                    unit: metric.displayUnit,
                    tint: Theme.Colors.accentSecondary,
                    icon: "arrow.up.circle",
                    subtitle: includeDayForExtremes ? maxPoint.map { formatDay($0.date) } : nil
                )
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                MetricStatCard(
                    title: "Average",
                    value: averageValue.map(metric.format) ?? "--",
                    unit: metric.displayUnit,
                    tint: metric.chartColor,
                    icon: "equal.circle"
                )
                MetricStatCard(
                    title: "Min",
                    value: minValue.map(metric.format) ?? "--",
                    unit: metric.displayUnit,
                    tint: Theme.Colors.accent,
                    icon: "arrow.down.circle",
                    subtitle: includeDayForExtremes ? minPoint.map { formatDay($0.date) } : nil
                )
                MetricStatCard(
                    title: "Max",
                    value: maxValue.map(metric.format) ?? "--",
                    unit: metric.displayUnit,
                    tint: Theme.Colors.accentSecondary,
                    icon: "arrow.up.circle",
                    subtitle: includeDayForExtremes ? maxPoint.map { formatDay($0.date) } : nil
                )
            }
        }
    }

    private func formatDay(_ date: Date) -> String {
        // Keep it compact so it fits on the stat tile.
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var sleepBreakdownSection: some View {
        let summaries = dailyData.compactMap { $0.sleepSummary }
        let count = Double(summaries.count)
        let stageAverages = averageSleepStages(summaries: summaries)
        let fallbackCount = summaries.filter(\.usedFallbackSource).count
        let maxHours = stageAverages.values.max() ?? 1

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Sleep Stages")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if count == 0 {
                Text("No sleep stage data available.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(SleepStage.allCases.filter { $0 != .unknown }, id: \.self) { stage in
                        if let hours = stageAverages[stage] {
                            HStack(spacing: Theme.Spacing.md) {
                                Text(stage.label)
                                    .font(Theme.Typography.subheadline)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .frame(width: 70, alignment: .leading)

                                GeometryReader { geo in
                                    let fraction = maxHours > 0 ? hours / maxHours : 0
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                        .fill(sleepStageColor(stage).opacity(0.7))
                                        .frame(width: max(4, geo.size.width * fraction))
                                }
                                .frame(height: 18)

                                Text(String(format: "%.1fh", hours))
                                    .font(Theme.Typography.monoSmall)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .frame(width: 42, alignment: .trailing)
                            }
                        }
                    }
                }
            }

            if fallbackCount > 0 {
                Text(
                    "\(fallbackCount) night\(fallbackCount == 1 ? "" : "s") used a fallback sleep source " +
                    "because the preferred source had no usable sleep data."
                )
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func sleepStageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .deep: return Theme.Colors.accent
        case .rem: return Theme.Colors.accentTertiary
        case .core: return Theme.Colors.accentSecondary
        case .awake: return Theme.Colors.error
        case .inBed: return Theme.Colors.textSecondary
        case .unknown: return Theme.Colors.textTertiary
        }
    }

    private func tooltipValueText(displayValue: Double) -> String {
        let formatted = metric.formatDisplay(displayValue)
        switch metric.displayUnit {
        case "%":
            return "\(formatted)\(metric.displayUnit)"
        case "":
            return formatted
        default:
            return "\(formatted) \(metric.displayUnit)"
        }
    }

    private func averageSleepStages(summaries: [SleepSummary]) -> [SleepStage: Double] {
        guard !summaries.isEmpty else { return [:] }
        var totals: [SleepStage: TimeInterval] = [:]

        for summary in summaries {
            for (stage, duration) in summary.stageDurations {
                totals[stage, default: 0] += duration
            }
        }

        let count = Double(summaries.count)
        return totals.mapValues { ($0 / count) / 3600 }
    }
}

private struct MetricStatCard: View {
    let title: String
    let value: String
    let unit: String
    var tint: Color = Theme.Colors.accent
    var icon: String?
    let subtitle: String?

    init(title: String, value: String, unit: String, tint: Color = Theme.Colors.accent, icon: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.value = value
        self.unit = unit
        self.tint = tint
        self.icon = icon
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer(minLength: 0)

                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.Typography.number)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(unit)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(tint.opacity(Theme.Opacity.subtleFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(tint.opacity(0.12), lineWidth: 1)
        )
    }
}
