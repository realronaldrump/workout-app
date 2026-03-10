import SwiftUI

struct ExerciseListView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @State private var searchText = ""
    @State private var sortOrder = SortOrder.alphabetical
    @State private var selectedExercise: ExerciseSelection?
    @State private var showingQuickStart = false
    @State private var quickStartExercise: String?
    @State private var cachedExercises: [(name: String, stats: ExerciseStats)] = []
    @AppStorage("favoriteExercises") private var favoriteExercisesData: String = "[]"

    private var favoriteExercises: Set<String> {
        get {
            guard let data = favoriteExercisesData.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return Set(array)
        }
    }

    private func toggleFavorite(_ name: String) {
        var favorites = favoriteExercises
        if favorites.contains(name) {
            favorites.remove(name)
        } else {
            favorites.insert(name)
        }
        if let data = try? JSONEncoder().encode(Array(favorites)),
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
        let filtered = dataManager.exerciseSummaries().filter { exercise in
            searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText)
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

    private var favoriteExerciseRows: [(name: String, stats: ExerciseStats)] {
        guard searchText.isEmpty else { return [] }
        return cachedExercises.filter { favoriteExercises.contains($0.name) }
    }

    private var nonFavoriteExerciseRows: [(name: String, stats: ExerciseStats)] {
        guard searchText.isEmpty else { return cachedExercises }
        return cachedExercises.filter { !favoriteExercises.contains($0.name) }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            VStack(spacing: Theme.Spacing.md) {
                topBar
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.sm)

                searchField
                    .padding(.horizontal, Theme.Spacing.lg)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        if !favoriteExerciseRows.isEmpty {
                            Text("Favorites")
                                .sectionHeaderStyle()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.top, Theme.Spacing.sm)

                            ForEach(favoriteExerciseRows, id: \.name) { exercise in
                                exerciseRow(exercise, showsInlineFavoriteControl: true)
                            }

                            if !nonFavoriteExerciseRows.isEmpty {
                                Text("All")
                                    .sectionHeaderStyle()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, Theme.Spacing.xs)
                                    .padding(.top, Theme.Spacing.md)
                            }
                        }

                        if cachedExercises.isEmpty {
                            ContentUnavailableView(
                                "No matches",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different exercise name.")
                            )
                            .padding(.top, Theme.Spacing.xl)
                        } else {
                            ForEach(nonFavoriteExerciseRows, id: \.name) { exercise in
                                exerciseRow(exercise)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedExercise) { selection in
            ExerciseDetailView(
                exerciseName: selection.id,
                dataManager: dataManager,
                annotationsManager: annotationsManager,
                gymProfilesManager: gymProfilesManager
            )
        }
        .sheet(isPresented: $showingQuickStart) {
            QuickStartView(exerciseName: quickStartExercise)
        }
        .onAppear {
            cachedExercises = buildExercises()
        }
        .onChange(of: searchText) { _, _ in
            cachedExercises = buildExercises()
        }
        .onChange(of: sortOrder) { _, _ in
            cachedExercises = buildExercises()
        }
        .onChange(of: dataManager.workouts) { _, _ in
            cachedExercises = buildExercises()
        }
    }

    private var topBar: some View {
        ZStack {
            HStack {
                AppToolbarIconButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Back",
                    variant: .subtle
                ) {
                    dismiss()
                }
                Spacer()
                sortMenu
            }

            Text("All Exercises")
                .font(Theme.Typography.cardHeader)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort Order", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Label(order.rawValue, systemImage: sortIcon(for: order))
                        .tag(order)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)
                Text(sortOrder.rawValue)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
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
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .glassBackground(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
    }

    private func sortIcon(for order: SortOrder) -> String {
        switch order {
        case .alphabetical:
            return "textformat"
        case .volume:
            return "scalemass"
        case .frequency:
            return "calendar"
        case .recent:
            return "clock"
        }
    }

    private func exerciseRow(
        _ exercise: (name: String, stats: ExerciseStats),
        showsInlineFavoriteControl: Bool = false
    ) -> some View {
        HStack(spacing: 0) {
            NavigationLink(
                destination: ExerciseDetailView(
                    exerciseName: exercise.name,
                    dataManager: dataManager,
                    annotationsManager: annotationsManager,
                    gymProfilesManager: gymProfilesManager
                )
            ) {
                ExerciseRowView(
                    name: exercise.name,
                    stats: exercise.stats,
                    showsCard: false
                )
            }
            .buttonStyle(.plain)

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
                    favoriteExercises.contains(exercise.name) ? "Unfavorite" : "Favorite",
                    systemImage: favoriteExercises.contains(exercise.name) ? "star.slash" : "star"
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

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    ExerciseMetricPill(icon: "repeat", text: "\(stats.frequency)x")
                    ExerciseMetricPill(icon: "scalemass", text: formatWeight(stats.maxWeight))

                    if let lastDate = stats.lastPerformed {
                        ExerciseMetricPill(icon: "clock", text: relativeDateString(for: lastDate))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .modifier(ExerciseRowCardModifier(isEnabled: showsCard))
    }

    private func formatWeight(_ weight: Double) -> String {
        return "\(Int(weight)) lbs"
    }

    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
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

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(Theme.Iconography.micro)
            Text(text)
                .font(Theme.Typography.caption)
        }
        .foregroundColor(Theme.Colors.textSecondary)
    }
}
