import CoreLocation
import Foundation
import HealthKit

struct AutoGymTaggingFallbackCandidate: Identifiable {
    let workoutId: UUID
    let workoutName: String
    let workoutDate: Date
    let startCoordinate: CLLocationCoordinate2D?

    var id: UUID { workoutId }
}

struct AutoGymTaggingResult {
    let report: AutoGymTaggingReport
    let routePermissionUnavailable: Bool
    let fallbackCandidates: [AutoGymTaggingFallbackCandidate]
}

private struct GymDistanceMatch {
    let gymId: UUID
    let gymName: String
    let distanceMeters: Double
}

private struct GymNameMatch {
    let gymId: UUID
    let gymName: String
    let score: Int
    let distanceMeters: Double?
}

private struct AutoTaggingQueryWindow {
    let start: Date
    let end: Date
}

private struct CachedWorkoutLocationSnapshot {
    let workoutDate: Date
    let appleWorkoutUUID: UUID?
    let appleWorkoutType: String?
    let location: CLLocation
}

private struct AutoTaggingRuntime {
    let maxDistanceMeters: Double
    let relaxedMaxDistanceMeters: Double
    let maxStartDiffSeconds: TimeInterval
    let relaxedStartDiffSeconds: TimeInterval
    let gymCoordinates: [UUID: CLLocationCoordinate2D]
    let appleWorkouts: [HKWorkout]
    let appleByUUID: [UUID: HKWorkout]
    let cachedLocationByAppleUUID: [UUID: CLLocation]
    let historicalLocations: [CachedWorkoutLocationSnapshot]

    var routePermissionDenied: Bool
    var resolvedLocationByAppleUUID: [UUID: CLLocation] = [:]
    var appleUUIDsWithNoLocation: Set<UUID> = []

    var assignments: [UUID: UUID] = [:]
    var items: [AutoGymTaggingItem] = []
    var fallbackCandidates: [AutoGymTaggingFallbackCandidate] = []
    var fallbackCandidateIds: Set<UUID> = []

    var skippedNoMatchingWorkout = 0
    var skippedNoRoute = 0
    var skippedNoGymMatch = 0
    var skippedGymsMissingLocation = 0
}

@MainActor
enum AutoGymTaggingRunner {
    static func workoutsNeedingGymTag(
        in workouts: [Workout],
        annotationsManager: WorkoutAnnotationsManager,
        gymProfilesManager: GymProfilesManager
    ) -> [Workout] {
        workouts.filter { workout in
            let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
            if gymId == nil { return true }
            return gymProfilesManager.gymName(for: gymId) == nil
        }
    }

    static func run(
        for workouts: [Workout],
        annotationsManager: WorkoutAnnotationsManager,
        gymProfilesManager: GymProfilesManager,
        healthManager: HealthKitManager,
        progress: ((Double) -> Void)? = nil
    ) async throws -> AutoGymTaggingResult {
        let targets = workoutsNeedingGymTag(
            in: workouts,
            annotationsManager: annotationsManager,
            gymProfilesManager: gymProfilesManager
        )

        progress?(0)

        guard !targets.isEmpty else {
            return AutoGymTaggingResult(
                report: AutoGymTaggingReport(
                    attempted: 0,
                    assigned: 0,
                    skippedNoMatchingWorkout: 0,
                    skippedNoRoute: 0,
                    skippedNoGymMatch: 0,
                    skippedGymsMissingLocation: 0,
                    items: []
                ),
                routePermissionUnavailable: false,
                fallbackCandidates: []
            )
        }

        guard healthManager.isHealthKitAvailable() else {
            throw HealthKitError.notAvailable
        }

        var runtime = try await prepareRuntime(
            for: targets,
            gymProfilesManager: gymProfilesManager,
            healthManager: healthManager
        )
        await processTargets(
            targets,
            runtime: &runtime,
            gymProfilesManager: gymProfilesManager,
            healthManager: healthManager,
            progress: progress
        )

        if !runtime.assignments.isEmpty {
            annotationsManager.applyGymAssignments(runtime.assignments.mapValues { Optional($0) })
        }

        return AutoGymTaggingResult(
            report: AutoGymTaggingReport(
                attempted: targets.count,
                assigned: runtime.assignments.count,
                skippedNoMatchingWorkout: runtime.skippedNoMatchingWorkout,
                skippedNoRoute: runtime.skippedNoRoute,
                skippedNoGymMatch: runtime.skippedNoGymMatch,
                skippedGymsMissingLocation: runtime.skippedGymsMissingLocation,
                items: runtime.items.sorted { $0.workoutDate > $1.workoutDate }
            ),
            routePermissionUnavailable: runtime.routePermissionDenied,
            fallbackCandidates: runtime.fallbackCandidates.sorted { $0.workoutDate > $1.workoutDate }
        )
    }

