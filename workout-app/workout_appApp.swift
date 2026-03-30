//
//  workout_appApp.swift
//  workout-app
//
//  Created by Davis Deaton on 12/30/25.
//

import SwiftUI

/// User-selectable appearance mode stored via @AppStorage.
enum AppearanceMode: Int, CaseIterable {
    case system = 0
    case light  = 1
    case dark   = 2

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

@main
struct WorkoutApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var sessionManager = WorkoutSessionManager()
    @AppStorage("appearanceMode") private var appearanceMode: Int = AppearanceMode.system.rawValue

    init() {
        // Defaults for settings that are read outside SwiftUI views (e.g. analytics/services).
        UserDefaults.standard.register(defaults: [
            "intentionalRestDays": 1,
            "sessionsPerWeekGoal": 4,
            "weightUnit": "lbs",
            "weightIncrement": 2.5,
            "preferredSleepSourceKey": "",
            "preferredSleepSourceName": "",
            "appearanceMode": AppearanceMode.system.rawValue,
            AppAnalytics.collectionEnabledKey: true
        ])

        AppAnalytics.shared.configureIfNeeded()
        FontRegistrar.registerFontsIfNeeded()
        Theme.configureGlobalAppearance()
    }

    private var resolvedColorScheme: ColorScheme? {
        (AppearanceMode(rawValue: appearanceMode) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .font(Theme.Typography.body)
                .environmentObject(healthManager)
                .environmentObject(sessionManager)
                .buttonStyle(AppInteractionButtonStyle())
                .preferredColorScheme(resolvedColorScheme)
        }
        .onChange(of: scenePhase) { _, newPhase in
            AppAnalytics.shared.handleScenePhaseChange(newPhase)
            guard newPhase == .inactive || newPhase == .background else { return }
            sessionManager.saveImmediately()
        }
    }
}
