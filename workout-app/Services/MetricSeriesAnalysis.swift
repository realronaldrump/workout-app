import Foundation

/// One day's value for a metric, already converted to display units.
nonisolated struct MetricDaySample: Sendable, Hashable, Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

/// Average for a single day of the week across the analysed range.
nonisolated struct MetricWeekdayStat: Sendable, Hashable, Identifiable {
    /// 1 = Sunday, matching `Calendar.component(.weekday:)`.
    let weekday: Int
    let average: Double
    let sampleCount: Int

    var id: Int { weekday }
}

/// A statistical read of one metric over one date range.
///
/// Every field is derived from the samples handed in — nothing is estimated or
/// invented. The type is `nonisolated` and `Sendable` so the whole computation can
/// run off the main thread, which is what keeps the metric screens from stalling
/// on multi-year histories.
nonisolated struct MetricSeriesAnalysis: Sendable {

    let metric: HealthMetric
    let polarity: MetricPolarity

    /// Every sample in range, ascending, in display units.
    let samples: [MetricDaySample]
    /// Samples excluding a still-accruing today. All statistics use this set.
    let completed: [MetricDaySample]

    /// Today's sample, when the range includes today and data exists for it.
    let todaySample: MetricDaySample?
    /// True when today's value is still climbing and cannot be compared as a total.
    let isTodayPartial: Bool
    /// How much of today has elapsed, 0...1.
    let dayFractionElapsed: Double
    /// Linear end-of-day projection for accruing metrics. `nil` when too early to mean anything.
    let projectedTodayTotal: Double?

    let mean: Double?
    let median: Double?
    let minimum: Double?
    let maximum: Double?
    /// 25th percentile — lower edge of the "typical" band.
    let percentile25: Double?
    /// 75th percentile — upper edge of the "typical" band.
    let percentile75: Double?

    /// Highest and lowest days by raw value.
    let highestDay: MetricDaySample?
    let lowestDay: MetricDaySample?
    /// Best and worst days once polarity is applied (for resting HR, best is lowest).
    let bestDay: MetricDaySample?
    let worstDay: MetricDaySample?

    let weekdayStats: [MetricWeekdayStat]
    let strongestWeekday: MetricWeekdayStat?
    let weakestWeekday: MetricWeekdayStat?

    /// Mean of the most recent seven completed days.
    let recentMean: Double?
    /// Mean of the seven completed days before those.
    let priorMean: Double?
    let momentum: TrendDelta?

    /// Where today sits in the distribution of completed days, 0...1.
    /// Uses the projection for accruing metrics so the comparison is like-for-like.
    let todayPercentile: Double?
    /// The value `todayPercentile` was computed from.
    let comparableTodayValue: Double?

    /// Consecutive most-recent calendar days on the favourable side of the median.
    /// Negative when the run is on the unfavourable side.
    let signedStreak: Int

    /// How repeatable the metric is, 0...1. Derived from the interquartile spread.
    let consistency: Double?

    /// Share of calendar days in range that carry a value, 0...1.
    let coverage: Double?
    let calendarDayCount: Int

    /// How this series should actually be drawn.
    ///
    /// Bars from a zero baseline only say something when the days differ in size.
    /// Resting energy varies by a few percent, so zero-baseline bars render as a
    /// solid block that hides every real movement. Those series are drawn as a line
    /// on a truncated axis instead — a line makes no claim about zero, so the axis
    /// can start where the data does.
    let suggestedChartForm: MetricChartForm

    var typicalRange: ClosedRange<Double>? {
        guard let percentile25, let percentile75, percentile25 <= percentile75 else { return nil }
        return percentile25...percentile75
    }

    var hasEnoughDataForRhythm: Bool {
        weekdayStats.count >= 5 && completed.count >= 14
    }

    var favourableStreak: Int { max(0, signedStreak) }
    var unfavourableStreak: Int { max(0, -signedStreak) }

    // MARK: - Construction

    init(
        metric: HealthMetric,
        samples: [MetricDaySample],
        range: DateInterval,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.metric = metric
        self.polarity = metric.polarity

        let sorted = samples.sorted { $0.date < $1.date }
        self.samples = sorted

        let todayStart = calendar.startOfDay(for: now)
        let todaySample = sorted.last.flatMap { last in
            calendar.isDate(last.date, inSameDayAs: todayStart) ? last : nil
        }
        self.todaySample = todaySample

        let dayInterval = calendar.dateInterval(of: .day, for: now)
        let dayLength = dayInterval?.duration ?? 86_400
        let elapsed = now.timeIntervalSince(dayInterval?.start ?? todayStart)
        let fraction = dayLength > 0 ? min(max(elapsed / dayLength, 0), 1) : 1
        self.dayFractionElapsed = fraction

        // A metric that accrues through the day is only comparable once the day is
        // over. Excluding it is what stops "2 flights" headlining a 62-flight average.
        let partial = todaySample != nil && metric.accumulatesDuringDay && fraction < 0.999
        self.isTodayPartial = partial

        let completed = partial ? Array(sorted.dropLast()) : sorted
        self.completed = completed

        if partial, let todayValue = todaySample?.value, fraction >= 0.15 {
            self.projectedTodayTotal = todayValue / fraction
        } else {
            self.projectedTodayTotal = nil
        }

        let values = completed.map(\.value)
        let ascending = values.sorted()

        self.mean = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        self.median = Self.percentile(ascending, 0.5)
        self.percentile25 = Self.percentile(ascending, 0.25)
        self.percentile75 = Self.percentile(ascending, 0.75)
        self.minimum = ascending.first
        self.maximum = ascending.last

        let highest = completed.max { $0.value < $1.value }
        let lowest = completed.min { $0.value < $1.value }
        self.highestDay = highest
        self.lowestDay = lowest

        switch metric.polarity {
        case .lowerIsBetter:
            self.bestDay = lowest
            self.worstDay = highest
        case .higherIsBetter, .neutral:
            self.bestDay = highest
            self.worstDay = lowest
        }

        let weekdayStats = Self.weekdayStats(for: completed, calendar: calendar)
        self.weekdayStats = weekdayStats

        switch metric.polarity {
        case .lowerIsBetter:
            self.strongestWeekday = weekdayStats.min { $0.average < $1.average }
            self.weakestWeekday = weekdayStats.max { $0.average < $1.average }
        case .higherIsBetter, .neutral:
            self.strongestWeekday = weekdayStats.max { $0.average < $1.average }
            self.weakestWeekday = weekdayStats.min { $0.average < $1.average }
        }

        let recent = Array(completed.suffix(7))
        let prior = Array(completed.dropLast(recent.count).suffix(7))
        let recentMean = recent.isEmpty ? nil : recent.map(\.value).reduce(0, +) / Double(recent.count)
        let priorMean = prior.count >= 3
            ? prior.map(\.value).reduce(0, +) / Double(prior.count)
            : nil
        self.recentMean = recentMean
        self.priorMean = priorMean
        self.momentum = recentMean.flatMap { current in
            priorMean.flatMap {
                TrendDelta(
                    current: current,
                    previous: $0,
                    higherIsBetter: metric.polarity != .lowerIsBetter
                )
            }
        }

        let comparable = partial ? self.projectedTodayTotal : todaySample?.value
        self.comparableTodayValue = comparable
        self.todayPercentile = comparable.flatMap { value in
            guard !ascending.isEmpty else { return nil }
            let below = ascending.reduce(into: 0) { $0 += ($1 < value ? 1 : 0) }
            return Double(below) / Double(ascending.count)
        }

        self.signedStreak = Self.computeSignedStreak(
            in: completed,
            median: self.median,
            polarity: metric.polarity,
            calendar: calendar
        )

        if let median = self.median, let percentile25, let percentile75, median != 0 {
            let spread = (percentile75 - percentile25) / abs(median)
            self.consistency = min(max(1 - spread, 0), 1)
        } else {
            self.consistency = nil
        }

        let dayCount = calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 0
        let calendarDayCount = max(1, dayCount)
        self.calendarDayCount = calendarDayCount
        self.coverage = sorted.isEmpty ? nil : min(1, Double(sorted.count) / Double(calendarDayCount))

        if metric.chartForm == .bars,
           let low = ascending.first,
           let high = ascending.last,
           let median = self.median,
           median != 0,
           (high - low) / abs(median) < 0.25 {
            self.suggestedChartForm = .ribbon
        } else {
            self.suggestedChartForm = metric.chartForm
        }
    }

    // MARK: - Helpers

    /// Linear-interpolated percentile over an ascending array.
    private static func percentile(_ ascending: [Double], _ fraction: Double) -> Double? {
        guard !ascending.isEmpty else { return nil }
        guard ascending.count > 1 else { return ascending[0] }
        let position = fraction * Double(ascending.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(lowerIndex + 1, ascending.count - 1)
        let weight = position - Double(lowerIndex)
        return ascending[lowerIndex] + (ascending[upperIndex] - ascending[lowerIndex]) * weight
    }

    private static func weekdayStats(
        for samples: [MetricDaySample],
        calendar: Calendar
    ) -> [MetricWeekdayStat] {
        var totals: [Int: (sum: Double, count: Int)] = [:]
        for sample in samples {
            let weekday = calendar.component(.weekday, from: sample.date)
            let existing = totals[weekday] ?? (0, 0)
            totals[weekday] = (existing.sum + sample.value, existing.count + 1)
        }

        return totals
            // One observation is an anecdote, not a weekday pattern.
            .filter { $0.value.count >= 2 }
            .map { MetricWeekdayStat(weekday: $0.key, average: $0.value.sum / Double($0.value.count), sampleCount: $0.value.count) }
            .sorted { $0.weekday < $1.weekday }
    }

    /// Counts back from the most recent day while the value stays on one side of the
    /// median. Requires true calendar adjacency, so a missing day ends the run.
    private static func computeSignedStreak(
        in samples: [MetricDaySample],
        median: Double?,
        polarity: MetricPolarity,
        calendar: Calendar
    ) -> Int {
        guard polarity != .neutral, let median, let last = samples.last else { return 0 }

        let favourable = polarity.isFavourable(last.value, comparedTo: median)
        var run = 0
        var expectedDay = last.date

        for sample in samples.reversed() {
            guard calendar.isDate(sample.date, inSameDayAs: expectedDay) else { break }
            guard polarity.isFavourable(sample.value, comparedTo: median) == favourable else { break }
            run += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: expectedDay) else { break }
            expectedDay = previous
        }

        return favourable ? run : -run
    }
}
