import CoreLocation
import Foundation
import HealthKit

struct ResolvedWorkoutLocation {
    let location: CLLocation
    let source: WorkoutLocationSource
}

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
                    if let auth = Self.authorizationFailure(from: error) {
                        Task { @MainActor in
                            self.authorizationStatus = auth.status
                        }
                        continuation.resume(throwing: auth.error)
                        return
                    }
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
        let workouts = try await fetchAppleWorkouts(from: start, to: end, limit: 1, ascending: true)
        return workouts.first
    }

    func fetchAppleWorkouts(
        from start: Date,
        to end: Date,
        limit: Int = HKObjectQueryNoLimit,
        ascending: Bool = true
    ) async throws -> [HKWorkout] {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)]
            ) { _, samples, error in
                if let error {
                    if let auth = Self.authorizationFailure(from: error) {
                        Task { @MainActor in
                            self.authorizationStatus = auth.status
                        }
                        continuation.resume(throwing: auth.error)
                        return
                    }
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            healthStore.execute(query)
        }
    }

    /// Match an imported workout to the most likely Apple workout.
    /// Uses a strict start-time pass first, then a relaxed pass to handle timezone/drift issues.
    func bestMatchingAppleWorkout(
        for workout: Workout,
        candidates: [HKWorkout],
        strictStartDifferenceSeconds: TimeInterval = 20 * 60,
        relaxedStartDifferenceSeconds: TimeInterval = 8 * 60 * 60
    ) -> HKWorkout? {
        let window = workout.estimatedWindow(defaultMinutes: 60)
        let preferredActivityTypes = inferredAppleWorkoutActivityTypes(for: workout)

        struct ScoredCandidate {
            let workout: HKWorkout
            let score: Double
            let startDiff: TimeInterval
            let preferredTypeMatch: Bool
        }

        func scoreCandidate(_ candidate: HKWorkout) -> ScoredCandidate {
            let startDiff = abs(candidate.startDate.timeIntervalSince(window.start))
            let durationDiff = abs(candidate.duration - window.duration)
            let candidateInterval = DateInterval(start: candidate.startDate, end: candidate.endDate)
            let overlap = candidateInterval.intersection(with: window)?.duration ?? 0
            let preferredTypeMatch = preferredActivityTypes.isEmpty ||
                activityType(candidate.workoutActivityType, matchesAnyOf: preferredActivityTypes)
            let activityPenalty = preferredTypeMatch ? 0.0 : 30.0 * 60.0
            // Lower is better. Prefer close start time, similar duration, and overlap.
            let score = startDiff + (durationDiff * 0.35) - (overlap * 0.25) + activityPenalty
            return ScoredCandidate(
                workout: candidate,
                score: score,
                startDiff: startDiff,
                preferredTypeMatch: preferredTypeMatch
            )
        }

        let strictMatches = candidates
            .map(scoreCandidate)
            .filter { $0.startDiff <= strictStartDifferenceSeconds }
            .sorted { $0.score < $1.score }

        if let strictBest = strictMatches.first {
            return strictBest.workout
        }

        let relaxedMatches = candidates
            .map(scoreCandidate)
            .filter { $0.startDiff <= relaxedStartDifferenceSeconds }
            .sorted { $0.score < $1.score }

        guard let relaxedBest = relaxedMatches.first else { return nil }

        // Avoid low-confidence assignments when the top two relaxed candidates are too close.
        if relaxedMatches.count > 1 {
            let second = relaxedMatches[1]
            if relaxedBest.preferredTypeMatch != second.preferredTypeMatch {
                return relaxedBest.workout
            }
            if (second.score - relaxedBest.score) < (20 * 60) {
                return nil
            }
        }

        return relaxedBest.workout
    }

    /// Queries Apple workouts around an imported workout and returns the best match.
    func fetchBestMatchingAppleWorkout(
        for workout: Workout,
        strictStartDifferenceSeconds: TimeInterval = 20 * 60,
        relaxedStartDifferenceSeconds: TimeInterval = 8 * 60 * 60
    ) async throws -> HKWorkout? {
        let window = workout.estimatedWindow(defaultMinutes: 60)
        let queryStart = window.start.addingTimeInterval(-relaxedStartDifferenceSeconds)
        let queryEnd = window.end.addingTimeInterval(relaxedStartDifferenceSeconds)
        let candidates = try await fetchAppleWorkouts(from: queryStart, to: queryEnd)
        return bestMatchingAppleWorkout(
            for: workout,
            candidates: candidates,
            strictStartDifferenceSeconds: strictStartDifferenceSeconds,
            relaxedStartDifferenceSeconds: relaxedStartDifferenceSeconds
        )
    }

    func fetchWorkoutLocation(for workout: HKWorkout) async throws -> ResolvedWorkoutLocation? {
        var routeError: Error?

        do {
            if let routeLocation = try await fetchWorkoutRouteStartLocation(for: workout) {
                return ResolvedWorkoutLocation(location: routeLocation, source: .route)
            }
        } catch {
            routeError = error
        }

        if let metadataLocation = Self.extractLocationFromMetadata(workout.metadata) {
            return ResolvedWorkoutLocation(location: metadataLocation, source: .metadata)
        }

        if let routeError {
            throw routeError
        }

        return nil
    }

    func fetchWorkoutRoutes(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }

        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    if let auth = Self.authorizationFailure(from: error) {
                        Task { @MainActor in
                            self.authorizationStatus = auth.status
                        }
                        continuation.resume(throwing: auth.error)
                        return
                    }
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }

            healthStore.execute(query)
        }
    }

    func fetchWorkoutRouteStartLocation(for workout: HKWorkout) async throws -> CLLocation? {
        let routes = try await fetchWorkoutRoutes(for: workout)
        guard let firstRoute = routes.first else { return nil }
        return try await fetchFirstLocation(for: firstRoute)
    }

    private func fetchFirstLocation(for route: HKWorkoutRoute) async throws -> CLLocation? {
        guard let healthStore = healthStore else {
            throw HealthKitError.notAvailable
        }

        if #available(iOS 15.4, macOS 13.0, watchOS 8.5, visionOS 1.0, *) {
            let descriptor = HKWorkoutRouteQueryDescriptor(route)
            let locations = descriptor.results(for: healthStore)
            for try await location in locations {
                return location
            }
            return nil
        }

        return try await fetchFirstLocationLegacy(for: route, healthStore: healthStore)
    }

    private func fetchFirstLocationLegacy(for route: HKWorkoutRoute, healthStore: HKHealthStore) async throws -> CLLocation? {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            let query = HKWorkoutRouteQuery(route: route) { query, locationsOrNil, done, errorOrNil in
                if let errorOrNil {
                    if didResume { return }
                    didResume = true
                    if let auth = Self.authorizationFailure(from: errorOrNil) {
                        Task { @MainActor in
                            self.authorizationStatus = auth.status
                        }
                        continuation.resume(throwing: auth.error)
                        return
                    }
                    if Self.isNoDataError(errorOrNil) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(errorOrNil.localizedDescription))
                    return
                }

                if let first = locationsOrNil?.first {
                    if didResume { return }
                    didResume = true
                    healthStore.stop(query)
                    continuation.resume(returning: first)
                    return
                }

                if done {
                    if didResume { return }
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }

    private nonisolated func inferredAppleWorkoutActivityTypes(for workout: Workout) -> Set<HKWorkoutActivityType> {
        let combined = ([workout.name] + workout.exercises.map(\.name))
            .joined(separator: " ")
            .lowercased()
        var inferred: Set<HKWorkoutActivityType> = []

        if combined.contains("stair") || combined.contains("stepper") || combined.contains("stepmill") {
            inferred.formUnion([.stairClimbing, .stairs, .stepTraining])
        }
        if combined.contains("ellipt") {
            inferred.insert(.elliptical)
        }
        if combined.contains("row") || combined.contains("erg") {
            inferred.insert(.rowing)
        }
        if combined.contains("cycle") || combined.contains("bike") || combined.contains("spin") || combined.contains("peloton") {
            inferred.insert(.cycling)
        }
        if combined.contains("run") || combined.contains("treadmill") || combined.contains("jog") {
            inferred.insert(.running)
        }
        if combined.contains("walk") || combined.contains("hike") {
            inferred.insert(.walking)
        }
        if combined.contains("yoga") {
            inferred.insert(.yoga)
        }
        if combined.contains("pilates") {
            inferred.insert(.pilates)
        }
        if combined.contains("hiit") || combined.contains("interval") {
            inferred.insert(.highIntensityIntervalTraining)
        }

        let strengthKeywords = [
            "bench", "press", "squat", "deadlift", "curl", "extension", "raise",
            "pulldown", "pull down", "lat pull", "row", "lunge", "fly",
            "tricep", "bicep", "shoulder", "leg press", "rdl", "weight", "strength"
        ]
        let hasStrengthKeyword = strengthKeywords.contains { combined.contains($0) }
        let hasWeightedSet = workout.exercises.contains { exercise in
            exercise.sets.contains { $0.weight > 0 }
        }

        if hasStrengthKeyword || hasWeightedSet {
            inferred.formUnion([.traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining])
        }

        return inferred
    }

    private nonisolated func activityType(
        _ candidate: HKWorkoutActivityType,
        matchesAnyOf preferredTypes: Set<HKWorkoutActivityType>
    ) -> Bool {
        guard !preferredTypes.isEmpty else { return true }
        if preferredTypes.contains(candidate) { return true }

        let strengthTypes: Set<HKWorkoutActivityType> = [
            .traditionalStrengthTraining,
            .functionalStrengthTraining,
            .crossTraining
        ]
        if strengthTypes.contains(candidate), !preferredTypes.isDisjoint(with: strengthTypes) {
            return true
        }

        let stairTypes: Set<HKWorkoutActivityType> = [
            .stairClimbing,
            .stairs,
            .stepTraining
        ]
        if stairTypes.contains(candidate), !preferredTypes.isDisjoint(with: stairTypes) {
            return true
        }

        return false
    }

    private nonisolated static func extractLocationFromMetadata(
        _ metadata: [String: Any]?
    ) -> CLLocation? {
        guard let metadata, !metadata.isEmpty else { return nil }

        if let latitude = metadataCoordinateComponent(in: metadata, matching: ["latitude", "lat"]),
           let longitude = metadataCoordinateComponent(in: metadata, matching: ["longitude", "lon", "lng"]),
           CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
            return CLLocation(latitude: latitude, longitude: longitude)
        }

        for (key, value) in metadata {
            let normalizedKey = normalizeMetadataKey(key)
            guard normalizedKey.contains("location") || normalizedKey.contains("coordinate") else { continue }
            if let coordinate = coordinatePair(from: value) {
                return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        }

        return nil
    }

    private nonisolated static func metadataCoordinateComponent(
        in metadata: [String: Any],
        matching hints: [String]
    ) -> Double? {
        for (key, value) in metadata {
            let normalizedKey = normalizeMetadataKey(key)
            guard hints.contains(where: { normalizedKey == $0 || normalizedKey.hasSuffix(".\($0)") || normalizedKey.contains($0) }) else {
                continue
            }
            guard let number = numericMetadataValue(value) else { continue }
            return number
        }
        return nil
    }

    private nonisolated static func coordinatePair(
        from value: Any
    ) -> CLLocationCoordinate2D? {
        guard let stringValue = stringMetadataValue(value) else { return nil }
        let components = stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard components.count == 2,
              let latitude = Double(components[0]),
              let longitude = Double(components[1]) else {
            return nil
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private nonisolated static func numericMetadataValue(_ value: Any) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private nonisolated static func stringMetadataValue(_ value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private nonisolated static func normalizeMetadataKey(_ key: String) -> String {
        key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: ".")
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
                    if let auth = Self.authorizationFailure(from: error) {
                        Task { @MainActor in
                            self.authorizationStatus = auth.status
                        }
                        continuation.resume(throwing: auth.error)
                        return
                    }
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
                    if let auth = Self.authorizationFailure(from: error) {
                        Task { @MainActor in
                            self.authorizationStatus = auth.status
                        }
                        continuation.resume(throwing: auth.error)
                        return
                    }
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
                    if let auth = Self.authorizationFailure(from: error) {
                        Task { @MainActor in
                            self.authorizationStatus = auth.status
                        }
                        continuation.resume(throwing: auth.error)
                        return
                    }
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
                    if let auth = Self.authorizationFailure(from: error) {
                        Task { @MainActor in
                            self.authorizationStatus = auth.status
                        }
                        continuation.resume(throwing: auth.error)
                        return
                    }
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

    private nonisolated static func authorizationFailure(from error: Error) -> (status: HealthKitAuthorizationStatus, error: HealthKitError)? {
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain else { return nil }

        if nsError.code == HKError.Code.errorAuthorizationDenied.rawValue {
            return (
                status: .denied,
                error: .authorizationFailed("Access denied. Enable permissions in Settings > Health > Data Access & Devices > workout-app.")
            )
        }

        if nsError.code == HKError.Code.errorAuthorizationNotDetermined.rawValue {
            return (
                status: .notDetermined,
                error: .authorizationFailed("Authorization not determined. Please authorize Apple Health access.")
            )
        }

        return nil
    }
}
