import Combine
import SwiftUI

struct HealthCategoryDetailView: View {
    let category: HealthHubCategory

    @EnvironmentObject var healthManager: HealthViewStore
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext

    @State private var model: CategoryScreenModel?
    @State private var hasComputedOnce = false

    private var refreshKey: CategoryRefreshKey {
        CategoryRefreshKey(
            category: category,
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
                        categoryHeader(rangeLabel: model.rangeLabel)
                            .staggeredAppear(index: 0)

                        HealthDateRangeSection(earliestDate: model.earliestDate)

                        spotlightSection(model)
                            .staggeredAppear(index: 1)

                        MetricInsightList(
                            insights: model.insights,
                            tint: model.spotlight.metric.accentColor
                        )

                        if !model.secondary.isEmpty {
                            secondarySection(model.secondary)
                        }

                        if !model.unavailable.isEmpty {
                            unavailableMetricsDisclosure(model.unavailable)
                        }
                    } else if hasComputedOnce {
                        categoryHeader(rangeLabel: dateRangeContext.rangeLabel(earliest: nil))
                        HealthDateRangeSection(earliestDate: nil)
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
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: refreshKey) {
            await recompute()
        }
    }

    // MARK: - Header

    private func categoryHeader(rangeLabel: String) -> some View {
        StatsPageHeader(
            eyebrow: "Health",
            title: category.title,
            subtitle: category.subtitle,
            systemImage: "heart.fill"
        ) {
            IconTile(systemImage: category.icon, tint: category.tint, size: 52)
        }
    }

    // MARK: - Spotlight

    private func spotlightSection(_ model: CategoryScreenModel) -> some View {
        let snapshot = model.spotlight
        let metric = snapshot.metric
        let analysis = snapshot.analysis

        return NavigationLink {
            HealthMetricDetailView(metric: metric)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: metric.icon)
                            .font(Theme.Iconography.mediumStrong)
                            .foregroundStyle(metric.accentColor)
                        Text(metric.title)
                            .font(Theme.Typography.sectionHeader2)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    Spacer()

                    if let delta = snapshot.previousDelta {
                        DeltaTag(delta: delta, suffix: "vs prev")
                    }

                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                // The period average leads. Today's partial total is a separate,
                // labelled figure rather than the headline it used to be.
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(analysis.mean.map(metric.formatDisplay) ?? "--")
                            .font(Theme.Typography.numberLarge)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(metric.displayUnit)
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }

                    Text("Average across \(analysis.completed.count) \(metric.dailyNoun)s")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                if analysis.samples.count >= 2 {
                    MetricMiniChart(metric: metric, analysis: analysis, height: 120)
                }

                Rectangle()
                    .fill(Theme.Colors.border.opacity(0.5))
                    .frame(height: 1)

                HStack(alignment: .top, spacing: 0) {
                    SpotlightStat(
                        label: "TYPICAL",
                        value: analysis.typicalRange.map {
                            "\(metric.formatDisplay($0.lowerBound))–\(metric.formatDisplay($0.upperBound))"
                        } ?? "--",
                        unit: metric.displayUnit
                    )
                    Spacer(minLength: Theme.Spacing.sm)
                    SpotlightStat(
                        label: metric.polarity == .lowerIsBetter ? "LOWEST" : "BEST",
                        value: analysis.bestDay.map { metric.formatDisplay($0.value) } ?? "--",
                        unit: metric.displayUnit
                    )
                    Spacer(minLength: Theme.Spacing.sm)
                    SpotlightStat(
                        label: analysis.isTodayPartial ? "TODAY SO FAR" : "LATEST",
                        value: analysis.todaySample.map { metric.formatDisplay($0.value) } ?? "--",
                        unit: metric.displayUnit
                    )
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: Theme.CornerRadius.large,
                    topTrailingRadius: Theme.CornerRadius.large,
                    style: .continuous
                )
                .fill(metric.accentGradient)
                .frame(height: 3)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Secondary metrics

    private func secondarySection(_ snapshots: [CategoryMetricSnapshot]) -> some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("ALL METRICS")
                .sectionHeaderStyle()
                .padding(.top, Theme.Spacing.sm)

