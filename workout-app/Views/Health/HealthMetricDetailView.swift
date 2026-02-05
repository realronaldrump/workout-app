import SwiftUI
import Charts

struct HealthMetricDetailView: View {
    let metric: HealthMetric
    let range: DateInterval
    let rangeLabel: String

    @EnvironmentObject var healthManager: HealthKitManager

    @State private var showRawSamples = false
    @State private var rawSamples: [HealthMetricSample] = []
    @State private var isLoadingSamples = false
    @State private var sampleError: String?

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

                    if metric.supportsSamples {
                        rawSamplesSection
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: showRawSamples) { _, newValue in
            if newValue {
                loadRawSamples()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(rangeLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No data in this range")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Try a longer time range or sync Apple Health.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.xl)
        .glassBackground(elevation: 1)
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
        .glassBackground(elevation: 1)
    }

    private var statsSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.md) {
                MetricStatCard(title: "Average", value: averageValue.map(metric.format) ?? "--", unit: metric.displayUnit)
                MetricStatCard(title: "Min", value: minValue.map(metric.format) ?? "--", unit: metric.displayUnit)
                MetricStatCard(title: "Max", value: maxValue.map(metric.format) ?? "--", unit: metric.displayUnit)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                MetricStatCard(title: "Average", value: averageValue.map(metric.format) ?? "--", unit: metric.displayUnit)
                MetricStatCard(title: "Min", value: minValue.map(metric.format) ?? "--", unit: metric.displayUnit)
                MetricStatCard(title: "Max", value: maxValue.map(metric.format) ?? "--", unit: metric.displayUnit)
            }
        }
    }

    private var sleepBreakdownSection: some View {
        let summaries = dailyData.compactMap { $0.sleepSummary }
        let count = Double(summaries.count)
        let stageAverages = averageSleepStages(summaries: summaries)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Sleep Stages")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if count == 0 {
                Text("No sleep stage data available.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(SleepStage.allCases.filter { $0 != .unknown }, id: \.self) { stage in
                    if let hours = stageAverages[stage] {
                        HStack {
                            Text(stage.label)
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Spacer()
                            Text(String(format: "%.1f h", hours))
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 1)
    }

    private var rawSamplesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Toggle(isOn: $showRawSamples) {
                Text("Show Raw Samples")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.Colors.accent))

            if showRawSamples {
                if isLoadingSamples {
                    ProgressView()
                        .tint(Theme.Colors.accent)
                } else if let sampleError {
                    Text(sampleError)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else if rawSamples.isEmpty {
                    Text("No raw samples available.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    let samplePoints = rawSamples.map {
                        HealthTrendPoint(
                            date: $0.timestamp,
                            value: metric.displayValue(from: $0.value),
                            label: metric.title
                        )
                    }

                    InteractiveTimeSeriesChart(
                        points: samplePoints,
                        color: metric.chartColor,
                        areaFill: false,
                        height: 180,
                        fullDomain: range.start...range.end,
                        valueText: { tooltipValueText(displayValue: $0) },
                        dateText: { $0.formatted(date: .abbreviated, time: .shortened) }
                    )
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 1)
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

    private func loadRawSamples() {
        guard metric.supportsSamples else { return }

        isLoadingSamples = true
        sampleError = nil

        Task {
            do {
                rawSamples = try await healthManager.fetchMetricSamples(metric: metric, range: range)
            } catch {
                sampleError = error.localizedDescription
            }
            isLoadingSamples = false
        }
    }
}

private struct MetricStatCard: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
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
        .glassBackground(elevation: 1)
    }
}
