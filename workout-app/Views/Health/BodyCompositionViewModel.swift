import Combine
import Foundation

@MainActor
final class BodyCompositionViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var sampleCountInDisplayRange: Int = 0
    @Published var lastUpdatedAt: Date?

    @Published var earliestSampleDate: Date?

    @Published var representativeSeries: [TimeSeriesPoint] = []
    @Published var ma7Series: [TimeSeriesPoint] = []
    @Published var ra30Series: [TimeSeriesPoint] = []

    @Published var logbookDays: [BodyLogbookDay] = []

    @Published var intervalDeltas: [IntervalDelta] = []
    @Published var trendSummary: TrendSummary?
    @Published var forecastPoints: [ForecastPoint] = []

    @Published var reportBuckets: [ReportBucket] = []

    nonisolated deinit {}

    func load(
        dailyEntries: [DailyHealthData],
        metricKind: BodyCompositionMetricKind,
        displayRange: DateInterval,
        reportGranularity: ReportGranularity
    ) {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
            lastUpdatedAt = Date()
        }

        earliestSampleDate = earliestLocalSampleDate(in: dailyEntries, metricKind: metricKind)

        let analysisRange = BodyCompositionAnalytics.bufferedAnalysisRange(for: displayRange, bufferDays: 35)
        let rawSamples = localSamples(from: dailyEntries, metricKind: metricKind, range: analysisRange)

        sampleCountInDisplayRange = rawSamples.filter { displayRange.contains($0.timestamp) }.count

        let daily = dailyRepresentativesPreservingStoredDayStarts(from: rawSamples)
        let repsInDisplayRange = daily.filter { displayRange.contains($0.dayStart) }

        guard !repsInDisplayRange.isEmpty else {
            clearComputedData(keepCounts: true)
            reportBuckets = []
            return
        }

        let ma7 = BodyCompositionAnalytics.trailingAverages(representatives: daily, windowDays: 7)
        let ra30 = BodyCompositionAnalytics.trailingAverages(representatives: daily, windowDays: 30)
        let regressions = BodyCompositionAnalytics.trailingRegression(representatives: daily, windowDays: 30)
        let flags = BodyCompositionAnalytics.recordFlagsSinceAnchor(representatives: repsInDisplayRange)

        let points = repsInDisplayRange
            .map { TimeSeriesPoint(date: $0.dayStart, value: $0.value) }
            .sorted { $0.date < $1.date }

        representativeSeries = points
        ma7Series = repsInDisplayRange.compactMap { rep in
            guard let value = ma7[rep.dayStart] else { return nil }
            return TimeSeriesPoint(date: rep.dayStart, value: value)
        }
        .sorted { $0.date < $1.date }

        ra30Series = repsInDisplayRange.compactMap { rep in
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

        logbookDays = logbookAscending.sorted { $0.dayStart > $1.dayStart }
        intervalDeltas = BodyCompositionAnalytics.intervalDeltas(points: points, displayRangeStart: displayRange.start)

        let latestTrend = BodyCompositionAnalytics.trendSummaryForLatest(representatives: daily, windowDays: 30)
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

        reportBuckets = BodyCompositionAnalytics.reportBuckets(points: points, granularity: reportGranularity)
    }

    func recomputeReports(granularity: ReportGranularity) {
        reportBuckets = BodyCompositionAnalytics.reportBuckets(points: representativeSeries, granularity: granularity)
    }

    private func clearComputedData(keepCounts: Bool = false) {
        if !keepCounts {
            sampleCountInDisplayRange = 0
        }
        representativeSeries = []
        ma7Series = []
        ra30Series = []
        logbookDays = []
        intervalDeltas = []
        trendSummary = nil
        forecastPoints = []
        reportBuckets = []
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

        let grouped = Dictionary(grouping: samples) { sample in
            sample.timestamp
        }

        let representatives: [BodyCompositionAnalytics.DailyRepresentative] = grouped.compactMap { entry in
            let sorted = entry.value.sorted { $0.timestamp < $1.timestamp }
            guard let first = sorted.first else { return nil }
            return BodyCompositionAnalytics.DailyRepresentative(
                dayStart: entry.key,
                timestamp: first.timestamp,
                value: first.value,
                samples: sorted
            )
        }

        return representatives.sorted { $0.dayStart < $1.dayStart }
    }
}
