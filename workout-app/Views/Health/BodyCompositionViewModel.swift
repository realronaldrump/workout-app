import Combine
import Foundation

@MainActor
final class BodyCompositionViewModel: ObservableObject {
    private struct Snapshot {
        var isLoading = false
        var errorMessage: String?
        var sampleCountInDisplayRange = 0
        var lastUpdatedAt: Date?
        var earliestSampleDate: Date?
        var representativeSeries: [TimeSeriesPoint] = []
        var ma7Series: [TimeSeriesPoint] = []
        var ra30Series: [TimeSeriesPoint] = []
        var logbookDays: [BodyLogbookDay] = []
        var intervalDeltas: [IntervalDelta] = []
        var trendSummary: TrendSummary?
        var forecastPoints: [ForecastPoint] = []
        var reportBuckets: [ReportBucket] = []
    }

    @Published private var snapshot = Snapshot()

    var isLoading: Bool { snapshot.isLoading }
    var errorMessage: String? { snapshot.errorMessage }
    var sampleCountInDisplayRange: Int { snapshot.sampleCountInDisplayRange }
    var lastUpdatedAt: Date? { snapshot.lastUpdatedAt }
    var earliestSampleDate: Date? { snapshot.earliestSampleDate }
    var representativeSeries: [TimeSeriesPoint] { snapshot.representativeSeries }
    var ma7Series: [TimeSeriesPoint] { snapshot.ma7Series }
    var ra30Series: [TimeSeriesPoint] { snapshot.ra30Series }
    var logbookDays: [BodyLogbookDay] { snapshot.logbookDays }
    var intervalDeltas: [IntervalDelta] { snapshot.intervalDeltas }
    var trendSummary: TrendSummary? { snapshot.trendSummary }
    var forecastPoints: [ForecastPoint] { snapshot.forecastPoints }
    var reportBuckets: [ReportBucket] { snapshot.reportBuckets }

    nonisolated deinit {}

    func load(
        dailyEntries: [DailyHealthData],
        metricKind: BodyCompositionMetricKind,
        displayRange: DateInterval,
        reportGranularity: ReportGranularity
    ) {
        let earliestSampleDate = earliestLocalSampleDate(in: dailyEntries, metricKind: metricKind)

        let analysisRange = BodyCompositionAnalytics.bufferedAnalysisRange(for: displayRange, bufferDays: 35)
        let rawSamples = localSamples(from: dailyEntries, metricKind: metricKind, range: analysisRange)

        apply(
            rawSamples: rawSamples,
            earliestSampleDate: earliestSampleDate,
            displayRange: displayRange,
            reportGranularity: reportGranularity,
            preservesStoredDayStarts: true
        )
    }

    /// Loads true HealthKit samples, preserving multiple readings and their timestamps.
    func load(
        rawSamples: [BodyRawSample],
        earliestSampleDate earliestHint: Date? = nil,
        displayRange: DateInterval,
        reportGranularity: ReportGranularity
    ) {
        let earliestRawSampleDate = rawSamples.map(\.timestamp).min()
        let earliestSampleDate = [earliestHint, earliestRawSampleDate]
            .compactMap { $0 }
            .min()
        let analysisRange = BodyCompositionAnalytics.bufferedAnalysisRange(for: displayRange, bufferDays: 35)
        let scopedSamples = rawSamples
            .filter { analysisRange.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }

        apply(
            rawSamples: scopedSamples,
            earliestSampleDate: earliestSampleDate,
            displayRange: displayRange,
            reportGranularity: reportGranularity,
            preservesStoredDayStarts: false
        )
    }

    func reportLoadFailure(_ error: Error) {
        snapshot = Snapshot(errorMessage: error.localizedDescription)
    }

