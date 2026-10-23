import SwiftUI

struct ExerciseListView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject private var relationshipManager = ExerciseRelationshipManager.shared
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @State private var searchText = ""
    @State private var sortOrder = SortOrder.alphabetical
    @State private var selectedExercise: ExerciseSelection?
    @State private var selectedExerciseMetric: ExerciseDirectoryMetricSelection?
    @State private var showingQuickStart = false
    @State private var quickStartExercise: String?
    @State private var cachedExercises: [(name: String, stats: ExerciseStats)] = []
    @State private var cachedFavoriteExercises: Set<String> = []
    @State private var cachedFavoriteExerciseRows: [(name: String, stats: ExerciseStats)] = []
    @State private var cachedNonFavoriteExerciseRows: [(name: String, stats: ExerciseStats)] = []
    @State private var cachedFavoriteRollupNames: Set<String> = []
    @AppStorage("favoriteExercises") private var favoriteExercisesData: String = "[]"

    private struct ExerciseDirectoryMetricSelection: Identifiable, Hashable {
        let exerciseName: String
        let metric: ExerciseAnalysisMetric
        let focus: ExerciseMetricFocus

        var id: String {
            "\(exerciseName)|\(metric.rawValue)|\(focus.rawValue)"
        }
    }

    private static func decodeFavoriteExercises(_ encoded: String) -> Set<String> {
        guard let data = encoded.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(array)
    }

    private func toggleFavorite(_ name: String) {
        var favorites = cachedFavoriteExercises
        let rollupNames = favoriteRollupNames(for: name)
        if !favorites.isDisjoint(with: rollupNames) {
            favorites.subtract(rollupNames)
        } else {
            favorites.insert(name)
        }
        cachedFavoriteExercises = favorites
        rebuildCachedExerciseRows(exercises: cachedExercises, favorites: favorites)

        if let data = try? JSONEncoder().encode(favorites.sorted()),
           let string = String(data: data, encoding: .utf8) {
            favoriteExercisesData = string
        }
        Haptics.selection()
    }

    enum SortOrder: String, CaseIterable {
        case alphabetical = "Name"
        case volume = "Volume"
        case frequency = "Frequency"
        case recent = "Recent"
    }

    private func buildExercises() -> [(name: String, stats: ExerciseStats)] {
        let resolver = relationshipManager.resolverSnapshot()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = dataManager.exerciseSummaries().filter { exercise in
            query.isEmpty ||
                exercise.name.localizedCaseInsensitiveContains(query) ||
                resolver.children(of: exercise.name).contains {
                    $0.exerciseName.localizedCaseInsensitiveContains(query)
                }
        }

        switch sortOrder {
        case .alphabetical:
            return filtered.map { ($0.name, $0.stats) }
        case .volume:
            return filtered
                .sorted { $0.stats.totalVolume > $1.stats.totalVolume }
                .map { ($0.name, $0.stats) }
        case .frequency:
            return filtered
                .sorted { $0.stats.frequency > $1.stats.frequency }
                .map { ($0.name, $0.stats) }
        case .recent:
            return filtered
                .sorted { ($0.stats.lastPerformed ?? .distantPast) > ($1.stats.lastPerformed ?? .distantPast) }
                .map { ($0.name, $0.stats) }
        }
    }

    private func isFavoriteRollup(_ name: String) -> Bool {
        cachedFavoriteRollupNames.contains(name)
    }

    private func favoriteRollupNames(for name: String) -> Set<String> {
        var names = Set([name])
        for child in relationshipManager.children(of: name) {
            names.insert(child.exerciseName)
        }
        return names
    }

    private func refreshExercises(favorites: Set<String>? = nil) {
        let exercises = buildExercises()
        let favorites = favorites ?? cachedFavoriteExercises
        cachedExercises = exercises
        rebuildCachedExerciseRows(exercises: exercises, favorites: favorites)
    }

    private func refreshFavorites(from encoded: String) {
        let favorites = Self.decodeFavoriteExercises(encoded)
        cachedFavoriteExercises = favorites
        rebuildCachedExerciseRows(exercises: cachedExercises, favorites: favorites)
    }

    private func rebuildCachedExerciseRows(
        exercises: [(name: String, stats: ExerciseStats)],
        favorites: Set<String>
    ) {
        var favoriteRows: [(name: String, stats: ExerciseStats)] = []
        var otherRows: [(name: String, stats: ExerciseStats)] = []
        var favoriteRollupNames: Set<String> = []

        favoriteRows.reserveCapacity(exercises.count)
        otherRows.reserveCapacity(exercises.count)
        favoriteRollupNames.reserveCapacity(favorites.count)

        for exercise in exercises {
            let isFavorite = !favorites.isDisjoint(with: self.favoriteRollupNames(for: exercise.name))
            if isFavorite {
                favoriteRollupNames.insert(exercise.name)
            }

            if searchText.isEmpty && isFavorite {
                favoriteRows.append(exercise)
            } else {
                otherRows.append(exercise)
            }
        }

        cachedFavoriteExerciseRows = searchText.isEmpty ? favoriteRows : []
        cachedNonFavoriteExerciseRows = otherRows
        cachedFavoriteRollupNames = favoriteRollupNames
    }

    var body: some View {
        destinationContent
            .navigationDestination(item: $selectedExercise) { selection in
                ExerciseDetailView(
                    exerciseName: selection.id,
                    dataManager: dataManager,
                    annotationsManager: annotationsManager,
                    gymProfilesManager: gymProfilesManager
                )
            }
            .navigationDestination(item: $selectedExerciseMetric) { route in
                exerciseMetricDestination(route)
            }
            .sheet(isPresented: $showingQuickStart) {
                QuickStartView(exerciseName: quickStartExercise)
            }
            .onAppear {
                let favorites = Self.decodeFavoriteExercises(favoriteExercisesData)
                cachedFavoriteExercises = favorites
                refreshExercises(favorites: favorites)
            }
            .onChange(of: searchText) { _, _ in
                refreshExercises()
            }
            .onChange(of: sortOrder) { _, _ in
                refreshExercises()
            }
            .onChange(of: dataManager.workouts) { _, _ in
                refreshExercises()
            }
            .onChange(of: relationshipManager.relationships) { _, _ in
                dataManager.refreshExerciseIdentityDerivedState()
                refreshExercises()
            }
            .onChange(of: favoriteExercisesData) { _, newValue in
                refreshFavorites(from: newValue)
            }
    }

    private var destinationContent: some View {
        directoryContent
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("exercise-list")
    }

    private var directoryContent: some View {
        ZStack {
            AdaptiveBackground()

            VStack(spacing: Theme.Spacing.sm) {
                searchField
                    .padding(.horizontal, Theme.Layout.screenGutter)
                    .padding(.top, Theme.Spacing.sm)

                sortChips
                    .padding(.horizontal, Theme.Layout.screenGutter)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if !cachedExercises.isEmpty {
                            Text(directorySummary)
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Theme.Spacing.xs)
                                .padding(.bottom, Theme.Spacing.sm)
                        }

                        exerciseRowsContent
                    }
                    .padding(.horizontal, Theme.Layout.screenGutter)
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .contentColumn()
        }
    }

    @ViewBuilder
    private var exerciseRowsContent: some View {
        if !cachedFavoriteExerciseRows.isEmpty {
            exerciseSectionLabel("Favorites", topPadding: Theme.Spacing.xs)

            ForEach(cachedFavoriteExerciseRows, id: \.name) { exercise in
                exerciseRow(exercise)
            }

            if !cachedNonFavoriteExerciseRows.isEmpty {
                exerciseSectionLabel("Everything else", topPadding: Theme.Spacing.xl)
            }
        }

        if cachedExercises.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                EmptyStateCard(
                    title: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "No exercises yet" : "No matching exercises",
                    message: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Log a workout and every exercise in it shows up here with its records."
                        : "Try another name, or clear the search."
                )

                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AppPrimaryButton(title: "Start workout") {
                        quickStartExercise = nil
                        showingQuickStart = true
                    }
                } else {
                    AppPillButton(title: "Clear search", systemImage: "xmark", variant: .neutral) {
                        searchText = ""
                    }
                }
            }
            .padding(.top, Theme.Spacing.xl)
        } else {
            ForEach(cachedNonFavoriteExerciseRows, id: \.name) { exercise in
                exerciseRow(exercise)
            }
        }
    }

    private func exerciseSectionLabel(
        _ title: String,
        topPadding: CGFloat
    ) -> some View {
        Text(title)
            .font(Theme.Typography.title3)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
            .padding(.bottom, Theme.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private func exerciseMetricDestination(
        _ route: ExerciseDirectoryMetricSelection
    ) -> some View {
        let selection = ExerciseMetricSelection(
            scope: ExerciseAnalysisScope(exerciseName: route.exerciseName),
            metric: route.metric,
            focus: route.focus
        )
        let sessions = dataManager.exerciseHistorySessions(
            for: route.exerciseName,
            includingVariants: true
        )
        return ExerciseMetricDetailView(
            selection: selection,
            sessions: sessions
        )
    }

    private var sortChips: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TimeRangePillPicker(
                options: SortOrder.allCases,
                selected: $sortOrder,
                label: { $0.rawValue },
                selectionHint: "Sorts exercises this way",
                controlTitle: "Sort exercises",
                controlIcon: "arrow.up.arrow.down"
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sort exercises")
    }

    private var directorySummary: String {
        let total = SharedFormatters.count(cachedExercises.count, "exercise")
        let favorites = cachedFavoriteRollupNames.count
        guard favorites > 0 else { return total }
        return "\(total), \(favorites) favorite\(favorites == 1 ? "" : "s")"
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textTertiary)

            TextField("Search exercises", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tint(Theme.Colors.textPrimary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Haptics.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(minHeight: 48)
        .background(Capsule(style: .continuous).fill(Theme.Colors.panelStrong))
    }

    private func exerciseRow(
        _ exercise: (name: String, stats: ExerciseStats)
    ) -> some View {
        HStack(spacing: 0) {
            ExerciseRowView(
                name: exercise.name,
                stats: exercise.stats,
                showsCard: false,
                supportsSessionVolume: supportsSessionVolume(
                    exerciseName: exercise.name,
                    stats: exercise.stats
                ),
                primaryMuscle: primaryMuscle(for: exercise.name),
                onOpen: {
                    selectedExercise = ExerciseSelection(id: exercise.name)
                },
                onMetricTap: { metric, focus in
                    selectedExerciseMetric = ExerciseDirectoryMetricSelection(
                        exerciseName: exercise.name,
                        metric: metric,
                        focus: focus
                    )
                }
            )

            Menu {
                Button {
                    toggleFavorite(exercise.name)
                } label: {
                    Label(
                        isFavoriteRollup(exercise.name) ? "Remove from favorites" : "Add to favorites",
                        systemImage: isFavoriteRollup(exercise.name) ? "star.slash" : "star"
                    )
                }
                Button("Start a workout with this", systemImage: "play.fill") {
                    quickStartExercise = exercise.name
                    showingQuickStart = true
                }
                Button("Sessions", systemImage: "calendar") {
                    selectedExerciseMetric = ExerciseDirectoryMetricSelection(
                        exerciseName: exercise.name,
                        metric: .sessions,
                        focus: .overview
                    )
                }
                if supportsSessionVolume(exerciseName: exercise.name, stats: exercise.stats) {
                    Button("Volume per session", systemImage: "chart.bar") {
                        selectedExerciseMetric = ExerciseDirectoryMetricSelection(
                            exerciseName: exercise.name,
                            metric: .sessionVolume,
                            focus: .total
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(exercise.name)")
            .accessibilityValue(isFavoriteRollup(exercise.name) ? "Favorite" : "")
            .accessibilityHint("Start a workout, open its sessions, or change favorite status.")
        }
        .ledgerRow(verticalPadding: 0)
        .contextMenu {
            Button {
                toggleFavorite(exercise.name)
            } label: {
                Label(
                    isFavoriteRollup(exercise.name) ? "Remove from favorites" : "Add to favorites",
                    systemImage: isFavoriteRollup(exercise.name) ? "star.slash" : "star"
                )
            }
            Button("Exercise history") {
                selectedExercise = ExerciseSelection(id: exercise.name)
            }
            Button("Start a workout with this") {
                quickStartExercise = exercise.name
                showingQuickStart = true
            }
        }
    }

    private func primaryMuscle(for exerciseName: String) -> MuscleTag? {
        let assignments = metadataManager.resolvedAssignments(for: exerciseName)
        return assignments.first(where: { $0.role == .primary })?.tag ?? assignments.first?.tag
    }

    private func supportsSessionVolume(
        exerciseName: String,
        stats: ExerciseStats
    ) -> Bool {
        let isCardio = metadataManager
            .resolvedTags(for: exerciseName)
            .contains(where: { $0.builtInGroup == .cardio })
        return ExerciseDirectoryMetricPolicy.supportsSessionVolume(
            exerciseName: exerciseName,
            isCardio: isCardio,
            totalVolume: stats.totalVolume
        )
    }
}

struct ExerciseStats {
    let totalVolume: Double
    let maxWeight: Double
    let frequency: Int
    let lastPerformed: Date?
    let oneRepMax: Double
}

struct ExerciseRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let name: String
    let stats: ExerciseStats
    var showsCard: Bool = true
    let supportsSessionVolume: Bool
    var primaryMuscle: MuscleTag?
    let onOpen: () -> Void
    let onMetricTap: (ExerciseAnalysisMetric, ExerciseMetricFocus) -> Void

    private var tint: Color {
        primaryMuscle?.tint ?? Theme.Colors.decorativeSubtle
    }

    /// One line of identity under the name: the main muscle, the best weight on
    /// record for loaded lifts, and how long since it was last trained.
    private var detailLine: String? {
        var parts: [String] = []
        if let primaryMuscle {
            parts.append(primaryMuscle.displayName)
        }
        if stats.maxWeight > 0, !ExerciseLoad.isAssistedExercise(name) {
            parts.append("best \(ExerciseLoad.formatWeight(stats.maxWeight, exerciseName: name))")
        }
        if let lastDate = stats.lastPerformed {
            parts.append(relativeDateString(for: lastDate))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Theme.Spacing.md) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 5, height: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)

                    if let detailLine {
                        Text(detailLine)
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                }

                Spacer(minLength: Theme.Spacing.sm)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(stats.frequency)")
                        .font(Theme.Typography.numberSmall)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(stats.frequency == 1 ? "session" : "sessions")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.vertical, Theme.Spacing.md)
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityHint("Opens exercise details.")
        .accessibilityIdentifier("exercise-row-\(name)")
    }

    private func relativeDateString(for date: Date) -> String {
        ExerciseListFormatters.relativeDate.localizedString(for: date, relativeTo: Date())
    }
}

private enum ExerciseListFormatters {
    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
