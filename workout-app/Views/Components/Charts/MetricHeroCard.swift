import SwiftUI

/// The headline block for a metric screen.
///
/// The previous hero led with the most recent reading, which for anything that
/// accrues through the day meant a half-finished number: "2 flights" sitting above
/// "Averaging 62 flights". This leads with the period average — the figure the rest
/// of the screen is actually about — and gives today its own clearly labelled row
/// with an honest pace projection.
struct MetricHeroCard: View {

    let metric: HealthMetric
    let analysis: MetricSeriesAnalysis
    let rangeLabel: String
    let previousAverage: Double?

    private var previousDelta: TrendDelta? {
        guard let mean = analysis.mean, let previousAverage else { return nil }
        return TrendDelta(
            current: mean,
            previous: previousAverage,
            higherIsBetter: metric.polarity != .lowerIsBetter
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            titleRow
            averageBlock

            if let range = analysis.typicalRange, analysis.completed.count >= 5 {
                MetricRangePositionBar(
                    metric: metric,
                    minimum: analysis.minimum ?? range.lowerBound,
                    maximum: analysis.maximum ?? range.upperBound,
                    typical: range,
                    marker: analysis.comparableTodayValue,
                    markerLabel: analysis.isTodayPartial ? "on pace" : "latest"
                )
            }

            if let todaySample = analysis.todaySample {
                Rectangle().fill(Theme.Colors.rule).frame(height: 1)
                todayRow(todaySample)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    private var titleRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(metric.accentColor)
                .frame(width: 4, height: 16)
                .accessibilityHidden(true)

            Text(rangeLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer(minLength: 0)

            if let previousDelta {
                DeltaTag(delta: previousDelta, suffix: "vs prior")
            }
        }
    }

    private var averageBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(analysis.mean.map(metric.formatDisplay) ?? "--")
                    .font(Theme.Typography.metricLarge)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(metric.displayUnit)
                    .font(Theme.Typography.title4)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Text(subtitle)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitle: String {
        let count = analysis.completed.count
        guard count > 0 else { return "No completed \(metric.dailyNoun)s in this range" }
        let noun = count == 1 ? metric.dailyNoun : "\(metric.dailyNoun)s"
        return "Daily average over \(count) \(noun)"
    }

    @ViewBuilder
    private func todayRow(_ sample: MetricDaySample) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(analysis.isTodayPartial ? "Today so far" : "Latest")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Spacer(minLength: 0)

                if let standing = MetricNarrative.todayStanding(for: analysis) {
                    Text(standing)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.sm) {
                Text(metric.formatWithUnit(sample.value))
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if analysis.isTodayPartial, let projected = analysis.projectedTodayTotal {
                    Text("on pace for \(metric.formatWithUnit(projected))")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(metric.accentColor)
                }

                Spacer(minLength: 0)
            }

            if analysis.isTodayPartial {
                dayProgressBar
            }
        }
    }

    private var dayProgressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.textPrimary.opacity(0.07))
                    Capsule()
                        .fill(metric.accentColor.opacity(0.55))
                        .frame(width: geometry.size.width * analysis.dayFractionElapsed)
                }
            }
            .frame(height: 5)

            Text("\(Int((analysis.dayFractionElapsed * 100).rounded()))% through the day")
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

// MARK: - Range position bar

/// Places a single value on the full span of the period, with the middle-50% band
/// called out. Answers "is this normal for me" faster than any number can.
struct MetricRangePositionBar: View {

    let metric: HealthMetric
    let minimum: Double
    let maximum: Double
    let typical: ClosedRange<Double>
    let marker: Double?
    var markerLabel: String = "now"

    private var span: Double { max(maximum - minimum, .ulpOfOne) }

    private func fraction(_ value: Double) -> CGFloat {
        CGFloat(min(max((value - minimum) / span, 0), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let bandStart = fraction(typical.lowerBound) * width
                let bandWidth = max(2, (fraction(typical.upperBound) - fraction(typical.lowerBound)) * width)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.textPrimary.opacity(0.06))

                    Capsule()
                        .fill(metric.accentColor.opacity(0.3))
                        .frame(width: bandWidth)
                        .offset(x: bandStart)

                    if let marker {
                        Capsule()
                            .fill(metric.accentColor)
                            .frame(width: 3)
                            .offset(x: min(max(fraction(marker) * width - 1.5, 0), width - 3))
                    }
                }
            }
            .frame(height: 10)

            HStack(spacing: 0) {
                Text(metric.formatDisplay(minimum))
                Spacer(minLength: Theme.Spacing.sm)
                Text("typical \(metric.formatDisplay(typical.lowerBound))–\(metric.formatDisplay(typical.upperBound))")
                    .foregroundStyle(metric.accentColor)
                Spacer(minLength: Theme.Spacing.sm)
                Text(metric.formatDisplay(maximum))
            }
            .font(Theme.Typography.caption2)
            .foregroundStyle(Theme.Colors.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Range position")
        .accessibilityValue(
            marker.map {
                "\(markerLabel) \(metric.formatWithUnit($0)), typical range "
                    + "\(metric.formatWithUnit(typical.lowerBound)) to \(metric.formatWithUnit(typical.upperBound))"
            } ?? "typical range \(metric.formatWithUnit(typical.lowerBound)) to \(metric.formatWithUnit(typical.upperBound))"
        )
    }
}
