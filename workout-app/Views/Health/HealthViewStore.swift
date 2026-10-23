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
    /// Invalidate before forwarding the event, but build only when a visible Health
    /// screen asks for it. Cache bootstrap can publish several entries in one turn.
    private var snapshotSource: [Date: DailyHealthData]
    private var cachedDailySnapshot: HealthDailySnapshot?
    private var snapshotCalendar: Calendar?
    private(set) var dailyDataRevision: UInt64 = 0

    var dailySnapshot: HealthDailySnapshot {
        let calendar = Calendar.current
        if let cachedDailySnapshot, snapshotCalendar == calendar { return cachedDailySnapshot }
        let snapshot = HealthDailySnapshot(store: snapshotSource, calendar: calendar)
        cachedDailySnapshot = snapshot
        snapshotCalendar = calendar
        return snapshot
    }
    @Published private(set) var healthDataStore: [UUID: WorkoutHealthData]
    @Published private(set) var workouts: [Workout]
    @Published private(set) var isDailySyncing: Bool
    @Published private(set) var lastDailySyncDate: Date?
    @Published private(set) var syncError: String?

    /// The app root owns `HealthKitManager` for the full scene lifetime. This projection must
    /// not become a second owner: releasing a main-actor manager from SwiftUI's view-graph
    /// teardown can happen while the graph is draining its executor-local state.
    private unowned let healthManager: HealthKitManager
    private var cancellables: Set<AnyCancellable> = []

    // Swift 6.2's isolated-deinit back deployment currently traps in repeated XCTest
    // teardown on the iOS 26 simulator. This store owns no actor-bound teardown work.
    nonisolated deinit {}

    init(healthManager: HealthKitManager, dataManager: WorkoutDataManager) {
        self.healthManager = healthManager
        authorizationStatus = healthManager.authorizationStatus
        dailyHealthStore = healthManager.dailyHealthStore
        snapshotSource = healthManager.dailyHealthStore
        healthDataStore = healthManager.healthDataStore
        workouts = dataManager.workouts
        isDailySyncing = healthManager.isDailySyncing
        lastDailySyncDate = healthManager.lastDailySyncDate
        syncError = healthManager.syncError

        healthManager.$authorizationStatus
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] in self?.authorizationStatus = $0 }
            .store(in: &cancellables)

        healthManager.$dailyHealthStore
            .dropFirst()
            .sink { [weak self] in self?.replaceDailyHealthStore($0) }
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

        healthManager.$syncError
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] in self?.syncError = $0 }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .NSCalendarDayChanged))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.invalidateDailyCalendar() }
            .store(in: &cancellables)
    }

    private func replaceDailyHealthStore(_ store: [Date: DailyHealthData]) {
        snapshotSource = store
        cachedDailySnapshot = nil
        dailyDataRevision &+= 1
        dailyHealthStore = store
    }

    /// Rolling ranges and partial-day statistics also change without a HealthKit write.
    func invalidateDailyCalendar() {
        cachedDailySnapshot = nil
        snapshotCalendar = nil
        dailyDataRevision &+= 1
        objectWillChange.send()
    }

    func refreshAuthorizationStatus() {
#if DEBUG
        guard !AnalyticsUITestFixture.isEnabled else { return }
#endif
        healthManager.refreshAuthorizationStatus()
    }

#if DEBUG
    func installAnalyticsFixture(
        dailyHealth: [Date: DailyHealthData],
        workouts: [Workout]
    ) {
        authorizationStatus = .authorized
        replaceDailyHealthStore(dailyHealth)
        self.workouts = workouts
        lastDailySyncDate = Date()
        syncError = nil
    }
#endif

    func requestAuthorization() async throws {
        try await healthManager.requestAuthorization()
    }

    func syncDailyHealthData(range: DateInterval) async throws {
        try await healthManager.syncDailyHealthData(range: range)
    }

    func clearSyncError() {
        healthManager.syncError = nil
    }

    /// Resolve this metric's full history without depending on which daily
    /// summaries have already been synced into the local cache.
    func fetchEarliestMetricSampleDate(metric: HealthMetric) async throws -> Date? {
        guard authorizationStatus == .authorized, metric.supportsSamples else { return nil }
#if DEBUG
        if AnalyticsUITestFixture.isEnabled {
            if let samples = AnalyticsUITestFixture.bodySamples[metric] {
                return samples.first?.timestamp
            }
            return dailyHealthStore.values
                .filter { day in day.value(for: metric).map(\.isFinite) ?? false }
                .map(\.dayStart)
                .min()
        }
#endif
        guard let type = metric.quantityType else { return nil }
        return try await healthManager.fetchEarliestQuantitySampleDate(type: type)
    }

    func fetchMetricSamples(
        metric: HealthMetric,
        range: DateInterval
    ) async throws -> [HealthMetricSample] {
#if DEBUG
        if AnalyticsUITestFixture.isEnabled {
            if let samples = AnalyticsUITestFixture.bodySamples[metric] {
                return samples.filter { range.contains($0.timestamp) }
            }
            return dailyHealthStore.values
                .compactMap { day -> HealthMetricSample? in
                    guard range.contains(day.dayStart),
                          let value = day.value(for: metric),
                          value.isFinite else { return nil }
                    return HealthMetricSample(timestamp: day.dayStart, value: value)
                }
                .sorted { $0.timestamp < $1.timestamp }
        }
#endif
        return try await healthManager.fetchMetricSamples(metric: metric, range: range)
    }
}
