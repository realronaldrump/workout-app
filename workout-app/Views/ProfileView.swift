import SwiftUI
import UIKit

struct ProfileView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @Binding var selectedTab: AppTab

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
    }

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Avatar with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.Colors.accent,
                                Color(uiColor: UIColor(hex: 0x3B82F6))
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: Theme.Colors.accent.opacity(0.25), radius: 16, x: 0, y: 8)

                Text(initials)
                    .font(Theme.Typography.avatarMonogram)
                    .foregroundStyle(.white)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text(displayName)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(0.8)

                if !profileName.isEmpty {
                    Text("Member")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(1.0)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                MetricTileButton(
                    chevronPlacement: .bottomTrailing,
                    action: {
                        showingWorkoutHistory = true
                    },
                    content: {
                        ProfileStat(title: "Workouts", value: "\(dataManager.workouts.count)", tint: Theme.Colors.accent)
                    }
                )
                .frame(maxWidth: .infinity)

                MetricTileButton(
                    chevronPlacement: .bottomTrailing,
                    action: {
                        showingExerciseList = true
                    },
                    content: {
                        ProfileStat(title: "Exercises", value: "\(uniqueExercisesCount)", tint: Theme.Colors.accentSecondary)
                    }
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .softCard()
    }

    private var personalInfoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionLabel(text: "Personal")

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

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionLabel(text: "Preferences")

            VStack(spacing: 1) {
                NavigationLink(destination: GymProfilesView()) {
                    ProfileLinkRow(
                        icon: "mappin.and.ellipse",
                        color: Theme.Colors.accent,
                        title: "Gym Profiles",
                        subtitle: "Manage saved gyms"
                    )
                }
                .buttonStyle(PlainButtonStyle())

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

                NavigationLink(
                    destination: SettingsView(
                        dataManager: dataManager,
                        iCloudManager: iCloudManager,
                        selectedTab: $selectedTab
                    )
                ) {
                    ProfileLinkRow(
                        icon: "gearshape.fill",
                        color: Theme.Colors.textTertiary,
                        title: "Settings",
                        subtitle: "Health, sync, units"
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
}

private struct ProfileFieldRow: View {
    let icon: String
    let color: Color
    let title: String
    let promptText: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(Theme.Typography.footnoteStrong)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                TextField(promptText, text: $text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .keyboardType(keyboardType)
            }

            Spacer()
        }
        .padding(Theme.Spacing.lg)
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
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(Theme.Typography.footnoteStrong)
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
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Image(systemName: "chevron.right")
                .font(Theme.Typography.caption2Bold)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

private struct ProfileStat: View {
    let title: String
    let value: String
    var tint: Color = Theme.Colors.accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
                .lineLimit(1)
            Text(value)
                .font(Theme.Typography.number)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .allowsTightening(true)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 80)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(tint.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(tint.opacity(0.12), lineWidth: 1)
        )
    }
}

/// Reusable section label used across Profile and Settings
private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.Typography.metricLabel)
            .foregroundStyle(Theme.Colors.textTertiary)
            .textCase(.uppercase)
            .tracking(1.2)
            .padding(.horizontal)
    }
}
