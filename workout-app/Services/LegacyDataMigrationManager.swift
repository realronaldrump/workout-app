import Combine
import Foundation

enum LegacyDataMigrationPhase: Equatable {
    case idle
    case checking
    case ready(LegacyMigrationSummary)
    case migrating(LegacyMigrationSummary)
    case completed(LegacyMigrationResult)
    case notNeeded
    case failed(LegacyMigrationSummary?, String)

    var blocksLaunch: Bool {
        switch self {
        case .idle, .notNeeded:
            return false
        case .checking, .ready, .migrating, .completed, .failed:
            return true
        }
    }

    var summary: LegacyMigrationSummary? {
        switch self {
        case .ready(let summary),
             .migrating(let summary):
            return summary
        case .completed(let result):
            return result.summary
        case .failed(let summary, _):
            return summary
        case .idle, .checking, .notNeeded:
            return nil
        }
    }
}

@MainActor
final class LegacyDataMigrationManager: ObservableObject {
    @Published private(set) var phase: LegacyDataMigrationPhase = .idle

    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    var blocksLaunch: Bool {
        phase.blocksLaunch
    }

    func prepare() async {
        if database.canSkipLegacyMigrationPresentation() {
            phase = .notNeeded
            return
        }

        phase = .checking

        do {
            let database = database
            let plan = try await Task.detached(priority: .userInitiated) {
                try database.legacyMigrationPlan()
            }.value

            switch plan.status {
            case .ready:
                phase = .ready(plan.summary)
            case .noMigratableRecords:
                phase = .failed(
                    plan.summary,
                    "Saved data files were found, but no records could be read from them."
                )
            case .alreadyCompleted, .notNeeded:
                phase = .notNeeded
            }
        } catch {
            phase = .failed(nil, error.localizedDescription)
        }
    }

    func migrate() async {
        let summary = phase.summary
        if let summary {
            phase = .migrating(summary)
        } else {
            phase = .checking
        }

        do {
            let database = database
            let result = try await Task.detached(priority: .userInitiated) {
                try database.performLegacyMigration()
            }.value
            phase = .completed(result)
        } catch {
            phase = .failed(summary, error.localizedDescription)
        }
    }

    func dismiss() {
        phase = .notNeeded
    }
}