    private func apply(
        rawSamples: [BodyRawSample],
        earliestSampleDate: Date?,
        displayRange: DateInterval,
        reportGranularity: ReportGranularity,
        preservesStoredDayStarts: Bool
    ) {
        let sampleCountInDisplayRange = rawSamples.filter { displayRange.contains($0.timestamp) }.count

        let daily = preservesStoredDayStarts
            ? dailyRepresentativesPreservingStoredDayStarts(from: rawSamples)
            : BodyCompositionAnalytics.dailyRepresentatives(from: rawSamples)
        let repsInDisplayRange = daily.filter { displayRange.contains($0.dayStart) }

        guard !repsInDisplayRange.isEmpty else {
            snapshot = Snapshot(
                sampleCountInDisplayRange: sampleCountInDisplayRange,
                lastUpdatedAt: Date(),
                earliestSampleDate: earliestSampleDate
            )
            return
        }

        let ma7 = BodyCompositionAnalytics.trailingAverages(representatives: daily, windowDays: 7)
        let ra30 = BodyCompositionAnalytics.trailingAverages(representatives: daily, windowDays: 30)
        let regressions = BodyCompositionAnalytics.trailingRegression(representatives: daily, windowDays: 30)
        let flags = BodyCompositionAnalytics.recordFlagsSinceAnchor(representatives: repsInDisplayRange)

        let points = repsInDisplayRange
            .map { TimeSeriesPoint(date: $0.dayStart, value: $0.value) }
            .sorted { $0.date < $1.date }

        let ma7Series: [TimeSeriesPoint] = repsInDisplayRange.compactMap { rep in
            guard let value = ma7[rep.dayStart] else { return nil }
            return TimeSeriesPoint(date: rep.dayStart, value: value)
        }
        .sorted { $0.date < $1.date }

        let ra30Series: [TimeSeriesPoint] = repsInDisplayRange.compactMap { rep in
            guard let value = ra30[rep.dayStart] else { return nil }
            return TimeSeriesPoint(date: rep.dayStart, value: value)
        }
        .sorted { $0.date < $1.date }

        let logbookAscending = repsInDisplayRange.sorted { $0.dayStart < $1.dayStart }.map { rep in
            let regression = regressions[rep.dayStart]
            let weeklyRate: Double?
            if let regression, regression.pointCount >= 6 {
                weeklyRate = regression.slopePerDay * 7
            } else {
                weeklyRate = nil
            }

            let flag = flags[rep.dayStart]
            return BodyLogbookDay(
                dayStart: rep.dayStart,
                representativeTimestamp: rep.timestamp,
                representative: rep.value,
                samples: rep.samples,
                movingAverage7d: ma7[rep.dayStart],
                rollingAverage30d: ra30[rep.dayStart],
                weeklyRate: weeklyRate,
                isNewLow: flag?.isNewLow ?? false,
                isNewHigh: flag?.isNewHigh ?? false
            )
        }

        let logbookDays = logbookAscending.sorted { $0.dayStart > $1.dayStart }
        let intervalDeltas = BodyCompositionAnalytics.intervalDeltas(
            points: points,
            displayRangeStart: displayRange.start
        )

        let latestTrend = BodyCompositionAnalytics.trendSummaryForLatest(representatives: daily, windowDays: 30)
        let trendSummary: TrendSummary?
        let forecastPoints: [ForecastPoint]
        if let latestTrend,
           let latestPoint = points.last,
           let latestRegression = regressions[latestPoint.date] {
            trendSummary = latestTrend
            forecastPoints = BodyCompositionAnalytics.forecast(
                latestDay: latestPoint.date,
                currentValue: latestPoint.value,
                regression: latestRegression
            )
        } else {
            trendSummary = nil
            forecastPoints = []
        }

        let reportBuckets = BodyCompositionAnalytics.reportBuckets(points: points, granularity: reportGranularity)

        snapshot = Snapshot(
            sampleCountInDisplayRange: sampleCountInDisplayRange,
            lastUpdatedAt: Date(),
            earliestSampleDate: earliestSampleDate,
            representativeSeries: points,
            ma7Series: ma7Series,
            ra30Series: ra30Series,
            logbookDays: logbookDays,
            intervalDeltas: intervalDeltas,
            trendSummary: trendSummary,
            forecastPoints: forecastPoints,
            reportBuckets: reportBuckets
        )
    }

    func recomputeReports(granularity: ReportGranularity) {
        var next = snapshot
        next.reportBuckets = BodyCompositionAnalytics.reportBuckets(
            points: snapshot.representativeSeries,
            granularity: granularity
        )
        snapshot = next
    }

    private func earliestLocalSampleDate(
        in dailyEntries: [DailyHealthData],
        metricKind: BodyCompositionMetricKind
    ) -> Date? {
        dailyEntries
            .filter { $0.value(for: metricKind.healthMetric) != nil }
            .map(\.dayStart)
            .min()
    }

    private func localSamples(
        from dailyEntries: [DailyHealthData],
        metricKind: BodyCompositionMetricKind,
        range: DateInterval
    ) -> [BodyRawSample] {
        dailyEntries
            .filter { range.contains($0.dayStart) }
            .compactMap { entry in
                guard let value = entry.value(for: metricKind.healthMetric) else { return nil }
                let displayValue = metricKind.healthMetric.displayValue(from: value)
                return BodyRawSample(timestamp: entry.dayStart, value: displayValue)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func dailyRepresentativesPreservingStoredDayStarts(
        from samples: [BodyRawSample]
    ) -> [BodyCompositionAnalytics.DailyRepresentative] {
        guard !samples.isEmpty else { return [] }

        let grouped = Dictionary(grouping: samples, by: \.timestamp)
        return grouped.compactMap { dayStart, daySamples in
            let sorted = daySamples.sorted { $0.timestamp < $1.timestamp }
            guard let first = sorted.first else { return nil }
            return BodyCompositionAnalytics.DailyRepresentative(
                dayStart: dayStart,
                timestamp: first.timestamp,
                value: first.value,
                samples: sorted
            )
        }
        .sorted { $0.dayStart < $1.dayStart }
    }

}
