import Combine
import SwiftUI

struct HealthMetricDetailView: View {
    let metric: HealthMetric

    @EnvironmentObject var healthManager: HealthViewStore
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext
    @State private var cachedPresentation: HealthMetricPresentation?

    private var earliestDate: Date? {
        healthManager.dailyHealthStore.keys.min()
    }

    private var range: DateInterval {
        dateRangeContext.resolvedRange(earliest: earliestDate)
    }

    private var rangeLabel: String {
        dateRangeContext.rangeLabel(earliest: earliestDate)
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let presentation = cachedPresentation {
                        headerSection(presentation)

                        if presentation.points.isEmpty {
                            emptyState
                        } else {
                            dailyChartSection(presentation)
                            statsSection(presentation)
                        }

                        if metric == .sleep && !presentation.sleepSummaries.isEmpty {
                            sleepBreakdownSection(presentation.sleepSummaries)
                        }
                    } else {
                        ProgressView()
                            .tint(metric.chartColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xxl)
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

    private func headerSection(_ presentation: HealthMetricPresentation) -> some View {
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
                if let latest = presentation.latest {
                    HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(metric.format(latest))
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(metric.displayUnit)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        }

                        if let delta = presentation.delta {
                            DeltaTag(
                                delta: delta,
                                tintOverride: deltaTintOverride
                            )
                        }
                    }
                }
                Text(rangeLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)

                if let sentence = averageSentence(for: presentation) {
                    Text(sentence)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .tintedSection(metric.chartColor)
    }

    private var emptyState: some View {
        EmptyStateCard(
            icon: metric.icon,
            tint: metric.chartColor,
            title: "No \(metric.title.lowercased()) data",
            message: "Choose a longer range or sync recent Apple Health data."
        )
    }

    private func dailyChartSection(_ presentation: HealthMetricPresentation) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Daily Trend")
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textPrimary)

