import SwiftUI

struct SettingsView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var logStore: WorkoutLogStore
    @EnvironmentObject var sessionManager: WorkoutSessionManager

    @State private var showingImportWizard = false
    @State private var showingHealthWizard = false
    @State private var showingHealthDashboard = false
    @State private var showingDeleteAlert = false

    @AppStorage("weightIncrement") private var weightIncrement: Double = 2.5
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1
    @AppStorage("sessionsPerWeekGoal") private var sessionsPerWeekGoal: Int = 4

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
                        .background(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                .fill(Theme.Colors.accent)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                .strokeBorder(Theme.Colors.border, lineWidth: 2)
                        )
                        .shadow(color: Color.black.opacity(Theme.Colors.shadowOpacity), radius: 0, x: 4, y: 4)

                    Text("Settings")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.5)
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
                            color: Theme.Colors.accent,
                            title: "Import Data",
                            subtitle: "Import CSV"
                        ) {
                            showingImportWizard = true
                        }

                        Divider().padding(.leading, 50)

                        NavigationLink(destination: ExportWorkoutsView(dataManager: dataManager, iCloudManager: iCloudManager)) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Theme.Colors.accentSecondary)
                                    .cornerRadius(6)

                                VStack(alignment: .leading) {
                                    Text("Export Data")
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text("CSV backup")
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

                        SettingsRow(
                            icon: "heart.fill",
                            color: Theme.Colors.error,
                            title: "Apple Health",
                            subtitle: healthManager.authorizationStatus == .authorized ? "Connected" : "Health off",
                            value: healthManager.authorizationStatus == .authorized ? "On" : "Off"
                        ) {
                            if healthManager.authorizationStatus == .authorized {
                                showingHealthDashboard = true
                            } else {
                                showingHealthWizard = true
                            }
                        }

                        Divider().padding(.leading, 50)

                        if healthManager.authorizationStatus == .authorized {
                            SettingsRow(
                                icon: "chart.xyaxis.line",
                                color: Theme.Colors.accentSecondary,
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
                                    .background(Theme.Colors.cardio)
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
                        // Weight increment
                        HStack {
                            Image(systemName: "ruler.fill")
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.Colors.accentSecondary)
                                .cornerRadius(6)

                            Text("Weight Increment")
                                .font(Theme.Typography.body)

                            Spacer()

                            Picker("", selection: $weightIncrement) {
                                ForEach(incrementOptions, id: \.self) { option in
                                    Text(incrementLabel(option)).tag(option)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding()
                        .softCard()

                        Divider().padding(.leading, 50)

                        // Intentional rest window (used for streak/consistency calculations)
                        HStack {
                            Image(systemName: "bed.double.fill")
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.Colors.accent)
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Intentional Rest")
                                    .font(Theme.Typography.body)
                                Text("Allow up to \(intentionalRestDays) day\(intentionalRestDays == 1 ? "" : "s") off without breaking streaks")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            Picker("", selection: $intentionalRestDays) {
                                ForEach(0...30, id: \.self) { days in
                                    Text("\(days) day\(days == 1 ? "" : "s")").tag(days)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding()
                        .softCard()

                        Divider().padding(.leading, 50)

                        // Sessions per week goal (used by consistency visualization)
                        HStack {
                            Image(systemName: "target")
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.Colors.success)
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sessions / Week Goal")
                                    .font(Theme.Typography.body)
                                Text("Used by consistency goal markers")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            Picker("", selection: $sessionsPerWeekGoal) {
                                ForEach(1...14, id: \.self) { sessions in
                                    Text("\(sessions)/wk").tag(sessions)
                                }
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
                                    .background(Theme.Colors.accent)
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
                                    .background(Theme.Colors.accentTertiary)
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
                Button(
                    action: { showingDeleteAlert = true },
                    label: {
                        Text("Clear All Data")
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(Theme.Colors.error)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .softCard()
                    }
                )
                .buttonStyle(.plain)

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
                    await logStore.clearAll()
                    await sessionManager.discardDraft()
                    await MainActor.run {
                        healthManager.clearAllData()
                        dataManager.clearAllData()
                    }
                }
            }
        } message: {
            Text(
                "WARNING: This will permanently delete all imported CSV files, logged workouts, " +
                "active session drafts, and health data from your device. This action cannot be undone."
            )
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            normalizeIncrementIfNeeded()
            normalizeSessionsGoalIfNeeded()
        }
    }

    private var incrementOptions: [Double] {
        [1.25, 2.5, 5.0]
    }

    private func incrementLabel(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func normalizeIncrementIfNeeded() {
        if !incrementOptions.contains(where: { abs($0 - weightIncrement) < 0.0001 }) {
            weightIncrement = 2.5
        }
        if weightIncrement <= 0 {
            weightIncrement = 2.5
        }
    }

    private func normalizeSessionsGoalIfNeeded() {
        if sessionsPerWeekGoal < 1 {
            sessionsPerWeekGoal = 1
        } else if sessionsPerWeekGoal > 14 {
            sessionsPerWeekGoal = 14
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var value: String?
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
        .buttonStyle(.plain)
    }
}
