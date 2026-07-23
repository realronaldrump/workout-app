import Combine
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @ObservedObject private var relationshipManager = ExerciseRelationshipManager.shared

    @State private var searchText = ""
    @State private var settledSearchText = ""
    @State private var allExercises: [String] = []
    @State private var recentExercises: [String] = []
    @State private var favoriteAggregates: Set<String> = []
    @State private var favoriteMembership: Set<String> = []
    @State private var recentMembership: Set<String> = []
    @AppStorage("favoriteExercises") private var favoriteExercisesData: String = "[]"

    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                if shouldShowCreateOption {
                    Section("New Exercise") {
                        createRow
                    }
                }

                if query.isEmpty {
                    if !recentExercises.isEmpty {
                        Section("Recent") {
                            ForEach(recentExercises, id: \.self) { name in
                                exerciseRow(name)
                            }
                        }
                    }

                    let favorites = favoriteNamesExcludingRecent
                    if !favorites.isEmpty {
                        Section("Favorites") {
                            ForEach(favorites, id: \.self) { name in
                                exerciseRow(name)
                            }
                        }
                    }

                    Section(recentExercises.isEmpty && favorites.isEmpty ? "All Exercises" : "All Others") {
                        ForEach(allExercisesExcludingFeatured, id: \.self) { name in
                            exerciseRow(name)
                        }
                    }
                } else if filteredExercises.isEmpty {
                    Section {
                        ContentUnavailableView.search(text: query)
                    }
                } else {
                    Section("Results") {
                        ForEach(filteredExercises, id: \.self) { name in
                            exerciseRow(name)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AdaptiveBackground())
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .searchSuggestions {
                if query.isEmpty {
                    ForEach(recentExercises.prefix(5), id: \.self) { name in
                        Text(name).searchCompletion(name)
                    }
                }
            }
            .task {
                refreshSnapshot()
            }
            .task(id: searchText) {
                do {
                    try await Task.sleep(for: .milliseconds(120))
                    settledSearchText = searchText
                } catch {
                    return
                }
            }
            .onReceive(
                dataManager.$workouts
                    .dropFirst()
                    .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            ) { _ in
                refreshSnapshot()
            }
            .onChange(of: relationshipManager.relationships) { _, _ in
                refreshSnapshot()
            }
            .onChange(of: favoriteExercisesData) { _, _ in
                refreshFavorites()
            }
        }
    }

    private var query: String {
        settledSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var favoriteNamesExcludingRecent: [String] {
        favoriteAggregates
            .filter { !recentMembership.contains($0) }
            .sorted(by: localizedAscending)
    }

    private var allExercisesExcludingFeatured: [String] {
        allExercises.filter { name in
            !recentMembership.contains(name) && !favoriteMembership.contains(name)
        }
    }

    private var filteredExercises: [String] {
        guard !query.isEmpty else { return allExercises }
        return allExercises.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var shouldShowCreateOption: Bool {
        guard !query.isEmpty else { return false }
        return !allExercises.contains {
            $0.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private var createRow: some View {
        Button {
            select(query)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create “\(query)”")
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Adds it to this workout and your exercise library")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } icon: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.Colors.accent)
            }
            .frame(minHeight: Theme.Layout.minimumTapTarget)
        }
        .buttonStyle(.plain)
    }

    private func exerciseRow(_ name: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                select(name)
            } label: {
                HStack {
                    Text(name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Theme.Spacing.sm)
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.Colors.accent)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(name)")

            Button {
                toggleFavorite(name)
            } label: {
                Image(systemName: isFavorite(name) ? "star.fill" : "star")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(isFavorite(name) ? Theme.Colors.warning : Theme.Colors.textSecondary)
                    .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite(name) ? "Remove \(name) from favorites" : "Add \(name) to favorites")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                toggleFavorite(name)
            } label: {
                Label(isFavorite(name) ? "Unfavorite" : "Favorite", systemImage: isFavorite(name) ? "star.slash" : "star")
            }
            .tint(Theme.Colors.warning)
        }
    }

    private func select(_ name: String) {
        onSelect(name)
        dismiss()
    }

    private func isFavorite(_ name: String) -> Bool {
        favoriteMembership.contains(name)
    }

    private func toggleFavorite(_ name: String) {
        let resolver = relationshipManager.resolverSnapshot()
        let aggregateName = resolver.aggregateName(for: name)
        if favoriteAggregates.contains(aggregateName) {
            favoriteAggregates.remove(aggregateName)
        } else {
            favoriteAggregates.insert(aggregateName)
        }
        persistFavorites()
        rebuildMembership(using: resolver)
        Haptics.selection()
    }

    private func refreshSnapshot() {
        let resolver = relationshipManager.resolverSnapshot()
        let catalogNames = ExerciseMetadataManager.defaultExerciseNames
        let relationshipNames = relationshipManager.relationships.values.flatMap { [$0.exerciseName, $0.parentName] }
        let dataNames = dataManager.allExerciseNames()
        allExercises = Array(Set(dataNames + catalogNames + relationshipNames)).sorted(by: localizedAscending)

        var seenRecent = Set<String>()
        recentExercises = dataManager.recentExerciseNames(limit: 20).compactMap { name in
            let aggregate = resolver.aggregateName(for: name)
            guard seenRecent.insert(aggregate).inserted else { return nil }
            return aggregate
        }
        .prefix(10)
        .map { $0 }

        refreshFavorites(using: resolver)
    }

    private func refreshFavorites(using resolver: ExerciseIdentityResolver? = nil) {
        let resolver = resolver ?? relationshipManager.resolverSnapshot()
        let decoded: [String]
        if let data = favoriteExercisesData.data(using: .utf8),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            decoded = values
        } else {
            decoded = []
        }
        favoriteAggregates = Set(decoded.map { resolver.aggregateName(for: $0) })
        rebuildMembership(using: resolver)
    }

    private func rebuildMembership(using resolver: ExerciseIdentityResolver) {
        favoriteMembership = expandedMembership(for: favoriteAggregates, resolver: resolver)
        recentMembership = expandedMembership(for: Set(recentExercises), resolver: resolver)
    }

    private func expandedMembership(
        for aggregateNames: Set<String>,
        resolver: ExerciseIdentityResolver
    ) -> Set<String> {
        var membership = aggregateNames
        for aggregateName in aggregateNames {
            for child in resolver.children(of: aggregateName) {
                membership.insert(child.exerciseName)
            }
        }
        return membership
    }

    private func persistFavorites() {
        let values = favoriteAggregates.sorted(by: localizedAscending)
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else { return }
        favoriteExercisesData = string
    }

    private func localizedAscending(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
}
