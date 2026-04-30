import Foundation
import HealthKit

enum DailyHealthCoverageDirection {
    case forward
    case backward
}

struct DailyHealthCoveragePlanner {
    static func dayStarts(in range: DateInterval, calendar: Calendar = .current) -> [Date] {
        guard range.start < range.end else { return [] }

        var days: [Date] = []
        var current = calendar.startOfDay(for: range.start)
        let end = calendar.startOfDay(for: range.end)

        while current <= end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return days
    }

    static func dayCount(in range: DateInterval, calendar: Calendar = .current) -> Int {
        dayStarts(in: range, calendar: calendar).count
    }

    static func missingRanges(
        in range: DateInterval,
        coveredDays: Set<Date>,
        batchSizeDays: Int,
        direction: DailyHealthCoverageDirection,
        calendar: Calendar = .current
    ) -> [DateInterval] {
        guard batchSizeDays > 0 else { return [] }

        let allDays = dayStarts(in: range, calendar: calendar)
        guard !allDays.isEmpty else { return [] }

        var uncoveredSpans: [(start: Date, end: Date)] = []
        var spanStart: Date?
        var previousDay: Date?

        for day in allDays {
            if coveredDays.contains(day) {
                if let startDay = spanStart, let previousDay {
                    uncoveredSpans.append((start: startDay, end: previousDay))
                    spanStart = nil
                }
            } else if spanStart == nil {
                spanStart = day
            }

            previousDay = day
        }

        if let startDay = spanStart, let previousDay {
            uncoveredSpans.append((start: startDay, end: previousDay))
        }

        switch direction {
        case .forward:
            return uncoveredSpans.flatMap { span in
                chunkedRanges(from: span.start, through: span.end, batchSizeDays: batchSizeDays, calendar: calendar)
            }
        case .backward:
            return uncoveredSpans.reversed().flatMap { span in
                chunkedRangesBackward(from: span.start, through: span.end, batchSizeDays: batchSizeDays, calendar: calendar)
            }
        }
    }

    private static func chunkedRanges(
        from startDay: Date,
        through endDay: Date,
        batchSizeDays: Int,
        calendar: Calendar
    ) -> [DateInterval] {
        guard batchSizeDays > 0 else { return [] }

        var intervals: [DateInterval] = []
        var currentStart = startDay

        while currentStart <= endDay {
            let maxEnd = calendar.date(byAdding: .day, value: batchSizeDays - 1, to: currentStart) ?? endDay
            let chunkEndDay = min(maxEnd, endDay)
            let chunkEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: chunkEndDay) ?? chunkEndDay
            intervals.append(DateInterval(start: currentStart, end: chunkEnd))

            guard let nextStart = calendar.date(byAdding: .day, value: 1, to: chunkEndDay) else { break }
            currentStart = nextStart
        }

        return intervals
    }

    private static func chunkedRangesBackward(
        from startDay: Date,
        through endDay: Date,
        batchSizeDays: Int,
        calendar: Calendar
    ) -> [DateInterval] {
        guard batchSizeDays > 0 else { return [] }

        var intervals: [DateInterval] = []
        var currentEnd = endDay

        while currentEnd >= startDay {
            let minStart = calendar.date(byAdding: .day, value: -(batchSizeDays - 1), to: currentEnd) ?? startDay
            let chunkStartDay = max(minStart, startDay)
            let chunkEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: currentEnd) ?? currentEnd
            intervals.append(DateInterval(start: chunkStartDay, end: chunkEnd))

            guard let previousEnd = calendar.date(byAdding: .day, value: -1, to: chunkStartDay) else { break }
            currentEnd = previousEnd
        }

        return intervals
    }
}

extension HealthKitManager {
    /// Sync daily aggregate health data for the given range
    func syncDailyHealthData(range: DateInterval) async throws {
        guard healthStore != nil else {
            throw HealthKitError.notAvailable
        }
        guard authorizationStatus == .authorized else {
            throw HealthKitError.authorizationFailed("Health access is not authorized.")
        }
        guard !isDailySyncing else { return }
        guard range.start < range.end else { return }

        isDailySyncing = true
        dailySyncProgress = 0

        defer { isDailySyncing = false }

        let metrics = HealthMetric.dailyQuantityMetrics
        let totalSteps = Double(metrics.count + 1)
        var completedSteps = 0.0

        var metricValues: [HealthMetric: [Date: Double]] = [:]

        for metric in metrics {
            guard let type = metric.quantityType,
                  let unit = metric.unit,
                  let options = metric.statisticsOption else {
                continue
            }

            let rawValues = try await fetchDailyStatistics(
                type: type,
                from: range.start,
                to: range.end,
                unit: unit,
                options: options
            )

            let normalized = rawValues.mapValues { metric.storedValue(from: $0) }
            metricValues[metric] = normalized

            completedSteps += 1
            dailySyncProgress = completedSteps / totalSteps
        }

        let sleepSummaries = try await fetchDailySleepSummaries(from: range.start, to: range.end)
        completedSteps += 1
        dailySyncProgress = completedSteps / totalSteps

        var updatedStore = dailyHealthStore
        var updatedCoverage = dailyHealthCoverage
        let days = DailyHealthCoveragePlanner.dayStarts(in: range)

        for day in days {
            var entry = DailyHealthData(dayStart: day)

            for metric in metrics {
                entry.setValue(metricValues[metric]?[day], for: metric)
            }

            // Always set (including nil) so stale cached sleep doesn't persist when resyncing.
            entry.sleepSummary = sleepSummaries[day]

            if entryHasData(entry) {
                updatedStore[day] = entry
            } else {
                updatedStore.removeValue(forKey: day)
            }

            updatedCoverage.insert(day)
        }

        dailyHealthStore = updatedStore
        dailyHealthCoverage = updatedCoverage
        lastDailySyncDate = Date()
        userDefaults.set(lastDailySyncDate, forKey: lastDailySyncKey)
        persistDailyHealthData()
        persistDailyHealthCoverage()
    }

