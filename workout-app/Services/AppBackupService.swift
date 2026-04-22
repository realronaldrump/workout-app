import Foundation

nonisolated enum AppBackupError: LocalizedError {
    case unsupportedImportFile
    case invalidBackupFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedImportFile:
            return "Select a Strong CSV or Big Beautiful Workout backup file."
        case .invalidBackupFormat:
            return "This backup file is not a valid Big Beautiful Workout backup."
        }
    }
}

nonisolated enum AppImportKind {
    case strongCSV(Data, fileName: String)
    case nativeBackup(BigBeautifulWorkoutBackup, fileName: String)
}

nonisolated enum AppBackupImportPolicy {
    case mergeKeepLocal
}

nonisolated struct AppBackupImportResult {
    var insertedWorkouts = 0
    var skippedWorkouts = 0
    var insertedLoggedWorkouts = 0
    var skippedLoggedWorkouts = 0
    var insertedGyms = 0
    var skippedGyms = 0
    var insertedAnnotations = 0
    var skippedAnnotations = 0
    var insertedWorkoutHealthEntries = 0
    var skippedWorkoutHealthEntries = 0
    var insertedDailyHealthEntries = 0
    var skippedDailyHealthEntries = 0
    var settingsFilled = 0
    var warnings: [String] = []

    var insertedTotal: Int {
        insertedWorkouts +
        insertedLoggedWorkouts +
        insertedGyms +
        insertedAnnotations +
        insertedWorkoutHealthEntries +
        insertedDailyHealthEntries
    }
}

nonisolated struct BigBeautifulWorkoutBackup: Codable {
    static let currentFormatIdentifier = "com.davis.big-beautiful-workout.backup"
    static let currentSchemaVersion = 1

    var formatIdentifier: String
    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String
    var appBuild: String
    var payload: AppBackupPayload

    init(
        formatIdentifier: String = Self.currentFormatIdentifier,
        schemaVersion: Int = Self.currentSchemaVersion,
        exportedAt: Date = Date(),
        appVersion: String,
        appBuild: String,
        payload: AppBackupPayload
    ) {
        self.formatIdentifier = formatIdentifier
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.payload = payload
    }
}

