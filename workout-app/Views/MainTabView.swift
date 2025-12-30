import SwiftUI

struct MainTabView: View {
    @StateObject private var dataManager = WorkoutDataManager()
    @StateObject private var iCloudManager = iCloudDocumentManager()
    @StateObject private var luminanceManager = AdaptiveLuminanceManager()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingOnboarding = false
    
    var body: some View {
        NavigationStack {
            DashboardView(dataManager: dataManager, iCloudManager: iCloudManager)
        }
        .environmentObject(dataManager)
        .tint(Theme.Colors.accent)
        .environment(\.adaptiveLuminance, luminanceManager.luminance)
        .preferredColorScheme(.dark)
        .onAppear { refreshOnboardingState() }
        .onChange(of: dataManager.workouts.count) { _ in
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
