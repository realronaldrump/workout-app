import Combine
import SwiftUI

struct ExerciseTaggingView: View {
    private struct ExerciseTaggingItem: Identifiable {
        let exerciseName: String
        let assignments: [ExerciseMuscleAssignment]
        let isCustomized: Bool

        var id: String { exerciseName }
        var isUntagged: Bool { assignments.isEmpty }
    }

    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @State private var searchText = ""
    @State private var cachedExerciseItems: [ExerciseTaggingItem] = []
    @State private var untaggedFilteredExercises: [ExerciseTaggingItem] = []
    @State private var taggedFilteredExercises: [ExerciseTaggingItem] = []

    var body: some View {
        ZStack {
            AdaptiveBackground()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    introCard

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Assign Muscle Roles")
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        if cachedExerciseItems.isEmpty {
                            EmptyStateCard(
                                title: "No exercises yet",
                                message: "Import workouts first, then come back here to tag your exercises.",
                                icon: "tray",
                                tint: Theme.Colors.textTertiary
                            )
                        } else if untaggedFilteredExercises.isEmpty && taggedFilteredExercises.isEmpty {
                            EmptyStateCard(
                                title: "No matches",
                                message: "Try a different search.",
                                icon: "magnifyingglass",
                                tint: Theme.Colors.accent
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
                .contentColumn()
            }
        }
        .navigationTitle("Exercise Muscle Roles")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search exercises")
        .onAppear(perform: rebuildExerciseCache)
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            applySearchFilter()
        }
        .onReceive(
            dataManager.$workouts
                .dropFirst()
                .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        ) { _ in
            rebuildExerciseCache()
        }
        .onReceive(
            metadataManager.objectWillChange
                .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        ) { _ in
            Task { @MainActor in
                await Task.yield()
                rebuildExerciseCache()
            }
        }
    }

    private func exerciseSection(title: String, exercises: [ExerciseTaggingItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("\(title) (\(exercises.count))")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.sm)

            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(exercises) { item in
                    NavigationLink(destination: ExerciseTagEditorView(exerciseName: item.exerciseName)) {
                        ExerciseTaggingRow(
                            exerciseName: item.exerciseName,
                            assignments: item.assignments,
                            isCustomized: item.isCustomized
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rebuildExerciseCache() {
        let names = Set(dataManager.workouts.flatMap { workout in
            workout.exercises.map(\.name)
        }).sorted()

        cachedExerciseItems = names.map { exercise in
            ExerciseTaggingItem(
                exerciseName: exercise,
                assignments: metadataManager.resolvedAssignments(for: exercise),
                isCustomized: metadataManager.isOverridden(for: exercise)
            )
        }
        applySearchFilter()
    }

    private func applySearchFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? cachedExerciseItems
            : cachedExerciseItems.filter { $0.exerciseName.localizedCaseInsensitiveContains(query) }
        untaggedFilteredExercises = filtered.filter(\.isUntagged)
        taggedFilteredExercises = filtered.filter { !$0.isUntagged }
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
                Text("Choose primary and secondary muscles once. Their weighted roles power charts, recency, coverage, and exports.")
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
    let assignments: [ExerciseMuscleAssignment]
    let isCustomized: Bool

    private var iconTint: Color {
        if let primary = assignments.first(where: { $0.role == .primary }) { return primary.tag.tint }
        return Theme.Colors.textTertiary
    }

    private var roleSummary: String {
        MuscleContributionPolicy.exportDescription(assignments)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: assignments.isEmpty ? "tag.slash.fill" : "tag.fill")
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

                Text(assignments.isEmpty ? "Untagged" : roleSummary)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(assignments.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}
