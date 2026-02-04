import SwiftUI

struct MainTabView: View {
    @StateObject private var dataManager = WorkoutDataManager()
    @StateObject private var iCloudManager = iCloudDocumentManager()
    @StateObject private var luminanceManager = AdaptiveLuminanceManager()
    @StateObject private var annotationsManager: WorkoutAnnotationsManager
    @StateObject private var gymProfilesManager: GymProfilesManager
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingOnboarding = false

    init() {
        let annotations = WorkoutAnnotationsManager()
        _annotationsManager = StateObject(wrappedValue: annotations)
        _gymProfilesManager = StateObject(wrappedValue: GymProfilesManager(annotationsManager: annotations))
    }
    
    var body: some View {
        TabView {
            NavigationStack {
                HomeView(
                    dataManager: dataManager,
                    iCloudManager: iCloudManager,
                    annotationsManager: annotationsManager,
                    gymProfilesManager: gymProfilesManager
                )
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

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

            NavigationStack {
                WorkoutHistoryView(workouts: dataManager.workouts)
            }
            .tabItem {
                Label("History", systemImage: "clock.fill")
            }

            NavigationStack {
                ProfileView(dataManager: dataManager, iCloudManager: iCloudManager)
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
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
