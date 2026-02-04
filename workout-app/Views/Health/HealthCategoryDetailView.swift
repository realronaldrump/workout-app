import SwiftUI
import Charts

struct HealthCategoryDetailView: View {
    let category: HealthHubCategory
    let range: DateInterval
    let rangeLabel: String

    @EnvironmentObject var healthManager: HealthKitManager

    private var dailyData: [DailyHealthData] {
        healthManager.dailyHealthStore.values
            .filter { range.contains($0.dayStart) }
            .sorted { $0.dayStart < $1.dayStart }
    }

    private var metrics: [HealthMetric] {
        HealthMetric.metrics(for: category)
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    headerSection

                    if dailyData.isEmpty {
                        emptyState
                    } else {
                        ForEach(metrics) { metric in
                            NavigationLink {
                                HealthMetricDetailView(metric: metric, range: range, rangeLabel: rangeLabel)
                            } label: {
                                HealthMetricRow(metric: metric, points: metricPoints(for: metric), latestValue: latestValue(for: metric))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(category.subtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(rangeLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No data yet")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Sync Apple Health to see \(category.title.lowercased()) metrics.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.xl)
        .glassBackground(elevation: 1)
    }

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
}

private struct HealthMetricRow: View {
    let metric: HealthMetric
    let points: [HealthTrendPoint]
    let latestValue: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: metric.icon)
                        .font(.caption)
                        .foregroundStyle(metric.chartColor)
                    Text(metric.title)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Spacer()

                if let latestValue {
                    Text(metric.format(latestValue))
                        .font(Theme.Typography.number)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(metric.displayUnit)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                } else {
                    Text("--")
                        .font(Theme.Typography.number)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            if points.isEmpty {
                Text("No data in this range")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(metric.chartColor)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 36)
            }
        }
        .padding(Theme.Spacing.md)
        .glassBackground(elevation: 1)
    }
}
