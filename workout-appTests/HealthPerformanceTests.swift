import Combine
import SwiftUI
import UIKit
import XCTest
@testable import workout_app

final class HealthPerformanceTests: XCTestCase {
    @MainActor
    func testExploreActivityOneWeekRenderStaysResponsiveDuringSyncProgressUpdates() {
        let healthManager = HealthKitManager()
        healthManager.authorizationStatus = .authorized
        healthManager.dailyHealthStore = makeDailyStore(dayCount: 1_500)
        do {
            let healthStore = HealthViewStore(
                healthManager: healthManager,
                dataManager: WorkoutDataManager()
            )

            let context = HealthDateRangeContext(selectedRange: .week)
            let view = NavigationStack {
                HealthCategoryDetailView(category: .activity)
            }
            .environmentObject(healthStore)
            .environmentObject(context)

            let controller = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 428, height: 926))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            let renderStart = CFAbsoluteTimeGetCurrent()
            controller.view.layoutIfNeeded()
            let initialRenderDuration = CFAbsoluteTimeGetCurrent() - renderStart
            XCTAssertLessThan(initialRenderDuration, 5)

            let options = XCTMeasureOptions()
            options.iterationCount = 3
            measure(
                metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
                options: options
            ) {
                for step in 0..<22 {
                    healthManager.dailySyncProgress = Double(step) / 21
                    RunLoop.main.run(until: Date())
                    controller.view.setNeedsLayout()
                    controller.view.layoutIfNeeded()
                }
            }