nonisolated struct AppBackupPayload: Codable {
    var importedWorkouts: [Workout]
    var loggedWorkouts: [LoggedWorkout]
    var workoutIdentities: [String: UUID]
    var workoutAnnotations: [WorkoutAnnotation]
    var gymProfiles: [GymProfile]
    var workoutHealthData: [WorkoutHealthData]
    var dailyHealthData: [DailyHealthData]
    var dailyHealthCoverage: [Date]
    var exerciseTagOverrides: [String: [MuscleTag]]
    var exerciseMetricPreferences: [String: ExerciseCardioMetricPreferences]
    var intentionalBreakRanges: [IntentionalBreakRange]
    var dismissedIntentionalBreakSuggestions: [IntentionalBreakRange]
    var favoriteExercises: [String]
    var completedFeatureGuideIDs: [String]
    var settings: AppBackupSettings

    init(
        importedWorkouts: [Workout] = [],
        loggedWorkouts: [LoggedWorkout] = [],
        workoutIdentities: [String: UUID] = [:],
        workoutAnnotations: [WorkoutAnnotation] = [],
        gymProfiles: [GymProfile] = [],
        workoutHealthData: [WorkoutHealthData] = [],
        dailyHealthData: [DailyHealthData] = [],
        dailyHealthCoverage: [Date] = [],
        exerciseTagOverrides: [String: [MuscleTag]] = [:],
        exerciseMetricPreferences: [String: ExerciseCardioMetricPreferences] = [:],
        intentionalBreakRanges: [IntentionalBreakRange] = [],
        dismissedIntentionalBreakSuggestions: [IntentionalBreakRange] = [],
        favoriteExercises: [String] = [],
        completedFeatureGuideIDs: [String] = [],
        settings: AppBackupSettings = AppBackupSettings()
    ) {
        self.importedWorkouts = importedWorkouts
        self.loggedWorkouts = loggedWorkouts
        self.workoutIdentities = workoutIdentities
        self.workoutAnnotations = workoutAnnotations
        self.gymProfiles = gymProfiles
        self.workoutHealthData = workoutHealthData
        self.dailyHealthData = dailyHealthData
        self.dailyHealthCoverage = dailyHealthCoverage
        self.exerciseTagOverrides = exerciseTagOverrides
        self.exerciseMetricPreferences = exerciseMetricPreferences
        self.intentionalBreakRanges = intentionalBreakRanges
        self.dismissedIntentionalBreakSuggestions = dismissedIntentionalBreakSuggestions
        self.favoriteExercises = favoriteExercises
        self.completedFeatureGuideIDs = completedFeatureGuideIDs
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        importedWorkouts = try container.decodeIfPresent([Workout].self, forKey: .importedWorkouts) ?? []
        loggedWorkouts = try container.decodeIfPresent([LoggedWorkout].self, forKey: .loggedWorkouts) ?? []
        workoutIdentities = try container.decodeIfPresent([String: UUID].self, forKey: .workoutIdentities) ?? [:]
        workoutAnnotations = try container.decodeIfPresent([WorkoutAnnotation].self, forKey: .workoutAnnotations) ?? []
        gymProfiles = try container.decodeIfPresent([GymProfile].self, forKey: .gymProfiles) ?? []
        workoutHealthData = try container.decodeIfPresent([WorkoutHealthData].self, forKey: .workoutHealthData) ?? []
        dailyHealthData = try container.decodeIfPresent([DailyHealthData].self, forKey: .dailyHealthData) ?? []
        dailyHealthCoverage = try container.decodeIfPresent([Date].self, forKey: .dailyHealthCoverage) ?? []
        exerciseTagOverrides = try container.decodeIfPresent(
            [String: [MuscleTag]].self,
            forKey: .exerciseTagOverrides
        ) ?? [:]
        exerciseMetricPreferences = try container.decodeIfPresent(
            [String: ExerciseCardioMetricPreferences].self,
            forKey: .exerciseMetricPreferences
        ) ?? [:]
        intentionalBreakRanges = try container.decodeIfPresent(
            [IntentionalBreakRange].self,
            forKey: .intentionalBreakRanges
        ) ?? []
        dismissedIntentionalBreakSuggestions = try container.decodeIfPresent(
            [IntentionalBreakRange].self,
            forKey: .dismissedIntentionalBreakSuggestions
        ) ?? []
        favoriteExercises = try container.decodeIfPresent([String].self, forKey: .favoriteExercises) ?? []
        completedFeatureGuideIDs = try container.decodeIfPresent([String].self, forKey: .completedFeatureGuideIDs) ?? []
        settings = try container.decodeIfPresent(AppBackupSettings.self, forKey: .settings) ?? AppBackupSettings()
    }
}

nonisolated struct AppBackupSettings: Codable {
    var profileName: String?
    var hasSeenOnboarding: Bool?
    var weightIncrement: Double?
    var intentionalRestDays: Int?
    var sessionsPerWeekGoal: Int?
    var appearanceMode: Int?
    var preferredSleepSourceKey: String?
    var preferredSleepSourceName: String?
    var lastUsedGymProfileId: UUID?
    var dismissedUntaggedCount: Int?
    var analyticsCollectionEnabled: Bool?
    var lastHealthSyncDate: Date?
    var lastDailyHealthSyncDate: Date?
    var earliestAvailableDailyHealthDate: Date?
    var dailyHealthStoreVersion: Int?
    var pendingWorkoutSleepSummaryRefresh: Bool?
}

enum AppBackupService {
    nonisolated static let backupFileExtension = "bbworkoutbackup"
    nonisolated static let nativeBackupSourceSignatureKey = "nativeBackupSourceSignature"