            InteractiveTimeSeriesChart(
                points: presentation.chartPoints,
                color: metric.chartColor,
                areaFill: true,
                height: 180,
                fullDomain: range.start...range.end,
                showsControls: false,
                showsAverageLine: true,
                averageLineValue: presentation.average.map(metric.displayValue(from:)),
                valueText: { tooltipValueText(displayValue: $0) }
            )
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func statsSection(_ presentation: HealthMetricPresentation) -> some View {
        let includeDayForExtremes = metric == .bodyMass

        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: Theme.Spacing.md
        ) {
            MetricStatCard(
                title: "Average",
                value: presentation.average.map(metric.format) ?? "--",
                unit: metric.displayUnit,
                tint: metric.chartColor,
                icon: "equal.circle"
            )
            MetricStatCard(
                title: "Prev period",
                value: presentation.previousAverage.map(metric.format) ?? "--",
                unit: metric.displayUnit,
                tint: Theme.Colors.textSecondary,
                icon: "clock.arrow.circlepath"
            )
            MetricStatCard(
                title: "Min",
                value: presentation.minimum.map(metric.format) ?? "--",
                unit: metric.displayUnit,
                tint: Theme.Colors.accent,
                icon: "arrow.down.circle",
                subtitle: includeDayForExtremes ? presentation.minimumPoint.map { formatDay($0.date) } : nil
            )
            MetricStatCard(
                title: "Max",
                value: presentation.maximum.map(metric.format) ?? "--",
                unit: metric.displayUnit,
                tint: Theme.Colors.accentSecondary,
                icon: "arrow.up.circle",
                subtitle: includeDayForExtremes ? presentation.maximumPoint.map { formatDay($0.date) } : nil
            )
        }
    }

    private func formatDay(_ date: Date) -> String {
        // Keep it compact so it fits on the stat tile.
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func sleepBreakdownSection(_ summaries: [SleepSummary]) -> some View {
        let count = Double(summaries.count)
        let stageAverages = averageSleepStages(summaries: summaries)
        let fallbackCount = summaries.filter(\.usedFallbackSource).count
        let maxHours = stageAverages.values.max() ?? 1

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Sleep Stages")
                .font(Theme.Typography.sectionHeader2)
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

    private var deltaTintOverride: Color? {
        switch metric {
        case .bodyMass, .bodyFatPercentage, .bodyTemperature:
            return Theme.Colors.textSecondary
        default:
            return nil
        }
    }

    private func averageSentence(for presentation: HealthMetricPresentation) -> String? {
        guard let average = presentation.average, let delta = presentation.delta else { return nil }
        let direction = delta.isFlat ? "flat" : (delta.percentChange > 0 ? "up" : "down")
        let change = delta.isFlat ? "" : " \(Int(abs(delta.percentChange).rounded()))%"
        let unit = metric.displayUnit.isEmpty ? "" : " \(metric.displayUnit)"
        let dayLabel = presentation.comparisonDayCount == 1
            ? "completed day"
            : "\(presentation.comparisonDayCount) completed days"
        return "Averaging \(metric.format(average))\(unit) — \(direction)\(change) vs the previous \(dayLabel)."
    }

    private func refreshPresentation(from emittedStore: [Date: DailyHealthData]? = nil) {
        let store = emittedStore ?? healthManager.dailyHealthStore
        let resolvedRange = dateRangeContext.resolvedRange(earliest: store.keys.min())
        let ranges = HealthDayComparisonRanges(
            resolvedRange: resolvedRange,
            comparesPreviousPeriod: dateRangeContext.selectedRange != .allTime
        )
        var current: [DailyHealthData] = []
        var currentComparison: [DailyHealthData] = []
        var previous: [DailyHealthData] = []

        for day in store.values {
            let dayStart = Calendar.current.startOfDay(for: day.dayStart)
            if ranges.display.contains(dayStart) {
                current.append(day)
            }
            if ranges.currentComparison?.contains(dayStart) == true {
                currentComparison.append(day)
            } else if ranges.previousComparison?.contains(dayStart) == true {
                previous.append(day)
            }
        }

        current.sort { $0.dayStart < $1.dayStart }
        currentComparison.sort { $0.dayStart < $1.dayStart }
        previous.sort { $0.dayStart < $1.dayStart }
        cachedPresentation = HealthMetricPresentation(
            metric: metric,
            dailyData: current,
            comparisonData: currentComparison.isEmpty ? current : currentComparison,
            previousData: previous,
            comparisonDayCount: ranges.comparisonDayCount
        )
    }
}

private struct HealthMetricPresentation {
    let points: [HealthTrendPoint]
    let chartPoints: [HealthTrendPoint]
    let latest: Double?
    let average: Double?
    let previousAverage: Double?
    let delta: TrendDelta?
    let minimum: Double?
    let maximum: Double?
    let minimumPoint: HealthTrendPoint?
    let maximumPoint: HealthTrendPoint?
    let sleepSummaries: [SleepSummary]
    let comparisonDayCount: Int

    init(
        metric: HealthMetric,
        dailyData: [DailyHealthData],
        comparisonData: [DailyHealthData],
        previousData: [DailyHealthData],
        comparisonDayCount: Int
    ) {
        let points = dailyData.compactMap { day -> HealthTrendPoint? in
            guard let value = day.value(for: metric) else { return nil }
            return HealthTrendPoint(date: day.dayStart, value: value, label: metric.title)
        }
        self.points = points
        chartPoints = points.map { point in
            HealthTrendPoint(
                date: point.date,
                value: metric.displayValue(from: point.value),
                label: point.label
            )
        }

        let values = points.map(\.value)
        let comparisonValues = comparisonData.compactMap { $0.value(for: metric) }
        let usesFallback = comparisonValues.isEmpty
        let averageValues = usesFallback ? values : comparisonValues
        let previousValues = previousData.compactMap { $0.value(for: metric) }
        let currentAverage = averageValues.isEmpty
            ? nil
            : averageValues.reduce(0, +) / Double(averageValues.count)
        let priorAverage = usesFallback || previousValues.isEmpty
            ? nil
            : previousValues.reduce(0, +) / Double(previousValues.count)
        latest = values.last
        average = currentAverage
        previousAverage = priorAverage
        delta = currentAverage.flatMap { current in
            priorAverage.flatMap {
                TrendDelta(
                    current: current,
                    previous: $0,
                    higherIsBetter: metric != .restingHeartRate
                )
            }
        }
        minimum = values.min()
        maximum = values.max()
        minimumPoint = Self.mostRecentPoint(matching: minimum, in: points)
        maximumPoint = Self.mostRecentPoint(matching: maximum, in: points)
        sleepSummaries = metric == .sleep ? dailyData.compactMap(\.sleepSummary) : []
        self.comparisonDayCount = comparisonDayCount
    }

    private static func mostRecentPoint(
        matching value: Double?,
        in points: [HealthTrendPoint]
    ) -> HealthTrendPoint? {
        guard let value else { return nil }
        return points.last { $0.value == value }
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
