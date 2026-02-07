import Foundation
import HealthKit

extension HealthKitManager {
    func checkAuthorizationStatus() {
        guard let healthStore = healthStore else {
            authorizationStatus = .unavailable
            return
        }

        healthStore.getRequestStatusForAuthorization(toShare: [], read: allReadTypes) { [weak self] status, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.authorizationStatus = .denied
                    self.syncError = error.localizedDescription
                    return
                }

                switch status {
                case .unnecessary:
                    self.authorizationStatus = .authorized
                case .shouldRequest, .unknown:
                    self.authorizationStatus = .notDetermined
                @unknown default:
                    self.authorizationStatus = .notDetermined
                }
            }
        }
    }
}
