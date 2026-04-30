import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @ObservedObject private var relationshipManager = ExerciseRelationshipManager.shared

    @State private var searchText: String = ""
    @AppStorage("favoriteExercises") private var favoriteExercisesData: String = "[]"

    let onSelect: (String) -> Void

    private var favoriteExerciseNames: [String] {
        guard let data = favoriteExercisesData.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        let resolver = relationshipManager.resolverSnapshot()
        return Array(Set(array.map { resolver.aggregateName(for: $0) }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func isFavorite(_ name: String) -> Bool {
        !favoriteRollupNames(for: name).isDisjoint(with: Set(favoriteExerciseNames))
    }

    private func toggleFavorite(_ name: String) {
        var favorites: Set<String>
        if let data = favoriteExercisesData.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            favorites = Set(array)
        } else {
            favorites = []
        }
        let rollupNames = favoriteRollupNames(for: name)
        if !favorites.isDisjoint(with: rollupNames) {
            favorites.subtract(rollupNames)
        } else {
            favorites.insert(relationshipManager.resolverSnapshot().aggregateName(for: name))
        }
        if let data = try? JSONEncoder().encode(Array(favorites)),
           let string = String(data: data, encoding: .utf8) {
            favoriteExercisesData = string
        }
        Haptics.selection()
    }

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

                            let favs = favoriteExerciseNames.filter { !recentExercises.contains($0) }
                            if !favs.isEmpty {
                                sectionHeader("Favorites")
                                VStack(spacing: Theme.Spacing.sm) {
                                    ForEach(favs, id: \.self) { name in
                                        exerciseRow(name)
                                    }
                                }
                            }

                            sectionHeader(recentExercises.isEmpty && favs.isEmpty ? "All" : "All Others")
                            VStack(spacing: Theme.Spacing.sm) {
                                ForEach(allExercisesExcludingRecent, id: \.self) { name in
                                    exerciseRow(name)
                                }
                            }
                        } else {
                            if filteredExercises.isEmpty {
                                EmptyStateCard(
                                    icon: "magnifyingglass",
                                    tint: Theme.Colors.textTertiary,
                                    title: "No Matches",
                                    message: "Create a new exercise or adjust your search."
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
                    AppToolbarButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
        }
    }

    private var recentExercises: [String] {
        dataManager.recentExerciseNames(limit: 10)
    }

    private var allExercises: [String] {
        let catalogNames = ExerciseMetadataManager.defaultExerciseNames
        let relationshipNames = relationshipManager.relationships.values.flatMap { [$0.exerciseName, $0.parentName] }
        if dataManager.allExerciseNames().isEmpty {
            return Array(Set(catalogNames + relationshipNames))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        return Array(Set(dataManager.allExerciseNames() + catalogNames + relationshipNames))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var allExercisesExcludingRecent: [String] {
        let recent = Set(recentExercises)
        let favs = Set(favoriteExerciseNames)
        return allExercises.filter { name in
            let rollupNames = favoriteRollupNames(for: name)
            return recent.isDisjoint(with: rollupNames) && favs.isDisjoint(with: rollupNames)
        }
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

    private func favoriteRollupNames(for name: String) -> Set<String> {
        let resolver = relationshipManager.resolverSnapshot()
        let aggregateName = resolver.aggregateName(for: name)
        var names = Set([name, aggregateName])
        for child in resolver.children(of: aggregateName) {
            names.insert(child.exerciseName)
        }
        return names
    }

    private var createRow: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            onSelect(query)
            dismiss()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "plus.circle.fill")
                    .font(Theme.Iconography.action)
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
                    .font(Theme.Typography.caption)
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
        HStack(spacing: 0) {
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
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.lg)
            }
            .buttonStyle(.plain)

            Button {
                toggleFavorite(name)
            } label: {
                Image(systemName: isFavorite(name) ? "star.fill" : "star")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(isFavorite(name) ? Theme.Colors.warning : Theme.Colors.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite(name) ? "Remove from favorites" : "Add to favorites")
        }
        .softCard(elevation: 1)
    }
}