    private static func prepareRuntime(
        for targets: [Workout],
        gymProfilesManager: GymProfilesManager,
        healthManager: HealthKitManager
    ) async throws -> AutoTaggingRuntime {
        let maxDistanceMeters: Double = 250
        let relaxedMaxDistanceMeters: Double = 450
        let maxStartDiffSeconds: TimeInterval = 20 * 60
        let relaxedStartDiffSeconds: TimeInterval = 12 * 60 * 60

        let routePermissionDenied = try await requestAuthorization(healthManager: healthManager)
        let gymCoordinates = await gymProfilesManager.resolveGymCoordinates()
        let window = autoTaggingQueryWindow(
            for: targets,
            padding: max(maxStartDiffSeconds, relaxedStartDiffSeconds)
        )
        let appleWorkouts = try await healthManager.fetchAppleWorkouts(from: window.start, to: window.end)
        let appleByUUID = Dictionary(uniqueKeysWithValues: appleWorkouts.map { ($0.uuid, $0) })
        let historicalLocations = healthManager.healthDataStore.values.compactMap(cachedWorkoutLocationSnapshot(from:))
        let cachedLocationByAppleUUID = historicalLocations.reduce(into: [UUID: CLLocation]()) { partialResult, snapshot in
            guard let appleWorkoutUUID = snapshot.appleWorkoutUUID else { return }
            partialResult[appleWorkoutUUID] = snapshot.location
        }

        var runtime = AutoTaggingRuntime(
            maxDistanceMeters: maxDistanceMeters,
            relaxedMaxDistanceMeters: relaxedMaxDistanceMeters,
            maxStartDiffSeconds: maxStartDiffSeconds,
            relaxedStartDiffSeconds: relaxedStartDiffSeconds,
            gymCoordinates: gymCoordinates,
            appleWorkouts: appleWorkouts,
            appleByUUID: appleByUUID,
            cachedLocationByAppleUUID: cachedLocationByAppleUUID,
            historicalLocations: historicalLocations,
            routePermissionDenied: routePermissionDenied
        )
        runtime.items.reserveCapacity(targets.count)
        return runtime
    }

    private static func requestAuthorization(healthManager: HealthKitManager) async throws -> Bool {
        if healthManager.authorizationStatus != .authorized {
            try await healthManager.requestAuthorization()
        }

        do {
            try await healthManager.requestWorkoutRouteAuthorization()
            return false
        } catch {
            return true
        }
    }

    private static func autoTaggingQueryWindow(
        for targets: [Workout],
        padding: TimeInterval
    ) -> AutoTaggingQueryWindow {
        let windows = targets.map { $0.estimatedWindow(defaultMinutes: 60) }
        let minStart = windows.map(\.start).min() ?? targets[0].date
        let maxEnd = windows.map(\.end).max() ?? targets[0].estimatedWindow(defaultMinutes: 60).end
        return AutoTaggingQueryWindow(
            start: minStart.addingTimeInterval(-padding),
            end: maxEnd.addingTimeInterval(padding)
        )
    }

