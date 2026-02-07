//
//  workout_appApp.swift
//  workout-app
//
//  Created by Davis Deaton on 12/30/25.
//

import SwiftUI

@main
struct WorkoutApp: App {
    @StateObject private var healthManager = HealthKitManager()

    init() {
        FontRegistrar.registerFontsIfNeeded()
        Theme.configureGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(healthManager)
        }
    }
}