            window.isHidden = true
            window.rootViewController = nil
        }
        // Keep the manager alive until after the nonisolated HealthViewStore teardown has
        // released its MainActor-isolated dependency.
        withExtendedLifetime(healthManager) {}
    }

    @MainActor
    func testHealthViewStoreIgnoresSyncProgressOnlyChanges() {
        let healthManager = HealthKitManager()
        healthManager.dailyHealthStore = makeDailyStore(dayCount: 7)
        let store = HealthViewStore(
            healthManager: healthManager,
            dataManager: WorkoutDataManager()
        )
        var changeCount = 0
        let cancellable = store.objectWillChange.sink { changeCount += 1 }

        healthManager.dailySyncProgress = 0.5
        XCTAssertEqual(changeCount, 0)

        let today = Calendar.current.startOfDay(for: Date())
        healthManager.dailyHealthStore[today] = DailyHealthData(dayStart: today, steps: 10_000)
        XCTAssertEqual(changeCount, 1)

        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testBodyCompositionLoadPublishesOneAtomicSnapshot() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let entries = (0..<30).map { offset in
            DailyHealthData(
                dayStart: calendar.date(byAdding: .day, value: offset, to: start) ?? start,
                bodyMass: 80 + Double(offset) / 10
            )
        }
        let range = DateInterval(start: start, end: entries.last?.dayStart ?? start)
        let model = BodyCompositionViewModel()
        var changeCount = 0
        let cancellable = model.objectWillChange.sink { changeCount += 1 }

        model.load(
            dailyEntries: entries,
            metricKind: .weight,
            displayRange: range,
            reportGranularity: .weekly
        )

        XCTAssertEqual(changeCount, 1)
        XCTAssertFalse(model.representativeSeries.isEmpty)
        withExtendedLifetime(cancellable) {}
    }

    func testChartPointSamplerCapsMarksAndPreservesExtrema() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let points = (0..<1_000).map { index in
            let value: Double
            switch index {
            case 333: value = -500
            case 777: value = 500
            default: value = Double(index % 25)
            }
            return HealthTrendPoint(
                date: start.addingTimeInterval(Double(index) * 86_400),
                value: value,
                label: "Test"
            )
        }

        let sampled = HealthChartPointSampler.sampled(points, limit: 400)

        XCTAssertLessThanOrEqual(sampled.count, 400)
        XCTAssertEqual(sampled.first?.id, points.first?.id)
        XCTAssertEqual(sampled.last?.id, points.last?.id)
        XCTAssertTrue(sampled.contains { $0.value == -500 })
        XCTAssertTrue(sampled.contains { $0.value == 500 })
    }

    @MainActor
    func testHealthCacheBootstrapLoadsEveryStoreWithoutBlockingMainActor() async {
        let defaultsContext = makeIsolatedDefaults()
        defer { defaultsContext.defaults.removePersistentDomain(forName: defaultsContext.suiteName) }

        let workoutID = UUID()
        let workout = makeWorkoutHealthData(workoutID: workoutID, averageHeartRate: 123)
        let day = Calendar.current.startOfDay(for: Date())
        let daily = DailyHealthData(dayStart: day, steps: 9_876)
        let workoutLoadStarted = expectation(description: "workout cache load started")
        let responsivenessGate = MainActorResponsivenessGate()
        let database = TestHealthCacheDatabase(
            workoutData: [workout],
            dailyData: [daily],
            dailyCoverage: [day]
        )
        database.workoutLoadStarted = workoutLoadStarted
        database.workoutLoadGate = responsivenessGate

        // Avoid hanging the suite if a regression puts the blocking database adapter back
        // on MainActor. A healthy implementation releases the gate from the test first.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            responsivenessGate.releaseAsFallback()
        }

        let manager = HealthKitManager(
            userDefaults: defaultsContext.defaults,
            cachePersistenceCoordinator: HealthCachePersistenceCoordinator {
                database
            }
        )
        let bootstrap = manager.startPersistedCacheBootstrapIfNeeded()

        await fulfillment(of: [workoutLoadStarted], timeout: 3)
        XCTAssertTrue(
            responsivenessGate.releaseFromTest(),
            "MainActor could not run while the cache database was blocked"
        )
        await bootstrap.value

        XCTAssertEqual(manager.healthDataStore[workoutID]?.avgHeartRate, 123)
        XCTAssertEqual(manager.dailyHealthStore[day]?.steps, 9_876)
        XCTAssertEqual(manager.dailyHealthCoverage, [day])
    }

    @MainActor
    func testHealthCacheWritesPreserveInvocationOrderAndUseLatestState() async throws {
        let defaultsContext = makeIsolatedDefaults()
        defer { defaultsContext.defaults.removePersistentDomain(forName: defaultsContext.suiteName) }

        let firstSaveStarted = expectation(description: "first workout cache save started")
        let firstSaveGate = DispatchSemaphore(value: 0)
        let database = TestHealthCacheDatabase()
        database.firstWorkoutSaveStarted = firstSaveStarted
        database.firstWorkoutSaveGate = firstSaveGate

        let manager = HealthKitManager(
            userDefaults: defaultsContext.defaults,
            cachePersistenceCoordinator: HealthCachePersistenceCoordinator {
                database
            }
        )
        await manager.bootstrapPersistedDataIfNeeded()

        let workoutID = UUID()
        manager.healthDataStore[workoutID] = makeWorkoutHealthData(
            workoutID: workoutID,
            averageHeartRate: 111
        )
        let firstWrite = manager.persistData(changedWorkoutIDs: [workoutID])

        await fulfillment(of: [firstSaveStarted], timeout: 2)
        manager.healthDataStore[workoutID]?.avgHeartRate = 222
        let secondWrite = manager.persistData(changedWorkoutIDs: [workoutID])
        firstSaveGate.signal()

        try await firstWrite.value
        try await secondWrite.value

        XCTAssertEqual(database.savedWorkoutHeartRates, [111, 222])
        XCTAssertEqual(database.currentWorkoutData[workoutID]?.avgHeartRate, 222)
    }

    @MainActor
    func testBackupImportDoesNotCompleteBeforeHealthCacheIsPersisted() async throws {
        let defaultsContext = makeIsolatedDefaults()
        defer { defaultsContext.defaults.removePersistentDomain(forName: defaultsContext.suiteName) }

        let saveStarted = expectation(description: "backup health cache save started")
        let saveGate = DispatchSemaphore(value: 0)
        defer { saveGate.signal() }
        let healthDatabase = TestHealthCacheDatabase()
        healthDatabase.firstWorkoutSaveStarted = saveStarted
        healthDatabase.firstWorkoutSaveGate = saveGate
        let healthManager = HealthKitManager(
            userDefaults: defaultsContext.defaults,
            cachePersistenceCoordinator: HealthCachePersistenceCoordinator {
                healthDatabase
            }
        )

        let appDatabase = AppDatabase(inMemory: true)
        let annotations = WorkoutAnnotationsManager(database: appDatabase, loadOnInit: false)
        let gyms = GymProfilesManager(
            annotationsManager: annotations,
            database: appDatabase,
            loadOnInit: false
        )
        let logStore = WorkoutLogStore(database: appDatabase)
        let breaks = IntentionalBreaksManager(loadOnInit: false)
        let workoutID = UUID()
        let backup = BigBeautifulWorkoutBackup(
            appVersion: "test",
            appBuild: "1",
            payload: AppBackupPayload(
                workoutHealthData: [makeWorkoutHealthData(
                    workoutID: workoutID,
                    averageHeartRate: 135
                )]
            )
        )
        let completion = AsyncCompletionProbe()

        let importTask = Task { @MainActor in
            let result = try await AppBackupImporter.importBackup(
                backup,
                dataManager: WorkoutDataManager(),
                logStore: logStore,
                healthManager: healthManager,
                annotationsManager: annotations,
                gymProfilesManager: gyms,
                intentionalBreaksManager: breaks,
                userDefaults: defaultsContext.defaults,
                userDefaultsPersistentDomainName: defaultsContext.suiteName
            )
            await completion.markComplete()
            return result
        }

        await fulfillment(of: [saveStarted], timeout: 2)
        try await Task.sleep(nanoseconds: 50_000_000)
        let completedBeforePersistence = await completion.isComplete
        XCTAssertFalse(completedBeforePersistence)

        saveGate.signal()
        _ = try await importTask.value

        let completedAfterPersistence = await completion.isComplete
        XCTAssertTrue(completedAfterPersistence)
        XCTAssertEqual(healthDatabase.currentWorkoutData[workoutID]?.avgHeartRate, 135)
    }

    @MainActor
    func testBootstrapPersistsRawSamplePruningPastRetentionWindow() async throws {
        let defaultsContext = makeIsolatedDefaults()
        defer { defaultsContext.defaults.removePersistentDomain(forName: defaultsContext.suiteName) }

        let database = AppDatabase(inMemory: true)
        let workoutID = UUID()
        let oldDate = Calendar.current.date(byAdding: .day, value: -181, to: Date()) ?? .distantPast
        let oldEntry = WorkoutHealthData(
            workoutId: workoutID,
            workoutDate: oldDate,
            workoutStartTime: oldDate,
            workoutEndTime: oldDate.addingTimeInterval(3_600),
            avgHeartRate: 120,
            heartRateSamples: [HeartRateSample(timestamp: oldDate, value: 120)],
            hrvSamples: [
                HRVSample(timestamp: oldDate, value: 40),
                HRVSample(timestamp: oldDate.addingTimeInterval(60), value: 50)
            ]
        )
        try database.saveWorkoutHealthData([oldEntry])

        let manager = HealthKitManager(
            userDefaults: defaultsContext.defaults,
            cachePersistenceCoordinator: HealthCachePersistenceCoordinator {
                database
            }
        )
        await manager.bootstrapPersistedDataIfNeeded()

        let memoryEntry = try XCTUnwrap(manager.healthDataStore[workoutID])
        XCTAssertFalse(memoryEntry.hasRawSamples)
        XCTAssertEqual(memoryEntry.avgHRV, 45)

        let persistedEntry = try XCTUnwrap(database.loadWorkoutHealthData().first)
        XCTAssertFalse(persistedEntry.hasRawSamples)
        XCTAssertEqual(persistedEntry.avgHRV, 45)
    }

    @MainActor
    func testAllCacheClearDeletesDiskDataEvenBeforeBootstrapPublishesIt() async throws {
        let defaultsContext = makeIsolatedDefaults()
        defer { defaultsContext.defaults.removePersistentDomain(forName: defaultsContext.suiteName) }

        let workoutID = UUID()
        let day = Calendar.current.startOfDay(for: Date())
        let database = TestHealthCacheDatabase(
            workoutData: [makeWorkoutHealthData(workoutID: workoutID, averageHeartRate: 125)],
            dailyData: [DailyHealthData(dayStart: day, steps: 8_000)],
            dailyCoverage: [day]
        )
        let manager = HealthKitManager(
            userDefaults: defaultsContext.defaults,
            cachePersistenceCoordinator: HealthCachePersistenceCoordinator {
                database
            }
        )

        _ = manager.clearCachedHealthData()
        try await manager.waitForPendingCachePersistence()

        XCTAssertTrue(try database.loadWorkoutHealthData().isEmpty)
        XCTAssertTrue(try database.loadDailyHealthData().isEmpty)
        XCTAssertTrue(try database.loadDailyHealthCoverage().isEmpty)
        XCTAssertTrue(manager.healthDataStore.isEmpty)
        XCTAssertTrue(manager.dailyHealthStore.isEmpty)
        XCTAssertTrue(manager.dailyHealthCoverage.isEmpty)
    }

    private func makeDailyStore(dayCount: Int) -> [Date: DailyHealthData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return Dictionary(uniqueKeysWithValues: (0..<dayCount).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let value = Double(offset % 7)
            let entry = DailyHealthData(
                dayStart: date,
                steps: 8_000 + value * 100,
                activeEnergy: 500 + value,
                basalEnergy: 1_700 + value,
                exerciseMinutes: 30 + value,
                moveMinutes: 60 + value,
                standMinutes: 700 + value,
                distanceWalkingRunning: 5 + value / 10,
                flightsClimbed: 8 + value
            )
            return (date, entry)
        })
    }

    private func makeWorkoutHealthData(
        workoutID: UUID,
        averageHeartRate: Double
    ) -> WorkoutHealthData {
        let date = Date()
        return WorkoutHealthData(
            workoutId: workoutID,
            workoutDate: date,
            workoutStartTime: date,
            workoutEndTime: date.addingTimeInterval(3_600),
            avgHeartRate: averageHeartRate
        )
    }

    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "HealthPerformanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(3, forKey: "dailyHealthStoreVersion")
        return (defaults, suiteName)
    }
}

