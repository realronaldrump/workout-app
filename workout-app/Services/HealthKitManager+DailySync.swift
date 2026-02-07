import Foundation
import HealthKit

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
        let days = enumerateDays(in: range)

        for day in days {
            var entry = updatedStore[day] ?? DailyHealthData(dayStart: day)

            for metric in metrics {
                if let value = metricValues[metric]?[day] {
                    entry.setValue(value, for: metric)
                }
            }

            // Always set (including nil) so stale cached sleep doesn't persist when resyncing.
            entry.sleepSummary = sleepSummaries[day]

            if entryHasData(entry) {
                updatedStore[day] = entry
            }
        }

        dailyHealthStore = updatedStore
        lastDailySyncDate = Date()
        userDefaults.set(lastDailySyncDate, forKey: lastDailySyncKey)
        persistDailyHealthData()
    }

    /// Sync only if the range has missing daily data
    func ensureDailyHealthData(range: DateInterval) async {
        guard authorizationStatus == .authorized else { return }
        guard !isDailySyncing else { return }

        let days = enumerateDays(in: range)
        let isMissing = days.contains { dailyHealthStore[$0] == nil }
        guard isMissing else { return }

        do {
            try await syncDailyHealthData(range: range)
        } catch {
            print("Failed to sync daily health data: \(error)")
        }
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

    private func enumerateDays(in range: DateInterval) -> [Date] {
        let calendar = Calendar.current
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
