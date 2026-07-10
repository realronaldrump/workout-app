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

private struct DailyMetricSyncResult {
    let metric: HealthMetric
    let values: [Date: Double]
}

private enum DailyHealthQueryPlan {
    /// HealthKit can service independent statistics queries concurrently, but an all-history
    /// sync should not enqueue every requested type at once.
    static let maximumConcurrentQueries = 4
}

private nonisolated struct DailyHealthMergePayload: @unchecked Sendable {
    let existingStore: [Date: DailyHealthData]
    let existingCoverage: Set<Date>
    let metrics: [HealthMetric]
    let metricValues: [HealthMetric: [Date: Double]]
    let sleepSummaries: [Date: SleepSummary]
    let days: [Date]
    let today: Date
}

private nonisolated struct DailyHealthMergeResult: @unchecked Sendable {
    let store: [Date: DailyHealthData]
    let coverage: Set<Date>
}

private nonisolated enum DailyHealthStoreMerger {
    static func merge(_ payload: DailyHealthMergePayload) -> DailyHealthMergeResult {
        var updatedStore = payload.existingStore
        var updatedCoverage = payload.existingCoverage

        for day in payload.days {
            var entry = DailyHealthData(dayStart: day)
            for metric in payload.metrics {
                entry.setValue(payload.metricValues[metric]?[day], for: metric)
            }
            entry.sleepSummary = payload.sleepSummaries[day]

            if entryHasData(entry) {
                updatedStore[day] = entry
            } else {
                updatedStore.removeValue(forKey: day)
            }

            // Today's totals are incomplete and must remain eligible for refresh.
            if day < payload.today {
                updatedCoverage.insert(day)
            } else {
                updatedCoverage.remove(day)
            }
        }

        return DailyHealthMergeResult(store: updatedStore, coverage: updatedCoverage)
    }

    private static func entryHasData(_ entry: DailyHealthData) -> Bool {
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

extension HealthKitManager {
    /// Sync daily aggregate health data for the given range
    func syncDailyHealthData(range: DateInterval) async throws {
        guard healthStore != nil else {
            throw HealthKitError.notAvailable
        }
        guard authorizationStatus == .authorized else {
            throw HealthKitError.authorizationFailed("Health access is not authorized.")
        }
        guard range.start < range.end else { return }

        if let activeTask = dailyHealthSyncTask {
            let activeRange = dailyHealthSyncRange
            try await activeTask.value

            // Callers requesting data already covered by the in-flight operation can share
            // its result. A disjoint request starts after it instead of being silently dropped.
            if let activeRange,
               activeRange.start <= range.start,
               activeRange.end >= range.end {
                return
            }
            return try await syncDailyHealthData(range: range)
        }

        let task = Task { @MainActor in
            defer {
                self.dailyHealthSyncTask = nil
                self.dailyHealthSyncRange = nil
            }
            try await self.performDailyHealthSync(range: range)
        }
        dailyHealthSyncRange = range
        dailyHealthSyncTask = task
        try await task.value
    }

    private func performDailyHealthSync(range: DateInterval) async throws {
        isDailySyncing = true
        dailySyncProgress = 0

        defer { isDailySyncing = false }

        let metrics = HealthMetric.dailyQuantityMetrics
        let totalSteps = Double(metrics.count + 1)
        var completedSteps = 0.0

        var metricValues: [HealthMetric: [Date: Double]] = [:]
        var metricIterator = metrics.makeIterator()

        try await withThrowingTaskGroup(of: DailyMetricSyncResult?.self) { group in
            func enqueueNextMetric() {
                guard let metric = metricIterator.next() else { return }
                group.addTask { @MainActor in
                    guard let type = metric.quantityType,
                          let unit = metric.unit,
                          let options = metric.statisticsOption else {
                        return nil
                    }

                    let rawValues = try await self.fetchDailyStatistics(
                        type: type,
                        from: range.start,
                        to: range.end,
                        unit: unit,
                        options: options
                    )
                    let normalized = await Task.detached(priority: .utility) {
                        rawValues.mapValues { metric.storedValue(from: $0) }
                    }.value
                    return DailyMetricSyncResult(metric: metric, values: normalized)
                }
            }

            for _ in 0..<min(DailyHealthQueryPlan.maximumConcurrentQueries, metrics.count) {
                enqueueNextMetric()
            }

            while let result = try await group.next() {
                if let result {
                    metricValues[result.metric] = result.values
                }
                completedSteps += 1
                dailySyncProgress = completedSteps / totalSteps
                enqueueNextMetric()
            }
        }

        let sleepSummaries = try await fetchDailySleepSummaries(from: range.start, to: range.end)
        completedSteps += 1
        dailySyncProgress = completedSteps / totalSteps

        let days = DailyHealthCoveragePlanner.dayStarts(in: range)
        let today = Calendar.current.startOfDay(for: Date())
        let mergePayload = DailyHealthMergePayload(
            existingStore: dailyHealthStore,
            existingCoverage: dailyHealthCoverage,
            metrics: metrics,
            metricValues: metricValues,
            sleepSummaries: sleepSummaries,
            days: days,
            today: today
        )
        let mergeResult = await Task.detached(priority: .userInitiated) {
            DailyHealthStoreMerger.merge(mergePayload)
        }.value

        dailyHealthStore = mergeResult.store
        dailyHealthCoverage = mergeResult.coverage
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
            return HealthMetricSample(
                id: sample.uuid,
                timestamp: sample.startDate,
                value: metric.storedValue(from: raw)
            )
        }
    }
}
