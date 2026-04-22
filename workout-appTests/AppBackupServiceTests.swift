import XCTest
@testable import workout_app

final class AppBackupServiceTests: XCTestCase {
    func testBackupRoundTripPreservesPayloadSections() throws {
        let workoutDate = date(day: 3, hour: 9)
        let workout = Workout(
            id: UUID(),
            date: workoutDate,
            name: "Upper",
            duration: "45m",
            exercises: [
                Exercise(name: "Bench Press", sets: [
                    WorkoutSet(
                        date: workoutDate,
                        workoutName: "Upper",
                        duration: "45m",
                        exerciseName: "Bench Press",
                        setOrder: 1,
                        weight: 135,
                        reps: 8,
                        distance: 0,
                        seconds: 0
                    )
                ])
            ]
        )
        let logged = LoggedWorkout(
            id: UUID(),
            startedAt: workoutDate,
            endedAt: workoutDate.addingTimeInterval(45 * 60),
            name: "Logged Upper",
            exercises: [LoggedExercise(name: "Row", sets: [LoggedSet(order: 1, weight: 90, reps: 10)])]
        )
        let gym = GymProfile(
            id: UUID(),
            name: "Main Gym",
            address: "1 Fitness Way",
            latitude: 40.0,
            longitude: -105.0
        )
        let health = WorkoutHealthData(
            workoutId: workout.id,
            workoutDate: workoutDate,
            workoutStartTime: workoutDate,
            workoutEndTime: workoutDate.addingTimeInterval(45 * 60),
            avgHeartRate: 122,
            activeCalories: 250
        )
        let day = Calendar.current.startOfDay(for: workoutDate)
        let breakRange = IntentionalBreakRange(startDate: day, endDate: day, name: "Travel")

        let backup = BigBeautifulWorkoutBackup(
            exportedAt: workoutDate,
            appVersion: "1.2.3",
            appBuild: "99",
            payload: AppBackupPayload(
                importedWorkouts: [workout],
                loggedWorkouts: [logged],
                workoutIdentities: ["2026-01-03-09|upper": workout.id],
                workoutAnnotations: [WorkoutAnnotation(workoutId: workout.id, gymProfileId: gym.id)],
                gymProfiles: [gym],
                workoutHealthData: [health],
                dailyHealthData: [DailyHealthData(dayStart: day, steps: 1_000, bodyMass: 80)],
                dailyHealthCoverage: [day],
                exerciseTagOverrides: ["Bench Press": [.builtIn(.chest)]],
                exerciseMetricPreferences: [
                    "Stair Stepper": ExerciseCardioMetricPreferences(
                        primaryMetric: .count,
                        countLabel: "floors",
                        schemaVersion: 1
                    )
                ],
                intentionalBreakRanges: [breakRange],
                dismissedIntentionalBreakSuggestions: [breakRange],
                favoriteExercises: ["Bench Press"],
                completedFeatureGuideIDs: ["dashboard"],
                settings: AppBackupSettings(
                    profileName: "Davis",
                    hasSeenOnboarding: true,
                    weightIncrement: 2.5,
                    intentionalRestDays: 2,
                    sessionsPerWeekGoal: 4,
                    appearanceMode: 1,
                    preferredSleepSourceKey: "watch",
                    preferredSleepSourceName: "Apple Watch",
                    lastUsedGymProfileId: gym.id,
                    dismissedUntaggedCount: 3,
                    analyticsCollectionEnabled: false,
                    lastHealthSyncDate: workoutDate,
                    lastDailyHealthSyncDate: workoutDate,
                    earliestAvailableDailyHealthDate: day,
                    dailyHealthStoreVersion: 3,
                    pendingWorkoutSleepSummaryRefresh: true
                )
            )
        )

        let data = try AppBackupService.exportBackup(backup)
        let decoded = try AppBackupService.decodeBackup(from: data)

        XCTAssertEqual(decoded.formatIdentifier, BigBeautifulWorkoutBackup.currentFormatIdentifier)
        XCTAssertEqual(decoded.schemaVersion, BigBeautifulWorkoutBackup.currentSchemaVersion)
        XCTAssertEqual(decoded.payload.importedWorkouts.first?.id, workout.id)
        XCTAssertEqual(decoded.payload.loggedWorkouts.first?.id, logged.id)
        XCTAssertEqual(decoded.payload.gymProfiles.first?.id, gym.id)
        XCTAssertEqual(decoded.payload.workoutAnnotations.first?.gymProfileId, gym.id)
        XCTAssertEqual(decoded.payload.workoutHealthData.first?.workoutId, workout.id)
        XCTAssertEqual(decoded.payload.dailyHealthData.first?.dayStart, day)
        XCTAssertEqual(decoded.payload.exerciseTagOverrides["Bench Press"], [.builtIn(.chest)])
        XCTAssertEqual(decoded.payload.exerciseMetricPreferences["Stair Stepper"]?.countLabel, "floors")
        XCTAssertEqual(decoded.payload.favoriteExercises, ["Bench Press"])
        XCTAssertEqual(decoded.payload.completedFeatureGuideIDs, ["dashboard"])
        XCTAssertEqual(decoded.payload.settings.profileName, "Davis")
    }

