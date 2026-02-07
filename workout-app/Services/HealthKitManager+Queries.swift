import Foundation
import HealthKit

extension HealthKitManager {
    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        let unit = HKUnit(from: "count/min")
        let samples = try await fetchQuantitySamples(type: .heartRate, from: start, to: end)
        return samples.map { sample in
            HeartRateSample(timestamp: sample.startDate, value: sample.quantity.doubleValue(for: unit))
        }
    }

    func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] {
        let unit = HKUnit.secondUnit(with: .milli)
        let samples = try await fetchQuantitySamples(type: .heartRateVariabilitySDNN, from: start, to: end)
        return samples.map { sample in
            HRVSample(timestamp: sample.startDate, value: sample.quantity.doubleValue(for: unit))
        }
    }

    func fetchBloodOxygenSamples(from start: Date, to end: Date) async throws -> [BloodOxygenSample] {
        let unit = HKUnit.percent()
        let samples = try await fetchQuantitySamples(type: .oxygenSaturation, from: start, to: end)
        return samples.map { sample in
            let percentage = sample.quantity.doubleValue(for: unit) * 100
            return BloodOxygenSample(timestamp: sample.startDate, value: percentage)
        }
    }

    func fetchRespiratoryRateSamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] {
        let unit = HKUnit(from: "count/min")
        let samples = try await fetchQuantitySamples(type: .respiratoryRate, from: start, to: end)
        return samples.map { sample in
            RespiratoryRateSample(timestamp: sample.startDate, value: sample.quantity.doubleValue(for: unit))
        }
    }

    func fetchQuantitySum(
        type: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        unit: HKUnit
    ) async throws -> Double? {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: type) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                let sum = result?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: sum)
            }
            healthStore.execute(query)
        }
    }

    func fetchLatestQuantity(
        type: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        unit: HKUnit
    ) async throws -> Double? {
        let samples = try await fetchQuantitySamples(type: type, from: start, to: end, limit: 1, ascending: false)
        return samples.first?.quantity.doubleValue(for: unit)
    }

    func fetchAppleWorkout(from start: Date, to end: Date) async throws -> HKWorkout? {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                let workout = samples?.first as? HKWorkout
                continuation.resume(returning: workout)
            }
            healthStore.execute(query)
        }
    }

    func fetchQuantitySamples(
        type: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        limit: Int = HKObjectQueryNoLimit,
        ascending: Bool = true
    ) async throws -> [HKQuantitySample] {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: type) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    func fetchSleepSummary(from start: Date, to end: Date) async throws -> SleepSummary? {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                let sleepSamples = samples as? [HKCategorySample] ?? []
                guard !sleepSamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                var stageIntervals: [SleepStage: [DateInterval]] = [:]
                var asleepIntervals: [DateInterval] = []
                var inBedIntervals: [DateInterval] = []
                var startTime: Date?
                var endTime: Date?

                for sample in sleepSamples {
                    let rawInterval = DateInterval(start: sample.startDate, end: sample.endDate)
                    guard let interval = Self.clampedInterval(rawInterval, to: start, end: end) else {
                        continue
                    }

                    if let existingStart = startTime {
                        startTime = min(existingStart, interval.start)
                    } else {
                        startTime = interval.start
                    }

                    if let existingEnd = endTime {
                        endTime = max(existingEnd, interval.end)
                    } else {
                        endTime = interval.end
                    }

                    let stage = Self.mapSleepStage(sample.value)
                    stageIntervals[stage, default: []].append(interval)

                    switch stage {
                    case .inBed:
                        inBedIntervals.append(interval)
                    case .core, .deep, .rem:
                        asleepIntervals.append(interval)
                    default:
                        break
                    }
                }

                guard let summaryStart = startTime, let summaryEnd = endTime else {
                    continuation.resume(returning: nil)
                    return
                }

                var stageDurations: [SleepStage: TimeInterval] = [:]
                for (stage, intervals) in stageIntervals {
                    let merged = Self.mergeIntervals(intervals)
                    stageDurations[stage] = merged.reduce(0) { $0 + $1.duration }
                }

                let totalSleep = Self.mergeIntervals(asleepIntervals).reduce(0) { $0 + $1.duration }
                let inBed = Self.mergeIntervals(inBedIntervals).reduce(0) { $0 + $1.duration }

                let summary = SleepSummary(
                    totalSleep: totalSleep,
                    inBed: inBed,
                    stageDurations: stageDurations,
                    start: summaryStart,
                    end: summaryEnd
                )

                continuation.resume(returning: summary)
            }
            healthStore.execute(query)
        }
    }

    func fetchDailyStatistics(
        type: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        unit: HKUnit,
        options: HKStatisticsOptions
    ) async throws -> [Date: Double] {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: type) else {
            return [:]
        }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: start)
        let anchorDate = calendar.startOfDay(for: dayStart)
        let interval = DateComponents(day: 1)
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: end, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [:])
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                var values: [Date: Double] = [:]
                let endDate = max(end, dayStart)
                results?.enumerateStatistics(from: dayStart, to: endDate) { stats, _ in
                    let value: Double?
                    if options.contains(.cumulativeSum) {
                        value = stats.sumQuantity()?.doubleValue(for: unit)
                    } else if options.contains(.discreteAverage) {
                        value = stats.averageQuantity()?.doubleValue(for: unit)
                    } else {
                        value = nil
                    }

                    if let value {
                        values[stats.startDate] = value
                    }
                }

                continuation.resume(returning: values)
            }

            healthStore.execute(query)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func fetchDailySleepSummaries(from start: Date, to end: Date) async throws -> [Date: SleepSummary] {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return [:]
        }

        // Sleep-day is labeled by the wake-up day, using a 6pm boundary (6pm -> 6pm).
        // Implemented by shifting timestamps +6h so the boundary aligns to calendar-midnight for bucketing.
        let sleepDayBoundaryHour = 18
        let shiftSeconds = TimeInterval((24 - sleepDayBoundaryHour) * 3600) // 6 hours

        let queryStart = start.addingTimeInterval(-shiftSeconds)
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: end, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [:])
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                let sleepSamples = samples as? [HKCategorySample] ?? []
                guard !sleepSamples.isEmpty else {
                    continuation.resume(returning: [:])
                    return
                }

                let calendar = Calendar.current

                let startDay = calendar.startOfDay(for: start)
                let endDay = calendar.startOfDay(for: end)
                let shiftedClampStart = start
                let shiftedClampEnd = end.addingTimeInterval(shiftSeconds)

                // dayStart -> sourceBundleId -> stage -> [shifted intervals]
                var intervalsByDay: [Date: [String: [SleepStage: [DateInterval]]]] = [:]
                var sourceNameByKey: [String: String] = [:]

                func unionDuration(_ intervals: [DateInterval]) -> TimeInterval {
                    Self.mergeIntervals(intervals).reduce(0) { $0 + $1.duration }
                }

                func addShiftedInterval(_ interval: DateInterval, toDay day: Date, sourceKey: String, stage: SleepStage) {
                    intervalsByDay[day, default: [:]][sourceKey, default: [:]][stage, default: []].append(interval)
                }

                func splitByShiftedDay(_ interval: DateInterval) -> [(day: Date, interval: DateInterval)] {
                    guard interval.end > interval.start else { return [] }
                    var parts: [(Date, DateInterval)] = []
                    var currentStart = interval.start

                    while currentStart < interval.end {
                        let dayKey = calendar.startOfDay(for: currentStart)
                        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayKey) else { break }
                        let partEnd = min(interval.end, nextDay)
                        if partEnd > currentStart {
                            parts.append((dayKey, DateInterval(start: currentStart, end: partEnd)))
                        }
                        currentStart = partEnd
                    }

                    return parts
                }

                for sample in sleepSamples {
                    let rawInterval = DateInterval(start: sample.startDate, end: sample.endDate)
                    guard rawInterval.end > rawInterval.start else { continue }

                    let shiftedRaw = DateInterval(
                        start: rawInterval.start.addingTimeInterval(shiftSeconds),
                        end: rawInterval.end.addingTimeInterval(shiftSeconds)
                    )

                    guard let shifted = Self.clampedInterval(shiftedRaw, to: shiftedClampStart, end: shiftedClampEnd) else {
                        continue
                    }

                    let stage = Self.mapSleepStage(sample.value)
                    let sourceKey = sample.sourceRevision.source.bundleIdentifier
                    let sourceName = sample.sourceRevision.source.name
                    if !sourceKey.isEmpty, sourceNameByKey[sourceKey] == nil {
                        sourceNameByKey[sourceKey] = sourceName
                    }

                    for (dayKey, part) in splitByShiftedDay(shifted) {
                        guard dayKey >= startDay && dayKey <= endDay else { continue }
                        let key = sourceKey.isEmpty ? sourceName : sourceKey
                        if sourceNameByKey[key] == nil {
                            sourceNameByKey[key] = sourceName
                        }
                        addShiftedInterval(part, toDay: dayKey, sourceKey: key, stage: stage)
                    }
                }

                var summaries: [Date: SleepSummary] = [:]
                let minMeaningfulSleep = 15.0 * 60.0

                for (dayKey, sources) in intervalsByDay {
                    // Pick the single best source for this day to avoid multi-source double counting.
                    var bestSourceKey: String?
                    var bestAsleep: TimeInterval = -1
                    var bestStageScore: Int = -1
                    var bestInBed: TimeInterval = -1

                    for (sourceKey, stageMap) in sources {
                        let coreIntervals = stageMap[.core] ?? []
                        let deepIntervals = stageMap[.deep] ?? []
                        let remIntervals = stageMap[.rem] ?? []
                        let inBedIntervals = stageMap[.inBed] ?? []

                        let asleepMerged = Self.mergeIntervals(coreIntervals + deepIntervals + remIntervals)
                        let asleepDuration = asleepMerged.reduce(0) { $0 + $1.duration }
                        let inBedDuration = unionDuration(inBedIntervals)

                        let stageScore = [
                            unionDuration(deepIntervals) > 0 ? 1 : 0,
                            unionDuration(remIntervals) > 0 ? 1 : 0,
                            unionDuration(coreIntervals) > 0 ? 1 : 0
                        ].reduce(0, +)

                        func isBetter() -> Bool {
                            if asleepDuration != bestAsleep { return asleepDuration > bestAsleep }
                            if stageScore != bestStageScore { return stageScore > bestStageScore }
                            if inBedDuration != bestInBed { return inBedDuration > bestInBed }
                            // Stable tie-break to avoid flapping.
                            if let bestSourceKey { return sourceKey < bestSourceKey }
                            return true
                        }

                        if bestSourceKey == nil || isBetter() {
                            bestSourceKey = sourceKey
                            bestAsleep = asleepDuration
                            bestStageScore = stageScore
                            bestInBed = inBedDuration
                        }
                    }

                    guard let chosenKey = bestSourceKey else { continue }
                    guard bestAsleep >= minMeaningfulSleep else { continue }

                    guard let stageMap = sources[chosenKey] else { continue }

                    var stageDurations: [SleepStage: TimeInterval] = [:]
                    var earliestShifted: Date?
                    var latestShifted: Date?

                    for (stage, intervals) in stageMap {
                        let merged = Self.mergeIntervals(intervals)
                        let duration = merged.reduce(0) { $0 + $1.duration }
                        stageDurations[stage] = duration

                        for interval in merged {
                            if let existing = earliestShifted {
                                earliestShifted = min(existing, interval.start)
                            } else {
                                earliestShifted = interval.start
                            }

                            if let existing = latestShifted {
                                latestShifted = max(existing, interval.end)
                            } else {
                                latestShifted = interval.end
                            }
                        }
                    }

                    let coreIntervals = stageMap[.core] ?? []
                    let deepIntervals = stageMap[.deep] ?? []
                    let remIntervals = stageMap[.rem] ?? []
                    let inBedIntervals = stageMap[.inBed] ?? []

                    let totalSleep = unionDuration(coreIntervals + deepIntervals + remIntervals)
                    let inBed = unionDuration(inBedIntervals)

                    let summaryStart = (earliestShifted ?? dayKey).addingTimeInterval(-shiftSeconds)
                    let summaryEnd = (latestShifted ?? dayKey).addingTimeInterval(-shiftSeconds)

                    let summary = SleepSummary(
                        totalSleep: totalSleep,
                        inBed: inBed,
                        stageDurations: stageDurations,
                        start: summaryStart,
                        end: summaryEnd,
                        primarySourceName: sourceNameByKey[chosenKey],
                        primarySourceBundleIdentifier: chosenKey
                    )
                    summaries[dayKey] = summary
                }

                continuation.resume(returning: summaries)
            }
            healthStore.execute(query)
        }
    }

    private nonisolated static func clampedInterval(_ interval: DateInterval, to start: Date, end: Date) -> DateInterval? {
        let clampedStart = max(interval.start, start)
        let clampedEnd = min(interval.end, end)
        guard clampedEnd > clampedStart else { return nil }
        return DateInterval(start: clampedStart, end: clampedEnd)
    }

    private nonisolated static func mergeIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = [sorted[0]]

        for interval in sorted.dropFirst() {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }

            if interval.start <= last.end {
                let newInterval = DateInterval(start: last.start, end: max(last.end, interval.end))
                merged[merged.count - 1] = newInterval
            } else {
                merged.append(interval)
            }
        }

        return merged
    }

    private nonisolated static func mapSleepStage(_ value: Int) -> SleepStage {
        guard let stage = HKCategoryValueSleepAnalysis(rawValue: value) else {
            return .unknown
        }

        switch stage {
        case .awake:
            return .awake
        case .inBed:
            return .inBed
        case .asleepREM:
            return .rem
        case .asleepDeep:
            return .deep
        case .asleepCore:
            return .core
        case .asleepUnspecified:
            return .core
        case .asleep:
            return .core
        @unknown default:
            return .unknown
        }
    }

    private nonisolated static func isNoDataError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == HKErrorDomain &&
            nsError.code == HKError.Code.errorNoData.rawValue
    }
}
