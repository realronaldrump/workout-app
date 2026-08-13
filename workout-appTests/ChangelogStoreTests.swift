import XCTest
@testable import workout_app

@MainActor
final class ChangelogStoreTests: XCTestCase {
    private let suiteName = "ChangelogStoreTests.\(UUID().uuidString)"
    private lazy var defaults = UserDefaults(suiteName: suiteName)!

    private func cleanUpDefaults() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFirstAdoptionShowsOnlyCurrentVersion() throws {
        defer { cleanUpDefaults() }
        let store = ChangelogStore(defaults: defaults, currentVersion: "1.9.2")

        let presentation = try XCTUnwrap(store.pendingPresentation())

        XCTAssertEqual(presentation.entries.map(\.version), ["1.9.2"])
    }

    func testCurrentVersionDoesNotRepeatAfterDismissal() {
        defer { cleanUpDefaults() }
        let store = ChangelogStore(defaults: defaults, currentVersion: "1.9.2")

        store.markSeen(version: "1.9.2")

        XCTAssertNil(store.pendingPresentation())
        XCTAssertEqual(defaults.string(forKey: ChangelogStore.lastSeenVersionKey), "1.9.2")
    }

    func testNewInstallCanSilentlyAdoptCurrentVersion() {
        defer { cleanUpDefaults() }
        let store = ChangelogStore(defaults: defaults, currentVersion: "1.9.2")

        store.markCurrentVersionSeen()

        XCTAssertNil(store.pendingPresentation())
        XCTAssertEqual(store.lastSeenVersion, "1.9.2")
    }

    func testMultipleMissedVersionsArePresentedNewestFirst() throws {
        defer { cleanUpDefaults() }
        defaults.set("1.7.2", forKey: ChangelogStore.lastSeenVersionKey)
        let store = ChangelogStore(defaults: defaults, currentVersion: "1.9.2")

        let presentation = try XCTUnwrap(store.pendingPresentation())

        XCTAssertEqual(presentation.entries.map(\.version), ["1.9.2", "1.9.1", "1.9", "1.8.2", "1.8"])
    }

    func testStoreReloadsSeenVersionWrittenByAnotherInstance() {
        defer { cleanUpDefaults() }
        let firstStore = ChangelogStore(defaults: defaults, currentVersion: "1.9.2")
        let secondStore = ChangelogStore(defaults: defaults, currentVersion: "1.9.2")

        secondStore.markCurrentVersionSeen()

        XCTAssertNil(firstStore.pendingPresentation())
        XCTAssertEqual(firstStore.lastSeenVersion, "1.9.2")
    }

    func testDowngradeDoesNotShowAnOlderChangelog() {
        defer { cleanUpDefaults() }
        defaults.set("1.9.2", forKey: ChangelogStore.lastSeenVersionKey)
        let store = ChangelogStore(defaults: defaults, currentVersion: "1.9.1")

        XCTAssertNil(store.pendingPresentation())
    }

    func testMissingCatalogEntryDoesNotShowTheWrongRelease() {
        defer { cleanUpDefaults() }
        let store = ChangelogStore(defaults: defaults, currentVersion: "1.9.3")

        XCTAssertNil(store.pendingPresentation())
    }

    func testVersionComparisonUsesNumericComponents() throws {
        let oneNine = try XCTUnwrap(AppReleaseVersion("1.9"))
        let oneTen = try XCTUnwrap(AppReleaseVersion("1.10"))
        let oneTenPatch = try XCTUnwrap(AppReleaseVersion("1.10.1"))

        XCTAssertLessThan(oneNine, oneTen)
        XCTAssertLessThan(oneTen, oneTenPatch)
        XCTAssertNil(AppReleaseVersion("release-one"))
    }

    func testCatalogIsCompleteSortedAndFreeOfEmDashes() throws {
        let entries = ChangelogCatalog.entries
        XCTAssertEqual(
            entries.map(\.version),
            [
                "1.9.2", "1.9.1", "1.9", "1.8.2", "1.8", "1.7.2", "1.6.1", "1.6", "1.5.3", "1.5.2",
                "1.5.1", "1.4.3", "1.4.2", "1.4.1", "1.4", "1.3.1", "1.3.0", "1.2.1", "1.1.0",
                "1.0.9", "1.0.8", "1.0.7", "1.0.6", "1.0.5", "1.0.2"
            ]
        )
        XCTAssertNil(entries.first?.releaseDate)
        XCTAssertTrue(entries.dropFirst().allSatisfy { $0.releaseDate != nil })

        for pair in zip(entries, entries.dropFirst()) {
            let newer = try XCTUnwrap(AppReleaseVersion(pair.0.version))
            let older = try XCTUnwrap(AppReleaseVersion(pair.1.version))
            XCTAssertGreaterThan(newer, older)
        }

        for entry in entries {
            XCTAssertFalse(entry.summary.isEmpty)
            XCTAssertFalse(entry.highlights.isEmpty)
            XCTAssertLessThanOrEqual(entry.highlights.count, 4)
            XCTAssertFalse(entry.summary.contains("—"))
            for highlight in entry.highlights {
                XCTAssertFalse(highlight.title.contains("—"))
                XCTAssertFalse(highlight.detail.contains("—"))
            }
        }
    }
}
