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

        let left = app.staticTexts["Left"].firstMatch
        scrollUntilVisible(left)
        XCTAssertTrue(left.exists)
        XCTAssertTrue(app.staticTexts["Right"].firstMatch.exists)

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
        let progress = app.buttons["body-open-progress"]
        XCTAssertTrue(progress.isHittable)
        progress.tap()
        let history = app.buttons["body-weigh-in-history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
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

    func testBodyOverviewLogsAndEditsAnEntryAndShowsProgressOnDemand() {
        app.tabBars.buttons["Body"].tap()
        let log = app.buttons["body-log-weight"]
        let latest = app.buttons["body-edit-latest-weigh-in"]
        let progress = app.buttons["body-open-progress"]

        XCTAssertTrue(latest.waitForExistence(timeout: 8))
        XCTAssertTrue(log.isHittable)
        XCTAssertEqual(log.label, "Log weight")
        XCTAssertTrue(progress.isHittable)
        XCTAssertFalse(app.staticTexts["Lean mass"].exists)
        attachScreenshot(named: "Body Overview")

        log.tap()
        let weight = app.textFields["body-weigh-in-value"]
        let save = app.buttons["body-save-weigh-in"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.tap()
        weight.typeText("181.5")
        save.tap()
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertTrue(latest.label.contains("181.5"), latest.label)

        latest.tap()
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        let oldValue = weight.value as? String ?? ""
        XCTAssertEqual(oldValue, "181.5")
        weight.tap()
        weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + "181.7")
        save.tap()
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertTrue(latest.label.contains("181.7"), latest.label)

        progress.tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("body-weight-chart").exists)
        attachScreenshot(named: "Body Progress")
    }

    func testBodyShowsATrendWhenRecentWeighInsAreSparse() {
        app.terminate()
        app.launchEnvironment["WORKOUT_APP_INITIAL_TAB"] = "body"
        app.launchEnvironment["WORKOUT_APP_SPARSE_BODY_HISTORY"] = "1"
        app.launch()

        let heading = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "body-latest-measurement", "Down about"
        )).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertTrue(heading.label.contains(" – "), heading.label)
        let chart = element("body-weight-chart")
        XCTAssertTrue(chart.exists)
        let count = (chart.value as? String)?.split(separator: " ").first.flatMap { Int($0) }
        XCTAssertGreaterThan(count ?? 0, 4)
        attachScreenshot(named: "Body Trend After a Gap")
    }

    func testBodyChangeRemembersTheSelectedStartDate() {
        app.tabBars.buttons["Body"].tap()
        let progress = app.buttons["body-open-progress"]
        let comparison = app.buttons["body-change-start-date"]
        let dateRange = app.buttons["Date range"]
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        progress.tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        scrollUntilVisible(comparison)
        XCTAssertTrue(comparison.isHittable)
        if comparison.label.hasPrefix("Since ") {
            comparison.tap()
            app.buttons["body-clear-comparison-start"].tap()
        }
        XCTAssertEqual(comparison.label, "Set start date")
        comparison.tap()
        XCTAssertTrue(element("body-comparison-date-picker").waitForExistence(timeout: 5))
        let save = app.buttons["body-save-comparison-start"]
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(comparison.waitForExistence(timeout: 5))
        let summary = comparison.label
        XCTAssertTrue(summary.hasPrefix("Since "), summary)
        XCTAssertTrue(summary.contains("lb"), summary)
        attachScreenshot(named: "Comparison Start Date")

        scrollUntilVisible(dateRange)
        XCTAssertTrue(dateRange.isHittable)
        let since = dateRange.value as? String ?? ""
        XCTAssertTrue(since.hasPrefix("Since "), since)
        let chart = element("body-weight-chart")
        let sinceChart = chart.value as? String
        XCTAssertNotNil(sinceChart)
        attachScreenshot(named: "Progress Chart Since Start")

        dateRange.tap()
        let twoWeeks = app.buttons["14 days"]
        XCTAssertTrue(twoWeeks.waitForExistence(timeout: 5))
        twoWeeks.tap()
        XCTAssertEqual(dateRange.value as? String, "14 days")
        XCTAssertNotEqual(chart.value as? String, sinceChart)

        app.terminate()
        app.launchEnvironment["WORKOUT_APP_INITIAL_TAB"] = "body"
        app.launch()
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        progress.tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        scrollUntilVisible(dateRange)
        XCTAssertEqual(dateRange.value as? String, since)
        XCTAssertEqual(chart.value as? String, sinceChart)
        scrollUntilVisible(comparison)
        XCTAssertEqual(comparison.label, summary)
        comparison.tap()
        app.buttons["body-clear-comparison-start"].tap()
        XCTAssertEqual(comparison.label, "Set start date")
    }

    func testBodyFatTrendConnectsAcrossLongGaps() {
        app.terminate()
        app.launchEnvironment["WORKOUT_APP_INITIAL_TAB"] = "body"
        app.launchArguments += ["-bodyGoalWeightLb", "200", "-bodyGoalStartWeightLb", "169", "-appearanceMode", "2"]
        app.launch()

        let progress = app.buttons["body-open-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        progress.tap()
        let range = app.buttons["Date range"]
        scrollUntilVisible(range)
        XCTAssertTrue(range.isHittable)
        range.tap()
        let allTime = app.buttons["All time"]
        XCTAssertTrue(allTime.waitForExistence(timeout: 5))
        allTime.tap()

        let goal = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "toward goal")).firstMatch
        scrollUntilVisible(goal)
        XCTAssertTrue(goal.isHittable)
        attachScreenshot(named: "Weight Goal Barbell")

        let chart = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Body fat trend chart")
        ).firstMatch
        scrollUntilVisible(chart)
        XCTAssertTrue(chart.exists)
        attachScreenshot(named: "Body Fat Trend Across Gaps")
        let detail = chart.value as? String ?? ""
        XCTAssertTrue(detail.contains("Thin lines mark gaps longer than two weeks"), detail)

        app.buttons["body-weigh-in-history"].tap()
        XCTAssertTrue(element("body-measurement-history").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Moving avg."].exists)
        XCTAssertTrue(app.staticTexts["lb/week"].exists)
        let milestone = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@", "Lowest since", "Highest since"
        )).firstMatch
        scrollUntilVisible(milestone)
        XCTAssertTrue(milestone.isHittable)
        XCTAssertTrue(milestone.label.contains("per week"))
        attachScreenshot(named: "Weigh-in Log")
    }

    func testWeightTrackingCanContinueAfterClearingAGoal() {
        app.tabBars.buttons["Body"].tap()
        let progress = app.buttons["body-open-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        progress.tap()

        let setGoal = app.buttons["body-set-weight-goal"]
        let editGoal = app.buttons["body-edit-weight-goal"]
        let trackOnly = app.buttons["body-track-without-goal"]
        let chart = element("body-weight-chart")
        XCTAssertTrue(setGoal.waitForExistence(timeout: 5))
        XCTAssertFalse(editGoal.exists)
        XCTAssertTrue(chart.exists)
        setGoal.tap()
        XCTAssertTrue(trackOnly.waitForExistence(timeout: 5))
        XCTAssertTrue(trackOnly.isHittable)
        trackOnly.tap()
        XCTAssertTrue(setGoal.waitForExistence(timeout: 5))
        XCTAssertTrue(chart.exists)

        setGoal.tap()
        let input = app.textFields["body-goal-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("200")
        let save = app.buttons["Save goal"]
        scrollUntilVisible(save, maximumSwipes: 5)
        XCTAssertTrue(save.isHittable)
        save.tap()
        scrollUntilVisible(editGoal)
        XCTAssertTrue(editGoal.isHittable)
        editGoal.tap()
        XCTAssertTrue(trackOnly.waitForExistence(timeout: 5))
        trackOnly.tap()

        XCTAssertTrue(setGoal.waitForExistence(timeout: 5))
        XCTAssertFalse(editGoal.exists)
        XCTAssertTrue(chart.exists)
        app.buttons["body-weigh-in-history"].tap()
        XCTAssertTrue(element("body-measurement-history").waitForExistence(timeout: 5))
    }

    func testBodyCanCorrectAndRestoreAnAppleHealthWeighIn() {
        app.tabBars.buttons["Body"].tap()
        let latest = app.buttons["body-edit-latest-weigh-in"]
        XCTAssertTrue(latest.waitForExistence(timeout: 8))
        let originalLabel = latest.label
        latest.tap()

        let weight = app.textFields["body-weigh-in-value"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This correction applies in your workout app."].exists)
        let oldValue = weight.value as? String ?? ""
        XCTAssertFalse(oldValue.isEmpty)
        weight.tap()
        weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + "180.6")
        app.buttons["body-save-weigh-in"].tap()
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertTrue(latest.label.contains("180.6"), latest.label)

        latest.tap()
        let restore = app.buttons["Restore Apple Health reading"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        let confirmation = app.sheets.buttons["Restore Apple Health reading"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertEqual(latest.label, originalLabel)
    }

    func testSettingsShowsTheWorkoutAppName() {
        app.tabBars.buttons["More"].tap()
        let settings = app.staticTexts["Settings"]
        scrollUntilVisible(settings)
        XCTAssertTrue(settings.isHittable)
        settings.tap()

        let name = app.staticTexts["Davis's Big Beautiful Workout App"]
        scrollUntilVisible(name)
        XCTAssertTrue(name.isHittable)
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
