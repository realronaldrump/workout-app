import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: WorkoutDataManager

    @State private var searchText: String = ""

    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        if shouldShowCreateOption {
                            createRow
                        }

                        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            if !recentExercises.isEmpty {
                                sectionHeader("Recent")
                                VStack(spacing: Theme.Spacing.sm) {
                                    ForEach(recentExercises, id: \.self) { name in
                                        exerciseRow(name)
                                    }
                                }
                            }

                            sectionHeader("All")
                            VStack(spacing: Theme.Spacing.sm) {
                                ForEach(allExercises, id: \.self) { name in
                                    exerciseRow(name)
                                }
                            }
                        } else {
                            if filteredExercises.isEmpty {
                                ContentUnavailableView(
                                    "No matches",
                                    systemImage: "magnifyingglass",
                                    description: Text("Create a new exercise or adjust your search.")
                                )
                                .padding(.top, Theme.Spacing.xl)
                            } else {
                                sectionHeader("Results")
                                VStack(spacing: Theme.Spacing.sm) {
                                    ForEach(filteredExercises, id: \.self) { name in
                                        exerciseRow(name)
                                    }
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationTitle("Pick Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
        }
    }

    private var recentExercises: [String] {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(10)

        for workout in dataManager.workouts.sorted(by: { $0.date > $1.date }) {
            for exercise in workout.exercises {
                let name = exercise.name
                let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if seen.insert(key).inserted {
                    result.append(name)
                    if result.count >= 10 { return result }
                }
            }
        }

        return result
    }

    private var allExercises: [String] {
        let names = dataManager.workouts.flatMap { $0.exercises.map(\.name) }
        let unique = Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredExercises: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allExercises }
        return allExercises.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var shouldShowCreateOption: Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        let exists = allExercises.contains { $0.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        return !exists
    }

    private var createRow: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            onSelect(query)
            dismiss()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text(query)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.captionBold)
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.sm)
    }

    private func exerciseRow(_ name: String) -> some View {
        Button {
            onSelect(name)
            dismiss()
        } label: {
            HStack {
                Text(name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
    }
}
