import Foundation

/// A single plain-language observation about a metric.
nonisolated struct MetricInsight: Sendable, Identifiable, Hashable {
    enum Tone: Sendable {
        case positive
        case neutral
        case caution
    }

    let id: String
    let icon: String
    let title: String
    let detail: String
    let tone: Tone
}

/// Turns a `MetricSeriesAnalysis` into sentences.
///
/// Every statement here is backed by a computed field — nothing is padded out with
/// filler like "your steps is trending up". When the data cannot support a claim,
/// the insight is simply omitted.
enum MetricNarrative {

    // MARK: - Hero summary

    /// One sentence describing the period as a whole. Deliberately leads with the
    /// average rather than the latest reading, because for an accruing metric the
    /// latest reading is a partial day.
    static func summary(for analysis: MetricSeriesAnalysis) -> String? {
        let metric = analysis.metric
        guard let mean = analysis.mean else { return nil }

        let noun = analysis.completed.count == 1 ? metric.dailyNoun : "\(metric.dailyNoun)s"
        var sentence = "Averaging \(metric.formatWithUnit(mean)) across \(analysis.completed.count) \(noun)"

        if let momentum = analysis.momentum, !momentum.isFlat {
            let direction = momentum.percentChange > 0 ? "up" : "down"
            let magnitude = Int(abs(momentum.percentChange).rounded())
            sentence += ". The last 7 are \(direction) \(magnitude)% on the 7 before"
        }

        return sentence + "."
    }

    /// Short label describing where today sits, e.g. "top 15% of days".
    static func todayStanding(for analysis: MetricSeriesAnalysis) -> String? {
        guard let percentile = analysis.todayPercentile, analysis.completed.count >= 5 else { return nil }
        let metric = analysis.metric

        let fromTop = Int(((1 - percentile) * 100).rounded())
        let fromBottom = Int((percentile * 100).rounded())

        switch metric.polarity {
        case .lowerIsBetter:
            if fromBottom <= 25 { return "lowest \(max(fromBottom, 1))% of \(metric.dailyNoun)s" }
            if fromTop <= 25 { return "highest \(max(fromTop, 1))% of \(metric.dailyNoun)s" }
        case .higherIsBetter, .neutral:
            if fromTop <= 25 { return "top \(max(fromTop, 1))% of \(metric.dailyNoun)s" }
            if fromBottom <= 25 { return "bottom \(max(fromBottom, 1))% of \(metric.dailyNoun)s" }
        }
        return "middle of your usual range"
    }

    // MARK: - Insight list

    static func insights(
        for analysis: MetricSeriesAnalysis,
        calendar: Calendar = .current
    ) -> [MetricInsight] {
        var insights: [MetricInsight] = []
        let metric = analysis.metric

        if let pace = paceInsight(analysis) { insights.append(pace) }
        if let rhythm = rhythmInsight(analysis, calendar: calendar) { insights.append(rhythm) }
        if let streak = streakInsight(analysis) { insights.append(streak) }
        if let peak = peakInsight(analysis, calendar: calendar) { insights.append(peak) }
        if let momentum = momentumInsight(analysis) { insights.append(momentum) }
        if let spread = spreadInsight(analysis) { insights.append(spread) }
        if let coverage = coverageInsight(analysis) { insights.append(coverage) }

        // Keep the section scannable. The ordering above is already by usefulness:
        // what is happening now, then patterns, then context.
        _ = metric
        return Array(insights.prefix(5))
    }

    // MARK: - Individual insights

    private static func paceInsight(_ analysis: MetricSeriesAnalysis) -> MetricInsight? {
        guard analysis.isTodayPartial,
              let projected = analysis.projectedTodayTotal,
              let median = analysis.median,
              median > 0 else { return nil }

        let metric = analysis.metric
        let percentOfUsual = Int(((projected / median) * 100).rounded())
        let tone: MetricInsight.Tone
        let verdict: String

        switch percentOfUsual {
        case ..<80:
            tone = metric.polarity == .higherIsBetter ? .caution : .neutral
            verdict = "behind"
        case 80...119:
            tone = .neutral
            verdict = "in line with"
        default:
            tone = metric.polarity == .higherIsBetter ? .positive : .neutral
            verdict = "ahead of"
        }

        let elapsed = Int((analysis.dayFractionElapsed * 100).rounded())
        return MetricInsight(
            id: "pace",
            icon: "timer",
            title: "On pace for \(metric.formatWithUnit(projected))",
            detail: "\(elapsed)% through the day and \(verdict) your typical \(metric.formatWithUnit(median)).",
            tone: tone
        )
    }

    private static func rhythmInsight(
        _ analysis: MetricSeriesAnalysis,
        calendar: Calendar
    ) -> MetricInsight? {
        guard analysis.hasEnoughDataForRhythm,
              let strongest = analysis.strongestWeekday,
              let weakest = analysis.weakestWeekday,
              strongest.weekday != weakest.weekday,
              weakest.average != 0 else { return nil }

        let gap = abs(strongest.average - weakest.average) / abs(weakest.average) * 100
        // Below this the difference is noise, not a rhythm worth naming.
        guard gap >= 15 else { return nil }

        let metric = analysis.metric
        let strongName = weekdayName(strongest.weekday, calendar: calendar)
        let weakName = weekdayName(weakest.weekday, calendar: calendar)
        let comparison = metric.polarity == .lowerIsBetter ? "lower" : "higher"

        return MetricInsight(
            id: "rhythm",
            icon: "calendar.day.timeline.left",
            title: "\(strongName)s are your strongest",
            detail: "You average \(metric.formatWithUnit(strongest.average)) on \(strongName)s — "
                + "\(Int(gap.rounded()))% \(comparison) than \(weakName)s at \(metric.formatWithUnit(weakest.average)).",
            tone: .neutral
        )
    }

