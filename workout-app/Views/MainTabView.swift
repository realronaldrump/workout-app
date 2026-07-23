import Combine
import SwiftUI

@MainActor
private final class MainTabServices: ObservableObject {
    let dataManager: WorkoutDataManager
    let annotationsManager: WorkoutAnnotationsManager
    let intentionalBreaksManager: IntentionalBreaksManager
    let gymProfilesManager: GymProfilesManager
    let insightsEngine: InsightsEngine

    init() {
        let annotationsManager = WorkoutAnnotationsManager(loadOnInit: false)
        let intentionalBreaksManager = IntentionalBreaksManager(loadOnInit: false)
        let dataManager = WorkoutDataManager()
        let gymProfilesManager = GymProfilesManager(
            annotationsManager: annotationsManager,
            loadOnInit: false
        )

        self.dataManager = dataManager
        self.annotationsManager = annotationsManager
        self.intentionalBreaksManager = intentionalBreaksManager
        self.gymProfilesManager = gymProfilesManager
        self.insightsEngine = InsightsEngine(
            dataManager: dataManager,
            annotationsProvider: { annotationsManager.annotations },
            gymNameProvider: { gymProfilesManager.gymNameSnapshot() }
        )
    }
}

enum AppTab: String, CaseIterable, Hashable {
    case today
    case health
    case history
    case more
}

private struct HistoryTabView: View {
    @ObservedObject var dataManager: WorkoutDataManager

    var body: some View {
        WorkoutHistoryView(workouts: dataManager.workouts, showsBackButton: false)
    }
}

private struct HealthTabRoot: View {
    @StateObject private var healthStore: HealthViewStore

    init(healthManager: HealthKitManager, dataManager: WorkoutDataManager) {
        _healthStore = StateObject(
            wrappedValue: HealthViewStore(
                healthManager: healthManager,
                dataManager: dataManager
            )
        )
    }

    var body: some View {
        NavigationStack {
            HealthHubView()
        }
        .environmentObject(healthStore)
    }
}

private struct ActiveSessionInset: View {
    @ObservedObject var sessionManager: WorkoutSessionManager
    let isVisible: Bool

    var body: some View {
        if isVisible,
           sessionManager.activeSession != nil,
           !sessionManager.isPresentingSessionUI {
            ActiveSessionBar()
                .environmentObject(sessionManager)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(9)
        }
    }
}

private struct SessionPresentationHost: View {
    @ObservedObject var sessionManager: WorkoutSessionManager
    let healthManager: HealthKitManager
    let dataManager: WorkoutDataManager
    let logStore: WorkoutLogStore
    let annotationsManager: WorkoutAnnotationsManager
    let intentionalBreaksManager: IntentionalBreaksManager
    let gymProfilesManager: GymProfilesManager
    let insightsEngine: InsightsEngine
    let variantEngine: WorkoutVariantEngine
    let similarityEngine: WorkoutSimilarityEngine

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .fullScreenCover(isPresented: $sessionManager.isPresentingSessionUI) {
                // Explicitly re-inject shared ObservableObjects so session UI is robust to
                // SwiftUI presentation/environment propagation quirks (e.g. presenting
                // the session UI while another sheet is currently displayed).
                WorkoutSessionView()
                    .environmentObject(sessionManager)
                    .environmentObject(healthManager)
                    .environmentObject(dataManager)
                    .environmentObject(logStore)
                    .environmentObject(annotationsManager)
                    .environmentObject(intentionalBreaksManager)
                    .environmentObject(gymProfilesManager)
                    .environmentObject(insightsEngine)
                    .environmentObject(variantEngine)
                    .environmentObject(similarityEngine)
            }
    }
}

struct MainTabView: View {
    let sessionManager: WorkoutSessionManager
    let healthManager: HealthKitManager

