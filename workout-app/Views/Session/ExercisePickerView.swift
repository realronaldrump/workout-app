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

    /// Exercises already in the current workout; shown as added instead of silently no-oping.
    var alreadyAdded: Set<String> = []
    var allowsMultipleSelection = false
    let onSelect: (String) -> Void
    @State private var selectedNames: [String] = []

    var body: some View {
        NavigationStack {
            List {
                if allowsMultipleSelection && !selectedNames.isEmpty {
                    Section {
                        ForEach(Array(selectedNames.enumerated()), id: \.element) { index, name in
                            HStack(spacing: Theme.Spacing.md) {
                                selectionNumber(index + 1)
                                Text(name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: Theme.Spacing.sm)
                                Button {
                                    select(name)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(Theme.Typography.subheadlineBold)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(name) from selection")
                            }
                            .loadedListRow()
                        }
                    } header: {
                        LoadedListHeader(title: "Adding", detail: "In this order")
                    }
                }

                if shouldShowCreateOption {
                    Section {
                        createRow
                            .loadedListRow()
                    } header: {
                        LoadedListHeader(title: "New exercise")
                    }
                }

                if query.isEmpty {
                    if !recentExercises.isEmpty {
                        Section {
                            ForEach(recentExercises, id: \.self) { name in
                                exerciseRow(name)
                                    .loadedListRow()
                            }
                        } header: {
                            LoadedListHeader(title: "Recent")
                        }
                    }

                    let favorites = favoriteNamesExcludingRecent
                    if !favorites.isEmpty {
                        Section {
                            ForEach(favorites, id: \.self) { name in
                                exerciseRow(name)
                                    .loadedListRow()
                            }
                        } header: {
                            LoadedListHeader(title: "Favorites")
                        }
                    }

                    Section {
                        ForEach(allExercisesExcludingFeatured, id: \.self) { name in
                            exerciseRow(name)
                                .loadedListRow()
                        }
                    } header: {
                        LoadedListHeader(title: recentExercises.isEmpty && favorites.isEmpty ? "All exercises" : "Everything else")
                    }
                } else if filteredExercises.isEmpty {
                    Section {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(Theme.Colors.ground)
                    }
                } else {
                    Section {
                        ForEach(filteredExercises, id: \.self) { name in
                            exerciseRow(name)
                                .loadedListRow()
                        }
                    } header: {
                        LoadedListHeader(title: "Results", detail: SharedFormatters.count(filteredExercises.count, "match", plural: "matches"))
                    }
                }
            }
            .loadedListStyle()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(allowsMultipleSelection ? "Add exercises" : "Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if allowsMultipleSelection {
                    VStack(spacing: Theme.Spacing.xs) {
                        AppPrimaryButton(
                            title: selectedNames.isEmpty ? "Pick exercises to add" : "Add \(SharedFormatters.count(selectedNames.count, "exercise"))",
                            isEnabled: !selectedNames.isEmpty
                        ) {
                            for name in selectedNames { onSelect(name) }
                            dismiss()
                        }
                    }
                    .contentColumn(maxWidth: 640)
                    .padding(.horizontal, Theme.Layout.screenGutter)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.ground)
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

    /// Every search word must appear somewhere in the name, so "db bench" finds
    /// "Bench Press (Dumbbell)"-style names. Names starting with the query rank first.
    private var filteredExercises: [String] {
        guard !query.isEmpty else { return allExercises }
        let tokens = query
            .split(whereSeparator: \.isWhitespace)
            .map { expandedSearchToken(String($0)) }
        let matches = allExercises.filter { name in
            tokens.allSatisfy { alternatives in
                alternatives.contains { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
        }
        let prefixMatches = matches.filter {
            $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }
        let prefixSet = Set(prefixMatches)
        return prefixMatches + matches.filter { !prefixSet.contains($0) }
    }

    /// Common gym shorthand mapped to the words used in exercise names.
    private func expandedSearchToken(_ token: String) -> [String] {
        switch token.lowercased() {
        case "db": return [token, "dumbbell"]
        case "bb": return [token, "barbell"]
        case "kb": return [token, "kettlebell"]
        case "ohp": return [token, "overhead press"]
        case "rdl": return [token, "romanian deadlift"]
        default: return [token]
        }
    }

    private var shouldShowCreateOption: Bool {
        guard !query.isEmpty else { return false }
        return !allExercises.contains {
            $0.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        } && !isAlreadyAdded(query)
    }

    private var createRow: some View {
        Button {
            select(query)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "plus")
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.Colors.accent))
                    .accessibilityHidden(true)
                Text("Create “\(query)”")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(minHeight: Theme.Layout.minimumTapTarget)
        }
        .buttonStyle(.plain)
    }

    private func exerciseRow(_ name: String) -> some View {
        let isAdded = isAlreadyAdded(name)
        let isSelected = selectedNames.contains(name)
        return HStack(spacing: Theme.Spacing.sm) {
            Button {
                select(name)
            } label: {
                HStack {
                    Text(name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(isAdded ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Theme.Spacing.sm)
                    if isAdded {
                        Text("In workout")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.success)
                    } else if let index = selectedNames.firstIndex(of: name) {
                        selectionNumber(index + 1)
                    } else if allowsMultipleSelection {
                        Circle()
                            .strokeBorder(Theme.Colors.rule, lineWidth: 2)
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "plus")
                            .font(Theme.Typography.subheadlineBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
            .accessibilityLabel(isAdded ? "\(name), already in this workout" : isSelected ? "Deselect \(name)" : "Add \(name)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button {
                toggleFavorite(name)
            } label: {
                Image(systemName: isFavorite(name) ? "star.fill" : "star")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(isFavorite(name) ? Theme.Colors.plateYellow : Theme.Colors.decorativeSubtle)
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
            .tint(Theme.Colors.plateYellow)
        }
    }

    /// The order an exercise will be added in, stamped in an ink disc.
    private func selectionNumber(_ number: Int) -> some View {
        Text("\(number)")
            .font(Theme.Typography.captionBold)
            .foregroundStyle(Theme.Colors.onAccent)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Theme.Colors.accent))
            .accessibilityHidden(true)
    }

    private func isAlreadyAdded(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return alreadyAdded.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }
    }

    private func select(_ name: String) {
        guard !isAlreadyAdded(name) else { return }
        if allowsMultipleSelection {
            if let index = selectedNames.firstIndex(of: name) {
                selectedNames.remove(at: index)
            } else {
                selectedNames.append(name)
                if !allExercises.contains(name) { allExercises.append(name); allExercises.sort(by: localizedAscending) }
            }
            Haptics.selection()
        } else {
            onSelect(name)
            dismiss()
        }
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
        let dataNames = dataManager.allExerciseNames() + selectedNames
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