    private static func streakInsight(_ analysis: MetricSeriesAnalysis) -> MetricInsight? {
        let metric = analysis.metric
        guard let median = analysis.median else { return nil }

        let favourable = analysis.favourableStreak
        let unfavourable = analysis.unfavourableStreak
        let noun = metric.dailyNoun

        if favourable >= 3 {
            let side = metric.polarity == .lowerIsBetter ? "below" : "above"
            return MetricInsight(
                id: "streak",
                icon: "flame.fill",
                title: "\(favourable) \(noun)s running \(side) your midpoint",
                detail: "Each of the last \(favourable) \(noun)s came in \(side) "
                    + "\(metric.formatWithUnit(median)), the median for this range.",
                tone: .positive
            )
        }

        if unfavourable >= 4 {
            let side = metric.polarity == .lowerIsBetter ? "above" : "below"
            return MetricInsight(
                id: "streak",
                icon: "arrow.down.right.circle",
                title: "\(unfavourable) \(noun)s under your midpoint",
                detail: "The last \(unfavourable) \(noun)s all landed \(side) "
                    + "\(metric.formatWithUnit(median)).",
                tone: .caution
            )
        }

        return nil
    }

    private static func peakInsight(
        _ analysis: MetricSeriesAnalysis,
        calendar: Calendar
    ) -> MetricInsight? {
        guard let best = analysis.bestDay, analysis.completed.count >= 7 else { return nil }
        let metric = analysis.metric

        let daysAgo = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: best.date),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0

        let whenText: String
        switch daysAgo {
        case ..<0: return nil
        case 0: whenText = "today"
        case 1: whenText = "yesterday"
        case 2...6: whenText = "\(daysAgo) days ago"
        default: whenText = best.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }

        let superlative = metric.polarity == .lowerIsBetter ? "lowest" : "best"
        return MetricInsight(
            id: "peak",
            icon: "star.fill",
            title: "\(metric.formatWithUnit(best.value)) was your \(superlative)",
            detail: "Set \(whenText). That is your \(superlative) \(metric.dailyNoun) in this range.",
            tone: daysAgo <= 6 ? .positive : .neutral
        )
    }

    private static func momentumInsight(_ analysis: MetricSeriesAnalysis) -> MetricInsight? {
        guard let momentum = analysis.momentum,
              let recent = analysis.recentMean,
              let prior = analysis.priorMean,
              abs(momentum.percentChange) >= 5 else { return nil }

        let metric = analysis.metric
        let rising = momentum.percentChange > 0
        let improved = metric.polarity == .lowerIsBetter ? !rising : rising
        let tone: MetricInsight.Tone = metric.polarity == .neutral
            ? .neutral
            : (improved ? .positive : .caution)

        return MetricInsight(
            id: "momentum",
            icon: rising ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
            title: "This week is \(rising ? "up" : "down") \(Int(abs(momentum.percentChange).rounded()))%",
            detail: "\(metric.formatWithUnit(recent)) a \(metric.dailyNoun) over the last 7, "
                + "against \(metric.formatWithUnit(prior)) the 7 before.",
            tone: tone
        )
    }

    private static func spreadInsight(_ analysis: MetricSeriesAnalysis) -> MetricInsight? {
        guard let consistency = analysis.consistency,
              let range = analysis.typicalRange,
              analysis.completed.count >= 10 else { return nil }

        let metric = analysis.metric
        let low = metric.formatWithUnit(range.lowerBound)
        let high = metric.formatWithUnit(range.upperBound)

        if consistency >= 0.7 {
            return MetricInsight(
                id: "spread",
                icon: "equal.circle.fill",
                title: "Very repeatable",
                detail: "Half your \(metric.dailyNoun)s land between \(low) and \(high) — a tight band.",
                tone: .positive
            )
        }

        if consistency <= 0.35 {
            return MetricInsight(
                id: "spread",
                icon: "waveform.path",
                title: "Swings day to day",
                detail: "The middle half of your \(metric.dailyNoun)s spans \(low) to \(high).",
                tone: .neutral
            )
        }

        return nil
    }

    private static func coverageInsight(_ analysis: MetricSeriesAnalysis) -> MetricInsight? {
        guard let coverage = analysis.coverage, coverage < 0.7, analysis.calendarDayCount >= 7 else { return nil }
        let recorded = analysis.samples.count

        return MetricInsight(
            id: "coverage",
            icon: "exclamationmark.circle",
            title: "\(recorded) of \(analysis.calendarDayCount) days recorded",
            detail: "Gaps in the data will pull the averages around. "
                + "Check that the source device synced on the missing days.",
            tone: .caution
        )
    }

    // MARK: - Helpers

    private static func weekdayName(_ weekday: Int, calendar: Calendar) -> String {
        let symbols = calendar.weekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "That day" }
        return symbols[index]
    }
}
