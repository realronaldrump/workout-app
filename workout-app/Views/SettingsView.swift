import SwiftUI

struct SettingsView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @EnvironmentObject var healthManager: HealthKitManager
    
    @State private var showingImportWizard = false
    @State private var showingHealthWizard = false
    @State private var showingHealthDashboard = false
    @State private var showingDeleteAlert = false
    
    @AppStorage("weightUnit") private var weightUnit = "lbs"
    @AppStorage("dateFormat") private var dateFormat = "relative"
    
    var body: some View {
        ZStack {
            AdaptiveBackground()
            
            ScrollView {
                VStack(spacing: Theme.Spacing.xxl) {
                // Header
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white)
                        .padding()
                        .background(Theme.Colors.accent)
                        .clipShape(Circle())
                        .shadow(radius: 10)
                    
                    Text("Settings")
                        .font(Theme.Typography.largeTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
                
                // Data Management Section
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Data & Sync")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal)
                    
                    VStack(spacing: 1) {
                        SettingsRow(
                            icon: "square.and.arrow.down",
                            color: .blue,
                            title: "Import Data",
                            subtitle: "Import CSV"
                        ) {
                            showingImportWizard = true
                        }
                        
                        Divider().padding(.leading, 50)
                        
                        SettingsRow(
                            icon: "heart.fill",
                            color: .red,
                            title: "Apple Health",
                            subtitle: healthManager.authorizationStatus == .authorized ? "Connected" : "Health off",
                            value: healthManager.authorizationStatus == .authorized ? "On" : "Off"
                        ) {
                            showingHealthWizard = true
                        }
                        
                        Divider().padding(.leading, 50)
                        
                        if healthManager.authorizationStatus == .authorized {
                            SettingsRow(
                                icon: "chart.xyaxis.line",
                                color: .pink,
                                title: "Health Insights",
                                subtitle: "Trends"
                            ) {
                                showingHealthDashboard = true
                            }
                            
                            Divider().padding(.leading, 50)
                        }
                        
                        NavigationLink(destination: BackupFilesView(iCloudManager: iCloudManager)) {
                            HStack {
                                Image(systemName: "icloud.fill")
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.cyan)
                                    .cornerRadius(6)
                                
                                VStack(alignment: .leading) {
                                    Text("Backups")
                                        .font(Theme.Typography.body)
                                    Text("iCloud")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .padding()
                            .softCard()
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                // Preferences Section
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Preferences")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal)
                    
                    VStack(spacing: 1) {
                        // Custom Picker Row for Weight
                        HStack {
                            Image(systemName: "scalemass.fill")
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.green)
                                .cornerRadius(6)
                            
                            Text("Weight Unit")
                                .font(Theme.Typography.body)
                            
                            Spacer()
                            
                            Picker("", selection: $weightUnit) {
                                Text("lbs").tag("lbs")
                                Text("kg").tag("kg")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding()
                        .softCard()
                        
                        Divider().padding(.leading, 50)
                        
                        // Custom Picker Row for Date
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.orange)
                                .cornerRadius(6)
                            
                            Text("Date Format")
                                .font(Theme.Typography.body)
                            
                            Spacer()
                            
                            Picker("", selection: $dateFormat) {
                                Text("Relative").tag("relative")
                                Text("Absolute").tag("absolute")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding()
                        .softCard()
                        
                        Divider().padding(.leading, 50)
                        
                        // Exercise Tags
                        NavigationLink(destination: GymProfilesView()) {
                            HStack {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.indigo)
                                    .cornerRadius(6)
                                
                                VStack(alignment: .leading) {
                                    Text("Gym Profiles")
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text("Tag workouts by location")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .padding()
                            .softCard()
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Divider().padding(.leading, 50)
                        
                        NavigationLink(destination: ExerciseTaggingView(dataManager: dataManager)) {
                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.purple)
                                    .cornerRadius(6)
                                
                                VStack(alignment: .leading) {
                                    Text("Exercise Tags")
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text("Assign muscle groups")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .padding()
                            .softCard()
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                // Danger Zone
                Button(action: { showingDeleteAlert = true }) {
                    Text("Clear All Data")
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .softCard()
                }
                
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Davis's Big Beautiful Workout App")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textTertiary)

                    Text("Version 1.0.0")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.top, Theme.Spacing.sm)
                }
                .padding()
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingImportWizard) {
            StrongImportWizard(
                isPresented: $showingImportWizard,
                dataManager: dataManager,
                iCloudManager: iCloudManager
            )
        }
        .sheet(isPresented: $showingHealthWizard) {
            HealthSyncWizard(
                isPresented: $showingHealthWizard,
                workouts: dataManager.workouts
            )
        }
        .sheet(isPresented: $showingHealthDashboard) {
            HealthDashboardView()
        }
        .alert("Clear All Data", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await iCloudManager.deleteAllWorkoutFiles()
                    await MainActor.run {
                        healthManager.clearAllData()
                        dataManager.clearAllData()
                    }
                }
            }
        } message: {
            Text("WARNING: This will permanently delete all imported CSV files and health data from your device. This action cannot be undone.")
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var value: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color)
                    .cornerRadius(6)
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Spacer()
                
                if let value = value {
                    Text(value)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding()
            .softCard(elevation: 1)
        }
    }
}
