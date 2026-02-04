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
    @StateObject private var luminanceManager = AdaptiveLuminanceManager()
    @StateObject private var annotationsManager: WorkoutAnnotationsManager
    @StateObject private var gymProfilesManager: GymProfilesManager
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingOnboarding = false
    @State private var selectedTab: AppTab = .home

    init() {
        let annotations = WorkoutAnnotationsManager()
        _annotationsManager = StateObject(wrappedValue: annotations)
        _gymProfilesManager = StateObject(wrappedValue: GymProfilesManager(annotationsManager: annotations))
    }
    
    var body: some View {
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
                WorkoutHistoryView(workouts: dataManager.workouts)
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
        .environmentObject(dataManager)
        .environmentObject(annotationsManager)
        .environmentObject(gymProfilesManager)
        .tint(Theme.Colors.accent)
        .environment(\.adaptiveLuminance, luminanceManager.luminance)
        .preferredColorScheme(.dark)
        .onAppear { refreshOnboardingState() }
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
        showingOnboarding = !hasSeenOnboarding && dataManager.workouts.isEmpty
    }
}
