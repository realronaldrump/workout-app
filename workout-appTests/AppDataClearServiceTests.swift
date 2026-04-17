import XCTest
@testable import workout_app

final class AppDataClearServiceTests: XCTestCase {
    func testWorkoutHistoryClearsDependentWorkoutState() {
        let plan = AppDataClearPlan(requestedCategories: [.workoutHistory])

        XCTAssertTrue(plan.effectiveCategories.contains(.workoutHistory))
        XCTAssertTrue(plan.effectiveCategories.contains(.gymAssignments))
        XCTAssertTrue(plan.effectiveCategories.contains(.activeSessionDraft))
        XCTAssertFalse(plan.effectiveCategories.contains(.gymProfiles))
        XCTAssertFalse(plan.effectiveCategories.contains(.healthData))
    }

    func testGymProfilesClearAssignmentsWithoutClearingWorkouts() {
        let plan = AppDataClearPlan(requestedCategories: [.gymProfiles])

        XCTAssertTrue(plan.effectiveCategories.contains(.gymProfiles))
        XCTAssertTrue(plan.effectiveCategories.contains(.gymAssignments))
        XCTAssertFalse(plan.effectiveCategories.contains(.workoutHistory))
    }

    func testIndependentCategoriesStayIndependent() {
        let plan = AppDataClearPlan(requestedCategories: [.intentionalBreaks, .exerciseCustomization])

        XCTAssertEqual(plan.effectiveCategories, [.intentionalBreaks, .exerciseCustomization])
        XCTAssertTrue(plan.impliedCategories.isEmpty)
    }
}
