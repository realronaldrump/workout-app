import Foundation
import HealthKit

extension HealthKitManager {
    func checkAuthorizationStatus() {
        // Keep a sync entry point for callers like init(), but do the actual work in the async version
        // so other code can await the status update when it matters (e.g., onboarding flows).
        Task { @MainActor in
            await checkAuthorizationStatusAsync()
        }
    }

    /// Async flavor that completes only after HealthKit returns a request-status response.
    /// This prevents race conditions where the UI proceeds assuming the status has been updated.
    func checkAuthorizationStatusAsync() async {
        guard let healthStore = healthStore else {
            authorizationStatus = .unavailable
            return
        }

        let readTypes = Self.normalizedAuthorizationReadTypes(for: allReadTypes)
        let (status, error): (HKAuthorizationRequestStatus, Error?) = await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                continuation.resume(returning: (status, error))
            }
        }

        if let error {
            authorizationStatus = .denied
            syncError = error.localizedDescription
            return
        }

        switch status {
        case .unnecessary:
            authorizationStatus = .authorized
        case .shouldRequest, .unknown:
            authorizationStatus = .notDetermined
        @unknown default:
            authorizationStatus = .notDetermined
        }
    }

    /// Requests read access for Workout Route samples (location series attached to workouts).
    /// Kept as a targeted entry point for callers that need to repair or retry route access independently.
    func requestWorkoutRouteAuthorization() async throws {
        if let authorizationTask {
            try await authorizationTask.value
        }

        if let workoutRouteAuthorizationTask {
            return try await workoutRouteAuthorizationTask.value
        }

        let task = Task { @MainActor in
            guard let healthStore = healthStore else {
                throw HealthKitError.notAvailable
            }

            do {
                let routeReadTypes = Self.normalizedAuthorizationReadTypes(
                    for: [HKSeriesType.workoutRoute()]
                )
                try await healthStore.requestAuthorization(toShare: [], read: routeReadTypes)
            } catch {
                throw HealthKitError.authorizationFailed(error.localizedDescription)
            }
        }

        workoutRouteAuthorizationTask = task
        defer { workoutRouteAuthorizationTask = nil }
        try await task.value
    }
}
