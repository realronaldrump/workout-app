import HealthKit
import XCTest
@testable import workout_app

final class HealthKitManagerAuthorizationTests: XCTestCase {
    func testNormalizedAuthorizationReadTypesAddsWorkoutParentForWorkoutRoute() {
        let readTypes = HealthKitManager.normalizedAuthorizationReadTypes(
            for: [HKSeriesType.workoutRoute()]
        )

        XCTAssertTrue(readTypes.contains(where: { $0.identifier == HKSeriesType.workoutRoute().identifier }))
        XCTAssertTrue(readTypes.contains(where: { $0.identifier == HKObjectType.workoutType().identifier }))
    }

    func testNormalizedAuthorizationReadTypesLeavesUnrelatedTypesAlone() throws {
        let heartRateType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .heartRate))
        let readTypes = HealthKitManager.normalizedAuthorizationReadTypes(for: [heartRateType])

        XCTAssertEqual(readTypes.count, 1)
        XCTAssertTrue(readTypes.contains(where: { $0.identifier == heartRateType.identifier }))
    }
}