    @MainActor
    static func makeBackup(
        dataManager: WorkoutDataManager,
        logStore: WorkoutLogStore,
        healthManager: HealthKitManager,
        annotationsManager: WorkoutAnnotationsManager,
        gymProfilesManager: GymProfilesManager,
        intentionalBreaksManager: IntentionalBreaksManager,
        exerciseMetadataManager: ExerciseMetadataManager? = nil,
        exerciseMetricManager: ExerciseMetricManager? = nil,
        featureGuideManager: FeatureGuideManager? = nil,
        userDefaults: UserDefaults = .standard,
        database: AppDatabase = .shared
    ) throws -> BigBeautifulWorkoutBackup {
        let exerciseMetadataManager = exerciseMetadataManager ?? .shared
        let exerciseMetricManager = exerciseMetricManager ?? .shared
        let featureGuideManager = featureGuideManager ?? .shared
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?[kCFBundleVersionKey as String] as? String ?? "?"

        let payload = AppBackupPayload(
            importedWorkouts: dataManager.importedWorkouts,
            loggedWorkouts: logStore.workouts,
            workoutIdentities: try database.loadWorkoutIdentities(),
            workoutAnnotations: Array(annotationsManager.annotations.values),
            gymProfiles: gymProfilesManager.gyms,
            workoutHealthData: Array(healthManager.healthDataStore.values),
            dailyHealthData: Array(healthManager.dailyHealthStore.values),
            dailyHealthCoverage: Array(healthManager.dailyHealthCoverage).sorted(),
            exerciseTagOverrides: exerciseMetadataManager.muscleTagOverrides,
            exerciseMetricPreferences: exerciseMetricManager.cardioOverrides,
            intentionalBreakRanges: intentionalBreaksManager.savedBreaks,
            dismissedIntentionalBreakSuggestions: intentionalBreaksManager.dismissedSuggestionRanges,
            favoriteExercises: favoriteExercises(userDefaults: userDefaults),
            completedFeatureGuideIDs: Array(featureGuideManager.completedGuideIDs),
            settings: backupSettings(
                healthManager: healthManager,
                gymProfilesManager: gymProfilesManager,
                userDefaults: userDefaults
            )
        )

        return BigBeautifulWorkoutBackup(appVersion: version, appBuild: build, payload: payload)
    }

    nonisolated static func exportBackup(_ backup: BigBeautifulWorkoutBackup) throws -> Data {
        try makeBackupJSONEncoder().encode(backup)
    }

    nonisolated static func exportBackup(
        to destinationURL: URL,
        backup: BigBeautifulWorkoutBackup
    ) throws {
        let encoder = makeBackupJSONEncoder()

        try iCloudDocumentManager.writeFileAtomically(to: destinationURL) { handle in
            let writer = BackupJSONStreamWriter(handle: handle, encoder: encoder)
            try writer.writeBackup(backup)
        }
    }

