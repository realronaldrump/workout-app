import Combine
import SwiftUI

struct HealthMetricDetailView: View {
    let metric: HealthMetric

    @EnvironmentObject var healthManager: HealthViewStore
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: MetricScreenModel?
    @State private var hasComputedOnce = false

    private var earliestDate: Date? {
        healthManager.dailyHealthStore.keys.min()
    }

    /// Recomputation is keyed rather than fired from every publisher emission, so a
    /// sync that changes nothing this screen shows does not rebuild the statistics.
    private var refreshKey: MetricRefreshKey {
        MetricRefreshKey(
            metric: metric,
            selectedRange: dateRangeContext.selectedRange,
            customRange: dateRangeContext.customRange,
            sampleCount: healthManager.dailyHealthStore.count,
            lastSync: healthManager.lastDailySyncDate
        )
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let model {
                        content(model)
                    } else if hasComputedOnce {
                        emptyState
                    } else {
                        loadingSkeleton
                    }
                }
                .padding(.vertical, Theme.Spacing.xl)
                .padding(.horizontal, Theme.Spacing.lg)
                .contentColumn()
            }
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HealthDateRangeToolbarMenu(earliestDate: earliestDate)
            }
        }
        .task(id: refreshKey) {
            await recompute()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ model: MetricScreenModel) -> some View {
        MetricHeroCard(
            metric: metric,
            analysis: model.analysis,
            rangeLabel: model.rangeLabel,
            previousAverage: model.previousAverage
        )
        .staggeredAppear(index: 0)

        trendCard(model)
            .staggeredAppear(index: 1)

        MetricInsightList(insights: model.insights, tint: metric.accentColor)

        if model.analysis.hasEnoughDataForRhythm {
            MetricRhythmStrip(
                metric: metric,
                stats: model.analysis.weekdayStats,
                strongest: model.analysis.strongestWeekday,
                weakest: model.analysis.weakestWeekday,
                chartForm: model.analysis.suggestedChartForm
            )
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
        }

        if model.analysis.samples.count >= 14 {
            MetricCalendarGrid(metric: metric, analysis: model.analysis)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 1)
        }

        if metric == .sleep && !model.sleepSummaries.isEmpty {
            sleepBreakdownSection(model.sleepSummaries)
        }
    }

    private func trendCard(_ model: MetricScreenModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(model.analysis.suggestedChartForm == .bars ? "Every \(metric.dailyNoun.capitalized)" : "Trend")
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textPrimary)

            MetricTrendChart(
                metric: metric,
                analysis: model.analysis,
                domain: model.domain
            )

            Divider().overlay(Theme.Colors.border.opacity(0.5))

            statFooter(model.analysis)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    /// Reference numbers the hero deliberately leaves out. Kept as one quiet row so
    /// they support the chart rather than competing with it, which is what the four
    /// large tinted tiles used to do.
    private func statFooter(_ analysis: MetricSeriesAnalysis) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 84), spacing: Theme.Spacing.md)],
            alignment: .leading,
            spacing: Theme.Spacing.md
        ) {
            footerStat("Median", analysis.median.map(metric.formatDisplay))
            footerStat(metric.polarity == .lowerIsBetter ? "Lowest" : "Best", analysis.bestDay.map { metric.formatDisplay($0.value) })
            footerStat(metric.polarity == .lowerIsBetter ? "Highest" : "Quietest", analysis.worstDay.map { metric.formatDisplay($0.value) })
            footerStat("Recorded", "\(analysis.samples.count) \(metric.dailyNoun)s")
        }
    }

    private func footerStat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.microLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(0.8)
                .textCase(.uppercase)
            Text(value ?? "--")
                .font(Theme.Typography.subheadlineBold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - States

    private var emptyState: some View {
        EmptyStateCard(
            icon: metric.icon,
            tint: metric.accentColor,
            title: "No \(metric.title.lowercased()) data",
            message: "Choose a longer range or sync recent Apple Health data."
        )
    }

    /// A shaped placeholder reads as "loading this screen" where a bare spinner
    /// reads as "stalled".
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge, style: .continuous)
                .fill(metric.accentColor.opacity(0.08))
                .frame(height: 190)
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .fill(Theme.Colors.textPrimary.opacity(0.045))
                .frame(height: 300)
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .fill(Theme.Colors.textPrimary.opacity(0.045))
                .frame(height: 120)
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading \(metric.title)")
    }

    // MARK: - Sleep breakdown

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
                            sleepStageRow(stage: stage, hours: hours, maxHours: maxHours)
                        }
                    }
                }
            }

            if fallbackCount > 0 {
                Text(
                    "\(fallbackCount) night\(fallbackCount == 1 ? "" : "s") used a fallback sleep source "
                    + "because the preferred source had no usable sleep data."
                )
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func sleepStageRow(stage: SleepStage, hours: Double, maxHours: Double) -> some View {
        let fraction = maxHours > 0 ? hours / maxHours : 0

        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(stage.label)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(String(format: "%.1fh", hours))
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            GeometryReader { geo in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [sleepStageColor(stage).opacity(0.55), sleepStageColor(stage)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * fraction))
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 22 : 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.label)
        .accessibilityValue(String(format: "%.1f hours average", hours))
    }

    private func sleepStageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .deep: return MetricVisualStyle.indigo
        case .rem: return MetricVisualStyle.violet
        case .core: return MetricVisualStyle.sky
        case .awake: return MetricVisualStyle.amber
        case .inBed: return Theme.Colors.textSecondary
        case .unknown: return Theme.Colors.textTertiary
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

    // MARK: - Computation

    /// Pulls the raw values on the main actor (a cheap dictionary walk) and hands the
    /// statistics off the main actor, so scrolling stays smooth on long histories.
    private func recompute() async {
        let store = healthManager.dailyHealthStore
        let resolvedRange = dateRangeContext.resolvedRange(earliest: store.keys.min())
        let ranges = HealthDayComparisonRanges(
            resolvedRange: resolvedRange,
            comparesPreviousPeriod: dateRangeContext.selectedRange != .allTime
        )

        var samples: [MetricDaySample] = []
        var previousValues: [Double] = []
        var sleepSummaries: [SleepSummary] = []
        let calendar = Calendar.current

        for day in store.values {
            let dayStart = calendar.startOfDay(for: day.dayStart)
            if ranges.display.contains(dayStart) {
                if let value = day.value(for: metric) {
                    samples.append(
                        MetricDaySample(date: dayStart, value: metric.displayValue(from: value))
                    )
                }
                if metric == .sleep, let summary = day.sleepSummary {
                    sleepSummaries.append(summary)
                }
            } else if ranges.previousComparison?.contains(dayStart) == true,
                      let value = day.value(for: metric) {
                previousValues.append(metric.displayValue(from: value))
            }
        }

        guard !samples.isEmpty else {
            model = nil
            hasComputedOnce = true
            return
        }

        let capturedSamples = samples
        let capturedMetric = metric
        let analysis = await Task.detached(priority: .userInitiated) {
            MetricSeriesAnalysis(
                metric: capturedMetric,
                samples: capturedSamples,
                range: resolvedRange
            )
        }.value

        guard !Task.isCancelled else { return }

        let previousAverage = previousValues.isEmpty
            ? nil
            : previousValues.reduce(0, +) / Double(previousValues.count)

        model = MetricScreenModel(
            analysis: analysis,
            insights: MetricNarrative.insights(for: analysis),
            previousAverage: previousAverage,
            rangeLabel: dateRangeContext.rangeLabel(earliest: store.keys.min()),
            domain: ranges.display.lowerBound...max(ranges.display.lowerBound, ranges.display.upperBound),
            sleepSummaries: sleepSummaries.sorted { $0.start < $1.start }
        )
        hasComputedOnce = true
    }
}

// MARK: - Supporting types

private struct MetricScreenModel {
    let analysis: MetricSeriesAnalysis
    let insights: [MetricInsight]
    let previousAverage: Double?
    let rangeLabel: String
    let domain: ClosedRange<Date>
    let sleepSummaries: [SleepSummary]
}

private struct MetricRefreshKey: Hashable {
    let metric: HealthMetric
    let selectedRange: AppTimeRange
    let customRange: DateInterval
    let sampleCount: Int
    let lastSync: Date?
}
