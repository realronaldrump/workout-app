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
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(
                            Circle()
                                .fill(Theme.accentGradient)
                        )
                        .shadow(color: Theme.Colors.accent.opacity(0.25), radius: 12, y: 4)
                        .shadow(color: Theme.Colors.accent.opacity(0.10), radius: 24, y: 8)

                    Text("Settings")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
                .animateOnAppear()

                // Data Management Section
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SettingsSectionLabel("DATA & SYNC")

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
                            SettingsInlineRow(
                                icon: "square.and.arrow.up",
                                color: Theme.Colors.accentSecondary,
                                title: "Export Data",
                                subtitle: "CSV backup"
                            )
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
                            SettingsInlineRow(
                                icon: "icloud.fill",
                                color: Theme.Colors.cardio,
                                title: "Backups",
                                subtitle: "iCloud"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Preferences Section
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SettingsSectionLabel("PREFERENCES")

                    VStack(spacing: 1) {
                        // Weight increment
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "ruler.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.accentSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

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
                        .softCard(elevation: 1)

                        Divider().padding(.leading, 50)

                        // Intentional rest window (used for streak/consistency calculations)
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "bed.double.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

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
                        .softCard(elevation: 1)

                        Divider().padding(.leading, 50)

                        // Sessions per week goal (used by consistency visualization)
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "target")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.success)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

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
                        .softCard(elevation: 1)

                        Divider().padding(.leading, 50)

                        // Gym & Exercise Tags
                        NavigationLink(destination: GymProfilesView()) {
                            SettingsInlineRow(
                                icon: "mappin.and.ellipse",
                                color: Theme.Colors.accent,
                                title: "Gym Profiles",
                                subtitle: "Tag workouts by location"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 50)

                        NavigationLink(destination: ExerciseTaggingView(dataManager: dataManager)) {
                            SettingsInlineRow(
                                icon: "tag.fill",
                                color: Theme.Colors.accentTertiary,
                                title: "Exercise Tags",
                                subtitle: "Assign muscle groups"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Danger Zone
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SettingsSectionLabel("DANGER ZONE")

                    Button(
                        action: { showingDeleteAlert = true },
                        label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Theme.Colors.error)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                                Text("Clear All Data")
                                    .font(Theme.Typography.bodyBold)
                                    .foregroundStyle(Theme.Colors.error)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.Colors.error.opacity(0.5))
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .fill(Theme.Colors.error.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .strokeBorder(Theme.Colors.error.opacity(0.15), lineWidth: 1)
                            )
                        }
                    )
                    .buttonStyle(AppInteractionButtonStyle())
                }

                VStack(spacing: Theme.Spacing.xs) {
                    Text("Davis's Big Beautiful Workout App")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textTertiary)

                    Text("Version 1.0.0")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.top, Theme.Spacing.md)
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

// MARK: - Settings Helper Views

private struct SettingsSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.Typography.metricLabel)
            .foregroundStyle(Theme.Colors.textTertiary)
            .tracking(1.2)
            .padding(.horizontal)
    }
}

private struct SettingsInlineRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding()
        .softCard(elevation: 1)
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
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                VStack(alignment: .leading, spacing: 2) {
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
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding()
            .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
    }
}
