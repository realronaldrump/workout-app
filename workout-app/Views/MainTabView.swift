import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home
    case health
    case progress
    case history
    case profile
}

struct MainTabView: View {
    @StateObject private var dataManager = WorkoutDataManager()
    @StateObject private var iCloudManager = iCloudDocumentManager()
    @StateObject private var annotationsManager: WorkoutAnnotationsManager
    @StateObject private var gymProfilesManager: GymProfilesManager
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingOnboarding = false
    @State private var pendingOnboarding = false
    @State private var selectedTab: AppTab = .home
    @State private var showSplash = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        let annotations = WorkoutAnnotationsManager()
        _annotationsManager = StateObject(wrappedValue: annotations)
        _gymProfilesManager = StateObject(wrappedValue: GymProfilesManager(annotationsManager: annotations))
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
                Label("Home", systemImage: "house.fill")
            }
            .tag(AppTab.home)

            NavigationStack {
                HealthHubView()
            }
            .tabItem {
                Label("Health", systemImage: "heart.fill")
            }
            .tag(AppTab.health)

            NavigationStack {
                DashboardView(
                    dataManager: dataManager,
                    iCloudManager: iCloudManager,
                    annotationsManager: annotationsManager,
                    gymProfilesManager: gymProfilesManager
                )
            }
            .tabItem {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(AppTab.progress)

            NavigationStack {
                WorkoutHistoryView(workouts: dataManager.workouts, showsBackButton: false)
            }
            .tabItem {
                Label("History", systemImage: "clock.fill")
            }
            .tag(AppTab.history)

            NavigationStack {
                ProfileView(dataManager: dataManager, iCloudManager: iCloudManager)
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(AppTab.profile)
            }
        }
        .environmentObject(dataManager)
        .environmentObject(annotationsManager)
        .environmentObject(gymProfilesManager)
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
        }
        .onChange(of: dataManager.workouts.count) { _, _ in
            refreshOnboardingState()
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(
                isPresented: $showingOnboarding,
                dataManager: dataManager,
                iCloudManager: iCloudManager,
                hasSeenOnboarding: $hasSeenOnboarding
            )
        }
    }

    private func refreshOnboardingState() {
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
            let minVisibleNs: UInt64 = reduceMotion ? 900_000_000 : 2_750_000_000
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
}
