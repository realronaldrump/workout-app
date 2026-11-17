import XCTest

/// Walks the app's screens and saves a screenshot of each one for design review.
///
/// Skipped unless `SCREEN_TOUR_DIR` names a folder to write into, so ordinary test runs
/// ignore it. Run it with:
///
///     TEST_RUNNER_SCREEN_TOUR_DIR=/some/folder xcodebuild test \
///       -only-testing:workout-appUITests/ScreenTourUITests ...
///
/// Every step is best-effort: a screen that cannot be reached is logged and skipped
/// rather than failing the run, because the tour is a camera, not an assertion.
final class ScreenTourUITests: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: URL!
    private var prefix = ""
    private var counter = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        guard let path = ProcessInfo.processInfo.environment["SCREEN_TOUR_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_SCREEN_TOUR_DIR to capture the screen tour.")
        }
        outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        app = XCUIApplication()
        if ProcessInfo.processInfo.environment["SCREEN_TOUR_DARK"] == "1" {
            app.launchArguments += ["-appearanceMode", "2"]
        }
    }

    // MARK: - Tours

    /// Today and the training screens, using whatever history is on the device.
    func testTourTraining() {
        launch(prefix: "a", fixture: true, tab: "today")
        captureScrolling("today", pages: 4)

        if open(identifier: "explore-performance") {
            captureScrolling("performance", pages: 5)
            if tapLabel("Workouts", in: app.buttons) {
                captureScrolling("change-metric", pages: 4)
                goBack()
            }
            goBack()
        }

        if open(identifier: "explore-exercises") {
            capture("exercises")
            if tapLabel("Bench Press") {
                captureScrolling("exercise-detail", pages: 7)
                goBack()
            }
            goBack()
        }

        if open(identifier: "explore-consistency") {
            captureScrolling("consistency", pages: 5)
            goBack()
        }
        if tapLabel("Muscles") {
            captureScrolling("muscles", pages: 3)
            goBack()
        }
        if open(identifier: "explore-signals") {
            captureScrolling("recovery", pages: 4)
            goBack()
        }
        if tapLabel("Variants") {
            captureScrolling("variants", pages: 2)
            goBack()
        }
    }

    /// History, a workout, and its session breakdown.
    func testTourHistory() {
        launch(prefix: "b", fixture: true, tab: "history")
        captureScrolling("history", pages: 2)

        scrollToTop()
        guard tapLabel("Analytics Upper") else { return }
        settle(1.2)
        guard app.descendants(matching: .any).matching(identifier: "workout-detail").firstMatch.exists else { return }
        captureScrolling("workout-detail", pages: 4)
        scrollToTop()
        if open(identifier: "workout-session-breakdown") {
            captureScrolling("session-insights", pages: 5)
            goBack()
        }
        goBack()
    }

    /// More, Settings, and every screen behind Settings.
    func testTourSettings() {
        launch(prefix: "c", fixture: true, tab: "more")
        captureScrolling("more", pages: 2)

        if tapLabel("Feature guides") {
            captureScrolling("guides", pages: 2)
            if tapLabel("Today tab") {
                captureScrolling("guide-detail", pages: 3)
                goBack()
            }
            goBack()
        }
        if tapLabel("What's new") {
            captureScrolling("whats-new", pages: 2)
            goBack()
        }

        guard tapLabel("Settings") else { return }
        captureScrolling("settings", pages: 3)

        for (label, name, pages) in [
            ("Planned breaks", "breaks", 3),
            ("Gyms", "gyms", 2),
            ("Muscle roles", "muscle-roles", 2),
            ("Permissions", "health-permissions", 2),
            ("Health data", "health-data", 3),
            ("Sleep source", "sleep-source", 2),
            ("Backups", "backups", 2)
        ] {
            scrollToTop()
            if tapLabel(label) {
                captureScrolling(name, pages: pages)
                if name == "muscle-roles" {
                    let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Ab Wheel'")).firstMatch
                    if first.exists, first.isHittable {
                        first.tap()
                        settle()
                        captureScrolling("tag-editor", pages: 2)
                        goBack()
                    }
                }
                goBack()
            }
        }

        scrollToTop()
        if tapLabel("Export") {
            captureScrolling("export-workouts", pages: 4)
            scrollToTop()
            if open(identifier: "export-format-llm") {
                captureScrolling("export-ai", pages: 2)
                if open(identifier: "workoutExportPreview") {
                    capture("export-ai-preview")
                    dismissSheet()
                }
            }
            scrollToTop()
            if tapLabel("Apple Health", in: app.buttons) {
                captureScrolling("export-health", pages: 3)
            }
            scrollToTop()
            if tapLabel("Backup", in: app.buttons) {
                captureScrolling("export-backup", pages: 2)
            }
            goBack()
        }

        scrollToTop()
        if tapLabel("Import") {
            capture("import-wizard")
            dismissSheet()
        }
        if tapLabel("Clear app data") {
            captureScrolling("clear-data", pages: 2)
            dismissSheet()
        }
    }

    /// Body and Health need Apple Health data, so this tour uses the debug fixture.
    func testTourHealthAndBody() {
        launch(prefix: "d", fixture: true, tab: "body")
        captureScrolling("body", pages: 5)

        app.tabBars.buttons["Health"].tap()
        settle()
        captureScrolling("health", pages: 4)
        scrollToTop()
        if open(identifier: "health-summary-steps") {
            captureScrolling("health-metric", pages: 4)
            goBack()
        }

        app.tabBars.buttons["Today"].tap()
        settle()
        captureScrolling("today-fixture", pages: 2)
    }

    /// The live session: start, add an exercise, then discard so nothing is saved.
    func testTourSession() {
        launch(prefix: "e", fixture: true, tab: "today")
        guard open(identifier: "today-start-workout") else { return }
        captureScrolling("quick-start", pages: 2)
        guard open(identifier: "quick-start-confirm") else {
            dismissSheet()
            return
        }
        settle(1.5)
        capture("session-empty")

        if app.navigationBars["Add exercises"].exists || open(identifier: "session-add-exercise") {
            settle(1.0)
            capture("exercise-picker")
            if open(identifier: "exercise-picker-Bench Press") {
                capture("exercise-picker-selected")
                _ = open(identifier: "exercise-picker-done")
                settle(1.2)
                captureScrolling("session-active", pages: 2)
            } else {
                dismissSheet()
            }
        }

        if tapLabel("Finish and review workout", in: app.buttons) {
            captureScrolling("finish-sheet", pages: 2)
            dismissSheet()
        }

        let actions = app.buttons["Workout actions"]
        if actions.exists, actions.isHittable {
            actions.tap()
            settle(0.6)
            capture("session-menu")
            if tapLabel("Discard workout", in: app.buttons) {
                settle(0.6)
                let discard = app.alerts.buttons["Discard"]
                if discard.waitForExistence(timeout: 3) { discard.tap() }
            }
        }
    }

    // MARK: - Driving

    private func launch(prefix: String, fixture: Bool, tab: String) {
        self.prefix = prefix
        counter = 0
        if fixture {
            app.launchEnvironment["WORKOUT_APP_ANALYTICS_FIXTURE"] = "1"
        }
        app.launchEnvironment["WORKOUT_APP_INITIAL_TAB"] = tab
        app.launch()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 15)
        settle(1.0)
    }

    private func settle(_ seconds: TimeInterval = 0.25) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func capture(_ name: String) {
        counter += 1
        let fileName = String(format: "%@%02d-%@.png", prefix, counter, name)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        do {
            try data.write(to: outputDirectory.appendingPathComponent(fileName))
        } catch {
            print("ScreenTour: could not write \(fileName): \(error)")
        }
    }

    /// Captures the screen, then pages down and captures again, stopping early once
    /// the content no longer moves.
    private func captureScrolling(_ name: String, pages: Int) {
        var previous = XCUIScreen.main.screenshot().pngRepresentation
        capture("\(name)-1")
        guard pages > 1 else { return }
        for page in 2...pages {
            pageDown()
            let current = XCUIScreen.main.screenshot().pngRepresentation
            if current == previous { break }
            previous = current
            capture("\(name)-\(page)")
        }
    }

    private func pageDown() {
        drag(fromY: 0.74, toY: 0.24)
    }

    private func scrollToTop() {
        for _ in 0..<3 {
            drag(fromY: 0.3, toY: 0.9, velocity: 2_400)
        }
        settle(0.5)
    }

    private func drag(fromY: CGFloat, toY: CGFloat, velocity: XCUIGestureVelocity = 900) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: 0.15)
        settle(0.5)
    }

    @discardableResult
    private func open(identifier: String) -> Bool {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        return scrollToAndTap(element, name: identifier)
    }

    /// Taps the first element whose label starts with `label`, scrolling to reach it.
    @discardableResult
    private func tapLabel(_ label: String, in query: XCUIElementQuery? = nil) -> Bool {
        let predicate = NSPredicate(format: "label BEGINSWITH[c] %@", label)
        let scope = query ?? app.descendants(matching: .any)
        let buttons = (query ?? app.buttons).matching(predicate).firstMatch
        if buttons.exists {
            return scrollToAndTap(buttons, name: label)
        }
        return scrollToAndTap(scope.matching(predicate).firstMatch, name: label)
    }

    private func scrollToAndTap(_ element: XCUIElement, name: String) -> Bool {
        _ = element.waitForExistence(timeout: 3)
        var attempts = 0
        while attempts < 4 && !(element.exists && element.isHittable) {
            drag(fromY: 0.7, toY: 0.4)
            attempts += 1
        }
        guard element.exists, element.isHittable else {
            print("ScreenTour: could not reach \(name)")
            return false
        }
        element.tap()
        settle(1.1)
        return true
    }

    private func goBack() {
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'")
        ).firstMatch
        if back.exists, back.isHittable {
            back.tap()
        } else {
            let first = app.navigationBars.buttons.firstMatch
            if first.exists, first.isHittable {
                first.tap()
            } else {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        settle(1.0)
    }

    private func dismissSheet() {
        for label in ["Close", "Cancel", "Done"] {
            let button = app.buttons[label]
            if button.exists, button.isHittable {
                button.tap()
                settle(0.9)
                return
            }
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: end)
        settle(0.9)
    }
}
