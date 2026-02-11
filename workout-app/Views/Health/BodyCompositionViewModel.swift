import Foundation
import Combine
import HealthKit
import SwiftUI

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

    private var loadTask: Task<Void, Never>?
    private var earliestCache: [BodyCompositionMetricKind: Date] = [:]

    func load(
        healthManager: HealthKitManager,
        metricKind: BodyCompositionMetricKind,
        displayRange: DateInterval,
        reportGranularity: ReportGranularity
    ) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadImpl(
                healthManager: healthManager,
                metricKind: metricKind,
                displayRange: displayRange,
                reportGranularity: reportGranularity
            )
        }
    }

    func recomputeReports(granularity: ReportGranularity) {
        reportBuckets = BodyCompositionAnalytics.reportBuckets(points: representativeSeries, granularity: granularity)
    }

    private func loadImpl(
        healthManager: HealthKitManager,
        metricKind: BodyCompositionMetricKind,
        displayRange: DateInterval,
        reportGranularity: ReportGranularity
    ) async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
            lastUpdatedAt = Date()
        }

        guard healthManager.authorizationStatus == .authorized else {
            clearComputedData()
            return
        }

        do {
            if earliestCache[metricKind] == nil {
                if let earliest = try await fetchEarliestSampleDate(healthManager: healthManager, metricKind: metricKind) {
                    earliestCache[metricKind] = earliest
                }
            }
            earliestSampleDate = earliestCache[metricKind]

            let analysisRange = BodyCompositionAnalytics.bufferedAnalysisRange(for: displayRange, bufferDays: 35)
            let samples = try await healthManager.fetchMetricSamples(metric: metricKind.healthMetric, range: analysisRange)

            let rawSamples: [BodyRawSample] = samples.map { sample in
                let displayValue = metricKind.healthMetric.displayValue(from: sample.value)
                return BodyRawSample(timestamp: sample.timestamp, value: displayValue)
            }
            .sorted { $0.timestamp < $1.timestamp }

            sampleCountInDisplayRange = rawSamples.filter { displayRange.contains($0.timestamp) }.count

            let daily = BodyCompositionAnalytics.dailyRepresentatives(from: rawSamples)
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

            let points: [TimeSeriesPoint] = repsInDisplayRange
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
                let reg = regressions[rep.dayStart]
                let weeklyRate: Double?
                if let reg, reg.pointCount >= 6 {
                    weeklyRate = reg.slopePerDay * 7
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

            // Latest trend + forecasts are based on the latest point in the displayed range, but use
            // the trailing 30-day window (buffered by analysisRange).
            let latestDay = points.last?.date ?? displayRange.end
            let latestTrend = BodyCompositionAnalytics.trendSummaryForLatest(representatives: daily, windowDays: 30)
            if let latestTrend,
               let latestReg = regressions[calendarStartOfDay(latestDay)] {
                trendSummary = latestTrend
                let windowStart = latestTrend.windowStart
                forecastPoints = BodyCompositionAnalytics.forecast(
                    latestDay: latestTrend.windowEnd,
                    regression: latestReg,
                    windowStart: windowStart
                )
            } else {
                trendSummary = nil
                forecastPoints = []
            }

            reportBuckets = BodyCompositionAnalytics.reportBuckets(points: points, granularity: reportGranularity)
        } catch {
            errorMessage = error.localizedDescription
            clearComputedData()
        }
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

    private func fetchEarliestSampleDate(
        healthManager: HealthKitManager,
        metricKind: BodyCompositionMetricKind
    ) async throws -> Date? {
        guard let identifier = metricKind.healthMetric.quantityType else { return nil }
        let samples = try await healthManager.fetchQuantitySamples(
            type: identifier,
            from: Date.distantPast,
            to: Date(),
            limit: 1,
            ascending: true
        )
        return samples.first?.startDate
    }

    private func calendarStartOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
