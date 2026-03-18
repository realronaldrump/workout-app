import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case today
    case health
    case history
    case profile
}

struct MainTabView: View {
    @StateObject private var dataManager = WorkoutDataManager()
    @StateObject private var iCloudManager = iCloudDocumentManager()
    @StateObject private var logStore = WorkoutLogStore()
    @StateObject private var annotationsManager: WorkoutAnnotationsManager
    @StateObject private var intentionalBreaksManager: IntentionalBreaksManager
    @StateObject private var gymProfilesManager: GymProfilesManager
    @StateObject private var insightsEngine: InsightsEngine
    @StateObject private var healthDateRangeContext = HealthDateRangeContext()
    @StateObject private var variantEngine = WorkoutVariantEngine()
    @StateObject private var similarityEngine = WorkoutSimilarityEngine()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingOnboarding = false
    @State private var pendingOnboarding = false
    @State private var selectedTab: AppTab = .today
    @State private var showSplash = true
    @State private var hasCompletedInitialLoad = false
    @State private var insightsRefreshTask: Task<Void, Never>?
    @State private var variantAnalysisTask: Task<Void, Never>?
    @State private var sleepSummaryRefreshTask: Task<Void, Never>?
    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @EnvironmentObject private var healthManager: HealthKitManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        let annotations = WorkoutAnnotationsManager()
        let intentionalBreaks = IntentionalBreaksManager()
        let gyms = GymProfilesManager(annotationsManager: annotations)
        let dataManager = WorkoutDataManager()
        _annotationsManager = StateObject(wrappedValue: annotations)
        _intentionalBreaksManager = StateObject(wrappedValue: intentionalBreaks)
        _gymProfilesManager = StateObject(wrappedValue: gyms)
        _dataManager = StateObject(wrappedValue: dataManager)
        _insightsEngine = StateObject(
            wrappedValue: InsightsEngine(
                dataManager: dataManager,
                annotationsProvider: { annotations.annotations },
                gymNameProvider: { gyms.gymNameSnapshot() }
            )
        )
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

            NavigationStack {
                HealthHubView()
            }
            .tabItem {
                Label("Health", systemImage: "heart.fill")
            }
            .tag(AppTab.health)

            NavigationStack {
                WorkoutHistoryView(workouts: dataManager.workouts, showsBackButton: false)
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
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(AppTab.profile)
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
        .overlay {
            if showSplash {
                InAppSplashView(statusText: "Stronger than Strong")
                    .transition(.opacity)
                    .zIndex(10)
                    .contentShape(Rectangle())
            }
        }
        .onAppear {
            beginSplashIfNeeded()
            refreshOnboardingState()
            bootstrapStoresIfNeeded()
            scheduleVariantAnalysis()
            schedulePendingSleepSummaryRefresh()
        }
        .onChange(of: dataManager.workouts) { _, _ in
            refreshOnboardingState()
            scheduleInsightsRefresh()
            scheduleVariantAnalysis()
            schedulePendingSleepSummaryRefresh()
        }
        .onChange(of: dataManager.isLoading) { _, isLoading in
            if !isLoading {
                refreshOnboardingState()
            }
        }
        .onChange(of: healthManager.authorizationStatus) { _, newValue in
            guard newValue == .authorized else { return }
            schedulePendingSleepSummaryRefresh()
        }
        .onReceive(annotationsManager.$annotations) { _ in
            scheduleVariantAnalysis()
        }
        .onReceive(gymProfilesManager.$gyms) { _ in
            scheduleVariantAnalysis()
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if sessionManager.activeSession != nil && !sessionManager.isPresentingSessionUI {
                ActiveSessionBar()
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(9)
            }
        }
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

    private func refreshOnboardingState() {
        // Don't evaluate onboarding until the initial data load finishes
        // and no load is in-flight. Otherwise workouts.isEmpty is temporarily
        // true for returning users, causing the onboarding wizard to flash
        // briefly before data arrives.
        guard hasCompletedInitialLoad, !dataManager.isLoading else { return }
        let shouldShow = !hasSeenOnboarding && dataManager.workouts.isEmpty
        if showSplash {
            pendingOnboarding = shouldShow
        } else {
            showingOnboarding = shouldShow
        }
    }

    private func beginSplashIfNeeded() {
        guard showSplash else { return }

        Task { @MainActor in
            // Make the brand moment feel intentional: allow the lockup to animate in,
            // then hold briefly before dismissing.
            let minVisibleNs: UInt64 = reduceMotion ? 650_000_000 : 1_200_000_000
            let fadeOutSeconds: Double = reduceMotion ? 0.2 : 0.45

            try? await Task.sleep(nanoseconds: minVisibleNs)

            // Subtle "closing" feedback to mark the transition into the app.
            Haptics.impact(.soft)

            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: fadeOutSeconds)) {
                showSplash = false
            }

            if pendingOnboarding {
                pendingOnboarding = false
                // Present onboarding only after the splash fades out.
                try? await Task.sleep(nanoseconds: UInt64(fadeOutSeconds * 1_000_000_000))
                showingOnboarding = true
            }
        }
    }

    private func bootstrapStoresIfNeeded() {
        Task { @MainActor in
            LegacyProgramCleanup.runIfNeeded()
            await logStore.load()
            dataManager.setLoggedWorkouts(logStore.workouts)
            await sessionManager.restoreDraft()
            hasCompletedInitialLoad = true
            refreshOnboardingState()
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
