import Foundation

enum AppDataClearCategory: String, CaseIterable, Identifiable, Sendable {
    case workoutHistory
    case gymProfiles
    case gymAssignments
    case healthData
    case intentionalBreaks
    case exerciseCustomization
    case profileAndPreferences
    case guideProgress
    case activeSessionDraft
    case importExportFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workoutHistory:
            return "Workout history"
        case .gymProfiles:
            return "Gym profiles"
        case .gymAssignments:
            return "Gym assignments"
        case .healthData:
            return "Health data"
        case .intentionalBreaks:
            return "Planned breaks"
        case .exerciseCustomization:
            return "Exercise setup"
        case .profileAndPreferences:
            return "Profile and preferences"
        case .guideProgress:
            return "Onboarding and guides"
        case .activeSessionDraft:
            return "Active session draft"
        case .importExportFiles:
            return "Import and backup files"
        }
    }

    var subtitle: String {
        switch self {
        case .workoutHistory:
            return "Imported workouts, logged workouts, workout identity maps, and CSV files."
        case .gymProfiles:
            return "Saved gyms, addresses, coordinates, and last-used gym."
        case .gymAssignments:
            return "Gym tags on workouts. Gym profiles and workouts stay."
        case .healthData:
            return "Cached workout Health metrics, daily Health history, coverage, and sync metadata."
        case .intentionalBreaks:
            return "Saved break ranges and dismissed break suggestions."
        case .exerciseCustomization:
            return "Primary and secondary muscle roles, custom muscles, exercise relationships, cardio metric preferences, and favorite exercises."
        case .profileAndPreferences:
            return "Profile name, appearance, goals, weight increment, and Health source preferences."
        case .guideProgress:
            return "Onboarding state, feature guide completion, and dashboard dismissals."
        case .activeSessionDraft:
            return "The unfinished workout saved as a draft."
        case .importExportFiles:
            return "CSV and app backup files stored on this device or in iCloud."
        }
    }
}

struct AppDataClearPlan: Equatable, Sendable {
    var requestedCategories: Set<AppDataClearCategory>
    var effectiveCategories: Set<AppDataClearCategory>

    init(requestedCategories: Set<AppDataClearCategory>) {
        self.requestedCategories = requestedCategories
        self.effectiveCategories = Self.effectiveCategories(for: requestedCategories)
    }

    var impliedCategories: Set<AppDataClearCategory> {
        effectiveCategories.subtracting(requestedCategories)
    }

    var isEmpty: Bool {
        requestedCategories.isEmpty
    }

    static func effectiveCategories(
        for requestedCategories: Set<AppDataClearCategory>
    ) -> Set<AppDataClearCategory> {
        var categories = requestedCategories

        if categories.contains(.workoutHistory) {
            categories.insert(.gymAssignments)
            categories.insert(.activeSessionDraft)
        }

        if categories.contains(.gymProfiles) {
            categories.insert(.gymAssignments)
        }

        return categories
    }
}

@MainActor
struct AppDataClearContext {
    var dataManager: WorkoutDataManager
    var iCloudManager: iCloudDocumentManager
    var logStore: WorkoutLogStore
    var sessionManager: WorkoutSessionManager
    var healthManager: HealthKitManager
    var intentionalBreaksManager: IntentionalBreaksManager
    var annotationsManager: WorkoutAnnotationsManager
    var gymProfilesManager: GymProfilesManager
    var exerciseMetadataManager: ExerciseMetadataManager = .shared
    var exerciseMetricManager: ExerciseMetricManager = .shared
    var exerciseRelationshipManager: ExerciseRelationshipManager = .shared
    var featureGuideManager: FeatureGuideManager = .shared
    var userDefaults: UserDefaults = .standard
}

