import XCTest

/// End-to-end checks for the redesigned controls and the analytical export path.
/// Uses transient fixture history on a dedicated simulator, never the owner's data.
final class DesignCompletionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["WORKOUT_APP_ANALYTICS_FIXTURE"] = "1"
        app.launchEnvironment["WORKOUT_APP_INITIAL_TAB"] = "more"
    }

    func testAIExportPreviewCopyAndRememberedFormat() {
        app.launch()
        openExport()
        tap(app.buttons["export-format-csv"])
        capture("export-csv-options")
        tap(app.buttons["export-select-Fields"])
        tap(app.buttons["Deselect all"])
        tap(app.buttons["Done"])
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        tap(app.buttons["export-format-llm"])
        XCTAssertTrue(app.buttons["workoutExportSave"].isEnabled, "AI export includes all fields even after restricting another format")
        tap(app.buttons["workoutExportPreview"])
        XCTAssertTrue(app.navigationBars["AI log preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'TRAINING_LOG 1'")).firstMatch.exists)
        capture("ai-preview")
        tap(app.buttons["Done"])
        tap(app.buttons["workoutExportCopy"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Copied.'")).firstMatch.waitForExistence(timeout: 10))
        capture("ai-export-copied")
        tap(app.buttons["workoutExportSave"])
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10))
        capture("ai-export-share")
        app.buttons["header.closeButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH '.txt'")).firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        openExport()
        scrollTo(app.buttons["export-format-llm"])
        XCTAssertTrue(app.buttons["export-format-llm"].isSelected)
    }

    func testLargeTextDarkExportAndHome() {
        app.launchArguments += ["-appearanceMode", "2", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["WORKOUT_APP_INITIAL_TAB"] = "today"
        app.launch()
        tap(app.buttons["today-start-workout"])
        if app.buttons["quick-start-confirm"].waitForExistence(timeout: 3) { tap(app.buttons["quick-start-confirm"]) }
        tap(app.buttons["Minimize session"])
        app.tabBars.buttons["More"].tap()
        let resume = app.buttons["active-session-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(resume.frame.maxY, app.tabBars.firstMatch.frame.minY)
        capture("active-session-large-dark")
        openExport()
        tap(app.buttons["export-format-llm"])
        capture("ai-export-large-dark")
        XCTAssertTrue(app.buttons["workoutExportCopy"].waitForExistence(timeout: 8))
        let hittable = NSPredicate(format: "hittable == true")
        expectation(for: hittable, evaluatedWith: app.buttons["workoutExportSave"])
        expectation(for: hittable, evaluatedWith: app.buttons["workoutExportCopy"])
        waitForExpectations(timeout: 8)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["today-start-workout"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["today-start-workout"].label.hasPrefix("Resume"))
        capture("today-large-dark")
        tap(app.buttons["today-start-workout"])
        tap(app.buttons["Workout actions"])
        tap(app.buttons["Discard workout"])
        app.alerts.buttons["Discard"].tap()
    }

    func testDeepExerciseScrollingRemainsResponsive() {
        app.launchEnvironment["WORKOUT_APP_INITIAL_TAB"] = "today"
        app.launchArguments += ["-appearanceMode", "2"]
        app.launch()
        tap(app.buttons["explore-exercises"])
        tap(app.buttons["exercise-row-Bench Press"])
        for _ in 0..<12 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 900, thenHoldForDuration: 0.15)
        }
        capture("exercise-deep-scroll")
        XCTAssertTrue(app.staticTexts["Recent sessions"].exists)
        let more = app.buttons["Show more sessions"]
        if more.exists && more.isHittable { more.tap() }
        let back = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
        back.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "exercise-list").firstMatch.waitForExistence(timeout: 5))
    }

    func testSleepSourceRemainsResponsiveAfterUnavailableHealthQuery() {
        app.launch()
        tap(prefix("Settings"))
        tap(prefix("Sleep source"))
        XCTAssertTrue(app.buttons["Auto"].waitForExistence(timeout: 8))
        // The unavailable-source query changes authorization while the parent settings
        // is offscreen. Navigating back must still work after that layout update.
        Thread.sleep(forTimeInterval: 2)
        let back = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("settings-after-sleep-source")
    }

    func testLogSetAndFinishWorkout() {
        app.launchEnvironment["WORKOUT_APP_INITIAL_TAB"] = "today"
        app.launch()
        XCTAssertTrue(app.buttons["today-start-workout"].waitForExistence(timeout: 10))
        if app.buttons["today-start-workout"].label.hasPrefix("Resume") {
            tap(app.buttons["today-start-workout"])
            tap(app.buttons["Workout actions"])
            tap(app.buttons["Discard workout"])
            app.alerts.buttons["Discard"].tap()
            XCTAssertTrue(app.buttons["today-start-workout"].waitForExistence(timeout: 5))
        }
        capture("today-final")
        tap(app.buttons["today-start-workout"])
        tap(app.buttons["quick-start-confirm"])
        let picker = app.navigationBars["Add exercises"]
        if !picker.waitForExistence(timeout: 5) { tap(app.buttons["session-add-exercise"]) }
        capture("exercise-picker-open")
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        tap(app.buttons["exercise-picker-Bench Press"])
        tap(app.buttons["exercise-picker-done"])
        tap(app.buttons["Log set 1"])
        XCTAssertTrue(app.buttons["Set 1 logged"].waitForExistence(timeout: 5))
        capture("session-logged-set")
        tap(app.buttons["Finish and review workout"])
        let unchecked = app.alerts["Leave unchecked sets out?"]
        if unchecked.waitForExistence(timeout: 2) { unchecked.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save 1 completed")).firstMatch.tap() }
        tap(app.buttons["Finish and save"])
        XCTAssertTrue(app.staticTexts["Workout saved"].waitForExistence(timeout: 10))
        capture("session-saved")
        tap(app.buttons["Done"])
    }

    private func openExport() {
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 10))
        tap(app.buttons["profile-export"])
    }

    private func prefix(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        scrollTo(element)
        if !(element.exists && element.isHittable && element.isEnabled) {
            capture("unavailable-control")
            print(app.debugDescription)
        }
        XCTAssertTrue(element.exists && element.isHittable && element.isEnabled, "Control unavailable: \(element)", file: file, line: line)
        element.tap()
    }

    private func scrollTo(_ element: XCUIElement) {
        // XCTest can report controls behind a safe-area action bar as hittable.
        // Bring export content fully above that bar before tapping its center.
        for _ in 0..<14 {
            let exists = element.exists
            let id = exists ? element.identifier : ""
            let needsClearance = id.hasPrefix("export-format-") || id.hasPrefix("export-select-") || id == "workoutExportPreview"
            let frame = exists ? element.frame : .zero
            let action = app.buttons["workoutExportSave"]
            let bottom = action.exists ? action.frame.minY - 12 : 700
            if exists && element.isHittable && (!needsClearance || (frame.minY >= 125 && frame.maxY <= bottom)) { return }
            let down = exists && frame.midY < 300
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.32 : 0.68))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.58 : 0.32))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SCREEN_TOUR_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: url.appendingPathComponent(name + ".png"))
        }
    }
}
