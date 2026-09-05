import XCTest
@testable import workout_app

final class WorkoutExportFileTests: XCTestCase {
    func testReportsAndJSONFollowExportInventoryMigrationAndDeletionRules() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let exports = ["workout_export_20260901.html", "exercise_history_2_20260901.json",
                       "muscle_group_export_1_20260901.html", "workout_dates_1_20260901.json", "strong_workouts_1.csv",
                       "workout_export_20260901.pdf"]
        let unrelated = ["notes.json", "index.html", "strong_workouts_fake.json", "notes.pdf"]
        for name in exports + unrelated {
            try Data(name.utf8).write(to: source.appendingPathComponent(name))
        }
        XCTAssertEqual(Set(iCloudDocumentManager.listExportAndBackupFiles(in: source).map(\.lastPathComponent)), Set(exports))
        XCTAssertEqual(iCloudDocumentManager.listStrongImportFiles(in: source).map(\.lastPathComponent), ["strong_workouts_1.csv"])
        XCTAssertEqual(try iCloudDocumentManager.migrateExportAndBackupFiles(from: source, to: destination), exports.count)
        XCTAssertEqual(iCloudDocumentManager.listExportAndBackupFiles(in: [destination, source]).count, exports.count)
        for name in exports where !name.hasSuffix(".csv") {
            XCTAssertEqual(try iCloudDocumentManager.deleteExportAndBackupFileCopies(named: name, in: [source, destination]), 2)
        }
        for name in unrelated {
            XCTAssertEqual(try iCloudDocumentManager.deleteExportAndBackupFileCopies(named: name, in: [source, destination]), 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent(name).path))
        }
    }
}
