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
                LazyVStack(spacing: Theme.Spacing.xl) {
                    headerSection
                    personalInfoSection
                    preferencesSection
                }
                .padding()
                .contentColumn()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
        .analyticsScreen("Profile")
        .navigationDestination(isPresented: $showingWorkoutHistory) {
            WorkoutHistoryView(workouts: dataManager.workouts, showsBackButton: true)
        }
        .navigationDestination(isPresented: $showingExerciseList) {
            ExerciseListView(dataManager: dataManager)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Text(initials)
                    .font(Theme.Typography.avatarMonogram)
                    .foregroundStyle(Theme.Colors.onHeroAccent)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(Color.white))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 3).padding(-4))
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    BrandBandLabel(text: memberBadge, fill: .white, textColor: Theme.Colors.onHeroAccent)
                    Text(displayName)
                        .font(Theme.Typography.displayHeroCompact)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                .accessibilityElement(children: .combine)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.sm) {
                    profileStats
                }

                VStack(spacing: Theme.Spacing.sm) {
                    profileStats
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(HeroCardBackground(watermark: "trophy.fill"))
    }

    private var memberBadge: String {
        guard let firstDate = dataManager.workouts.last?.date else { return "New lifter" }
        return "Lifting since \(firstDate.formatted(.dateTime.year()))"
    }

    @ViewBuilder
    private var profileStats: some View {
        heroStat(title: "Workouts", value: "\(dataManager.workouts.count)") {
            showingWorkoutHistory = true
        }
        .accessibilityLabel(SharedFormatters.count(dataManager.workouts.count, "workout"))
        .accessibilityHint("Double tap to view workout history")

        heroStat(title: "Exercises", value: "\(uniqueExercisesCount)") {
            showingExerciseList = true
        }
        .accessibilityLabel(SharedFormatters.count(uniqueExercisesCount, "exercise"))
        .accessibilityHint("Double tap to view exercise list")
    }

    private func heroStat(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(Theme.Typography.number)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                    Text(title)
                        .font(Theme.Typography.metricLabel)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "arrow.up.right")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                    .fill(Color.black.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardButtonStyle())
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

            VStack(spacing: 0) {
                NavigationLink(destination: FeatureGuidesView(iCloudManager: iCloudManager)) {
                    ProfileLinkRow(
                        icon: "book.fill",
                        color: Theme.Colors.accent,
                        title: "Feature Guides",
                        subtitle: "Learn how everything works"
                    )
                }
                .buttonStyle(PressableCardButtonStyle())

                Divider().padding(.leading, 66)

                NavigationLink(destination: ChangelogHistoryView()) {
                    ProfileLinkRow(
                        icon: "sparkles",
                        color: Theme.Colors.accentTertiary,
                        title: "What's New",
                        subtitle: "Release notes and update history"
                    )
                }
                .buttonStyle(PressableCardButtonStyle())

                Divider().padding(.leading, 66)

                NavigationLink(
                    destination: SettingsView(
                        dataManager: dataManager,
                        iCloudManager: iCloudManager,
                        selectedTab: $selectedTab
                    )
                ) {
                    ProfileLinkRow(
                        icon: "gearshape.fill",
                        color: Color(uiColor: .systemGray),
                        title: "Settings",
                        subtitle: "Health, sync, units"
                    )
                }
                .buttonStyle(PressableCardButtonStyle())
            }
            .softCard(elevation: 1)
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
        dataManager.allExerciseNames().count
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
            IconTile(systemImage: icon, tint: color, size: 32)

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
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
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
            IconTile(systemImage: icon, tint: color, size: 32)

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
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
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
