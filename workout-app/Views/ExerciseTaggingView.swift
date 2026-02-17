import SwiftUI

struct ExerciseTaggingView: View {
    private struct ExerciseTaggingItem: Identifiable {
        let exerciseName: String
        let tags: [MuscleTag]
        let isCustomized: Bool

        var id: String { exerciseName }
        var isUntagged: Bool { tags.isEmpty }
    }

    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @State private var searchText = ""

    private var uniqueExercises: [String] {
        let allExercises = dataManager.workouts.flatMap { $0.exercises.map { $0.name } }
        let unique = Set(allExercises)
        return Array(unique).sorted()
    }

    private var filteredExercises: [String] {
        if searchText.isEmpty {
            return uniqueExercises
        } else {
            return uniqueExercises.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var filteredExerciseItems: [ExerciseTaggingItem] {
        filteredExercises.map { exercise in
            ExerciseTaggingItem(
                exerciseName: exercise,
                tags: metadataManager.resolvedTags(for: exercise),
                isCustomized: metadataManager.isOverridden(for: exercise)
            )
        }
    }

    private var untaggedFilteredExercises: [ExerciseTaggingItem] {
        filteredExerciseItems.filter(\.isUntagged)
    }

    private var taggedFilteredExercises: [ExerciseTaggingItem] {
        filteredExerciseItems.filter { !$0.isUntagged }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    introCard

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Assign Muscle Tags")
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        if uniqueExercises.isEmpty {
                            EmptyStateCard(
                                icon: "tray",
                                tint: Theme.Colors.textTertiary,
                                title: "No exercises yet",
                                message: "Import workouts first, then come back here to tag your exercises."
                            )
                        } else if filteredExercises.isEmpty {
                            EmptyStateCard(
                                icon: "magnifyingglass",
                                tint: Theme.Colors.accent,
                                title: "No matches",
                                message: "Try a different search."
                            )
                        } else {
                            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                                if !untaggedFilteredExercises.isEmpty {
                                    exerciseSection(title: "Untagged", exercises: untaggedFilteredExercises)
                                }

                                if !taggedFilteredExercises.isEmpty {
                                    exerciseSection(title: "Tagged", exercises: taggedFilteredExercises)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle("Exercise Tags")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search exercises")
    }

    private func exerciseSection(title: String, exercises: [ExerciseTaggingItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("\(title) (\(exercises.count))")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.sm)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(exercises) { item in
                    NavigationLink(destination: ExerciseTagEditorView(exerciseName: item.exerciseName)) {
                        ExerciseTaggingRow(
                            exerciseName: item.exerciseName,
                            tags: item.tags,
                            isCustomized: item.isCustomized
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "tag.fill")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.Colors.accentTertiary)
                .cornerRadius(Theme.CornerRadius.large)

            VStack(alignment: .leading, spacing: 4) {
                Text("Clean data in, clean insights out.")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Tag each exercise once. These muscle groups power your charts and show up in exports.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}

private struct ExerciseTaggingRow: View {
    let exerciseName: String
    let tags: [MuscleTag]
    let isCustomized: Bool

    private var iconTint: Color {
        if let first = tags.first { return first.tint }
        return Theme.Colors.textTertiary
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: tags.isEmpty ? "tag.slash.fill" : "tag.fill")
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(iconTint)
                .cornerRadius(Theme.CornerRadius.large)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(exerciseName)
                        .font(Theme.Typography.condensed)
                        .tracking(-0.2)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    if isCustomized {
                        Text("CUSTOM")
                            .font(Theme.Typography.metricLabel)
                            .foregroundStyle(Theme.Colors.accentSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.Colors.accentSecondary.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .strokeBorder(Theme.Colors.accentSecondary.opacity(0.7), lineWidth: 2)
                            )
                    }
                }

                Text(tags.isEmpty ? "Untagged" : tags.map(\.displayName).joined(separator: ", "))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(tags.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}

private struct EmptyStateCard: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(tint)
                .cornerRadius(Theme.CornerRadius.large)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}
