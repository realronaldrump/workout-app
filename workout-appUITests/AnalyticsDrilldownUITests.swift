import XCTest

final class AnalyticsDrilldownUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["WORKOUT_APP_ANALYTICS_FIXTURE"] = "1"
        app.launchEnvironment["WORKOUT_APP_INITIAL_TAB"] = "today"
        app.launch()
    }

    func testStrengthPersonalRecordOpensRecordHistoryAndSourceBackedAnalysis() {
        let exploreExercises = element("explore-exercises")
        scrollUntilVisible(exploreExercises)
        XCTAssertTrue(exploreExercises.exists)
        exploreExercises.tap()

        XCTAssertTrue(element("exercise-list").waitForExistence(timeout: 8))
        let benchPress = element("exercise-row-Bench Press")
        XCTAssertTrue(benchPress.waitForExistence(timeout: 8))
        benchPress.tap()

        let record = app.buttons["personal-record-maxLoad"]
        scrollUntilVisible(record)
        XCTAssertTrue(record.exists)
        record.tap()

        XCTAssertTrue(
            element("exercise-metric-detail-maxLoad")
                .waitForExistence(timeout: 8)
        )
        attachScreenshot(named: "Strength Record Analysis Hero")
        let recordHistory = app.staticTexts["Record history"]
        scrollUntilVisible(recordHistory)
        XCTAssertTrue(recordHistory.exists)
        let topAttempts = app.staticTexts["Top attempts"]
        scrollUntilVisible(topAttempts)
        XCTAssertTrue(topAttempts.exists)
        attachScreenshot(named: "Strength Record Analysis")

        let sourceAttempt = app.buttons["top-attempt-source"].firstMatch
        scrollUntilVisible(sourceAttempt)
        XCTAssertTrue(sourceAttempt.exists)
        sourceAttempt.tap()
        XCTAssertTrue(element("workout-detail").waitForExistence(timeout: 8))
    }

    func testHealthSummaryOpensCanonicalMetricDetail() {
        let healthTab = app.tabBars.buttons["Health"]
        XCTAssertTrue(healthTab.waitForExistence(timeout: 8))
        healthTab.tap()

        let steps = app.buttons["health-summary-steps"]
        scrollUntilVisible(steps)
        XCTAssertTrue(steps.exists)
        steps.tap()

        XCTAssertTrue(
            element("health-metric-detail-steps")
                .waitForExistence(timeout: 8)
        )
        attachScreenshot(named: "Health Metric Analysis")

        let best = app.buttons["health-footer-best"]
        scrollUntilVisible(best)
        XCTAssertTrue(best.exists)
        best.tap()

        let sourceDay = app.buttons["health-selected-day-source"]
        scrollUntilVisible(sourceDay)
        XCTAssertTrue(sourceDay.exists)
        sourceDay.tap()
        XCTAssertTrue(element("health-day-detail").waitForExistence(timeout: 8))
    }

    func testAssistedExerciseUsesCanonicalRecordAnalysis() {
        openExercise(named: "Assisted Pull Up")

        let record = app.buttons["personal-record-maxLoad"]
        scrollUntilVisible(record)
        XCTAssertTrue(record.exists)
        record.tap()

        XCTAssertTrue(element("exercise-metric-detail-maxLoad").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Least assistance"].waitForExistence(timeout: 5))
    }

    func testCardioExerciseUsesHonestDistanceAnalysis() {
        openExercise(named: "Running (Treadmill)")

        let record = app.buttons["personal-record-distance"]
        scrollUntilVisible(record)
        XCTAssertTrue(record.exists)
        record.tap()

        XCTAssertTrue(element("exercise-metric-detail-distance").waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Pace"].exists)
    }

    func testParentExerciseKeepsLeftAndRightPerformanceTracksSeparate() {
        openExercise(named: "Single Arm Row")

        let left = app.staticTexts["Left"]
        scrollUntilVisible(left)
        XCTAssertTrue(left.exists)
        XCTAssertTrue(app.staticTexts["Right"].exists)

        let record = app.buttons["personal-record-maxLoad"].firstMatch
        scrollUntilVisible(record)
        XCTAssertTrue(record.exists)
        record.tap()
        XCTAssertTrue(element("exercise-metric-detail-maxLoad").waitForExistence(timeout: 8))
        let exactTrack = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Single Arm Row -")
        ).firstMatch
        XCTAssertTrue(exactTrack.waitForExistence(timeout: 5))
    }

    func testHomeTotalSetsOpensItsAnalysis() {
        let totalSets = app.buttons["home-summary-totalSets"].firstMatch
        scrollUntilVisible(totalSets)
        XCTAssertTrue(totalSets.exists)
        totalSets.tap()

        XCTAssertTrue(element("workout-metric-detail-totalSets").waitForExistence(timeout: 8))
    }

    func testPerformanceGlanceAndHistorySummaryOpenCanonicalAnalysis() {
        let performance = element("explore-performance")
        scrollUntilVisible(performance)
        XCTAssertTrue(performance.exists)
        performance.tap()
        XCTAssertTrue(element("performance-lab").waitForExistence(timeout: 8))

        let streak = app.buttons["performance-glance-streak"]
        scrollUntilVisible(streak)
        XCTAssertTrue(streak.exists)
        streak.tap()
        XCTAssertTrue(element("workout-metric-detail-streak").waitForExistence(timeout: 8))

        app.tabBars.buttons["History"].tap()
        let averageDuration = app.buttons["history-summary-averageDuration"]
        scrollUntilVisible(averageDuration)
        XCTAssertTrue(averageDuration.exists)
        averageDuration.tap()
        XCTAssertTrue(element("workout-metric-detail-averageDuration").waitForExistence(timeout: 8))
    }

    func testPerformanceAveragePerWeekOpensWeeklyFrequencyAnalysis() {
        let performance = element("explore-performance")
        scrollUntilVisible(performance)
        XCTAssertTrue(performance.exists)
        performance.tap()
        XCTAssertTrue(element("performance-lab").waitForExistence(timeout: 8))

        let averagePerWeek = app.buttons["performance-glance-averageFrequency"]
        scrollUntilVisible(averagePerWeek)
        XCTAssertTrue(averagePerWeek.exists)
        averagePerWeek.tap()

        XCTAssertTrue(
            element("workout-metric-detail-averageFrequency")
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["Weekly frequency"].waitForExistence(timeout: 5))
    }

    func testBodyCompositionAndRecoverySignalsFocusTheirEvidence() {
        let healthTab = app.tabBars.buttons["Health"]
        XCTAssertTrue(healthTab.waitForExistence(timeout: 8))
        healthTab.tap()

        let bodyCategory = element("health-category-body")
        scrollUntilVisible(bodyCategory)
        XCTAssertTrue(bodyCategory.exists)
        bodyCategory.tap()
        XCTAssertTrue(element("body-composition").waitForExistence(timeout: 8))

        XCTAssertTrue(element("body-latest-measurement").exists)
        XCTAssertTrue(element("body-weight-chart").exists)
        XCTAssertFalse(app.staticTexts["Chart options"].exists)
        let history = app.buttons["body-all-readings"]
        scrollUntilVisible(history)
        history.tap()
        XCTAssertTrue(element("body-measurement-history").waitForExistence(timeout: 5))
        attachScreenshot(named: "Weight History")
        app.buttons["Done"].tap()

        app.tabBars.buttons["Today"].tap()
        let signals = element("explore-signals")
        scrollUntilVisible(signals)
        XCTAssertTrue(signals.exists)
        signals.tap()
        XCTAssertTrue(element("recovery-coverage-detail").waitForExistence(timeout: 8))

        let heartRateVariability = app.buttons["recovery-signal-heartRateVariability"]
        scrollUntilVisible(heartRateVariability)
        XCTAssertTrue(heartRateVariability.exists)
        heartRateVariability.tap()
        XCTAssertTrue(element("health-metric-detail-heartRateVariability").waitForExistence(timeout: 8))
    }

    func testConsistencyExplanationIsAvailableOnlyOnRequest() {
        let consistency = app.buttons["explore-consistency"]
        scrollUntilVisible(consistency)
        consistency.tap()
        XCTAssertTrue(element("consistency-summary").waitForExistence(timeout: 5))

        let explanation = "Saved break days lower weekly goals. Workouts during a break still count. "
            + "Streaks allow the rest days set in Settings."
        XCTAssertFalse(app.staticTexts[explanation].exists)
        app.buttons["app-help-Consistency"].tap()
        XCTAssertTrue(app.staticTexts[explanation].waitForExistence(timeout: 5))
        app.buttons["app-help-close"].tap()
        XCTAssertFalse(app.staticTexts[explanation].exists)
    }

    private func openExercise(named name: String) {
        let exploreExercises = element("explore-exercises")
        scrollUntilVisible(exploreExercises)
        XCTAssertTrue(exploreExercises.exists)
        exploreExercises.tap()

        XCTAssertTrue(element("exercise-list").waitForExistence(timeout: 8))
        let exercise = element("exercise-row-\(name)")
        XCTAssertTrue(exercise.waitForExistence(timeout: 8))
        exercise.tap()
        XCTAssertTrue(element("exercise-detail-\(name)").waitForExistence(timeout: 8))
    }

    private func scrollUntilVisible(
        _ element: XCUIElement,
        maximumSwipes: Int = 30
    ) {
        for _ in 0..<maximumSwipes {
            if element.exists, element.isHittable { return }

            if element.exists {
                let viewport = app.windows.firstMatch.frame
                if element.frame.midY < viewport.midY {
                    app.swipeDown()
                } else {
                    app.swipeUp()
                }
            } else {
                app.swipeUp()
            }
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