private actor AsyncCompletionProbe {
    private(set) var isComplete = false

    func markComplete() {
        isComplete = true
    }
}

nonisolated private final class TestHealthCacheDatabase: HealthCacheDatabase, @unchecked Sendable {
    private let lock = NSLock()
    private var workoutData: [UUID: WorkoutHealthData]
    private var dailyData: [Date: DailyHealthData]
    private var dailyCoverage: Set<Date>
    private var workoutSaveCount = 0
    private var workoutSaveHeartRates: [Double] = []

    var workoutLoadStarted: XCTestExpectation?
    var workoutLoadGate: MainActorResponsivenessGate?
    var firstWorkoutSaveStarted: XCTestExpectation?
    var firstWorkoutSaveGate: DispatchSemaphore?

    init(
        workoutData: [WorkoutHealthData] = [],
        dailyData: [DailyHealthData] = [],
        dailyCoverage: Set<Date> = []
    ) {
        self.workoutData = Dictionary(
            uniqueKeysWithValues: workoutData.map { ($0.workoutId, $0) }
        )
        self.dailyData = Dictionary(
            uniqueKeysWithValues: dailyData.map { ($0.dayStart, $0) }
        )
        self.dailyCoverage = dailyCoverage
    }

    var savedWorkoutHeartRates: [Double] {
        withLock { workoutSaveHeartRates }
    }

    var currentWorkoutData: [UUID: WorkoutHealthData] {
        withLock { workoutData }
    }

    func loadWorkoutHealthData() throws -> [WorkoutHealthData] {
        workoutLoadStarted?.fulfill()
        workoutLoadGate?.wait()
        return withLock {
            return Array(workoutData.values)
        }
    }

    func saveWorkoutHealthData(_ entries: [WorkoutHealthData]) throws {
        let saveNumber = withLock { () -> Int in
            workoutSaveCount += 1
            return workoutSaveCount
        }

        if saveNumber == 1, let firstWorkoutSaveStarted, let firstWorkoutSaveGate {
            firstWorkoutSaveStarted.fulfill()
            firstWorkoutSaveGate.wait()
        }

        withLock {
            for entry in entries {
                workoutData[entry.workoutId] = entry
                if let averageHeartRate = entry.avgHeartRate {
                    workoutSaveHeartRates.append(averageHeartRate)
                }
            }
        }
    }

    func deleteWorkoutHealthData(ids: [UUID]) throws {
        withLock {
            ids.forEach { workoutData.removeValue(forKey: $0) }
        }
    }

    func clearWorkoutHealthData() throws {
        withLock { workoutData.removeAll() }
    }

    func loadDailyHealthData() throws -> [DailyHealthData] {
        withLock {
            return Array(dailyData.values)
        }
    }

    func saveDailyHealthData(_ entries: [DailyHealthData]) throws {
        withLock {
            dailyData = Dictionary(uniqueKeysWithValues: entries.map { ($0.dayStart, $0) })
        }
    }

    func clearDailyHealthData() throws {
        withLock { dailyData.removeAll() }
    }

    func loadDailyHealthCoverage() throws -> Set<Date> {
        withLock {
            return dailyCoverage
        }
    }

    func saveDailyHealthCoverage(_ coveredDays: Set<Date>) throws {
        withLock { dailyCoverage = coveredDays }
    }

    func clearDailyHealthCoverage() throws {
        withLock { dailyCoverage.removeAll() }
    }

    @discardableResult
    private func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

nonisolated private final class MainActorResponsivenessGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var isReleased = false

    func wait() {
        semaphore.wait()
    }

    /// Returns false when only the background failsafe could unblock the database load.
    func releaseFromTest() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isReleased else { return false }
        isReleased = true
        semaphore.signal()
        return true
    }

    func releaseAsFallback() {
        lock.lock()
        defer { lock.unlock() }
        guard !isReleased else { return }
        isReleased = true
        semaphore.signal()
    }
}