            ForEach(snapshots) { snapshot in
                NavigationLink {
                    HealthMetricDetailView(metric: snapshot.metric)
                } label: {
                    CategoryMetricRow(snapshot: snapshot)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func unavailableMetricsDisclosure(_ unavailableMetrics: [HealthMetric]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(unavailableMetrics) { metric in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: metric.icon)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(metric.accentColor)
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

    // MARK: - States

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(elevation: 1)
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .fill(category.tint.opacity(0.08))
                .frame(height: 76)
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .fill(Theme.Colors.textPrimary.opacity(0.045))
                .frame(height: 330)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                    .fill(Theme.Colors.textPrimary.opacity(0.045))
                    .frame(height: 130)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading \(category.title)")
    }

    // MARK: - Computation

    /// One pass over the store fills every metric's series, then the statistics for
    /// all of them are built together off the main actor. The previous version built
    /// a snapshot per metric inline, re-walking and re-sorting the store each time.
    private func recompute() async {
        let store = healthManager.dailyHealthStore
        let earliestDate = store.keys.min()
        let resolvedRange = dateRangeContext.resolvedRange(earliest: earliestDate)
        let ranges = HealthDayComparisonRanges(
            resolvedRange: resolvedRange,
            comparesPreviousPeriod: dateRangeContext.selectedRange != .allTime
        )
        let metrics = HealthMetric.metrics(for: category)
        let calendar = Calendar.current

        var samplesByMetric: [HealthMetric: [MetricDaySample]] = [:]
        var previousTotals: [HealthMetric: (sum: Double, count: Int)] = [:]

        for day in store.values {
            let dayStart = calendar.startOfDay(for: day.dayStart)
            let inDisplay = ranges.display.contains(dayStart)
            let inPrevious = ranges.previousComparison?.contains(dayStart) == true
            guard inDisplay || inPrevious else { continue }

            for metric in metrics {
                guard let raw = day.value(for: metric) else { continue }
                let value = metric.displayValue(from: raw)
                if inDisplay {
                    samplesByMetric[metric, default: []].append(
                        MetricDaySample(date: dayStart, value: value)
                    )
                } else {
                    let existing = previousTotals[metric] ?? (0, 0)
                    previousTotals[metric] = (existing.sum + value, existing.count + 1)
                }
            }
        }

        let capturedSamples = samplesByMetric
        let analyses = await Task.detached(priority: .userInitiated) {
            capturedSamples.reduce(into: [HealthMetric: MetricSeriesAnalysis]()) { result, entry in
                result[entry.key] = MetricSeriesAnalysis(
                    metric: entry.key,
                    samples: entry.value,
                    range: resolvedRange
                )
            }
        }.value

        guard !Task.isCancelled else { return }

        let snapshots: [CategoryMetricSnapshot] = metrics.compactMap { metric in
            guard let analysis = analyses[metric], !analysis.samples.isEmpty else { return nil }
            let previous = previousTotals[metric].map { $0.sum / Double($0.count) }
            return CategoryMetricSnapshot(
                metric: metric,
                analysis: analysis,
                previousAverage: previous
            )
        }

        guard let spotlight = snapshots.first(where: { $0.metric == category.primaryMetric })
            ?? snapshots.first else {
            model = nil
            hasComputedOnce = true
            return
        }

        model = CategoryScreenModel(
            spotlight: spotlight,
            secondary: snapshots.filter { $0.metric != spotlight.metric },
            unavailable: metrics.filter { metric in !snapshots.contains { $0.metric == metric } },
            insights: MetricNarrative.insights(for: spotlight.analysis),
            rangeLabel: dateRangeContext.rangeLabel(earliest: earliestDate),
            earliestDate: earliestDate
        )
        hasComputedOnce = true
    }
}

// MARK: - Metric row

private struct CategoryMetricRow: View {
    let snapshot: CategoryMetricSnapshot

    private var metric: HealthMetric { snapshot.metric }
    private var analysis: MetricSeriesAnalysis { snapshot.analysis }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: metric.icon)
                        .font(Theme.Iconography.medium)
                        .foregroundStyle(metric.accentColor)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.small, style: .continuous)
                                .fill(metric.accentColor.opacity(Theme.Opacity.mediumFill))
                        )

                    Text(metric.title)
                        .font(Theme.Typography.subheadlineBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Spacer()

                if let delta = snapshot.previousDelta {
                    DeltaTag(delta: delta)
                }
            }

            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(analysis.mean.map(metric.formatDisplay) ?? "--")
                        .font(Theme.Typography.number)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(metric.displayUnit)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("avg")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                if let today = analysis.todaySample {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(analysis.isTodayPartial ? "TODAY SO FAR" : "LATEST")
                            .font(Theme.Typography.microLabel)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .tracking(0.6)
                        Text(metric.formatWithUnit(today.value))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }

            MetricMiniChart(metric: metric, analysis: analysis)
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.CornerRadius.large,
                bottomLeadingRadius: Theme.CornerRadius.large,
                style: .continuous
            )
            .fill(metric.accentGradient)
            .frame(width: 3)
        }
    }
}

// MARK: - Spotlight stat

private struct SpotlightStat: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.microLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(0.8)
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }
}

// MARK: - Supporting types

private struct CategoryMetricSnapshot: Identifiable {
    let metric: HealthMetric
    let analysis: MetricSeriesAnalysis
    let previousAverage: Double?

    var id: HealthMetric { metric }

    var previousDelta: TrendDelta? {
        guard let mean = analysis.mean, let previousAverage else { return nil }
        return TrendDelta(
            current: mean,
            previous: previousAverage,
            higherIsBetter: metric.polarity != .lowerIsBetter
        )
    }
}

private struct CategoryScreenModel {
    let spotlight: CategoryMetricSnapshot
    let secondary: [CategoryMetricSnapshot]
    let unavailable: [HealthMetric]
    let insights: [MetricInsight]
    let rangeLabel: String
    let earliestDate: Date?
}

private struct CategoryRefreshKey: Hashable {
    let category: HealthHubCategory
    let selectedRange: AppTimeRange
    let customRange: DateInterval
    let sampleCount: Int
    let lastSync: Date?
}
