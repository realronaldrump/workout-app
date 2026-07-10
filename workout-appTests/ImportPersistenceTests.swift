import XCTest
@testable import workout_app

final class ImportPersistenceTests: XCTestCase {
    func testLatestWorkoutFileUsesNewestStrongImportAcrossAllDirectories() throws {
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
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000)],
            ofItemAtPath: localFile.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: iCloudFile.path
        )

        let selected = WorkoutDataManager.latestWorkoutFile(in: [iCloudDirectory, localDirectory])

        XCTAssertEqual(selected?.standardizedFileURL, localFile.standardizedFileURL)
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

    func testLatestWorkoutFileUsesNewestExportAcrossAllDirectoriesWhenNoStrongImportExists() throws {
        let primaryDirectory = try makeTemporaryDirectory()
        let fallbackDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: primaryDirectory)
            try? FileManager.default.removeItem(at: fallbackDirectory)
        }

        let olderPrimaryExport = primaryDirectory.appendingPathComponent("workout_export_primary.csv")
        let newerFallbackExport = fallbackDirectory.appendingPathComponent("workout_export_fallback.csv")
        try Data("older".utf8).write(to: olderPrimaryExport)
        try Data("newer".utf8).write(to: newerFallbackExport)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: olderPrimaryExport.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000)],
            ofItemAtPath: newerFallbackExport.path
        )

        let selected = WorkoutDataManager.latestWorkoutFile(
            in: [primaryDirectory, fallbackDirectory]
        )

        XCTAssertEqual(selected?.standardizedFileURL, newerFallbackExport.standardizedFileURL)
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

    func testUnifiedExportAndBackupInventoryCombinesDirectoriesAndPrefersPrimaryCopy() throws {
        let primaryDirectory = try makeTemporaryDirectory()
        let fallbackDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: primaryDirectory)
            try? FileManager.default.removeItem(at: fallbackDirectory)
        }

        let duplicateName = "strong_workouts_shared.csv"
        let primaryDuplicate = primaryDirectory.appendingPathComponent(duplicateName)
        let fallbackDuplicate = fallbackDirectory.appendingPathComponent(duplicateName)
        let primaryExport = primaryDirectory.appendingPathComponent("workout_export_primary.csv")
        let fallbackBackup = fallbackDirectory.appendingPathComponent("fallback.bbworkoutbackup")
        try Data("primary".utf8).write(to: primaryDuplicate)
        try Data("fallback".utf8).write(to: fallbackDuplicate)
        try Data("export".utf8).write(to: primaryExport)
        try Data("backup".utf8).write(to: fallbackBackup)

        let files = iCloudDocumentManager.listExportAndBackupFiles(
            in: [primaryDirectory, fallbackDirectory]
        )

        XCTAssertEqual(Set(files.map(\.lastPathComponent)), [
            duplicateName,
            primaryExport.lastPathComponent,
            fallbackBackup.lastPathComponent
        ])
        XCTAssertEqual(
            files.first { $0.lastPathComponent == duplicateName }?.standardizedFileURL,
            primaryDuplicate.standardizedFileURL
        )
    }

    func testLatestBackupFileUsesNewestFileAcrossAllDirectories() throws {
        let primaryDirectory = try makeTemporaryDirectory()
        let fallbackDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: primaryDirectory)
            try? FileManager.default.removeItem(at: fallbackDirectory)
        }

        let olderPrimaryBackup = primaryDirectory.appendingPathComponent("primary.bbworkoutbackup")
        let newerFallbackBackup = fallbackDirectory.appendingPathComponent("fallback.bbworkoutbackup")
        try Data("older".utf8).write(to: olderPrimaryBackup)
        try Data("newer".utf8).write(to: newerFallbackBackup)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: olderPrimaryBackup.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000)],
            ofItemAtPath: newerFallbackBackup.path
        )

        let latest = iCloudDocumentManager.latestBackupFile(
            in: [primaryDirectory, fallbackDirectory]
        )

        XCTAssertEqual(latest?.standardizedFileURL, newerFallbackBackup.standardizedFileURL)
    }

    func testMigrateExportAndBackupFilesIncludesNativeBackups() throws {
        let sourceDirectory = try makeTemporaryDirectory()
        let destinationDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceDirectory)
            try? FileManager.default.removeItem(at: destinationDirectory)
        }

        let csvFile = sourceDirectory.appendingPathComponent("workout_export.csv")
        let backupFile = sourceDirectory.appendingPathComponent("backup.bbworkoutbackup")
        let ignoredFile = sourceDirectory.appendingPathComponent("notes.txt")
        try Data("csv".utf8).write(to: csvFile)
        try Data("backup".utf8).write(to: backupFile)
        try Data("ignore".utf8).write(to: ignoredFile)

        let migratedCount = try iCloudDocumentManager.migrateExportAndBackupFiles(
            from: sourceDirectory,
            to: destinationDirectory
        )

        XCTAssertEqual(migratedCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destinationDirectory.appendingPathComponent(csvFile.lastPathComponent).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destinationDirectory.appendingPathComponent(backupFile.lastPathComponent).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destinationDirectory.appendingPathComponent(ignoredFile.lastPathComponent).path
        ))
    }

    func testStrongImportCountAndDeletionExcludeGeneratedExportsAndBackups() throws {
        let primaryDirectory = try makeTemporaryDirectory()
        let fallbackDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: primaryDirectory)
            try? FileManager.default.removeItem(at: fallbackDirectory)
        }

        let duplicateName = "strong_workouts_shared.csv"
        let primaryStrong = primaryDirectory.appendingPathComponent(duplicateName)
        let fallbackStrong = fallbackDirectory.appendingPathComponent(duplicateName)
        let fallbackUniqueStrong = fallbackDirectory.appendingPathComponent("strong_workouts_unique.csv")
        let exportFile = primaryDirectory.appendingPathComponent("exercise_history.csv")
        let backupFile = fallbackDirectory.appendingPathComponent("backup.bbworkoutbackup")
        for file in [primaryStrong, fallbackStrong, fallbackUniqueStrong, exportFile, backupFile] {
            try Data(file.lastPathComponent.utf8).write(to: file)
        }

        XCTAssertEqual(
            iCloudDocumentManager.countStrongImportFiles(in: [primaryDirectory, fallbackDirectory]),
            2
        )

        let deletedCount = try iCloudDocumentManager.deleteStrongImportFiles(
            in: [primaryDirectory, fallbackDirectory]
        )

        XCTAssertEqual(deletedCount, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryStrong.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fallbackStrong.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fallbackUniqueStrong.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupFile.path))
    }

    func testDeletingLogicalBackupFileDeletesEveryPhysicalCopy() throws {
        let primaryDirectory = try makeTemporaryDirectory()
        let fallbackDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: primaryDirectory)
            try? FileManager.default.removeItem(at: fallbackDirectory)
        }

        let duplicateName = "bbworkout_backup_shared.bbworkoutbackup"
        let primaryCopy = primaryDirectory.appendingPathComponent(duplicateName)
        let fallbackCopy = fallbackDirectory.appendingPathComponent(duplicateName)
        let unrelatedFile = fallbackDirectory.appendingPathComponent("keep.bbworkoutbackup")
        for file in [primaryCopy, fallbackCopy, unrelatedFile] {
            try Data(file.lastPathComponent.utf8).write(to: file)
        }

        let deletedCount = try iCloudDocumentManager.deleteExportAndBackupFileCopies(
            named: duplicateName,
            in: [primaryDirectory, fallbackDirectory]
        )

        XCTAssertEqual(deletedCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: primaryCopy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fallbackCopy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedFile.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