    @StateObject private var services = MainTabServices()
    @StateObject private var iCloudManager = iCloudDocumentManager()
    @StateObject private var logStore = WorkoutLogStore()
    @StateObject private var healthDateRangeContext = HealthDateRangeContext()
    @StateObject private var variantEngine = WorkoutVariantEngine()
    @StateObject private var similarityEngine = WorkoutSimilarityEngine()
    @StateObject private var migrationManager = LegacyDataMigrationManager()
    @StateObject private var changelogStore = ChangelogStore()
    @ObservedObject private var relationshipManager = ExerciseRelationshipManager.shared
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingOnboarding = false
    @State private var selectedTab: AppTab
    @State private var hasCompletedInitialLoad = false
    @State private var hasStartedLaunchFlow = false
    @State private var hasBootstrappedStores = false
    @State private var changelogPresentation: ChangelogPresentation?
    @State private var insightsRefreshTask: Task<Void, Never>?
    @State private var variantAnalysisTask: Task<Void, Never>?
    @State private var similarityAnalysisTask: Task<Void, Never>?
    @State private var sleepSummaryRefreshTask: Task<Void, Never>?
    private var dataManager: WorkoutDataManager { services.dataManager }
    private var annotationsManager: WorkoutAnnotationsManager { services.annotationsManager }
    private var intentionalBreaksManager: IntentionalBreaksManager { services.intentionalBreaksManager }
    private var gymProfilesManager: GymProfilesManager { services.gymProfilesManager }
    private var insightsEngine: InsightsEngine { services.insightsEngine }

    init(sessionManager: WorkoutSessionManager, healthManager: HealthKitManager) {
        self.sessionManager = sessionManager
        self.healthManager = healthManager

#if DEBUG
        let requestedTab = ProcessInfo.processInfo.environment["WORKOUT_APP_INITIAL_TAB"]
            .flatMap(AppTab.init(rawValue:))
        _selectedTab = State(initialValue: requestedTab ?? .today)
#else
        _selectedTab = State(initialValue: .today)
#endif
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(
                        dataManager: dataManager,
                        iCloudManager: iCloudManager,
                        annotationsManager: annotationsManager,
                        gymProfilesManager: gymProfilesManager,
                        selectedTab: $selectedTab
                    )
                }
                .tabItem {
                    Label("Today", systemImage: "chart.bar.fill")
                }
                .tag(AppTab.today)

                HealthTabRoot(
                    healthManager: healthManager,
                    dataManager: dataManager
                )
                .tabItem {
                    Label("Health", systemImage: "heart.fill")
                }
                .tag(AppTab.health)

                NavigationStack {
                    HistoryTabView(dataManager: dataManager)
                }
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(AppTab.history)

