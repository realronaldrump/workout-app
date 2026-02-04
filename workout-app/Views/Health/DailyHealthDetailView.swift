import SwiftUI

struct DailyHealthDetailView: View {
    let day: DailyHealthData

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: day.dayStart)
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    headerSection

                    overviewSection

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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.md) {
                DailyOverviewCard(title: "Steps", value: formatInt(day.steps), unit: "steps", icon: "figure.walk", tint: Theme.Colors.warning)
                DailyOverviewCard(title: "Sleep", value: day.sleepSummary.map { String(format: "%.1f", $0.totalHours) } ?? "--", unit: "h", icon: "moon.zzz.fill", tint: Theme.Colors.accentSecondary)
                DailyOverviewCard(title: "Energy", value: formatInt(day.activeEnergy), unit: "cal", icon: "flame.fill", tint: Theme.Colors.warning)
                DailyOverviewCard(title: "Resting HR", value: formatInt(day.restingHeartRate), unit: "bpm", icon: "heart", tint: Theme.Colors.error)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                DailyOverviewCard(title: "Steps", value: formatInt(day.steps), unit: "steps", icon: "figure.walk", tint: Theme.Colors.warning)
                DailyOverviewCard(title: "Sleep", value: day.sleepSummary.map { String(format: "%.1f", $0.totalHours) } ?? "--", unit: "h", icon: "moon.zzz.fill", tint: Theme.Colors.accentSecondary)
                DailyOverviewCard(title: "Energy", value: formatInt(day.activeEnergy), unit: "cal", icon: "flame.fill", tint: Theme.Colors.warning)
                DailyOverviewCard(title: "Resting HR", value: formatInt(day.restingHeartRate), unit: "bpm", icon: "heart", tint: Theme.Colors.error)
            }
        }
    }

    private func metricsSection(title: String, metrics: [HealthMetric]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(metrics) { metric in
                    if metric != .sleep {
                        DailyMetricRow(metric: metric, value: day.value(for: metric))
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

            HStack(spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f", summary.totalHours))
                        .font(Theme.Typography.number)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("h asleep")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDuration(summary.inBed))
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("in bed")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
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
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 1)
    }

    private func formatInt(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value))"
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

private struct DailyOverviewCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(elevation: 1)
    }
}

private struct DailyMetricRow: View {
    let metric: HealthMetric
    let value: Double?

    var body: some View {
        HStack {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: metric.icon)
                    .font(.caption)
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
        }
        .padding(Theme.Spacing.md)
        .glassBackground(elevation: 1)
    }
}
