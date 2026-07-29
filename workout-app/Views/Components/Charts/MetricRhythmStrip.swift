import SwiftUI

/// Average value per day of the week.
///
/// A raw timeline hides weekly structure — you can see the spikes but not that they
/// land on Tuesdays. This collapses the range onto a seven-day axis so the pattern
/// becomes the point rather than something to squint for.
///
/// Metrics that belong on a zero baseline (step counts, energy) draw as columns.
/// Metrics that never approach zero (resting heart rate, body mass) draw as a dot
/// plot on a truncated axis, because columns on a truncated axis would misstate the
/// ratios between days.
struct MetricRhythmStrip: View {

    let metric: HealthMetric
    let stats: [MetricWeekdayStat]
    let strongest: MetricWeekdayStat?
    let weakest: MetricWeekdayStat?
    /// Comes from the analysis rather than the metric, so a low-variance daily total
    /// gets the dot plot too instead of seven near-identical full-height columns.
    let chartForm: MetricChartForm

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private var calendar: Calendar { .current }

    /// Weekday columns ordered by the user's locale, starting at their first weekday.
    private var orderedStats: [MetricWeekdayStat] {
        let first = calendar.firstWeekday
        return (0..<7).compactMap { offset in
            let weekday = (first - 1 + offset) % 7 + 1
            return stats.first { $0.weekday == weekday }
        }
    }

    private var usesZeroBaseline: Bool {
        chartForm == .bars
    }

    private var scale: ClosedRange<Double> {
        let values = orderedStats.map(\.average)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        if usesZeroBaseline {
            return 0...(high <= 0 ? 1 : high * 1.05)
        }
        guard high > low else {
            let padding = max(abs(high) * 0.05, 1)
            return (low - padding)...(high + padding)
        }
        let padding = (high - low) * 0.35
        return (low - padding)...(high + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            HStack(alignment: .bottom, spacing: Theme.Spacing.xs) {
                ForEach(orderedStats) { stat in
                    column(for: stat)
                }
            }
            .frame(height: 132)

            if !usesZeroBaseline {
                Text("Axis starts at \(metric.formatWithUnit(scale.lowerBound)) — differences are small by nature for this metric.")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(Theme.Animation.gentleSpring.delay(0.05)) { hasAppeared = true }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Weekly Rhythm")
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textPrimary)

            if let strongest, let weakest, strongest.weekday != weakest.weekday {
                Text("\(fullName(strongest.weekday))s average \(metric.formatWithUnit(strongest.average)); "
                     + "\(fullName(weakest.weekday))s average \(metric.formatWithUnit(weakest.average)).")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func column(for stat: MetricWeekdayStat) -> some View {
        let fraction = normalized(stat.average)
        let isStrongest = strongest?.weekday == stat.weekday
        let isWeakest = weakest?.weekday == stat.weekday

        return VStack(spacing: 6) {
            Text(metric.formatDisplay(stat.average))
                .font(Theme.Typography.caption2)
                .foregroundStyle(isStrongest ? metric.accentColor : Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            GeometryReader { geometry in
                let height = max(4, geometry.size.height * (hasAppeared ? fraction : 0))

                ZStack(alignment: .bottom) {
                    // A visible track behind a column reads as a second stacked
                    // segment, so it is only drawn for the dot plot, where the
                    // column is otherwise just empty space.
                    if !usesZeroBaseline {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.Colors.textPrimary.opacity(0.04))
                    }

                    if usesZeroBaseline {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(fill(isStrongest: isStrongest, isWeakest: isWeakest))
                            .frame(height: height)
                    } else {
                        // Dot plot: a stem plus a marker, which makes no claim about
                        // proportion to zero.
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Circle()
                                .fill(fill(isStrongest: isStrongest, isWeakest: isWeakest))
                                .frame(width: isStrongest || isWeakest ? 13 : 10)
                            Rectangle()
                                .fill(metric.accentColor.opacity(0.18))
                                .frame(width: 2)
                                .frame(height: max(0, height - 13))
                        }
                    }
                }
                // Without an explicit fill the ZStack shrinks to the bar and the
                // GeometryReader pins it to the top, leaving the columns floating.
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .bottom
                )
            }

            Text(shortName(stat.weekday))
                .font(isStrongest ? Theme.Typography.caption2Bold : Theme.Typography.caption2)
                .foregroundStyle(isStrongest ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fullName(stat.weekday))
        .accessibilityValue("\(metric.formatWithUnit(stat.average)) average across \(stat.sampleCount) days")
    }

    private func fill(isStrongest: Bool, isWeakest: Bool) -> AnyShapeStyle {
        if isStrongest { return AnyShapeStyle(metric.accentGradient) }
        if isWeakest { return AnyShapeStyle(metric.accentColor.opacity(0.28)) }
        return AnyShapeStyle(metric.accentColor.opacity(0.5))
    }

    private func normalized(_ value: Double) -> CGFloat {
        let span = scale.upperBound - scale.lowerBound
        guard span > 0 else { return 0.5 }
        return CGFloat(min(max((value - scale.lowerBound) / span, 0), 1))
    }

    private func shortName(_ weekday: Int) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        let index = weekday - 1
        return symbols.indices.contains(index) ? symbols[index] : "?"
    }

    private func fullName(_ weekday: Int) -> String {
        let symbols = calendar.weekdaySymbols
        let index = weekday - 1
        return symbols.indices.contains(index) ? symbols[index] : "That day"
    }
}
