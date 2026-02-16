import SwiftUI
import UIKit

struct ProfileView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var ouraManager: OuraManager

    @State private var showingHealthWizard = false
    @State private var showingHealthDashboard = false
    @State private var showingOuraActions = false
    @State private var showingWorkoutHistory = false
    @State private var showingExerciseList = false

    @AppStorage("profileName") private var profileName = ""

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(spacing: Theme.Spacing.xxl) {
                    headerSection
                    personalInfoSection
                    connectionsSection
                    preferencesSection
                }
                .padding()
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showingWorkoutHistory) {
            WorkoutHistoryView(workouts: dataManager.workouts, showsBackButton: true)
        }
        .navigationDestination(isPresented: $showingExerciseList) {
            ExerciseListView(dataManager: dataManager)
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
        .confirmationDialog("Oura Actions", isPresented: $showingOuraActions, titleVisibility: .visible) {
            Button("Sync Now") {
                Task {
                    await ouraManager.manualRefresh()
                }
            }
            Button("Disconnect Oura", role: .destructive) {
                Task {
                    await ouraManager.disconnect()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            Task {
                await ouraManager.refreshConnectionStatus()
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Theme.Colors.accent)
                    .frame(width: 96, height: 96)

                Text(initials)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.white)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(Theme.Colors.border, lineWidth: 3)
            )

            VStack(spacing: Theme.Spacing.xs) {
                Text(displayName)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(1.0)
            }

            HStack(spacing: Theme.Spacing.md) {
                MetricTileButton(
                    chevronPlacement: .bottomTrailing,
                    action: {
                        showingWorkoutHistory = true
                    },
                    content: {
                        ProfileStat(title: "Workouts", value: "\(dataManager.workouts.count)")
                    }
                )
                .frame(maxWidth: .infinity)

                MetricTileButton(
                    chevronPlacement: .bottomTrailing,
                    action: {
                        showingExerciseList = true
                    },
                    content: {
                        ProfileStat(title: "Exercises", value: "\(uniqueExercisesCount)")
                    }
                )
                .frame(maxWidth: .infinity)
            }
            // Keep these tiles inset from the header card border so they don't visually
            // "kiss" the edges of the top square/card.
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .softCard()
    }

    private var personalInfoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Personal")
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(1.0)
                .padding(.horizontal)

            VStack(spacing: Theme.Spacing.sm) {
                ProfileFieldRow(
                    icon: "person.fill",
                    color: Theme.Colors.accent,
                    title: "Name",
                    promptText: "Name",
                    text: $profileName
                )

            }
        }
    }

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Connections")
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(1.0)
                .padding(.horizontal)

            VStack(spacing: 1) {
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

                SettingsRow(
                    icon: "moon.stars.fill",
                    color: Theme.Colors.accentSecondary,
                    title: "Oura",
                    subtitle: ouraSubtitleText,
                    value: ouraValueText
                ) {
                    handleOuraRowTapped()
                }

                Divider().padding(.leading, 50)

                NavigationLink(destination: BackupFilesView(iCloudManager: iCloudManager)) {
                    ProfileLinkRow(
                        icon: "icloud.fill",
                        color: Theme.Colors.cardio,
                        title: "Backups",
                        subtitle: "iCloud",
                        value: iCloudStatusText
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Preferences")
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(1.0)
                .padding(.horizontal)

            VStack(spacing: 1) {
                NavigationLink(destination: ExerciseTaggingView(dataManager: dataManager)) {
                    ProfileLinkRow(
                        icon: "tag.fill",
                        color: Theme.Colors.accentTertiary,
                        title: "Exercise Tags",
                        subtitle: "Assign muscle groups"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Divider().padding(.leading, 50)

                NavigationLink(destination: SettingsView(dataManager: dataManager, iCloudManager: iCloudManager)) {
                    ProfileLinkRow(
                        icon: "gearshape.fill",
                        color: Theme.Colors.textTertiary,
                        title: "Settings",
                        subtitle: "Sync, units, tags"
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var displayName: String {
        profileName.isEmpty ? "Your Profile" : profileName
    }

    private var initials: String {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        let fallback = "ME"
        return letters.isEmpty ? fallback : String(letters)
    }

    private var uniqueExercisesCount: Int {
        let names = dataManager.workouts.flatMap { $0.exercises.map(\.name) }
        return Set(names).count
    }

    private var iCloudStatusText: String {
        if iCloudManager.isInitializing {
            return "Checking"
        }

        return iCloudManager.isUsingLocalFallback ? "Local" : "Connected"
    }

    private var ouraSubtitleText: String {
        switch ouraManager.connectionStatus {
        case .connected:
            return "Scores synced"
        case .syncing:
            return "Syncing"
        case .connecting:
            return "Waiting for authorization"
        case .error(let message):
            return message
        case .notConnected:
            return "Not connected"
        }
    }

    private var ouraValueText: String {
        switch ouraManager.connectionStatus {
        case .connected, .syncing:
            return "On"
        case .connecting:
            return "Pending"
        case .error:
            return "Error"
        case .notConnected:
            return "Off"
        }
    }

    private func handleOuraRowTapped() {
        switch ouraManager.connectionStatus {
        case .notConnected, .error:
            Task {
                await ouraManager.startConnectionFlow()
            }
        case .connecting:
            return
        case .connected, .syncing:
            showingOuraActions = true
        }
    }
}

private struct ProfileFieldRow: View {
    let icon: String
    let color: Color
    let title: String
    let promptText: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .cornerRadius(Theme.CornerRadius.small)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)

                TextField(promptText, text: $text)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .keyboardType(keyboardType)
            }

            Spacer()
        }
        .padding()
        .softCard()
    }
}

private struct ProfileLinkRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var value: String?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .cornerRadius(Theme.CornerRadius.small)

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

private struct ProfileStat: View {
    let title: String
    let value: String

    // Slightly smaller than the dashboard stat tiles so they sit comfortably under the avatar.
    private let tileHeight: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .lineLimit(1)
            Text(value)
                .font(Theme.Typography.number)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .allowsTightening(true)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: tileHeight)
        .softCard(elevation: 1)
    }
}
