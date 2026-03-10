import XCTest
@testable import workout_app

final class ImportPersistenceTests: XCTestCase {
    func testLatestWorkoutFilePrefersPrimaryDirectoryStrongImport() throws {
        let localDirectory = try makeTemporaryDirectory()
        let iCloudDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: localDirectory)
            try? FileManager.default.removeItem(at: iCloudDirectory)
        }

        let localFile = localDirectory.appendingPathComponent("strong_workouts_local.csv")
        let iCloudFile = iCloudDirectory.appendingPathComponent("strong_workouts_cloud.csv")
        try Data("local".utf8).write(to: localFile)
        try Data("icloud".utf8).write(to: iCloudFile)

        let selected = WorkoutDataManager.latestWorkoutFile(in: [iCloudDirectory, localDirectory])

        XCTAssertEqual(selected?.lastPathComponent, iCloudFile.lastPathComponent)
    }

    func testLatestWorkoutFileFallsBackToLocalStrongImportWhenPrimaryHasOnlyExports() throws {
        let localDirectory = try makeTemporaryDirectory()
        let iCloudDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: localDirectory)
            try? FileManager.default.removeItem(at: iCloudDirectory)
        }

        try Data("export".utf8).write(to: iCloudDirectory.appendingPathComponent("exercise_history.csv"))
        let localImport = localDirectory.appendingPathComponent("strong_workouts_local.csv")
        try Data("local".utf8).write(to: localImport)

        let selected = WorkoutDataManager.latestWorkoutFile(in: [iCloudDirectory, localDirectory])

        XCTAssertEqual(selected?.lastPathComponent, localImport.lastPathComponent)
    }

    func testMigrateWorkoutFilesCopiesOnlyMissingCSVs() throws {
        let sourceDirectory = try makeTemporaryDirectory()
        let destinationDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceDirectory)
            try? FileManager.default.removeItem(at: destinationDirectory)
        }

        let importFile = sourceDirectory.appendingPathComponent("strong_workouts_a.csv")
        let exportFile = sourceDirectory.appendingPathComponent("exercise_history.csv")
        let ignoredFile = sourceDirectory.appendingPathComponent("notes.txt")
        try Data("import".utf8).write(to: importFile)
        try Data("export".utf8).write(to: exportFile)
        try Data("ignore".utf8).write(to: ignoredFile)

        let existingDestinationFile = destinationDirectory.appendingPathComponent(importFile.lastPathComponent)
        try Data("existing".utf8).write(to: existingDestinationFile)

        let migratedCount = try iCloudDocumentManager.migrateWorkoutFiles(
            from: sourceDirectory,
            to: destinationDirectory
        )

        XCTAssertEqual(migratedCount, 1)
        XCTAssertEqual(try String(contentsOf: existingDestinationFile), "existing")
        XCTAssertEqual(
            try String(contentsOf: destinationDirectory.appendingPathComponent(exportFile.lastPathComponent)),
            "export"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationDirectory.appendingPathComponent(ignoredFile.lastPathComponent).path
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
