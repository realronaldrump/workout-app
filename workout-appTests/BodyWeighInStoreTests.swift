import Foundation
import XCTest
@testable import workout_app

final class BodyWeighInStoreTests: XCTestCase {
    @MainActor
    func testManualWeighInAndBackdatedEditSurviveReopeningTheLog() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("weigh-ins.json")
        let timestamp = Date()
        let store = BodyStore(fileURL: file)

        try store.saveWeighIn(pounds: 182, at: timestamp, editing: nil)

        let reopened = BodyStore(fileURL: file)
        let original = try XCTUnwrap(reopened.weight.readings.first)
        XCTAssertEqual(original.value, 182)
        XCTAssertEqual(reopened.savedWeighIn(id: original.id)?.isHealthCorrection, false)
        let yesterday = timestamp.addingTimeInterval(-86_400)
        try reopened.saveWeighIn(pounds: 181.5, at: yesterday, editing: original)

        let edited = BodyStore(fileURL: file)
        XCTAssertEqual(edited.weight.readings, [BodyRawSample(id: original.id, timestamp: yesterday, value: 181.5)])
        try edited.removeWeighIn(id: original.id)
        XCTAssertTrue(BodyStore(fileURL: file).weight.isEmpty)
    }

    @MainActor
    func testFailedLogReadDoesNotReplaceTheFileWhenSaving() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let unreadable = Data("unreadable log".utf8)
        try unreadable.write(to: file)
        let store = BodyStore(fileURL: file)

        XCTAssertThrowsError(try store.saveWeighIn(pounds: 180, at: Date(), editing: nil))
        XCTAssertEqual(try Data(contentsOf: file), unreadable)
    }
}
