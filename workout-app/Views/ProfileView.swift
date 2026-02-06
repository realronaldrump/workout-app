import SwiftUI
import UIKit

struct ProfileView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @EnvironmentObject var healthManager: HealthKitManager

    @State private var showingHealthWizard = false
    @State private var showingHealthDashboard = false
    @State private var showingWorkoutHistory = false
    @State private var showingExerciseList = false

    @AppStorage("profileName") private var profileName = ""
    @AppStorage("weightUnit") private var weightUnit = "lbs"
    @AppStorage("dateFormat") private var dateFormat = "relative"

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
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
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
        .onAppear {
            healthManager.refreshAuthorizationStatus()
        }
    }

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.surface)
                    .frame(width: 96, height: 96)

                Text(initials)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .overlay(
                Circle()
                    .strokeBorder(Theme.Colors.textTertiary, lineWidth: 1)
            )

            VStack(spacing: Theme.Spacing.xs) {
                Text(displayName)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            HStack(spacing: Theme.Spacing.md) {
                MetricTileButton(chevronPlacement: .bottomTrailing, action: {
                    showingWorkoutHistory = true
                }) {
                    ProfileStat(title: "Workouts", value: "\(dataManager.workouts.count)")
                }
                .frame(maxWidth: .infinity)
                
                MetricTileButton(chevronPlacement: .bottomTrailing, action: {
                    showingExerciseList = true
                }) {
                    ProfileStat(title: "Exercises", value: "\(uniqueExercisesCount)")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .softCard()
    }

    private var personalInfoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Personal")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal)

            VStack(spacing: Theme.Spacing.sm) {
                ProfileFieldRow(
                    icon: "person.fill",
                    color: Theme.Colors.accent,
                    title: "Name",
                    placeholder: "Name",
                    text: $profileName
                )

            }
        }
    }

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Connections")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
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
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal)

            VStack(spacing: 1) {
                HStack {
                    Image(systemName: "scalemass.fill")
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.Colors.success)
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

                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.Colors.warning)
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
}

private struct ProfileFieldRow: View {
    let icon: String
    let color: Color
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)

                TextField(placeholder, text: $text)
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
    var value: String? = nil

    var body: some View {
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

private struct ProfileStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Typography.number)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface.opacity(0.5))
        .cornerRadius(Theme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(Theme.Colors.border.opacity(0.5), lineWidth: 1)
        )
    }
}