    nonisolated static func decodeBackup(from data: Data) throws -> BigBeautifulWorkoutBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BigBeautifulWorkoutBackup.self, from: data)
        guard backup.formatIdentifier == BigBeautifulWorkoutBackup.currentFormatIdentifier else {
            throw AppBackupError.invalidBackupFormat
        }
        guard backup.schemaVersion <= BigBeautifulWorkoutBackup.currentSchemaVersion else {
            throw AppBackupError.invalidBackupFormat
        }
        return backup
    }

    nonisolated static func classifyImport(data: Data, fileName: String) throws -> AppImportKind {
        if let backup = try? decodeBackup(from: data) {
            return .nativeBackup(backup, fileName: fileName)
        }

        if fileName.lowercased().hasSuffix(".csv") {
            return .strongCSV(data, fileName: fileName)
        }

        throw AppBackupError.unsupportedImportFile
    }

    nonisolated static func makeBackupFileName(exportedAt: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "bbworkout_backup_\(formatter.string(from: exportedAt)).\(backupFileExtension)"
    }

    private nonisolated static func makeBackupJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private nonisolated struct BackupJSONStreamWriter {
        let handle: FileHandle
        let encoder: JSONEncoder

        func writeBackup(_ backup: BigBeautifulWorkoutBackup) throws {
            try writeObject {
                try $0.field("appBuild") {
                    try writeEncoded(backup.appBuild)
                }
                try $0.field("appVersion") {
                    try writeEncoded(backup.appVersion)
                }
                try $0.field("exportedAt") {
                    try writeEncoded(backup.exportedAt)
                }
                try $0.field("formatIdentifier") {
                    try writeEncoded(backup.formatIdentifier)
                }
                try $0.field("payload") {
                    try writePayload(backup.payload)
                }
                try $0.field("schemaVersion") {
                    try writeEncoded(backup.schemaVersion)
                }
            }
        }

        private func writePayload(_ payload: AppBackupPayload) throws {
            try writeObject {
                try $0.field("completedFeatureGuideIDs") {
                    try writeArray(payload.completedFeatureGuideIDs)
                }
                try $0.field("dailyHealthCoverage") {
                    try writeArray(payload.dailyHealthCoverage)
                }
                try $0.field("dailyHealthData") {
                    try writeArray(payload.dailyHealthData)
                }
                try $0.field("dismissedIntentionalBreakSuggestions") {
                    try writeArray(payload.dismissedIntentionalBreakSuggestions)
                }
                try $0.field("exerciseMetricPreferences") {
                    try writeDictionary(payload.exerciseMetricPreferences)
                }
                try $0.field("exerciseTagOverrides") {
                    try writeDictionary(payload.exerciseTagOverrides)
                }
                try $0.field("favoriteExercises") {
                    try writeArray(payload.favoriteExercises)
                }
                try $0.field("gymProfiles") {
                    try writeArray(payload.gymProfiles)
                }
                try $0.field("importedWorkouts") {
                    try writeArray(payload.importedWorkouts)
                }
                try $0.field("intentionalBreakRanges") {
                    try writeArray(payload.intentionalBreakRanges)
                }
                try $0.field("loggedWorkouts") {
                    try writeArray(payload.loggedWorkouts)
                }
                try $0.field("settings") {
                    try writeEncoded(payload.settings)
                }
                try $0.field("workoutAnnotations") {
                    try writeArray(payload.workoutAnnotations)
                }
                try $0.field("workoutHealthData") {
                    try writeArray(payload.workoutHealthData)
                }
                try $0.field("workoutIdentities") {
                    try writeDictionary(payload.workoutIdentities)
                }
            }
        }

        private func writeObject(
            _ body: (_ writer: inout ObjectWriter) throws -> Void
        ) throws {
            try writeRaw("{")
            var writer = ObjectWriter(owner: self)
            try body(&writer)
            try writeRaw("}")
        }

        private func writeArray<Element: Encodable>(_ values: [Element]) throws {
            try writeRaw("[")
            for (index, value) in values.enumerated() {
                if index > 0 {
                    try writeRaw(",")
                }
                try writeEncoded(value)
            }
            try writeRaw("]")
        }

        private func writeDictionary<Value: Encodable>(_ values: [String: Value]) throws {
            try writeRaw("{")
            let sortedKeys = values.keys.sorted()
            for (index, key) in sortedKeys.enumerated() {
                if index > 0 {
                    try writeRaw(",")
                }
                try writeEncoded(key)
                try writeRaw(":")
                if let value = values[key] {
                    try writeEncoded(value)
                } else {
                    try writeRaw("null")
                }
            }
            try writeRaw("}")
        }

        private func writeEncoded<Value: Encodable>(_ value: Value) throws {
            try handle.write(contentsOf: try encoder.encode(value))
        }

        private func writeRaw(_ string: String) throws {
            try handle.write(contentsOf: Data(string.utf8))
        }

        struct ObjectWriter {
            private let owner: BackupJSONStreamWriter
            private var wroteField = false

            fileprivate init(owner: BackupJSONStreamWriter) {
                self.owner = owner
            }

            mutating func field(_ name: String, valueWriter: () throws -> Void) throws {
                if wroteField {
                    try owner.writeRaw(",")
                }
                try owner.writeEncoded(name)
                try owner.writeRaw(":")
                try valueWriter()
                wroteField = true
            }
        }
    }

    nonisolated static func importSourceSignature(for fileURL: URL?) -> String? {
        guard let fileURL else { return nil }
        let creationDate = (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
        return "\(fileURL.standardizedFileURL.path)|\(creationDate.timeIntervalSince1970)"
    }

    nonisolated static func cachedNativeBackupSourceSignature(userDefaults: UserDefaults = .standard) -> String? {
        userDefaults.string(forKey: nativeBackupSourceSignatureKey)
    }

    nonisolated static func persistNativeBackupSourceSignature(
        _ signature: String?,
        userDefaults: UserDefaults = .standard
    ) {
        if let signature {
            userDefaults.set(signature, forKey: nativeBackupSourceSignatureKey)
        } else {
            userDefaults.removeObject(forKey: nativeBackupSourceSignatureKey)
        }
    }

    private static func favoriteExercises(userDefaults: UserDefaults) -> [String] {
        guard let data = userDefaults.string(forKey: "favoriteExercises")?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded.sorted()
    }

    @MainActor
    private static func backupSettings(
        healthManager: HealthKitManager,
        gymProfilesManager: GymProfilesManager,
        userDefaults: UserDefaults
    ) -> AppBackupSettings {
        AppBackupSettings(
            profileName: userDefaults.string(forKey: "profileName"),
            hasSeenOnboarding: userDefaults.object(forKey: "hasSeenOnboarding") as? Bool,
            weightIncrement: userDefaults.object(forKey: "weightIncrement") as? Double,
            intentionalRestDays: userDefaults.object(forKey: "intentionalRestDays") as? Int,
            sessionsPerWeekGoal: userDefaults.object(forKey: "sessionsPerWeekGoal") as? Int,
            appearanceMode: userDefaults.object(forKey: "appearanceMode") as? Int,
            preferredSleepSourceKey: userDefaults.string(forKey: healthManager.preferredSleepSourceKey),
            preferredSleepSourceName: userDefaults.string(forKey: healthManager.preferredSleepSourceNameKey),
            lastUsedGymProfileId: gymProfilesManager.lastUsedGymProfileId,
            dismissedUntaggedCount: userDefaults.object(forKey: "dismissedUntaggedCount") as? Int,
            analyticsCollectionEnabled: userDefaults.object(forKey: AppAnalytics.collectionEnabledKey) as? Bool,
            lastHealthSyncDate: userDefaults.object(forKey: healthManager.lastSyncKey) as? Date,
            lastDailyHealthSyncDate: userDefaults.object(forKey: healthManager.lastDailySyncKey) as? Date,
            earliestAvailableDailyHealthDate: userDefaults.object(
                forKey: healthManager.earliestAvailableDailyHealthDateKey
            ) as? Date,
            dailyHealthStoreVersion: userDefaults.object(forKey: healthManager.dailyHealthStoreVersionKey) as? Int,
            pendingWorkoutSleepSummaryRefresh: userDefaults.object(
                forKey: healthManager.pendingWorkoutSleepSummaryRefreshKey
            ) as? Bool
        )
    }
}

