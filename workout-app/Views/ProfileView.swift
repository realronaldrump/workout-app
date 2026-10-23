import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @Binding var selectedTab: AppTab

    @State private var showingWorkoutHistory = false
    @State private var showingExerciseList = false
    @State private var lifetimeVolume: Double = 0

    @AppStorage("profileName") private var profileName = ""

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    headerSection
                    preferencesSection
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xxl)
                .contentColumn()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
        .analyticsScreen("Profile")
        .task(id: dataManager.datasetRevision) {
            await refreshLifetimeVolume()
        }
        .navigationDestination(isPresented: $showingWorkoutHistory) {
            WorkoutHistoryView(workouts: dataManager.workouts, showsBackButton: true)
        }
        .navigationDestination(isPresented: $showingExerciseList) {
            ExerciseListView(dataManager: dataManager)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(displayName)
                    .font(Theme.Typography.displayHero)
                    .foregroundStyle(profileName.isEmpty ? Theme.Colors.decorativeSubtle : Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(memberBadge)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)

            ProfileFieldRow(
                title: "Name",
                promptText: "Add your name",
                text: $profileName
            )

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
                : AnyLayout(StatColumns())
            layout {
                profileStats
            }
            .padding(.vertical, Theme.Spacing.lg)
            .padding(.horizontal, Theme.Spacing.md)
            .softCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memberBadge: String {
        guard let firstDate = dataManager.workouts.last?.date else { return "No workouts logged yet." }
        return "Lifting since \(firstDate.formatted(.dateTime.month(.wide).year()))."
    }

    @ViewBuilder
    private var profileStats: some View {
        heroStat(title: dataManager.workouts.count == 1 ? "workout" : "workouts", value: "\(dataManager.workouts.count)") {
            showingWorkoutHistory = true
        }
        .accessibilityLabel(SharedFormatters.count(dataManager.workouts.count, "workout"))
        .accessibilityHint("Opens workout history")

        heroStat(title: uniqueExercisesCount == 1 ? "exercise" : "exercises", value: "\(uniqueExercisesCount)") {
            showingExerciseList = true
        }
        .accessibilityLabel(SharedFormatters.count(uniqueExercisesCount, "exercise"))
        .accessibilityHint("Opens exercise list")

        heroStat(title: "lbs lifted", value: SharedFormatters.volumeCompact(lifetimeVolume)) {
            showingWorkoutHistory = true
        }
        .accessibilityLabel("\(SharedFormatters.volumeWithUnit(lifetimeVolume)) lifted")
        .accessibilityHint("Opens workout history")
    }

    private func heroStat(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            DisplayStat(value: value, label: title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.xs)
                .contentShape(.rect)
        }
        .buttonStyle(PressableCardButtonStyle())
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(title: "App")

            VStack(spacing: 0) {
                NavigationLink(destination: FeatureGuidesView(iCloudManager: iCloudManager)) {
                    ExploreRow(title: "Feature guides", subtitle: "Walkthroughs of the main screens", showsRule: false)
                }
                .buttonStyle(PressableCardButtonStyle())

                NavigationLink(destination: ChangelogHistoryView()) {
                    ExploreRow(title: "What's new", subtitle: "Release notes for each version")
                }
                .buttonStyle(PressableCardButtonStyle())

                NavigationLink(
                    destination: SettingsView(
                        dataManager: dataManager,
                        iCloudManager: iCloudManager,
                        selectedTab: $selectedTab
                    )
                ) {
                    ExploreRow(title: "Settings", subtitle: "Training, Apple Health, data, and appearance")
                }
                .buttonStyle(PressableCardButtonStyle())
            }
        }
    }

    private var displayName: String {
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Your name" : name
    }

    /// Matches History's total: relationship-aggregated volume per workout.
    private func refreshLifetimeVolume() async {
        let workouts = dataManager.workouts
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()
        let total = await Task.detached(priority: .utility) {
            workouts.reduce(0) { $0 + ExerciseAggregation.summary(for: $1, resolver: resolver).volume }
        }.value
        lifetimeVolume = total
    }

    private var uniqueExercisesCount: Int {
        dataManager.allExerciseNames().count
    }
}

private struct ProfileFieldRow: View {
    let title: String
    let promptText: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            TextField(promptText, text: $text)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .textContentType(.name)
                .accessibilityLabel(title)
                .accessibilityHint("Saved automatically as you type")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                .fill(Theme.Colors.panelInset)
        )
    }
}
