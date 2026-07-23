import SwiftUI

struct DailyHealthDetailView: View {
    let day: DailyHealthData
    private let maxContentWidth: CGFloat = 760
    private var overviewColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 132, maximum: 210), spacing: Theme.Spacing.md)]
    }

    private var dayTitle: String {
        day.dayStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var overviewItems: [DailyOverviewItem] {
        var items: [DailyOverviewItem] = []

        if let steps = day.steps {
            items.append(
                DailyOverviewItem(
                    title: "Steps",
                    value: "\(Int(steps))",
                    unit: "steps",
                    icon: "figure.walk",
                    tint: Theme.Colors.warning
                )
            )
        }

        if let sleep = day.sleepSummary?.totalHours {
            items.append(
                DailyOverviewItem(
                    title: "Sleep",
                    value: String(format: "%.1f", sleep),
                    unit: "h",
                    icon: "moon.zzz.fill",
                    tint: Theme.Colors.accentSecondary
                )
            )
        }

        if let activeEnergy = day.activeEnergy {
            items.append(
                DailyOverviewItem(
                    title: "Energy",
                    value: "\(Int(activeEnergy))",
                    unit: "cal",
                    icon: "flame.fill",
                    tint: Theme.Colors.warning
                )
            )
        }

        if let restingHeartRate = day.restingHeartRate {
            items.append(
                DailyOverviewItem(
                    title: "Resting HR",
                    value: "\(Int(restingHeartRate))",
                    unit: "bpm",
                    icon: "heart",
                    tint: Theme.Colors.error
                )
            )
        }

        return items
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    headerSection

                    if !overviewItems.isEmpty {
                        overviewSection
                    }

                    if let sleepSummary = day.sleepSummary {
                        sleepSummarySection(summary: sleepSummary)
                    }

                    metricsSection(title: "Activity", metrics: HealthMetric.metrics(for: .activity))
                    metricsSection(title: "Heart", metrics: HealthMetric.metrics(for: .heart))
                    metricsSection(title: "Vitals", metrics: HealthMetric.metrics(for: .vitals))
                    metricsSection(title: "Cardio", metrics: HealthMetric.metrics(for: .cardio))
                    metricsSection(title: "Body", metrics: HealthMetric.metrics(for: .body))
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Daily Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(dayTitle)
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)

            if Calendar.current.isDateInToday(day.dayStart) {
                Text("Today")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if Calendar.current.isDateInYesterday(day.dayStart) {
                Text("Yesterday")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var overviewSection: some View {
        LazyVGrid(columns: overviewColumns, spacing: Theme.Spacing.md) {
            ForEach(overviewItems) { item in
                DailyOverviewCard(item: item)
            }
        }
    }

    @ViewBuilder
    private func metricsSection(title: String, metrics: [HealthMetric]) -> some View {
        let availableMetrics = metrics.filter { metric in
            metric != .sleep && day.value(for: metric) != nil
        }

        if !availableMetrics.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(availableMetrics) { metric in
                        NavigationLink {
                            HealthMetricDetailView(metric: metric)
                        } label: {
                            DailyMetricRow(metric: metric, value: day.value(for: metric))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sleepSummarySection(summary: SleepSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Sleep")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f", summary.totalHours))
                    .font(Theme.Typography.number)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("h asleep")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(SleepStage.allCases.filter { $0 != .unknown }, id: \.self) { stage in
                    if let duration = summary.stageDurations[stage] {
                        HStack {
                            Text(stage.label)
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Spacer()
                            Text(String(format: "%.1f h", duration / 3600))
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                }
            }

            SleepSourceAttributionView(summary: summary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

private struct DailyOverviewItem: Identifiable {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color

    var id: String { title }
}

private struct DailyOverviewCard: View {
    let item: DailyOverviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: item.icon)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(item.tint)
                Text(item.title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(item.value)
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !item.unit.isEmpty {
                    Text(item.unit)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(elevation: 1)
    }
}

private struct DailyMetricRow: View {
    let metric: HealthMetric
    let value: Double?

    var body: some View {
        HStack {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: metric.icon)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(metric.chartColor)
                Text(metric.title)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            Spacer()

            if let value {
                Text(metric.format(value))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(metric.displayUnit)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else {
                Text("--")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Image(systemName: "chevron.right")
                .font(Theme.Typography.caption2Bold)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}