    /// Sync only if the range has missing daily data
    func ensureDailyHealthData(
        range: DateInterval,
        batchSizeDays: Int = 365,
        maxBatches: Int? = nil,
        direction: DailyHealthCoverageDirection = .forward
    ) async {
        guard authorizationStatus == .authorized else { return }
        guard range.start < range.end else { return }

        let missingRanges = DailyHealthCoveragePlanner.missingRanges(
            in: range,
            coveredDays: dailyHealthCoverage,
            batchSizeDays: batchSizeDays,
            direction: direction
        )
        guard !missingRanges.isEmpty else { return }

        let plannedRanges: [DateInterval]
        if let maxBatches {
            plannedRanges = Array(missingRanges.prefix(maxBatches))
        } else {
            plannedRanges = missingRanges
        }

        for missingRange in plannedRanges {
            guard !isDailySyncing else { return }

            do {
                try await syncDailyHealthData(range: missingRange)
            } catch {
                print("Failed to sync daily health data: \(error)")
                return
            }
        }
    }

    func ensureEarliestAvailableDailyHealthDate(force: Bool = false) async {
        guard authorizationStatus == .authorized else { return }
        guard !isResolvingDailyHealthHistory else { return }
        if earliestAvailableDailyHealthDate != nil && !force {
            return
        }

        isResolvingDailyHealthHistory = true
        defer { isResolvingDailyHealthHistory = false }

        do {
            let earliestDate = try await fetchEarliestAvailableDailyHealthDate()
            earliestAvailableDailyHealthDate = earliestDate

            if let earliestDate {
                userDefaults.set(earliestDate, forKey: earliestAvailableDailyHealthDateKey)
            } else {
                userDefaults.removeObject(forKey: earliestAvailableDailyHealthDateKey)
            }
        } catch {
            print("Failed to resolve earliest daily health date: \(error)")
        }
    }

    func dayCount(in range: DateInterval) -> Int {
        DailyHealthCoveragePlanner.dayCount(in: range)
    }

    func coveredDayCount(in range: DateInterval) -> Int {
        DailyHealthCoveragePlanner.dayStarts(in: range).reduce(into: 0) { count, day in
            if dailyHealthCoverage.contains(day) {
                count += 1
            }
        }
    }

    func isDailyHealthRangeFullyCovered(_ range: DateInterval) -> Bool {
        let totalDays = dayCount(in: range)
        guard totalDays > 0 else { return true }
        return coveredDayCount(in: range) == totalDays
    }

    /// Fetch raw samples for a metric (used in detail views)
    func fetchMetricSamples(metric: HealthMetric, range: DateInterval) async throws -> [HealthMetricSample] {
        guard metric.supportsSamples else { return [] }
        guard authorizationStatus == .authorized else { return [] }
        guard let type = metric.quantityType,
              let unit = metric.unit else {
            return []
        }

        let samples = try await fetchQuantitySamples(
            type: type,
            from: range.start,
            to: range.end,
            limit: HKObjectQueryNoLimit,
            ascending: true
        )

        return samples.map { sample in
            let raw = sample.quantity.doubleValue(for: unit)
            return HealthMetricSample(timestamp: sample.startDate, value: metric.storedValue(from: raw))
        }
    }
    private func entryHasData(_ entry: DailyHealthData) -> Bool {
        entry.steps != nil ||
        entry.activeEnergy != nil ||
        entry.basalEnergy != nil ||
        entry.exerciseMinutes != nil ||
        entry.moveMinutes != nil ||
        entry.standMinutes != nil ||
        entry.distanceWalkingRunning != nil ||
        entry.flightsClimbed != nil ||
        entry.sleepSummary != nil ||
        entry.restingHeartRate != nil ||
        entry.walkingHeartRateAverage != nil ||
        entry.heartRateVariability != nil ||
        entry.heartRateRecovery != nil ||
        entry.bloodOxygen != nil ||
        entry.respiratoryRate != nil ||
        entry.bodyTemperature != nil ||
        entry.vo2Max != nil ||
        entry.bodyMass != nil ||
        entry.bodyFatPercentage != nil
    }
}
