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
            .navigationTitle("All Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("exercise-list")
    }

    private var directoryContent: some View {
        ZStack {
            AdaptiveBackground()

            VStack(spacing: Theme.Spacing.sm) {
                searchField
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.sm)

                sortChips
                    .padding(.horizontal, Theme.Spacing.lg)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        if !cachedExercises.isEmpty {
                            Text(directorySummary)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.top, Theme.Spacing.xs)
                        }

                        exerciseRowsContent
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
            .contentColumn()
        }
    }

    @ViewBuilder
    private var exerciseRowsContent: some View {
        if !cachedFavoriteExerciseRows.isEmpty {
            exerciseSectionLabel("Favorites", topPadding: Theme.Spacing.xs)

            ForEach(cachedFavoriteExerciseRows, id: \.name) { exercise in
                exerciseRow(exercise, showsInlineFavoriteControl: true)
            }

            if !cachedNonFavoriteExerciseRows.isEmpty {
                exerciseSectionLabel("All", topPadding: Theme.Spacing.md)
            }
        }

        if cachedExercises.isEmpty {
            EmptyStateCard(
                icon: "magnifyingglass",
                tint: Theme.Colors.textTertiary,
                title: "No Matches",
                message: "Try a different exercise name."
            )
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
            .sectionHeaderStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.top, topPadding)
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
            Image(systemName: "arrow.up.arrow.down")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)

            TimeRangePillPicker(
                options: SortOrder.allCases,
                selected: $sortOrder,
                label: { $0.rawValue },
                selectionHint: "Double-tap to sort exercises this way"
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sort exercises")
    }

    private var directorySummary: String {
        let total = SharedFormatters.count(cachedExercises.count, "exercise")
        let favorites = cachedFavoriteRollupNames.count
        guard favorites > 0 else { return total }
        return "\(total) · \(favorites) favorite\(favorites == 1 ? "" : "s")"
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
                .tint(Theme.Colors.accent)

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
        .padding(.vertical, Theme.Spacing.md)
        .glassBackground(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
    }

    private func exerciseRow(
        _ exercise: (name: String, stats: ExerciseStats),
        showsInlineFavoriteControl: Bool = false
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

            if showsInlineFavoriteControl {
                Button {
                    toggleFavorite(exercise.name)
                } label: {
                    Image(systemName: "star.fill")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.warning)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from favorites")
            }
        }
        .softCard(elevation: 1)
        .contextMenu {
            Button {
                toggleFavorite(exercise.name)
            } label: {
                Label(
                    isFavoriteRollup(exercise.name) ? "Unfavorite" : "Favorite",
                    systemImage: isFavoriteRollup(exercise.name) ? "star.slash" : "star"
                )
            }
            Button("View History") {
                selectedExercise = ExerciseSelection(id: exercise.name)
            }
            Button("Quick Start") {
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
    let name: String
    let stats: ExerciseStats
    var showsCard: Bool = true
    let supportsSessionVolume: Bool
    var primaryMuscle: MuscleTag?
    let onOpen: () -> Void
    let onMetricTap: (ExerciseAnalysisMetric, ExerciseMetricFocus) -> Void

    private let monogramSize: CGFloat = 42

    private var tint: Color {
        primaryMuscle?.tint ?? Theme.Colors.accent
    }

    private var monogram: String {
        let words = name
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)
        let letters = words.compactMap(\.first).map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// One line of identity under the name: the main muscle and, for loaded lifts,
    /// the best weight on record.
    private var detailLine: String? {
        var parts: [String] = []
        if let primaryMuscle {
            parts.append(primaryMuscle.displayName)
        }
        if stats.maxWeight > 0, !ExerciseLoad.isAssistedExercise(name) {
            parts.append("Best \(ExerciseLoad.formatWeight(stats.maxWeight, exerciseName: name))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button(action: onOpen) {
                HStack(spacing: Theme.Spacing.md) {
                    Text(monogram)
                        .font(Theme.Typography.subheadlineBold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: monogramSize, height: monogramSize)
                        .background(
                            RoundedRectangle(cornerRadius: monogramSize * 0.28, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [tint.opacity(0.75), tint],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let detailLine {
                            Text(detailLine)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: Theme.Spacing.sm)

                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(PressableCardButtonStyle())
            .accessibilityHint("Opens exercise details.")
            .accessibilityIdentifier("exercise-row-\(name)")

            HStack(spacing: Theme.Spacing.xs) {
                ExerciseMetricPill(
                    icon: "repeat",
                    text: "\(stats.frequency)x",
                    accessibilityLabel: SharedFormatters.count(stats.frequency, "session")
                ) {
                    onMetricTap(.sessions, .overview)
                }
                if supportsSessionVolume {
                    ExerciseMetricPill(
                        icon: "chart.bar.fill",
                        text: SharedFormatters.volumeCompact(stats.totalVolume),
                        accessibilityLabel: "\(SharedFormatters.volumeWithUnit(stats.totalVolume)) total volume"
                    ) {
                        onMetricTap(.sessionVolume, .total)
                    }
                }

                if let lastDate = stats.lastPerformed {
                    ExerciseMetricPill(
                        icon: "clock",
                        text: relativeDateString(for: lastDate),
                        accessibilityLabel: "Last performed \(relativeDateString(for: lastDate))"
                    ) {
                        onMetricTap(.sessions, .overview)
                    }
                }
            }
            // Pills line up under the name rather than the monogram.
            .padding(.leading, monogramSize + Theme.Spacing.md)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xs)
        .modifier(ExerciseRowCardModifier(isEnabled: showsCard))
    }

    private func relativeDateString(for date: Date) -> String {
        ExerciseListFormatters.relativeDate.localizedString(for: date, relativeTo: Date())
    }
}

private enum ExerciseListFormatters {
    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private struct ExerciseRowCardModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.softCard(elevation: 1)
        } else {
            content
        }
    }
}

private struct ExerciseMetricPill: View {
    let icon: String
    let text: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(Theme.Typography.caption2Bold)
                    .foregroundColor(Theme.Colors.accent)
                    .accessibilityHidden(true)
                Text(text)
                    .font(Theme.Typography.captionStrong)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.Colors.surfaceRaised))
            .overlay(Capsule().strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 1))
            // The visible pill stays compact; the hit area keeps the 44pt minimum.
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppInteractionButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this metric's analysis.")
    }
}
