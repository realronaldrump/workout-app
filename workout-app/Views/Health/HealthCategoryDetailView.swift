import Combine
import SwiftUI

struct HealthCategoryDetailView: View {
    let category: HealthHubCategory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var healthManager: HealthViewStore
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext

    @State private var model: CategoryScreenModel?
    @State private var hasComputedOnce = false

    private var refreshKey: CategoryRefreshKey {
        CategoryRefreshKey(
            category: category,
            selectedRange: dateRangeContext.selectedRange,
            customRange: dateRangeContext.customRange,
            dataRevision: healthManager.dailyDataRevision
        )
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let model {
                        categoryHeader(rangeLabel: model.rangeLabel)

                        HealthDateRangeSection(earliestDate: model.earliestDate)

                        spotlightSection(model)

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
                        categoryHeader(rangeLabel: dateRangeContext.rangeLabel(earliest: healthManager.dailySnapshot.earliestDate))
                        HealthDateRangeSection(earliestDate: healthManager.dailySnapshot.earliestDate)
                        emptyState
                    } else {
                        loadingSkeleton
                    }
                }
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Layout.screenGutter)
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
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(category.title)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(category.subtitle)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    TintMark(tint: metric.accentColor, height: 20)
                    Text(metric.title)
                        .font(Theme.Typography.sectionHeader2)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: Theme.Spacing.sm)

                    if let delta = snapshot.previousDelta {
                        DeltaTag(delta: delta, suffix: "vs prior")
                    }

                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .accessibilityHidden(true)
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
                            .font(Theme.Typography.title4)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Text("Daily average over \(analysis.completed.count) \(metric.dailyNoun)\(analysis.completed.count == 1 ? "" : "s")")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                if analysis.samples.count >= 2 {
                    MetricMiniChart(metric: metric, analysis: analysis, height: 120)
                }

                Rectangle()
                    .fill(Theme.Colors.rule)
                    .frame(height: 1)

                let statsLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
                    : AnyLayout(StatColumns())
                statsLayout {
                    SpotlightStat(
                        label: "Typical",
                        value: analysis.typicalRange.map {
                            "\(metric.formatDisplay($0.lowerBound))–\(metric.formatDisplay($0.upperBound))"
                        } ?? "--",
                        unit: metric.displayUnit
                    )
                    SpotlightStat(
                        label: metric.polarity == .lowerIsBetter ? "Lowest" : "Best",
                        value: analysis.bestDay.map { metric.formatDisplay($0.value) } ?? "--",
                        unit: metric.displayUnit
                    )
                    SpotlightStat(
                        label: analysis.isTodayPartial ? "Today so far" : "Latest",
                        value: analysis.todaySample.map { metric.formatDisplay($0.value) } ?? "--",
                        unit: metric.displayUnit
                    )
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard()
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardButtonStyle())
    }

    // MARK: - Secondary metrics

    private func secondarySection(_ snapshots: [CategoryMetricSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(title: "Other metrics", subtitle: "Daily averages for the range")

            VStack(spacing: 0) {
                ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                    NavigationLink {
                        HealthMetricDetailView(metric: snapshot.metric)
                    } label: {
                        CategoryMetricRow(snapshot: snapshot, showsRule: index > 0)
                    }
                    .buttonStyle(PressableCardButtonStyle())
                }
            }
        }
    }

    private func unavailableMetricsDisclosure(_ unavailableMetrics: [HealthMetric]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text("No readings in this range: \(unavailableMetrics.map(\.title).joined(separator: ", ")).")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            AppHelpButton(
                title: "Unavailable metrics",
                message: "Your devices may not record these metrics, access may be off, or there may be no readings in this range."
            )
        }
        .ledgerRow()
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
            HealthEmptyStateActions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerRow()
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SkeletonRect(width: 180, height: 44, cornerRadius: Theme.CornerRadius.small)
            SkeletonRect(height: 330, cornerRadius: Theme.CornerRadius.xlarge)
            ForEach(0..<3, id: \.self) { _ in
                SkeletonRect(height: 64, cornerRadius: Theme.CornerRadius.small)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading \(category.title)")
    }

    // MARK: - Computation

    /// One pass over the store fills every metric's series, then the statistics for
    /// all of them are built together off the main actor. The previous version built
    /// a snapshot per metric inline, re-walking and re-sorting the store each time.
    private func recompute() async {
        let request = refreshKey
        let snapshot = healthManager.dailySnapshot
        let earliestDate = snapshot.earliestDate
        let reference = Date()
        let resolvedRange = dateRangeContext.resolvedRange(reference: reference, earliest: earliestDate)
        let rangeLabel = dateRangeContext.rangeLabel(reference: reference, earliest: earliestDate)
        let ranges = HealthDayComparisonRanges(
            resolvedRange: resolvedRange,
            comparesPreviousPeriod: dateRangeContext.selectedRange != .allTime
        )
        let metrics = HealthMetric.metrics(for: category)
        let worker = Task.detached(priority: .userInitiated) {
            try HealthMetricRangeAnalysis(
                snapshot: snapshot, metrics: metrics, ranges: ranges,
                resolvedRange: resolvedRange, now: reference
            )
        }
        let result = try? await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled, request == refreshKey, let result else { return }

        let snapshots: [CategoryMetricSnapshot] = metrics.compactMap { metric in
            guard let analysis = result.analyses[metric], !analysis.samples.isEmpty else { return nil }
            let previous = result.previousAverages[metric]
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
            rangeLabel: rangeLabel,
            earliestDate: earliestDate
        )
        hasComputedOnce = true
    }
}

// MARK: - Metric row

private struct CategoryMetricRow: View {
    let snapshot: CategoryMetricSnapshot
    var showsRule = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var metric: HealthMetric { snapshot.metric }
    private var analysis: MetricSeriesAnalysis { snapshot.analysis }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.md))
        layout {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Theme.Spacing.sm) {
                    TintMark(tint: metric.accentColor)
                    Text(metric.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                }
                if let delta = snapshot.previousDelta {
                    DeltaTag(delta: delta, suffix: "vs prior")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize, analysis.samples.count >= 2 {
                Sparkline(values: analysis.samples.map(\.value), tint: metric.accentColor, areaFill: false)
                    .frame(width: 72, height: 30)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(analysis.mean.map(metric.formatDisplay) ?? "--")
                    .font(Theme.Typography.number)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(metric.displayUnit)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(minWidth: 96, alignment: .trailing)
        }
        .ledgerRow(showsRule: showsRule)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(metric.title)")
    }
}

// MARK: - Spotlight stat

private struct SpotlightStat: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
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
    let dataRevision: UInt64
}