    private static func processTargets(
        _ targets: [Workout],
        runtime: inout AutoTaggingRuntime,
        gymProfilesManager: GymProfilesManager,
        healthManager: HealthKitManager,
        progress: ((Double) -> Void)?
    ) async {
        for (index, workout) in targets.enumerated() {
            progress?(Double(index) / Double(max(1, targets.count)))
            await processWorkout(
                workout,
                runtime: &runtime,
                gymProfilesManager: gymProfilesManager,
                healthManager: healthManager
            )
        }
        progress?(1)
    }

    private static func processWorkout(
        _ workout: Workout,
        runtime: inout AutoTaggingRuntime,
        gymProfilesManager: GymProfilesManager,
        healthManager: HealthKitManager
    ) async {
        let cached = healthManager.getHealthData(for: workout.id)
        if let cachedLocation = cachedWorkoutLocation(from: cached) {
            applyResolvedAssignment(
                for: workout,
                location: cachedLocation,
                runtime: &runtime,
                gymProfilesManager: gymProfilesManager
            )
            return
        }

        let appleWorkout = resolveAppleWorkout(
            for: workout,
            cachedHealthData: cached,
            runtime: runtime,
            healthManager: healthManager
        )
        if appleWorkout == nil,
           let historicalLocation = historicalCachedLocation(for: workout, appleWorkout: nil, runtime: runtime) {
            applyResolvedAssignment(
                for: workout,
                location: historicalLocation,
                runtime: &runtime,
                gymProfilesManager: gymProfilesManager
            )
            return
        }

        guard let appleWorkout else {
            if applyWorkoutNameAssignmentIfPossible(
                for: workout,
                location: nil,
                runtime: &runtime,
                gymProfilesManager: gymProfilesManager
            ) {
                return
            }
            runtime.skippedNoMatchingWorkout += 1
            runtime.items.append(.skipped(workout: workout, reason: "No matching Apple workout near this timestamp"))
            queueFallbackCandidate(for: workout, location: nil, runtime: &runtime)
            return
        }

        guard let startLocation = await fetchWorkoutLocation(
            for: workout,
            appleWorkout: appleWorkout,
            runtime: &runtime,
            healthManager: healthManager
        ) else {
            if applyWorkoutNameAssignmentIfPossible(
                for: workout,
                location: nil,
                runtime: &runtime,
                gymProfilesManager: gymProfilesManager
            ) {
                return
            }
            runtime.skippedNoRoute += 1
            let reason = runtime.routePermissionDenied
                ? "No workout location available (route permission unavailable)"
                : "No workout location returned by Apple Health"
            runtime.items.append(.skipped(workout: workout, reason: reason))
            queueFallbackCandidate(for: workout, location: nil, runtime: &runtime)
            return
        }

        applyResolvedAssignment(
            for: workout,
            location: startLocation,
            runtime: &runtime,
            gymProfilesManager: gymProfilesManager
        )
    }

