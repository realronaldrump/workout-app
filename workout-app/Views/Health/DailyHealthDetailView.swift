import SwiftUI

struct DailyHealthDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let day: DailyHealthData

    private var dayLead: String {
        if Calendar.current.isDateInToday(day.dayStart) { return "Today" }
        if Calendar.current.isDateInYesterday(day.dayStart) { return "Yesterday" }
        return day.dayStart.formatted(.dateTime.weekday(.wide))
    }

    private var dayTitle: String {
        let sameYear = Calendar.current.isDate(day.dayStart, equalTo: .now, toGranularity: .year)
        return sameYear
            ? day.dayStart.formatted(.dateTime.month(.wide).day())
            : day.dayStart.formatted(.dateTime.month(.wide).day().year())
    }

    private var overviewItems: [DailyOverviewItem] {
        var items: [DailyOverviewItem] = []
        if let steps = day.steps {
            items.append(DailyOverviewItem(label: "steps", value: Int(steps).formatted()))
        }
        if let sleep = day.sleepSummary?.totalHours {
            items.append(DailyOverviewItem(label: "h asleep", value: String(format: "%.1f", sleep)))
        }
        if let activeEnergy = day.activeEnergy {
            items.append(DailyOverviewItem(label: "active cal", value: Int(activeEnergy).formatted()))
        }
        if let restingHeartRate = day.restingHeartRate {
            items.append(DailyOverviewItem(label: "resting bpm", value: "\(Int(restingHeartRate))"))
        }
        return items
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        headerSection

                        if !overviewItems.isEmpty {
                            overviewSection
                        }
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
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xxl)
                .contentColumn()
            }
        }
        .navigationTitle(dayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("health-day-detail")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dayLead)
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(dayTitle)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .combine)
    }

    private var overviewSection: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
            : AnyLayout(StatColumns())
        return layout {
            ForEach(overviewItems) { item in
                DisplayStat(value: item.value, label: item.label, valueFont: Theme.Typography.number)
            }
        }
        .padding(.vertical, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    @ViewBuilder
    private func metricsSection(title: String, metrics: [HealthMetric]) -> some View {
        let availableMetrics = metrics.filter { metric in
            metric != .sleep && day.value(for: metric) != nil
        }

        if !availableMetrics.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SectionHeading(title: title)

                VStack(spacing: 0) {
                    ForEach(Array(availableMetrics.enumerated()), id: \.element) { index, metric in
                        NavigationLink {
                            HealthMetricDetailView(metric: metric)
                        } label: {
                            DailyMetricRow(metric: metric, value: day.value(for: metric), showsRule: index > 0)
                        }
                        .buttonStyle(PressableCardButtonStyle())
                    }
                }
            }
        }
    }

    private func sleepSummarySection(summary: SleepSummary) -> some View {
        let stages = SleepStage.allCases
            .filter { $0 != .unknown && $0 != .inBed }
            .compactMap { stage in summary.stageDurations[stage].map { (stage: stage, duration: $0) } }
            .filter { $0.duration > 0 }
        let stageTotal = stages.reduce(0) { $0 + $1.duration }

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(title: "Sleep")

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", summary.totalHours))
                    .font(Theme.Typography.metric)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("hours asleep")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)

            if stageTotal > 0 {
                SleepStageBar(stages: stages.map { ($0.stage, $0.duration / stageTotal) })
                    .frame(height: 18)

                VStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.element.stage) { index, item in
                        HStack(spacing: Theme.Spacing.sm) {
                            TintMark(tint: item.stage.tint)
                            Text(item.stage.label)
                                .font(Theme.Typography.callout)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer(minLength: Theme.Spacing.sm)
                            Text(formatDuration(item.duration))
                                .font(Theme.Typography.callout)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("\(Int((item.duration / stageTotal * 100).rounded()))%")
                                .font(Theme.Typography.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(minWidth: 40, alignment: .trailing)
                        }
                        .ledgerRow(showsRule: index > 0, verticalPadding: Theme.Spacing.sm)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            SleepSourceAttributionView(summary: summary)
        }
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
    let label: String
    let value: String

    var id: String { label }
}

/// The night as one bar, each stage's share in its step of the sleep hue.
private struct SleepStageBar: View {
    let stages: [(stage: SleepStage, share: Double)]

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let available = max(proxy.size.width - spacing * CGFloat(max(stages.count - 1, 0)), 0)
            HStack(spacing: spacing) {
                ForEach(stages, id: \.stage) { item in
                    Rectangle()
                        .fill(item.stage.tint)
                        .frame(width: max(available * item.share, 2))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}

private struct DailyMetricRow: View {
    let metric: HealthMetric
    let value: Double?
    var showsRule = true

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TintMark(tint: metric.chartColor)
            Text(metric.title)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Theme.Spacing.sm)

            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(metric.format(value))
                        .font(Theme.Typography.numberSmall)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(metric.displayUnit)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                Text("No reading")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Image(systemName: "chevron.right")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .ledgerRow(showsRule: showsRule, verticalPadding: Theme.Spacing.sm)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
