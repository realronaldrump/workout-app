import Foundation

/// One chronological index per published cache snapshot. Range changes and chart
/// selections should not walk or normalize every date in a multi-year history.
nonisolated struct HealthDailySnapshot: Sendable {
    let days: [DailyHealthData]
    private let dayStarts: [Date]
    private let calendar: Calendar
    private let earliestMetricDates: [HealthMetric: Date]

    var earliestDate: Date? { dayStarts.first }

    init(store: [Date: DailyHealthData], calendar: Calendar = .current) {
        self.calendar = calendar
        days = store.values.sorted { $0.dayStart < $1.dayStart }
        dayStarts = days.map { calendar.startOfDay(for: $0.dayStart) }
        var earliest: [HealthMetric: Date] = [:]
        for metric in HealthMetric.allCases {
            earliest[metric] = days.first { $0.value(for: metric)?.isFinite == true }?.dayStart
        }
        earliestMetricDates = earliest
    }

    func earliestDate(for metric: HealthMetric) -> Date? {
        earliestMetricDates[metric]
    }

    /// Includes both calendar-day boundaries, matching HealthDayComparisonRanges.
    func days(in range: ClosedRange<Date>) -> ArraySlice<DailyHealthData> {
        let lower = lowerBound(for: range.lowerBound)
        let upper = upperBound(for: range.upperBound)
        return days[lower..<max(lower, upper)]
    }

    func day(on date: Date) -> DailyHealthData? {
        let dayStart = calendar.startOfDay(for: date)
        let index = lowerBound(for: dayStart)
        guard index < days.count, dayStarts[index] == dayStart else { return nil }
        return days[index]
    }

    private func lowerBound(for date: Date) -> Int {
        var lower = 0
        var upper = dayStarts.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if dayStarts[middle] < date { lower = middle + 1 } else { upper = middle }
        }
        return lower
    }

    private func upperBound(for date: Date) -> Int {
        var lower = 0
        var upper = dayStarts.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if dayStarts[middle] <= date { lower = middle + 1 } else { upper = middle }
        }
        return lower
    }
}

/// Shared worker for category and metric screens. Both extraction and statistics
/// run away from MainActor, and cancelled range requests stop between days/metrics.
nonisolated struct HealthMetricRangeAnalysis: Sendable {
    let analyses: [HealthMetric: MetricSeriesAnalysis]
    let previousAverages: [HealthMetric: Double]
    let sleepStageAverages: [SleepStage: Double]
    let sleepSummaryCount: Int
    let fallbackSleepCount: Int

    init(
        snapshot: HealthDailySnapshot,
        metrics: [HealthMetric],
        ranges: HealthDayComparisonRanges,
        resolvedRange: DateInterval,
        calendar: Calendar = .current,
        now: Date = Date()
    ) throws {
        try Task.checkCancellation()
        var samples: [HealthMetric: [MetricDaySample]] = [:]
        var previous: [HealthMetric: (sum: Double, count: Int)] = [:]
        var stages: [SleepStage: Double] = [:]
        var sleepCount = 0
        var fallbackCount = 0
        let includesSleep = metrics.contains(.sleep)

        for day in snapshot.days(in: ranges.display) {
            try Task.checkCancellation()
            let date = calendar.startOfDay(for: day.dayStart)
            for metric in metrics {
                guard let raw = day.value(for: metric), raw.isFinite else { continue }
                samples[metric, default: []].append(
                    MetricDaySample(date: date, value: metric.displayValue(from: raw))
                )
            }
            if includesSleep, let summary = day.sleepSummary {
                sleepCount += 1
                if summary.usedFallbackSource { fallbackCount += 1 }
                for (stage, duration) in summary.stageDurations where duration.isFinite {
                    stages[stage, default: 0] += duration / 3600
                }
            }
        }
        if let previousRange = ranges.previousComparison {
            for day in snapshot.days(in: previousRange) {
                try Task.checkCancellation()
                for metric in metrics {
                    guard let raw = day.value(for: metric), raw.isFinite else { continue }
                    let total = previous[metric] ?? (0, 0)
                    previous[metric] = (total.sum + metric.displayValue(from: raw), total.count + 1)
                }
            }
        }

        var analyses: [HealthMetric: MetricSeriesAnalysis] = [:]
        for metric in metrics {
            try Task.checkCancellation()
            guard let values = samples[metric], !values.isEmpty else { continue }
            analyses[metric] = MetricSeriesAnalysis(
                metric: metric, samples: values, range: resolvedRange, calendar: calendar, now: now
            )
        }
        self.analyses = analyses
        previousAverages = previous.mapValues { $0.sum / Double($0.count) }
        sleepStageAverages = sleepCount == 0 ? [:] : stages.mapValues { $0 / Double(sleepCount) }
        sleepSummaryCount = sleepCount
        fallbackSleepCount = fallbackCount
    }
}