    private static func cachedWorkoutLocation(from cachedHealthData: WorkoutHealthData?) -> CLLocation? {
        guard let coordinate = cachedHealthData?.resolvedWorkoutLocationCoordinate else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private static func cachedWorkoutLocationSnapshot(from healthData: WorkoutHealthData) -> CachedWorkoutLocationSnapshot? {
        guard let coordinate = healthData.resolvedWorkoutLocationCoordinate else { return nil }
        return CachedWorkoutLocationSnapshot(
            workoutDate: healthData.workoutDate,
            appleWorkoutUUID: healthData.appleWorkoutUUID,
            appleWorkoutType: healthData.appleWorkoutType,
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }

    private static func resolveAppleWorkout(
        for workout: Workout,
        cachedHealthData: WorkoutHealthData?,
        runtime: AutoTaggingRuntime,
        healthManager: HealthKitManager
    ) -> HKWorkout? {
        if let appleUUID = cachedHealthData?.appleWorkoutUUID, let exact = runtime.appleByUUID[appleUUID] {
            return exact
        }
        return healthManager.bestMatchingAppleWorkout(
            for: workout,
            candidates: runtime.appleWorkouts,
            strictStartDifferenceSeconds: runtime.maxStartDiffSeconds,
            relaxedStartDifferenceSeconds: runtime.relaxedStartDiffSeconds
        )
    }

    private static func fetchWorkoutLocation(
        for workout: Workout,
        appleWorkout: HKWorkout,
        runtime: inout AutoTaggingRuntime,
        healthManager: HealthKitManager
    ) async -> CLLocation? {
        let appleUUID = appleWorkout.uuid
        if let cachedLocation = runtime.resolvedLocationByAppleUUID[appleUUID] {
            return cachedLocation
        }
        if let cachedLocation = runtime.cachedLocationByAppleUUID[appleUUID] {
            runtime.resolvedLocationByAppleUUID[appleUUID] = cachedLocation
            return cachedLocation
        }
        if let historicalLocation = historicalCachedLocation(for: workout, appleWorkout: appleWorkout, runtime: runtime) {
            runtime.resolvedLocationByAppleUUID[appleUUID] = historicalLocation
            return historicalLocation
        }
        if runtime.appleUUIDsWithNoLocation.contains(appleUUID) {
            return nil
        }

        do {
            if let location = try await healthManager.fetchWorkoutLocation(for: appleWorkout)?.location {
                runtime.resolvedLocationByAppleUUID[appleUUID] = location
                return location
            }
        } catch let error as HealthKitError {
            if case .authorizationFailed = error {
                runtime.routePermissionDenied = true
            }
        } catch {
            // Keep processing with map fallback.
        }

        runtime.appleUUIDsWithNoLocation.insert(appleUUID)
        return nil
    }

    private static func historicalCachedLocation(
        for workout: Workout,
        appleWorkout: HKWorkout?,
        runtime: AutoTaggingRuntime
    ) -> CLLocation? {
        let preferredAppleType = appleWorkout?.workoutActivityType.name
        let strictCandidates = runtime.historicalLocations.filter { snapshot in
            abs(snapshot.workoutDate.timeIntervalSince(workout.date)) <= runtime.maxStartDiffSeconds
        }
        if let exact = bestHistoricalLocation(
            from: strictCandidates,
            workoutDate: workout.date,
            preferredAppleType: preferredAppleType
        ) {
            return exact
        }

        guard let preferredAppleType else { return nil }

        let relaxedCandidates = runtime.historicalLocations.filter { snapshot in
            guard snapshot.appleWorkoutType == preferredAppleType else { return false }
            return abs(snapshot.workoutDate.timeIntervalSince(workout.date)) <= runtime.relaxedStartDiffSeconds
        }
        return bestHistoricalLocation(
            from: relaxedCandidates,
            workoutDate: workout.date,
            preferredAppleType: preferredAppleType
        )
    }

    private static func bestHistoricalLocation(
        from snapshots: [CachedWorkoutLocationSnapshot],
        workoutDate: Date,
        preferredAppleType: String?
    ) -> CLLocation? {
        let sorted = snapshots.sorted { lhs, rhs in
            let lhsTypeMatch = preferredAppleType != nil && lhs.appleWorkoutType == preferredAppleType
            let rhsTypeMatch = preferredAppleType != nil && rhs.appleWorkoutType == preferredAppleType
            if lhsTypeMatch != rhsTypeMatch {
                return lhsTypeMatch
            }
            return abs(lhs.workoutDate.timeIntervalSince(workoutDate)) < abs(rhs.workoutDate.timeIntervalSince(workoutDate))
        }
        return sorted.first?.location
    }

    private static func applyResolvedAssignment(
        for workout: Workout,
        location: CLLocation,
        runtime: inout AutoTaggingRuntime,
        gymProfilesManager: GymProfilesManager
    ) {
        if applyWorkoutNameAssignmentIfPossible(
            for: workout,
            location: location,
            runtime: &runtime,
            gymProfilesManager: gymProfilesManager
        ) {
            return
        }

        guard !runtime.gymCoordinates.isEmpty else {
            runtime.skippedGymsMissingLocation += 1
            runtime.items.append(.skipped(workout: workout, reason: "Gyms missing addresses/coordinates"))
            queueFallbackCandidate(for: workout, location: location, runtime: &runtime)
            return
        }

        guard let match = nearestGym(
            to: location,
            gymCoordinates: runtime.gymCoordinates,
            maxDistanceMeters: runtime.maxDistanceMeters,
            gymProfilesManager: gymProfilesManager
        ) ?? uniqueNearbyGym(
            to: location,
            gymCoordinates: runtime.gymCoordinates,
            maxDistanceMeters: runtime.relaxedMaxDistanceMeters,
            gymProfilesManager: gymProfilesManager
        ) else {
            runtime.skippedNoGymMatch += 1
            let nearestDistance = nearestGym(
                to: location,
                gymCoordinates: runtime.gymCoordinates,
                maxDistanceMeters: .greatestFiniteMagnitude,
                gymProfilesManager: gymProfilesManager
            )?.distanceMeters
            let reason: String
            if let nearestDistance {
                reason = "No confident gym match (nearest saved gym is \(Int(nearestDistance.rounded()))m away)"
            } else {
                reason = "No saved gym coordinates were close enough"
            }
            runtime.items.append(.skipped(workout: workout, reason: reason))
            queueFallbackCandidate(for: workout, location: location, runtime: &runtime)
            return
        }

        runtime.assignments[workout.id] = match.gymId
        runtime.items.append(
            .assigned(
                workout: workout,
                detail: "Tagged by location: \(match.gymName) (\(Int(match.distanceMeters.rounded()))m)"
            )
        )
    }

    private static func applyWorkoutNameAssignmentIfPossible(
        for workout: Workout,
        location: CLLocation?,
        runtime: inout AutoTaggingRuntime,
        gymProfilesManager: GymProfilesManager
    ) -> Bool {
        guard let match = inferredGymFromWorkoutName(
            workout.name,
            location: location,
            runtime: runtime,
            gymProfilesManager: gymProfilesManager
        ) else {
            return false
        }

        runtime.assignments[workout.id] = match.gymId
        runtime.items.append(
            .assigned(
                workout: workout,
                detail: "Tagged from workout name: \(match.gymName)"
            )
        )
        return true
    }

    private static func queueFallbackCandidate(
        for workout: Workout,
        location: CLLocation?,
        runtime: inout AutoTaggingRuntime
    ) {
        guard runtime.fallbackCandidateIds.insert(workout.id).inserted else { return }
        runtime.fallbackCandidates.append(
            AutoGymTaggingFallbackCandidate(
                workoutId: workout.id,
                workoutName: workout.name,
                workoutDate: workout.date,
                startCoordinate: location?.coordinate
            )
        )
    }

    private static func nearestGym(
        to location: CLLocation,
        gymCoordinates: [UUID: CLLocationCoordinate2D],
        maxDistanceMeters: Double,
        gymProfilesManager: GymProfilesManager
    ) -> GymDistanceMatch? {
        var best: GymDistanceMatch?

        for (gymId, coordinate) in gymCoordinates {
            let gymLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = location.distance(from: gymLocation)
            guard distance <= maxDistanceMeters else { continue }

            let name = gymProfilesManager.gymName(for: gymId) ?? "Gym"
            let candidate = GymDistanceMatch(gymId: gymId, gymName: name, distanceMeters: distance)
            guard let existing = best else {
                best = candidate
                continue
            }
            if candidate.distanceMeters < existing.distanceMeters {
                best = candidate
            }
        }

        return best
    }

    private static func uniqueNearbyGym(
        to location: CLLocation,
        gymCoordinates: [UUID: CLLocationCoordinate2D],
        maxDistanceMeters: Double,
        gymProfilesManager: GymProfilesManager
    ) -> GymDistanceMatch? {
        let candidates = gymCoordinates.compactMap { gymId, coordinate -> GymDistanceMatch? in
            let gymLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = location.distance(from: gymLocation)
            guard distance <= maxDistanceMeters else { return nil }
            let name = gymProfilesManager.gymName(for: gymId) ?? "Gym"
            return GymDistanceMatch(gymId: gymId, gymName: name, distanceMeters: distance)
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }

        guard let best = candidates.first else { return nil }
        guard candidates.count > 1 else { return best }

        let secondBest = candidates[1]
        return (secondBest.distanceMeters - best.distanceMeters) >= 125 ? best : nil
    }

    private static func inferredGymFromWorkoutName(
        _ workoutName: String,
        location: CLLocation?,
        runtime: AutoTaggingRuntime,
        gymProfilesManager: GymProfilesManager
    ) -> GymNameMatch? {
        let normalizedWorkoutName = normalizedGymLookupText(workoutName)
        let workoutTokens = meaningfulGymLookupTokens(from: workoutName)
        guard !normalizedWorkoutName.isEmpty, !workoutTokens.isEmpty else { return nil }

        let matches = gymProfilesManager.gyms.compactMap { gym -> GymNameMatch? in
            let normalizedGymName = normalizedGymLookupText(gym.name)
            let normalizedAddress = normalizedGymLookupText(gym.address ?? "")
            let gymNameTokens = meaningfulGymLookupTokens(from: gym.name)
            let addressTokens = meaningfulGymLookupTokens(from: gym.address ?? "")

            let matchedNameTokens = workoutTokens.intersection(gymNameTokens)
            let matchedAddressTokens = workoutTokens.intersection(addressTokens)
            let namePhraseMatch = !normalizedGymName.isEmpty && normalizedWorkoutName.contains(normalizedGymName)
            let addressPhraseMatch = !normalizedAddress.isEmpty && normalizedWorkoutName.contains(normalizedAddress)

            let hasMeaningfulMatch =
                namePhraseMatch ||
                addressPhraseMatch ||
                matchedNameTokens.count >= max(1, min(gymNameTokens.count, 2)) ||
                (!matchedNameTokens.isEmpty && !matchedAddressTokens.isEmpty)

            guard hasMeaningfulMatch else { return nil }

            var score = matchedNameTokens.count * 14 + matchedAddressTokens.count * 10
            if namePhraseMatch {
                score += 40
            }
            if addressPhraseMatch {
                score += 25
            }
            if !gymNameTokens.isEmpty && matchedNameTokens.count == gymNameTokens.count {
                score += 12
            }

            var distanceMeters: Double?
            if let location, let latitude = gym.latitude, let longitude = gym.longitude {
                let gymLocation = CLLocation(latitude: latitude, longitude: longitude)
                let distance = location.distance(from: gymLocation)
                distanceMeters = distance

                if distance <= runtime.maxDistanceMeters {
                    score += 20
                } else if distance <= runtime.relaxedMaxDistanceMeters {
                    score += 12
                } else if distance <= runtime.relaxedMaxDistanceMeters * 2 {
                    score += 4
                } else {
                    score -= 30
                }
            }

            return GymNameMatch(
                gymId: gym.id,
                gymName: gym.name,
                score: score,
                distanceMeters: distanceMeters
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }

            switch (lhs.distanceMeters, rhs.distanceMeters) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.gymName.localizedCaseInsensitiveCompare(rhs.gymName) == .orderedAscending
            }
        }

        guard let best = matches.first, best.score >= 28 else { return nil }
        if let distance = best.distanceMeters,
           location != nil,
           distance > runtime.relaxedMaxDistanceMeters * 2,
           best.score < 60 {
            return nil
        }

        guard matches.count > 1 else { return best }

        let secondBest = matches[1]
        if best.score - secondBest.score >= 12 {
            return best
        }

        if let bestDistance = best.distanceMeters,
           let secondDistance = secondBest.distanceMeters,
           secondDistance - bestDistance >= 125 {
            return best
        }

        return nil
    }

    private static func normalizedGymLookupText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func meaningfulGymLookupTokens(from value: String) -> Set<String> {
        let ignoredTokens: Set<String> = [
            "am", "and", "at", "club", "day", "evening", "for", "gym", "in", "lift",
            "morning", "night", "of", "pm", "session", "the", "training", "workout"
        ]

        let normalized = normalizedGymLookupText(value)
        let tokens = normalized.split(separator: " ").map(String.init)
        return Set(tokens.filter { token in
            token.count >= 2 && !ignoredTokens.contains(token)
        })
    }
}
