//
//  workout_appApp.swift
//  workout-app
//
//  Created by Davis Deaton on 12/30/25.
//

import SwiftUI

@main
struct WorkoutApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var ouraManager = OuraManager()
    @StateObject private var sessionManager = WorkoutSessionManager()

    init() {
        // Defaults for settings that are read outside SwiftUI views (e.g. analytics/services).
        UserDefaults.standard.register(defaults: [
            "intentionalRestDays": 1,
            "sessionsPerWeekGoal": 4,
            "weightUnit": "lbs",
            "weightIncrement": 2.5
        ])

        FontRegistrar.registerFontsIfNeeded()
        Theme.configureGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(healthManager)
                .environmentObject(ouraManager)
                .environmentObject(sessionManager)
                .buttonStyle(AppInteractionButtonStyle())
                .onOpenURL { url in
                    ouraManager.handleIncomingURL(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await ouraManager.autoRefreshOnForeground()
                }
                return
            }

            guard newPhase == .inactive || newPhase == .background else { return }
            sessionManager.saveImmediately()
        }
    }
}
