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
}
