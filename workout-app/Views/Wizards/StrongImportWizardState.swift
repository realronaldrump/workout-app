import Foundation

enum ImportPhase: Double {
    case idle = 0
    case reading = 0.2
    case parsing = 0.4
    case processing = 0.6
    case saving = 0.8
    case complete = 1.0

    var message: String {
        switch self {
        case .idle:
            return "Awaiting file"
        case .reading:
            return "Reading CSV"
        case .parsing:
            return "Parsing"
        case .processing:
            return "Processing"
        case .saving:
            return "Saving"
        case .complete:
            return "Complete"
        }
    }
}

enum HealthSyncState {
    case idle
    case unavailable
    case needsAuthorization
    case syncing
    case synced(Date)
    case failed(String)
}

enum AutoGymTagState {
    case idle
    case unavailable
    case needsAuthorization
    case tagging
    case complete
    case failed
}
