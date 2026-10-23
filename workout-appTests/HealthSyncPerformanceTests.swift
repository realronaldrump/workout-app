import Foundation
import XCTest
@testable import workout_app

final class HealthSyncPerformanceTests: XCTestCase {
    @MainActor
    func testDailyRangeRequestWaitsForRunningSyncInsteadOfDroppingTheRequest() async throws {
        let suiteName = "HealthSyncPerformanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = HealthKitManager(userDefaults: defaults)
        manager.authorizationStatus = .authorized
        let day = Calendar.current.startOfDay(for: Date())
        let range = DateInterval(start: day, duration: 3_600)
        let gate = DailySyncTestGate()
        manager.isDailySyncing = true
        manager.dailyHealthSyncRange = range
        manager.dailyHealthSyncTask = Task { @MainActor in
            await gate.wait()
            manager.dailyHealthSyncTask = nil
            manager.dailyHealthSyncRange = nil
            manager.isDailySyncing = false
            // Today's totals never enter permanent coverage, even after a successful load.
        }

        let requestStarted = expectation(description: "Coverage request started")
        var didFinishRequest = false
        let request = Task { @MainActor in
            // Init may have queued a real authorization-status refresh; this test exercises
            // only orchestration, so establish the fixture status at the request boundary.
            manager.authorizationStatus = .authorized
            requestStarted.fulfill()
            await manager.ensureDailyHealthData(range: range)
            didFinishRequest = true
        }
        await fulfillment(of: [requestStarted], timeout: 2)
        XCTAssertFalse(didFinishRequest)

        await gate.open()
        await request.value
        XCTAssertTrue(didFinishRequest)
        XCTAssertTrue(manager.dailyHealthCoverage.isEmpty)
    }

    @MainActor
    func testWorkoutBatchLoadsDayMetricsOncePerDistinctDayIncludingEmptyDays() async throws {
        let cache = WorkoutDayHealthMetricsCache()
        let firstDay = Date(timeIntervalSinceReferenceDate: 0)
        let secondDay = firstDay.addingTimeInterval(86_400)
        let workoutDays = [firstDay, firstDay, secondDay, firstDay, secondDay, secondDay]
        var loadedDays: [Date] = []

        for day in workoutDays {
            let result = try await cache.value(for: day) {
                loadedDays.append(day)
                return WorkoutDayHealthMetrics(dailySteps: day == firstDay ? 8_000 : nil)
            }
            XCTAssertEqual(result.dailySteps, day == firstDay ? 8_000 : nil)
        }

        // The same 22 day-scoped queries now run twice rather than six times.
        XCTAssertEqual(loadedDays, [firstDay, secondDay])
    }

    @MainActor
    func testFailedDayLoadIsRetriedByTheNextWorkout() async throws {
        let cache = WorkoutDayHealthMetricsCache()
        let day = Date(timeIntervalSinceReferenceDate: 0)
        var attempts = 0

        do {
            _ = try await cache.value(for: day) {
                attempts += 1
                throw HealthKitError.queryFailed("Temporary failure")
            }
            XCTFail("The failed HealthKit query must propagate")
        } catch {
            XCTAssertEqual(attempts, 1)
        }

        let retried = try await cache.value(for: day) {
            attempts += 1
            return WorkoutDayHealthMetrics(dailySteps: 9_000)
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(retried.dailySteps, 9_000)
    }

    @MainActor
    func testNewSyncBatchReadsUpdatedHealthData() async throws {
        let day = Date(timeIntervalSinceReferenceDate: 0)
        var currentSteps = 4_000
        let firstBatch = WorkoutDayHealthMetricsCache()
        let initial = try await firstBatch.value(for: day) {
            WorkoutDayHealthMetrics(dailySteps: currentSteps)
        }

        currentSteps = 7_000
        let secondBatch = WorkoutDayHealthMetricsCache()
        let refreshed = try await secondBatch.value(for: day) {
            WorkoutDayHealthMetrics(dailySteps: currentSteps)
        }

        XCTAssertEqual(initial.dailySteps, 4_000)
        XCTAssertEqual(refreshed.dailySteps, 7_000)
    }

    func testSharedDayMetricsPreserveEachWorkoutsSamplesAndSleepWindow() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let sleep = SleepSummary(
            totalSleep: 25_200,
            inBed: 28_800,
            stageDurations: [.core: 25_200],
            start: start.addingTimeInterval(-28_800),
            end: start
        )
        let oxygen = BloodOxygenSample(timestamp: start, value: 98)
        var workout = WorkoutHealthData(
            workoutId: UUID(),
            workoutDate: start,
            workoutStartTime: start,
            workoutEndTime: start.addingTimeInterval(3_600),
            avgHeartRate: 135,
            activeCalories: 420,
            bloodOxygenSamples: [oxygen],
            bodyMass: 85,
            sleepSummary: sleep
        )

        WorkoutDayHealthMetrics(bodyMass: 80, dailySteps: 9_000).apply(to: &workout)

        XCTAssertEqual(workout.bodyMass, 80)
        XCTAssertEqual(workout.dailySteps, 9_000)
        XCTAssertEqual(workout.avgHeartRate, 135)
        XCTAssertEqual(workout.activeCalories, 420)
        XCTAssertEqual(workout.bloodOxygenSamples.map(\.id), [oxygen.id])
        XCTAssertEqual(workout.sleepSummary?.start, sleep.start)
        XCTAssertEqual(workout.sleepSummary?.end, sleep.end)
        XCTAssertEqual(workout.sleepSummary?.totalSleep, sleep.totalSleep)
    }
}

private actor DailySyncTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
