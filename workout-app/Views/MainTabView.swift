import SwiftUI

struct MainTabView: View {
    @StateObject private var dataManager = WorkoutDataManager()
    @StateObject private var iCloudManager = iCloudDocumentManager()
    
    var body: some View {
        TabView {
            DashboardView(dataManager: dataManager, iCloudManager: iCloudManager)
                .tabItem {
                    Label("Summary", systemImage: "chart.bar.fill")
                }
            
            NavigationView {
                WorkoutHistoryView(workouts: dataManager.workouts)
            }
            .tabItem {
                Label("History", systemImage: "clock.fill")
            }
            
            NavigationView {
                SettingsView(dataManager: dataManager, iCloudManager: iCloudManager)
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .tint(Theme.Colors.accent)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            appearance.backgroundColor = UIColor(Theme.Colors.background.opacity(0.5))
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