@MainActor
enum AppDataClearService {
    static func clear(
        plan: AppDataClearPlan,
        context: AppDataClearContext,
        setHasSeenOnboarding: (Bool) -> Void
    ) async throws {
        let categories = plan.effectiveCategories
        guard !categories.isEmpty else { return }

        if categories.contains(.workoutHistory) {
            try await context.logStore.clearAll()
            try context.dataManager.clearWorkoutHistoryReportingErrors()
        }

        if categories.contains(.healthData) {
            try await context.healthManager.clearAllData().value
            clearHealthPreferences(healthManager: context.healthManager, userDefaults: context.userDefaults)
        } else if categories.contains(.workoutHistory) {
            try await context.healthManager.clearAllWorkoutHealthData().value
        }

        if categories.contains(.gymProfiles) {
            try await context.gymProfilesManager.clearAll()
        }

        if categories.contains(.gymAssignments) {
            try await context.annotationsManager.clearAll()
        }

        if categories.contains(.intentionalBreaks) {
            context.intentionalBreaksManager.clearAll()
        }

        if categories.contains(.exerciseCustomization) {
            context.exerciseMetadataManager.clearOverrides()
            context.exerciseMetricManager.clearOverrides()
            context.exerciseRelationshipManager.resetToDefaults()
            context.dataManager.refreshExerciseIdentityDerivedState()
            context.userDefaults.removeObject(forKey: "favoriteExercises")
        }

        if categories.contains(.profileAndPreferences) {
            clearProfileAndPreferences(
                healthManager: context.healthManager,
                gymProfilesManager: context.gymProfilesManager,
                userDefaults: context.userDefaults
            )
        }

        if categories.contains(.guideProgress) {
            context.featureGuideManager.resetAll()
            context.userDefaults.removeObject(forKey: "dismissedUntaggedCount")
            setHasSeenOnboarding(false)
        }

        if categories.contains(.activeSessionDraft) {
            guard await context.sessionManager.discardDraft() else {
                throw NSError(
                    domain: "AppDataClearService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The active workout draft could not be cleared. Your recovery files have been kept. Try clearing the draft again."]
                )
            }
        }

        // Delete source and recovery files only after in-app stores have cleared successfully.
        // A failed store clear must not remove the user's remaining recovery path or mark it seen.
        if categories.contains(.importExportFiles) {
            try await context.iCloudManager.deleteAllExportAndBackupFiles()
            AppBackupService.persistNativeBackupSourceSignature(nil, userDefaults: context.userDefaults)
        } else {
            if categories.contains(.workoutHistory) {
                try await context.iCloudManager.deleteAllStrongImportFiles()
            }
            if shouldMarkExistingBackupAsSeen(for: categories) {
                await markLatestNativeBackupAsSeen(
                    iCloudManager: context.iCloudManager,
                    userDefaults: context.userDefaults
                )
            }
        }
    }

    private static func shouldMarkExistingBackupAsSeen(
        for categories: Set<AppDataClearCategory>
    ) -> Bool {
        !categories.isDisjoint(with: [
            .workoutHistory,
            .gymProfiles,
            .gymAssignments,
            .healthData,
            .intentionalBreaks,
            .exerciseCustomization,
            .profileAndPreferences,
            .guideProgress
        ])
    }

    private static func markLatestNativeBackupAsSeen(
        iCloudManager: iCloudDocumentManager,
        userDefaults: UserDefaults
    ) async {
        let directories = await iCloudManager.storageSearchDirectories()
        let latestBackup = iCloudDocumentManager.latestBackupFile(in: directories)
        guard let signature = AppBackupService.importSourceSignature(for: latestBackup) else { return }
        AppBackupService.persistNativeBackupSourceSignature(signature, userDefaults: userDefaults)
    }

    private static func clearHealthPreferences(
        healthManager: HealthKitManager,
        userDefaults: UserDefaults
    ) {
        userDefaults.removeObject(forKey: healthManager.preferredSleepSourceKey)
        userDefaults.removeObject(forKey: healthManager.preferredSleepSourceNameKey)
    }

    private static func clearProfileAndPreferences(
        healthManager: HealthKitManager,
        gymProfilesManager: GymProfilesManager,
        userDefaults: UserDefaults
    ) {
        [
            "profileName",
            "weightIncrement",
            "intentionalRestDays",
            "sessionsPerWeekGoal",
            "appearanceMode",
            Haptics.preferenceKey,
            "bodyGoalWeightLb",
            "bodyGoalStartWeightLb",
            "bodyGoalStartDate",
            "bodyGoalReachedDate",
            "bodyRange"
        ].forEach { userDefaults.removeObject(forKey: $0) }

        clearHealthPreferences(healthManager: healthManager, userDefaults: userDefaults)
        gymProfilesManager.setLastUsedGymProfileId(nil)
    }
}
