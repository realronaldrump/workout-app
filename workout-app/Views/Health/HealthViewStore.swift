import Combine
import Foundation

/// A narrow observable projection for the Health tab.
///
/// `HealthKitManager` also publishes transient operation state such as per-metric
/// sync progress. Observing that broad object directly made every Health chart
/// rebuild for updates that did not change its data. This store forwards only the
/// values that can change Health-tab presentation.
@MainActor
final class HealthViewStore: ObservableObject {
    @Published private(set) var authorizationStatus: HealthKitAuthorizationStatus
    @Published private(set) var dailyHealthStore: [Date: DailyHealthData]
    @Published private(set) var healthDataStore: [UUID: WorkoutHealthData]
    @Published private(set) var workouts: [Workout]
    @Published private(set) var isDailySyncing: Bool
    @Published private(set) var lastDailySyncDate: Date?

    private let healthManager: HealthKitManager
    private var cancellables: Set<AnyCancellable> = []

    nonisolated deinit {}

    init(healthManager: HealthKitManager, dataManager: WorkoutDataManager) {
        self.healthManager = healthManager
        authorizationStatus = healthManager.authorizationStatus
        dailyHealthStore = healthManager.dailyHealthStore
        healthDataStore = healthManager.healthDataStore
        workouts = dataManager.workouts
        isDailySyncing = healthManager.isDailySyncing
        lastDailySyncDate = healthManager.lastDailySyncDate

        healthManager.$authorizationStatus
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] in self?.authorizationStatus = $0 }
            .store(in: &cancellables)

        healthManager.$dailyHealthStore
            .dropFirst()
            .sink { [weak self] in self?.dailyHealthStore = $0 }
            .store(in: &cancellables)

        healthManager.$healthDataStore
            .dropFirst()
            .sink { [weak self] in self?.healthDataStore = $0 }
            .store(in: &cancellables)

        dataManager.$workouts
            .dropFirst()
            .sink { [weak self] in self?.workouts = $0 }
            .store(in: &cancellables)

        healthManager.$isDailySyncing
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] in self?.isDailySyncing = $0 }
            .store(in: &cancellables)

        healthManager.$lastDailySyncDate
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] in self?.lastDailySyncDate = $0 }
            .store(in: &cancellables)
    }

    func refreshAuthorizationStatus() {
        healthManager.refreshAuthorizationStatus()
    }

    func requestAuthorization() async throws {
        try await healthManager.requestAuthorization()
    }

    func syncDailyHealthData(range: DateInterval) async throws {
        try await healthManager.syncDailyHealthData(range: range)
    }
}