                NavigationStack {
                    ProfileView(
                        dataManager: dataManager,
                        iCloudManager: iCloudManager,
                        selectedTab: $selectedTab
                    )
                }
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag(AppTab.more)
            }
        }
        .environmentObject(dataManager)
        .environmentObject(logStore)
        .environmentObject(annotationsManager)
        .environmentObject(intentionalBreaksManager)
        .environmentObject(gymProfilesManager)
        .environmentObject(insightsEngine)
        .environmentObject(healthDateRangeContext)
        .environmentObject(variantEngine)
        .environmentObject(similarityEngine)
        .tint(Theme.Colors.accent)
        .analyticsScreen("MainTabs")
        .overlay {
            if migrationManager.blocksLaunch {
                LegacyMigrationWizardView(
                    manager: migrationManager,
                    onContinue: continueAfterMigration
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .overlay {
            SessionPresentationHost(
                sessionManager: sessionManager,
                healthManager: healthManager,
                dataManager: dataManager,
                logStore: logStore,
                annotationsManager: annotationsManager,
                intentionalBreaksManager: intentionalBreaksManager,
                gymProfilesManager: gymProfilesManager,
                insightsEngine: insightsEngine,
                variantEngine: variantEngine,
                similarityEngine: similarityEngine
            )
        }
        .onAppear {
            refreshOnboardingState()
            startLaunchFlowIfNeeded()
            scheduleVariantAnalysis()
            scheduleSimilarityAnalysis()
            schedulePendingSleepSummaryRefresh()
            AppAnalytics.shared.track(
                AnalyticsSignal.tabSelected,
                payload: ["Navigation.tab": selectedTab.rawValue]
            )
        }
        .onChange(of: selectedTab) { _, newValue in
            AppAnalytics.shared.track(
                AnalyticsSignal.tabSelected,
                payload: ["Navigation.tab": newValue.rawValue]
            )
        }
        .onReceive(dataManager.$workouts.dropFirst()) { _ in
            refreshOnboardingState()
            scheduleInsightsRefresh()
            scheduleVariantAnalysis()
            scheduleSimilarityAnalysis()
            schedulePendingSleepSummaryRefresh()
        }
        .onReceive(dataManager.$isLoading.dropFirst()) { isLoading in
            if !isLoading {
                refreshOnboardingState()
            }
        }
        .onReceive(healthManager.$authorizationStatus.dropFirst()) { newValue in
            guard newValue == .authorized else { return }
            schedulePendingSleepSummaryRefresh()
        }
        .onReceive(annotationsManager.$annotations) { _ in
            scheduleVariantAnalysis()
        }
        .onReceive(gymProfilesManager.$gyms) { _ in
            scheduleVariantAnalysis()
        }
        .onChange(of: relationshipManager.relationships) { _, _ in
            dataManager.refreshExerciseIdentityDerivedState()
            scheduleInsightsRefresh()
            scheduleVariantAnalysis()
            scheduleSimilarityAnalysis()
        }
        .onReceive(intentionalBreaksManager.$savedBreaks) { _ in
            scheduleInsightsRefresh()
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(
                isPresented: $showingOnboarding,
                dataManager: dataManager,
                iCloudManager: iCloudManager,
                hasSeenOnboarding: $hasSeenOnboarding
            )
        }
        .sheet(item: $changelogPresentation) { presentation in
            WhatsNewSheetView(presentation: presentation) {
                changelogStore.markSeen(version: presentation.latestVersion)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Theme.CornerRadius.xlarge)
        }
        .onChange(of: showingOnboarding) { _, isShowing in
            if !isShowing {
                presentChangelogIfReady()
            }
        }
        .onChange(of: hasCompletedInitialLoad) { _, isComplete in
            if isComplete {
                presentChangelogIfReady()
            }
        }
        .onReceive(sessionManager.$isPresentingSessionUI.dropFirst()) { isPresented in
            if !isPresented {
                presentChangelogIfReady()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ActiveSessionInset(
                sessionManager: sessionManager,
                isVisible: selectedTab != .today
            )
        }
    }

    private func refreshOnboardingState() {
        // Don't evaluate onboarding until the initial data load finishes
        // and no load is in-flight. Otherwise workouts.isEmpty is temporarily
        // true for returning users, causing the onboarding wizard to flash
        // briefly before data arrives.
        guard hasCompletedInitialLoad, !dataManager.isLoading else { return }

        // If the user already has workout data, permanently suppress onboarding
        // so it never flashes again — even during transient empty states.
        if !dataManager.workouts.isEmpty && !hasSeenOnboarding {
            hasSeenOnboarding = true
        }

        let shouldShow = !hasSeenOnboarding && dataManager.workouts.isEmpty
        if shouldShow {
            changelogStore.markCurrentVersionSeen()
        }
        showingOnboarding = shouldShow
    }

    private func startLaunchFlowIfNeeded() {
        guard !hasStartedLaunchFlow else { return }
        hasStartedLaunchFlow = true

        Task { @MainActor in
            await migrationManager.prepare()
            guard !migrationManager.blocksLaunch else { return }
            bootstrapStoresIfNeeded()
        }
    }

    private func continueAfterMigration() {
        migrationManager.dismiss()
        bootstrapStoresIfNeeded()
    }

    private func bootstrapStoresIfNeeded() {
        guard !hasBootstrappedStores else { return }
        hasBootstrappedStores = true

        Task { @MainActor in
            LegacyProgramCleanup.runIfNeeded()
            intentionalBreaksManager.reloadPersistedBreaks()
            async let annotationLoad: Void = annotationsManager.reloadPersistedAnnotations()
            async let gymLoad: Void = gymProfilesManager.reloadPersistedGyms()
            async let healthBootstrap: Void = healthManager.bootstrapPersistedDataIfNeeded()
            async let loggedWorkoutLoad: Void = logStore.load()
            _ = await (annotationLoad, gymLoad, healthBootstrap, loggedWorkoutLoad)
            await dataManager.setLoggedWorkoutsOffMain(logStore.workouts)
            await dataManager.reloadPersistedMigrationState()
            await importLatestNativeBackupIfNeeded()
            await sessionManager.restoreDraft()

            // Detect existing users before evaluating onboarding. CSV-imported
            // workout data loads later (in HomeView), so at this point
            // dataManager.workouts may still be empty for users whose data is
            // primarily from imports. A quick file-existence check prevents the
            // onboarding wizard from flashing for those users.
            if !hasSeenOnboarding {
                let hasLoggedData = !logStore.workouts.isEmpty
                let directories = await iCloudManager.storageSearchDirectories()
                let hasImportedFile = WorkoutDataManager.latestWorkoutFile(in: directories) != nil
                if hasLoggedData || hasImportedFile {
                    hasSeenOnboarding = true
                }
            }

            hasCompletedInitialLoad = true
            refreshOnboardingState()
            presentChangelogIfReady()
        }
    }

    private func presentChangelogIfReady() {
        guard hasCompletedInitialLoad else { return }
        guard !showingOnboarding else { return }
        guard !migrationManager.blocksLaunch else { return }
        guard !sessionManager.isPresentingSessionUI else { return }
        guard changelogPresentation == nil else { return }

        changelogPresentation = changelogStore.pendingPresentation()
    }

    private func importLatestNativeBackupIfNeeded() async {
        let directories = await iCloudManager.storageSearchDirectories()
        guard let backupFile = iCloudDocumentManager.latestBackupFile(in: directories) else { return }

        let signature = AppBackupService.importSourceSignature(for: backupFile)
        guard signature != AppBackupService.cachedNativeBackupSourceSignature() else { return }

        do {
            let backupData = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: backupFile)
            }.value
            let backup = try AppBackupService.decodeBackup(from: backupData)
            _ = try await AppBackupImporter.importBackup(
                backup,
                dataManager: dataManager,
                logStore: logStore,
                healthManager: healthManager,
                annotationsManager: annotationsManager,
                gymProfilesManager: gymProfilesManager,
                intentionalBreaksManager: intentionalBreaksManager
            )
            AppBackupService.persistNativeBackupSourceSignature(signature)
            if !dataManager.workouts.isEmpty {
                hasSeenOnboarding = true
            }
        } catch {
            print("Failed to import native backup on launch: \(error)")
        }
    }

    private func triggerVariantAnalysis() async {
        await variantEngine.analyze(
            workouts: dataManager.workouts,
            annotations: annotationsManager.annotations,
            gymNames: gymProfilesManager.gymNameSnapshot()
        )
    }

    private func scheduleInsightsRefresh(debounceNs: UInt64 = 250_000_000) {
        insightsRefreshTask?.cancel()
        insightsRefreshTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await insightsEngine.generateInsights()
        }
    }

    private func scheduleVariantAnalysis(debounceNs: UInt64 = 250_000_000) {
        variantAnalysisTask?.cancel()
        variantAnalysisTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await triggerVariantAnalysis()
        }
    }

    private func scheduleSimilarityAnalysis(debounceNs: UInt64 = 250_000_000) {
        similarityAnalysisTask?.cancel()
        similarityAnalysisTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await similarityEngine.analyze(workouts: dataManager.workouts)
        }
    }

    private func schedulePendingSleepSummaryRefresh(debounceNs: UInt64 = 250_000_000) {
        sleepSummaryRefreshTask?.cancel()
        sleepSummaryRefreshTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await healthManager.refreshPendingWorkoutSleepSummariesIfNeeded(
                workouts: dataManager.workouts
            )
        }
    }
}