enum AppBackupImporter {
    @MainActor
    static func importBackup(
        _ backup: BigBeautifulWorkoutBackup,
        policy: AppBackupImportPolicy = .mergeKeepLocal,
        dataManager: WorkoutDataManager,
        logStore: WorkoutLogStore,
        healthManager: HealthKitManager,
        annotationsManager: WorkoutAnnotationsManager,
        gymProfilesManager: GymProfilesManager,
        intentionalBreaksManager: IntentionalBreaksManager,
        exerciseMetadataManager: ExerciseMetadataManager? = nil,
        exerciseMetricManager: ExerciseMetricManager? = nil,
        featureGuideManager: FeatureGuideManager? = nil,
        userDefaults: UserDefaults = .standard
    ) throws -> AppBackupImportResult {
        _ = policy
        let exerciseMetadataManager = exerciseMetadataManager ?? .shared
        let exerciseMetricManager = exerciseMetricManager ?? .shared
        let featureGuideManager = featureGuideManager ?? .shared
        var result = AppBackupImportResult()
        var warnings: [String] = []

        let loggedMerge = logStore.mergeWorkoutsFromBackup(backup.payload.loggedWorkouts)
        result.insertedLoggedWorkouts = loggedMerge.inserted
        result.skippedLoggedWorkouts = loggedMerge.skipped
        dataManager.setLoggedWorkouts(logStore.workouts)

        let importedMerge = dataManager.mergeImportedWorkoutsFromBackup(backup.payload.importedWorkouts)
        result.insertedWorkouts = importedMerge.inserted
        result.skippedWorkouts = importedMerge.skipped
        var workoutIdMap = importedMerge.idMap
        for logged in backup.payload.loggedWorkouts {
            workoutIdMap[logged.id] = logStore.workout(id: logged.id)?.id ?? logged.id
        }

        let identityInserted = dataManager.mergeWorkoutIdentitiesFromBackup(
            backup.payload.workoutIdentities,
            workoutIdMap: workoutIdMap
        )
        if identityInserted == 0, !backup.payload.workoutIdentities.isEmpty {
            warnings.append("Workout identity map entries already existed locally.")
        }

        let gymMerge = gymProfilesManager.mergeGymsFromBackup(backup.payload.gymProfiles)
        result.insertedGyms = gymMerge.inserted
        result.skippedGyms = gymMerge.skipped

        let annotationMerge = annotationsManager.mergeAnnotationsFromBackup(
            backup.payload.workoutAnnotations,
            workoutIdMap: workoutIdMap,
            gymIdMap: gymMerge.idMap
        )
        result.insertedAnnotations = annotationMerge.inserted
        result.skippedAnnotations = annotationMerge.skipped

        let healthMerge = healthManager.mergeCachedHealthDataFromBackup(
            workoutEntries: backup.payload.workoutHealthData,
            dailyEntries: backup.payload.dailyHealthData,
            dailyCoverage: backup.payload.dailyHealthCoverage,
            workoutIdMap: workoutIdMap
        )
        result.insertedWorkoutHealthEntries = healthMerge.workoutInserted
        result.skippedWorkoutHealthEntries = healthMerge.workoutSkipped
        result.insertedDailyHealthEntries = healthMerge.dailyInserted
        result.skippedDailyHealthEntries = healthMerge.dailySkipped

        _ = exerciseMetadataManager.mergeOverridesFromBackup(backup.payload.exerciseTagOverrides)
        _ = exerciseMetricManager.mergePreferencesFromBackup(backup.payload.exerciseMetricPreferences)
        _ = intentionalBreaksManager.mergeBreaksFromBackup(backup.payload.intentionalBreakRanges)
        _ = intentionalBreaksManager.mergeDismissedSuggestionsFromBackup(
            backup.payload.dismissedIntentionalBreakSuggestions
        )
        _ = featureGuideManager.mergeCompletedGuideIDs(backup.payload.completedFeatureGuideIDs)
        result.settingsFilled += mergeFavoriteExercises(backup.payload.favoriteExercises, userDefaults: userDefaults)
        result.settingsFilled += mergeSettings(
            backup.payload.settings,
            healthManager: healthManager,
            gymProfilesManager: gymProfilesManager,
            gymIdMap: gymMerge.idMap,
            userDefaults: userDefaults
        )

        result.warnings = warnings
        return result
    }

