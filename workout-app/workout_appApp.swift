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
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(healthManager)
        }
    }
}