    func testClassifyImportDetectsNativeBackupBeforeExtension() throws {
        let backup = BigBeautifulWorkoutBackup(
            appVersion: "1.0",
            appBuild: "1",
            payload: AppBackupPayload(settings: AppBackupSettings(profileName: "Backup"))
        )
        let data = try AppBackupService.exportBackup(backup)

        let classified = try AppBackupService.classifyImport(data: data, fileName: "backup.json")

        guard case .nativeBackup(let decoded, let fileName) = classified else {
            XCTFail("Expected native backup import")
            return
        }
        XCTAssertEqual(decoded.payload.settings.profileName, "Backup")
        XCTAssertEqual(fileName, "backup.json")
    }

    func testStreamingBackupExportRoundTripPreservesPayloadSections() throws {
        let backup = BigBeautifulWorkoutBackup(
            appVersion: "1.0.0",
            appBuild: "7",
            payload: AppBackupPayload(
                favoriteExercises: ["Bench Press", "Row"],
                settings: AppBackupSettings(profileName: "Streamed")
            )
        )

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("backup.\(AppBackupService.backupFileExtension)")
        try AppBackupService.exportBackup(to: fileURL, backup: backup)

        let decoded = try AppBackupService.decodeBackup(from: try Data(contentsOf: fileURL))
        XCTAssertEqual(decoded.appVersion, backup.appVersion)
        XCTAssertEqual(decoded.appBuild, backup.appBuild)
        XCTAssertEqual(decoded.payload.favoriteExercises, backup.payload.favoriteExercises)
        XCTAssertEqual(decoded.payload.settings.profileName, "Streamed")
    }

    func testClassifyImportTreatsCSVAsStrong() throws {
        let csv = Data("Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds\n".utf8)

        let classified = try AppBackupService.classifyImport(data: csv, fileName: "strong.csv")

        guard case .strongCSV(let data, let fileName) = classified else {
            XCTFail("Expected Strong CSV import")
            return
        }
        XCTAssertEqual(data, csv)
        XCTAssertEqual(fileName, "strong.csv")
    }

    func testBackupFileListingOnlyIncludesNativeBackups() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let backupFile = directory.appendingPathComponent("bbworkout_backup_20260101_090000.bbworkoutbackup")
        let csvFile = directory.appendingPathComponent("strong_workouts.csv")
        let ignoredFile = directory.appendingPathComponent("notes.json")
        try Data("backup".utf8).write(to: backupFile)
        try Data("csv".utf8).write(to: csvFile)
        try Data("notes".utf8).write(to: ignoredFile)

        let backupFiles = iCloudDocumentManager.listBackupFiles(in: directory).map(\.lastPathComponent)
        let allFiles = iCloudDocumentManager.listExportAndBackupFiles(in: directory).map(\.lastPathComponent)

        XCTAssertEqual(backupFiles, [backupFile.lastPathComponent])
        XCTAssertTrue(allFiles.contains(backupFile.lastPathComponent))
        XCTAssertTrue(allFiles.contains(csvFile.lastPathComponent))
        XCTAssertFalse(allFiles.contains(ignoredFile.lastPathComponent))
    }

    func testBackupFileSectionsGroupFilesInLogicalOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let files = try makeFiles(
            in: directory,
            named: [
                "health_daily_3_20260101_20260131_1700000000.csv",
                "notes.csv",
                "workout_export_20260101_20260131_1700000001.csv",
                "bbworkout_backup_20260131_090000.bbworkoutbackup",
                "strong_workouts_1700000002.csv"
            ]
        )

        let sections = BackupFileSection.sections(from: files.shuffled())

        XCTAssertEqual(
            sections.map(\.kind),
            [.fullBackup, .strongImport, .workoutExport, .healthDaily, .otherCSV]
        )
    }

    func testBackupFileSectionsSortNewestFirstWithinGroup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let oldWorkoutExport = "workout_export_20260101_20260131_1700000001.csv"
        let newWorkoutExport = "workout_export_20260201_20260228_1800000001.csv"
        let files = try makeFiles(in: directory, named: [oldWorkoutExport, newWorkoutExport])

        let section = try XCTUnwrap(BackupFileSection.sections(from: files).first)

        XCTAssertEqual(section.kind, .workoutExport)
        XCTAssertEqual(section.files.map(\.fileName), [newWorkoutExport, oldWorkoutExport])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeFiles(in directory: URL, named names: [String]) throws -> [URL] {
        try names.map { name in
            let url = directory.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return url
        }
    }

    private func date(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "America/Denver")
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }
}
