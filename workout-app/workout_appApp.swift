//
//  workout_appApp.swift
//  workout-app
//
//  Created by Davis Deaton on 12/30/25.
//

import SwiftUI

@main
struct workout_appApp: App {
    @StateObject private var healthManager = HealthKitManager()
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    init() {
        FontRegistrar.registerFontsIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(healthManager)
                .preferredColorScheme(colorScheme)
        }
    }
    
    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil  // System default
        }
    }
}
