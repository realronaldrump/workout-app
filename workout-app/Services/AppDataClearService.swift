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
            return "Workout History"
        case .gymProfiles:
            return "Gym Profiles"
        case .gymAssignments:
            return "Gym Assignments"
        case .healthData:
            return "Health Data"
        case .intentionalBreaks:
            return "Intentional Breaks"
        case .exerciseCustomization:
            return "Exercise Setup"
        case .profileAndPreferences:
            return "Profile & Preferences"
        case .guideProgress:
            return "Onboarding & Guides"
        case .activeSessionDraft:
            return "Active Session Draft"
        case .importExportFiles:
            return "Import & Backup Files"
        }
    }

    var subtitle: String {
        switch self {
        case .workoutHistory:
            return "Imported workouts, logged workouts, workout identity maps, and CSV files."
        case .gymProfiles:
            return "Saved gyms, addresses, coordinates, and last-used gym."
        case .gymAssignments:
            return "Per-workout gym tags while keeping gym profiles and workouts."
        case .healthData:
            return "Cached workout Health metrics, daily Health history, coverage, and sync metadata."
        case .intentionalBreaks:
            return "Saved break ranges and dismissed break suggestions."
        case .exerciseCustomization:
            return "Muscle tags, custom tags, cardio metric preferences, and favorite exercises."
        case .profileAndPreferences:
            return "Profile name, appearance, goals, weight increment, and Health source preferences."
        case .guideProgress:
            return "Onboarding state, feature guide completion, and dashboard dismissals."
        case .activeSessionDraft:
            return "The unfinished workout currently saved as a draft."
        case .importExportFiles:
            return "CSV files and native app backup files stored locally or in iCloud."
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
    var featureGuideManager: FeatureGuideManager = .shared
    var userDefaults: UserDefaults = .standard
}

@MainActor
enum AppDataClearService {
    static func clear(
        plan: AppDataClearPlan,
        context: AppDataClearContext,
        setHasSeenOnboarding: (Bool) -> Void
    ) async {
        let categories = plan.effectiveCategories
        guard !categories.isEmpty else { return }

        if categories.contains(.importExportFiles) {
            await context.iCloudManager.deleteAllExportAndBackupFiles()
            AppBackupService.persistNativeBackupSourceSignature(nil, userDefaults: context.userDefaults)
        } else if shouldMarkExistingBackupAsSeen(for: categories) {
            await markLatestNativeBackupAsSeen(
                iCloudManager: context.iCloudManager,
                userDefaults: context.userDefaults
            )
        }

        if categories.contains(.workoutHistory) {
            await context.iCloudManager.deleteAllWorkoutFiles()
            await context.logStore.clearAll()
            context.dataManager.clearWorkoutHistory()
        }

        if categories.contains(.healthData) {
            context.healthManager.clearAllData()
            clearHealthPreferences(healthManager: context.healthManager, userDefaults: context.userDefaults)
        } else if categories.contains(.workoutHistory) {
            _ = context.healthManager.clearCachedHealthData(includeWorkoutData: true, includeDailyData: false)
        }

        if categories.contains(.gymProfiles) {
            context.gymProfilesManager.clearAll()
        }

        if categories.contains(.gymAssignments) {
            context.annotationsManager.clearAll()
        }

        if categories.contains(.intentionalBreaks) {
            context.intentionalBreaksManager.clearAll()
        }

        if categories.contains(.exerciseCustomization) {
            context.exerciseMetadataManager.clearOverrides()
            context.exerciseMetricManager.clearOverrides()
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
            await context.sessionManager.discardDraft()
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
            "appearanceMode"
        ].forEach { userDefaults.removeObject(forKey: $0) }

        clearHealthPreferences(healthManager: healthManager, userDefaults: userDefaults)
        gymProfilesManager.setLastUsedGymProfileId(nil)
    }
}