    private static func mergeFavoriteExercises(_ backupFavorites: [String], userDefaults: UserDefaults) -> Int {
        guard !backupFavorites.isEmpty else { return 0 }

        let existingData = userDefaults.string(forKey: "favoriteExercises")?.data(using: .utf8)
        let existing = (existingData.flatMap { try? JSONDecoder().decode([String].self, from: $0) }) ?? []
        let merged = Array(Set(existing).union(backupFavorites)).sorted()
        guard merged != existing.sorted() else { return 0 }

        if let data = try? JSONEncoder().encode(merged),
           let string = String(data: data, encoding: .utf8) {
            userDefaults.set(string, forKey: "favoriteExercises")
            return 1
        }
        return 0
    }

    @MainActor
    private static func mergeSettings(
        _ settings: AppBackupSettings,
        healthManager: HealthKitManager,
        gymProfilesManager: GymProfilesManager,
        gymIdMap: [UUID: UUID],
        userDefaults: UserDefaults
    ) -> Int {
        var filled = 0
        filled += setIfMissingOrEmpty(settings.profileName, forKey: "profileName", userDefaults: userDefaults)
        filled += setIfMissing(settings.hasSeenOnboarding, forKey: "hasSeenOnboarding", userDefaults: userDefaults)
        filled += setIfMissing(settings.weightIncrement, forKey: "weightIncrement", userDefaults: userDefaults)
        filled += setIfMissing(settings.intentionalRestDays, forKey: "intentionalRestDays", userDefaults: userDefaults)
        filled += setIfMissing(settings.sessionsPerWeekGoal, forKey: "sessionsPerWeekGoal", userDefaults: userDefaults)
        filled += setIfMissing(settings.appearanceMode, forKey: "appearanceMode", userDefaults: userDefaults)
        filled += setIfMissingOrEmpty(
            settings.preferredSleepSourceKey,
            forKey: healthManager.preferredSleepSourceKey,
            userDefaults: userDefaults
        )
        filled += setIfMissingOrEmpty(
            settings.preferredSleepSourceName,
            forKey: healthManager.preferredSleepSourceNameKey,
            userDefaults: userDefaults
        )
        filled += setIfMissing(settings.dismissedUntaggedCount, forKey: "dismissedUntaggedCount", userDefaults: userDefaults)
        filled += setIfMissing(
            settings.analyticsCollectionEnabled,
            forKey: AppAnalytics.collectionEnabledKey,
            userDefaults: userDefaults
        )
        filled += setIfMissing(settings.lastHealthSyncDate, forKey: healthManager.lastSyncKey, userDefaults: userDefaults)
        filled += setIfMissing(
            settings.lastDailyHealthSyncDate,
            forKey: healthManager.lastDailySyncKey,
            userDefaults: userDefaults
        )
        filled += setIfMissing(
            settings.earliestAvailableDailyHealthDate,
            forKey: healthManager.earliestAvailableDailyHealthDateKey,
            userDefaults: userDefaults
        )
        filled += setIfMissing(
            settings.dailyHealthStoreVersion,
            forKey: healthManager.dailyHealthStoreVersionKey,
            userDefaults: userDefaults
        )
        filled += setIfMissing(
            settings.pendingWorkoutSleepSummaryRefresh,
            forKey: healthManager.pendingWorkoutSleepSummaryRefreshKey,
            userDefaults: userDefaults
        )

        if gymProfilesManager.lastUsedGymProfileId == nil,
           let backupLastUsed = settings.lastUsedGymProfileId {
            gymProfilesManager.setLastUsedGymProfileId(gymIdMap[backupLastUsed] ?? backupLastUsed)
            filled += 1
        }

        healthManager.lastSyncDate = userDefaults.object(forKey: healthManager.lastSyncKey) as? Date
        healthManager.lastDailySyncDate = userDefaults.object(forKey: healthManager.lastDailySyncKey) as? Date
        healthManager.earliestAvailableDailyHealthDate = userDefaults.object(
            forKey: healthManager.earliestAvailableDailyHealthDateKey
        ) as? Date

        return filled
    }

    private static func setIfMissing<T>(_ value: T?, forKey key: String, userDefaults: UserDefaults) -> Int {
        guard let value else { return 0 }
        guard userDefaults.object(forKey: key) == nil else { return 0 }
        userDefaults.set(value, forKey: key)
        return 1
    }

    private static func setIfMissingOrEmpty(_ value: String?, forKey key: String, userDefaults: UserDefaults) -> Int {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        let existing = userDefaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty else { return 0 }
        userDefaults.set(value, forKey: key)
        return 1
    }
}

extension WorkoutHealthData {
    nonisolated func remappingWorkoutId(_ workoutId: UUID) -> WorkoutHealthData {
        guard workoutId != self.workoutId else { return self }
        return WorkoutHealthData(
            id: id,
            workoutId: workoutId,
            workoutDate: workoutDate,
            workoutStartTime: workoutStartTime,
            workoutEndTime: workoutEndTime,
            syncedAt: syncedAt,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            minHeartRate: minHeartRate,
            heartRateSamples: heartRateSamples,
            activeCalories: activeCalories,
            basalCalories: basalCalories,
            distance: distance,
            avgSpeed: avgSpeed,
            avgPower: avgPower,
            stepCount: stepCount,
            flightsClimbed: flightsClimbed,
            hrvSamples: hrvSamples,
            storedHRVAverage: storedHRVAverage,
            restingHeartRate: restingHeartRate,
            bloodOxygenSamples: bloodOxygenSamples,
            storedBloodOxygenAverage: storedBloodOxygenAverage,
            respiratoryRateSamples: respiratoryRateSamples,
            storedRespiratoryRateAverage: storedRespiratoryRateAverage,
            bodyMass: bodyMass,
            bodyFatPercentage: bodyFatPercentage,
            bodyTemperature: bodyTemperature,
            sleepSummary: sleepSummary,
            dailyActiveEnergy: dailyActiveEnergy,
            dailyBasalEnergy: dailyBasalEnergy,
            dailySteps: dailySteps,
            dailyExerciseMinutes: dailyExerciseMinutes,
            dailyMoveMinutes: dailyMoveMinutes,
            dailyStandMinutes: dailyStandMinutes,
            vo2Max: vo2Max,
            heartRateRecovery: heartRateRecovery,
            walkingHeartRateAverage: walkingHeartRateAverage,
            appleWorkoutType: appleWorkoutType,
            appleWorkoutDuration: appleWorkoutDuration,
            appleWorkoutUUID: appleWorkoutUUID,
            workoutRouteStartLatitude: workoutRouteStartLatitude,
            workoutRouteStartLongitude: workoutRouteStartLongitude,
            workoutLocationLatitude: workoutLocationLatitude,
            workoutLocationLongitude: workoutLocationLongitude,
            workoutLocationSource: workoutLocationSource,
            distanceSwimming: distanceSwimming,
            swimmingStrokeCount: swimmingStrokeCount,
            distanceWheelchair: distanceWheelchair,
            pushCount: pushCount,
            distanceDownhillSnowSports: distanceDownhillSnowSports,
            bloodPressureSystolic: bloodPressureSystolic,
            bloodPressureDiastolic: bloodPressureDiastolic,
            bloodGlucose: bloodGlucose,
            basalBodyTemperature: basalBodyTemperature,
            dietaryWater: dietaryWater,
            dietaryEnergyConsumed: dietaryEnergyConsumed,
            dietaryProtein: dietaryProtein,
            dietaryCarbohydrates: dietaryCarbohydrates,
            dietaryFatTotal: dietaryFatTotal,
            mindfulSessionDuration: mindfulSessionDuration
        )
    }
}
