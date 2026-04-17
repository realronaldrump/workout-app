import SwiftUI

struct WorkoutHistoryView: View {
    let workouts: [Workout]
    var showsBackButton: Bool = false

    @State private var searchText = ""
    @State private var selectedTimeWindow: HistoryDateWindow = .allTime
    @State private var selectedLocations: Set<HistoryLocationOption>?
    @State private var selectedExercises: Set<HistoryExerciseOption>?
    @State private var selectedDurationBands: Set<HistoryDurationBand>?
    @State private var presentedFilterSheet: HistoryFilterSheet?
    @State private var presentedSummarySheet: HistorySummarySheet?
    @State private var cachedFilteredWorkouts: [Workout] = []
    @State private var cachedGroupedWorkouts: [(month: String, workouts: [Workout])] = []
    @State private var cachedLocationBreakdownItems: [HistoryLocationBreakdownItem] = []
    @State private var cachedAvailableLocationOptions: [HistoryLocationOption] = []
    @State private var cachedAvailableExerciseOptions: [HistoryExerciseOption] = []
    @State private var derivedRefreshTask: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager

    var body: some View {
        let filteredWorkouts = cachedFilteredWorkouts
        let groupedWorkouts = cachedGroupedWorkouts
        let locationBreakdownItems = cachedLocationBreakdownItems

        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header

                    if !workouts.isEmpty {
                        resultsOverviewCard(
                            filteredWorkouts: filteredWorkouts,
                            locationBreakdownItems: locationBreakdownItems
                        )
                        filterDeck
                    }

                    contentSection(groupedWorkouts: groupedWorkouts)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xl)
                .frame(maxWidth: Theme.Layout.maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $presentedFilterSheet) { sheet in
            switch sheet {
            case .location:
                MultiSelectSheet(
                    title: "Filter Locations",
                    items: availableLocationOptions,
                    selectedItems: $selectedLocations,
                    itemTitle: { $0.title },
                    itemSubtitle: { $0.subtitle }
                )
            case .exercise:
                MultiSelectSheet(
                    title: "Filter Exercises",
                    items: availableExerciseOptions,
                    selectedItems: $selectedExercises,
                    itemTitle: { $0.name },
                    itemSubtitle: { $0.subtitle }
                )
            case .duration:
                MultiSelectSheet(
                    title: "Filter Durations",
                    items: HistoryDurationBand.allCases,
                    selectedItems: $selectedDurationBands,
                    itemTitle: { $0.title },
                    itemSubtitle: durationSubtitle(for:)
                )
            }
        }
        .sheet(item: $presentedSummarySheet) { sheet in
            switch sheet {
            case .locations:
                HistoryLocationBreakdownSheet(items: locationBreakdownItems)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear(perform: refreshDerivedState)
        .onChange(of: searchText) { _, _ in
            scheduleDerivedStateRefresh()
        }
        .onChange(of: selectedTimeWindow) { _, _ in
            scheduleDerivedStateRefresh()
        }
        .onChange(of: selectedLocations) { _, _ in
            scheduleDerivedStateRefresh()
        }
        .onChange(of: selectedExercises) { _, _ in
            scheduleDerivedStateRefresh()
        }
        .onChange(of: selectedDurationBands) { _, _ in
            scheduleDerivedStateRefresh()
        }
        .onChange(of: workouts) { _, _ in
            scheduleDerivedStateRefresh(debounceNs: 0)
        }
        .onReceive(annotationsManager.$annotations) { _ in
            scheduleDerivedStateRefresh(debounceNs: 0)
        }
        .onReceive(gymProfilesManager.$gyms) { _ in
            scheduleDerivedStateRefresh(debounceNs: 0)
        }
        .onDisappear {
            derivedRefreshTask?.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if showsBackButton {
                AppToolbarIconButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Back",
                    variant: .subtle
                ) {
                    dismiss()
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("History")
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(1.5)

                Text("Search, then stack filters by place, movement, session length, and recency.")
                    .font(Theme.Typography.microcopy)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            searchField
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textTertiary)

            TextField("Search workouts or exercises", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tint(Theme.Colors.accent)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
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

    private func resultsOverviewCard(
        filteredWorkouts: [Workout],
        locationBreakdownItems: [HistoryLocationBreakdownItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("TRAINING ARCHIVE")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(1.0)

                    Text(resultsHeadline(filteredWorkouts: filteredWorkouts))
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(resultsSubheadline(filteredWorkouts: filteredWorkouts))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.md)

                if activeFilterCount > 0 {
                    Text("\(activeFilterCount) LIVE")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.accentTint)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Theme.Colors.accent.opacity(0.16), lineWidth: 1)
                        )
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.sm)],
                spacing: Theme.Spacing.sm
            ) {
                HistorySummaryMetricTile(
                    title: "Shown",
                    value: "\(filteredWorkouts.count)",
                    tint: Theme.Colors.accent
                )

                HistorySummaryMetricTile(
                    title: "Locations",
                    value: "\(uniqueLocationCount(in: filteredWorkouts))",
                    tint: Theme.Colors.accentSecondary,
                    action: {
                        Haptics.selection()
                        presentedSummarySheet = .locations
                    }
                )

                HistorySummaryMetricTile(
                    title: "Avg Length",
                    value: averageDurationLabel(for: filteredWorkouts),
                    tint: Theme.Colors.success
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.Colors.surface,
                            Theme.Colors.accentTint,
                            Theme.Colors.surfaceRaised
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .strokeBorder(Theme.Colors.border.opacity(0.45), lineWidth: 1)
        )
    }

    private var filterDeck: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("REFINE THE FEED")
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(1.0)

                Text("Dial the archive down to where you trained, what you did, and how long the session ran.")
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Exercise filtering matches any selected movement, so chest days, run days, or mixed sessions stay easy to surface.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TimeRangePillPicker(
                options: HistoryDateWindow.allCases,
                selected: $selectedTimeWindow,
                label: { $0.title }
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 156, maximum: 260), spacing: Theme.Spacing.sm)],
                spacing: Theme.Spacing.sm
            ) {
                HistoryFilterLauncherCard(
                    title: "Location",
                    value: locationSummary,
                    detail: "Saved gyms, deleted gyms, and unassigned sessions.",
                    systemImage: "mappin.and.ellipse",
                    tint: Theme.Colors.accentSecondary,
                    isActive: selectedLocations != nil
                ) {
                    presentedFilterSheet = .location
                }

                HistoryFilterLauncherCard(
                    title: "Exercises",
                    value: exerciseSummary,
                    detail: "Any selected movement counts as a match.",
                    systemImage: "figure.strengthtraining.traditional",
                    tint: Theme.Colors.accent,
                    isActive: selectedExercises != nil
                ) {
                    presentedFilterSheet = .exercise
                }

                HistoryFilterLauncherCard(
                    title: "Duration",
                    value: durationSummary,
                    detail: "Short lifts through long-session grind days.",
                    systemImage: "clock.badge.checkmark",
                    tint: Theme.Colors.success,
                    isActive: selectedDurationBands != nil
                ) {
                    presentedFilterSheet = .duration
                }
            }

            if hasActiveFilters {
                AppPillButton(
                    title: "Clear All Filters",
                    systemImage: "line.3.horizontal.decrease.circle",
                    variant: .subtle
                ) {
                    clearFilters()
                    Haptics.selection()
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .strokeBorder(Theme.Colors.border.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }

    private func contentSection(
        groupedWorkouts: [(month: String, workouts: [Workout])]
    ) -> some View {
        Group {
            if workouts.isEmpty {
                EmptyStateCard(
                    icon: "clock.badge.exclamationmark",
                    tint: Theme.Colors.accent,
                    title: "No History Yet",
                    message: "Import from Strong or start a session to see your workouts here."
                )
                .padding(.top, Theme.Spacing.xl)
            } else if groupedWorkouts.isEmpty {
                VStack(alignment: .center, spacing: Theme.Spacing.md) {
                    EmptyStateCard(
                        icon: "line.3.horizontal.decrease.circle",
                        tint: Theme.Colors.accentSecondary,
                        title: "No Matches",
                        message: "Try a wider date window, remove a few filters, or search with a broader term."
                    )

                    if hasActiveFilters {
                        AppPillButton(
                            title: "Reset Filters",
                            systemImage: "arrow.counterclockwise",
                            variant: .accent
                        ) {
                            clearFilters()
                            Haptics.selection()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.xl)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    // Inline active filter summary — stays visible when scrolled past the filter deck
                    if hasActiveFilters {
                        activeFilterSummaryBar
                    }

                    ForEach(groupedWorkouts, id: \.month) { group in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(group.month.uppercased())
                                .font(Theme.Typography.metricLabel)
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .tracking(1.2)
                                .padding(.leading, 4)

                            VStack(spacing: Theme.Spacing.sm) {
                                ForEach(group.workouts) { workout in
                                    WorkoutHistoryRow(workout: workout)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var availableLocationOptions: [HistoryLocationOption] {
        cachedAvailableLocationOptions
    }

    private func buildAvailableLocationOptions() -> [HistoryLocationOption] {
        var countsByID: [String: Int] = [:]
        var optionByID: [String: HistoryLocationOption] = [:]

        for workout in workouts {
            let option = locationOption(for: workout)
            countsByID[option.id, default: 0] += 1
            optionByID[option.id] = option
        }

        return optionByID.values
            .map { option in
                HistoryLocationOption(
                    kind: option.kind,
                    title: option.title,
                    subtitle: optionSubtitle(
                        baseSubtitle: option.subtitle,
                        workoutCount: countsByID[option.id, default: 0]
                    ),
                    sortOrder: option.sortOrder
                )
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var availableExerciseOptions: [HistoryExerciseOption] {
        cachedAvailableExerciseOptions
    }

    private func buildAvailableExerciseOptions() -> [HistoryExerciseOption] {
        var counts: [String: Int] = [:]

        for workout in workouts {
            for exerciseName in Set(workout.exercises.map(\.name)) {
                counts[exerciseName, default: 0] += 1
            }
        }

        return counts.map { name, workoutCount in
            HistoryExerciseOption(
                name: name,
                workoutCount: workoutCount,
                subtitle: optionSubtitle(baseSubtitle: nil, workoutCount: workoutCount)
            )
        }
        .sorted { lhs, rhs in
            if lhs.workoutCount != rhs.workoutCount {
                return lhs.workoutCount > rhs.workoutCount
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var hasActiveFilters: Bool {
        !searchText.isEmpty
        || selectedTimeWindow != .allTime
        || selectedLocations != nil
        || selectedExercises != nil
        || selectedDurationBands != nil
    }

    private var activeFilterSummaryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accentSecondary)

                if selectedTimeWindow != .allTime {
                    filterPill(selectedTimeWindow.title, tint: Theme.Colors.accentSecondary)
                }
                if selectedLocations != nil {
                    filterPill(locationSummary, tint: Theme.Colors.accentSecondary)
                }
                if selectedExercises != nil {
                    filterPill(exerciseSummary, tint: Theme.Colors.accentSecondary)
                }
                if selectedDurationBands != nil {
                    filterPill(durationSummary, tint: Theme.Colors.accentSecondary)
                }
                if !searchText.isEmpty {
                    filterPill("\"\(searchText)\"", tint: Theme.Colors.textSecondary)
                }

                Button {
                    clearFilters()
                    Haptics.selection()
                } label: {
                    Text("Clear")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.error)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func filterPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.Typography.captionBold)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                Capsule().fill(tint.opacity(Theme.Opacity.subtleFill))
            )
            .lineLimit(1)
    }

    private var activeFilterCount: Int {
        [
            !searchText.isEmpty,
            selectedTimeWindow != .allTime,
            selectedLocations != nil,
            selectedExercises != nil,
            selectedDurationBands != nil
        ]
        .filter { $0 }
        .count
    }

    private var locationSummary: String {
        selectionSummary(
            selected: selectedLocations,
            allLabel: "All places",
            emptyLabel: "No places",
            singularTransform: { $0.title },
            pluralLabel: "places"
        )
    }

    private var exerciseSummary: String {
        selectionSummary(
            selected: selectedExercises,
            allLabel: "All movements",
            emptyLabel: "No movements",
            singularTransform: { $0.name },
            pluralLabel: "movements"
        )
    }

    private var durationSummary: String {
        selectionSummary(
            selected: selectedDurationBands,
            allLabel: "Any length",
            emptyLabel: "No lengths",
            singularTransform: { $0.title },
            pluralLabel: "bands"
        )
    }

    private func filteredWorkouts() -> [Workout] {
        workouts.filter { workout in
            matchesSearch(workout)
            && matchesTimeWindow(workout)
            && matchesLocation(workout)
            && matchesExercises(workout)
            && matchesDuration(workout)
        }
    }

    private func buildGroupedWorkouts(from workouts: [Workout]) -> [(month: String, workouts: [Workout])] {
        let grouped = Dictionary(grouping: workouts) { workout in
            let calendar = Calendar.current
            return calendar.dateInterval(of: .month, for: workout.date)?.start
                ?? calendar.startOfDay(for: workout.date)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { monthStart, workouts in
                (
                    month: monthStart.formatted(.dateTime.year().month(.wide)),
                    workouts: workouts.sorted { $0.date > $1.date }
                )
            }
    }

    private func matchesSearch(_ workout: Workout) -> Bool {
        guard !searchText.isEmpty else { return true }
        return workout.name.localizedCaseInsensitiveContains(searchText)
            || workout.exercises.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func matchesTimeWindow(_ workout: Workout) -> Bool {
        selectedTimeWindow.contains(
            workout.date,
            referenceDate: Date(),
            calendar: Calendar.current
        )
    }

    private func matchesLocation(_ workout: Workout) -> Bool {
        guard let selectedLocations else { return true }
        guard !selectedLocations.isEmpty else { return false }
        return selectedLocations.contains(locationOption(for: workout))
    }

    private func matchesExercises(_ workout: Workout) -> Bool {
        guard let selectedExercises else { return true }
        guard !selectedExercises.isEmpty else { return false }

        let names = Set(workout.exercises.map(\.name))
        return selectedExercises.contains { names.contains($0.name) }
    }

    private func matchesDuration(_ workout: Workout) -> Bool {
        guard let selectedDurationBands else { return true }
        guard !selectedDurationBands.isEmpty else { return false }

        let minutes = workout.estimatedDurationMinutes()
        return selectedDurationBands.contains { $0.contains(minutes: minutes) }
    }

    private func durationSubtitle(for band: HistoryDurationBand) -> String {
        optionSubtitle(
            baseSubtitle: band.subtitle,
            workoutCount: workouts.filter { band.contains(minutes: $0.estimatedDurationMinutes()) }.count
        )
    }

    private func resultsHeadline(filteredWorkouts: [Workout]) -> String {
        if hasActiveFilters {
            if filteredWorkouts.isEmpty {
                return "Nothing matches the current filter stack."
            }
            return "\(filteredWorkouts.count) of \(workouts.count) workouts are in view."
        }
        return "\(workouts.count) workouts ready to browse."
    }

    private func resultsSubheadline(filteredWorkouts: [Workout]) -> String {
        if filteredWorkouts.isEmpty {
            return "Try a broader search, a wider time window, or clear one of the filters below."
        }

        var fragments: [String] = []
        if selectedTimeWindow != .allTime {
            fragments.append(selectedTimeWindow.summaryLabel)
        }
        if let selectedLocations {
            fragments.append(selectedLocations.isEmpty ? "0 places selected" : "\(selectedLocations.count) places selected")
        }
        if let selectedExercises {
            fragments.append(selectedExercises.isEmpty ? "0 movements selected" : "\(selectedExercises.count) movements selected")
        }
        if let selectedDurationBands {
            fragments.append(selectedDurationBands.isEmpty ? "0 length bands selected" : "\(selectedDurationBands.count) length bands selected")
        }

        if fragments.isEmpty {
            return "Use the filters below to isolate a gym, a movement family, or a tighter training window."
        }

        return fragments.joined(separator: " • ")
    }

    private func averageDurationLabel(for workouts: [Workout]) -> String {
        guard !workouts.isEmpty else { return "0m" }

        let totalMinutes = workouts.reduce(0) { partialResult, workout in
            partialResult + workout.estimatedDurationMinutes()
        }
        let averageMinutes = Double(totalMinutes) / Double(workouts.count)
        return SharedFormatters.durationMinutes(averageMinutes)
    }

    private func uniqueLocationCount(in workouts: [Workout]) -> Int {
        Set(workouts.map { locationOption(for: $0).id }).count
    }

    private func buildLocationBreakdownItems(from workouts: [Workout]) -> [HistoryLocationBreakdownItem] {
        let grouped = Dictionary(grouping: workouts, by: locationOption(for:))

        return grouped.compactMap { option, groupedWorkouts in
            guard let lastWorkoutDate = groupedWorkouts.map(\.date).max() else { return nil }

            return HistoryLocationBreakdownItem(
                option: option,
                workoutCount: groupedWorkouts.count,
                lastWorkoutDate: lastWorkoutDate
            )
        }
        .sorted { lhs, rhs in
            if lhs.workoutCount != rhs.workoutCount {
                return lhs.workoutCount > rhs.workoutCount
            }
            if lhs.lastWorkoutDate != rhs.lastWorkoutDate {
                return lhs.lastWorkoutDate > rhs.lastWorkoutDate
            }
            if lhs.option.sortOrder != rhs.option.sortOrder {
                return lhs.option.sortOrder < rhs.option.sortOrder
            }
            return lhs.option.title.localizedCaseInsensitiveCompare(rhs.option.title) == .orderedAscending
        }
    }

    private func locationOption(for workout: Workout) -> HistoryLocationOption {
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId

        guard let gymId else {
            return HistoryLocationOption(
                kind: .unassigned,
                title: "Unassigned",
                subtitle: "No gym attached",
                sortOrder: 90
            )
        }

        if let gym = gymProfilesManager.gyms.first(where: { $0.id == gymId }) {
            return HistoryLocationOption(
                kind: .gym(gym.id),
                title: gym.name,
                subtitle: gym.address ?? "Saved gym",
                sortOrder: 0
            )
        }

        return HistoryLocationOption(
            kind: .deleted,
            title: "Deleted Gym",
            subtitle: "Original gym no longer saved",
            sortOrder: 95
        )
    }

    private func optionSubtitle(baseSubtitle: String?, workoutCount: Int) -> String {
        let countLabel = "\(workoutCount) workout" + (workoutCount == 1 ? "" : "s")
        guard let baseSubtitle, !baseSubtitle.isEmpty else { return countLabel }
        return "\(baseSubtitle) • \(countLabel)"
    }

    private func clearFilters() {
        searchText = ""
        selectedTimeWindow = .allTime
        selectedLocations = nil
        selectedExercises = nil
        selectedDurationBands = nil
        refreshDerivedState()
    }

    private func sanitizeSelections() {
        selectedLocations = sanitizedSelection(selectedLocations, validItems: cachedAvailableLocationOptions)
        selectedExercises = sanitizedSelection(selectedExercises, validItems: cachedAvailableExerciseOptions)
    }

    private func scheduleDerivedStateRefresh(debounceNs: UInt64 = 120_000_000) {
        derivedRefreshTask?.cancel()
        derivedRefreshTask = Task { @MainActor in
            if debounceNs > 0 {
                try? await Task.sleep(nanoseconds: debounceNs)
            }
            guard !Task.isCancelled else { return }
            refreshDerivedState()
        }
    }

    private func refreshDerivedState() {
        cachedAvailableLocationOptions = buildAvailableLocationOptions()
        cachedAvailableExerciseOptions = buildAvailableExerciseOptions()
        sanitizeSelections()
        let filtered = filteredWorkouts()
        cachedFilteredWorkouts = filtered
        cachedGroupedWorkouts = buildGroupedWorkouts(from: filtered)
        cachedLocationBreakdownItems = buildLocationBreakdownItems(from: filtered)
    }

    private func sanitizedSelection<Item: Hashable>(
        _ selection: Set<Item>?,
        validItems: [Item]
    ) -> Set<Item>? {
        guard let selection else { return nil }
        let validSet = Set(validItems)

        guard !validSet.isEmpty else { return nil }
        if selection.isEmpty { return [] }

        let sanitized = selection.intersection(validSet)
        if sanitized.isEmpty { return nil }
        if sanitized.count == validSet.count { return nil }
        return sanitized
    }

    private func selectionSummary<Item>(
        selected: Set<Item>?,
        allLabel: String,
        emptyLabel: String,
        singularTransform: (Item) -> String,
        pluralLabel: String
    ) -> String {
        guard let selected else { return allLabel }
        guard !selected.isEmpty else { return emptyLabel }
        if selected.count == 1, let item = selected.first {
            return singularTransform(item)
        }
        return "\(selected.count) \(pluralLabel)"
    }
}

struct WorkoutHistoryRow: View {
    let workout: Workout
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @EnvironmentObject var sessionManager: WorkoutSessionManager
    @EnvironmentObject var dataManager: WorkoutDataManager
    @AppStorage("weightIncrement") private var weightIncrement: Double = 2.5

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(workout.name)
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text(workout.date.formatted(date: .omitted, time: .shortened))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }

                        Text(workout.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        GymBadge(text: gymLabel, style: gymBadgeStyle)

                        HStack(spacing: 12) {
                            metric(workout.duration, systemImage: "clock")
                            metric("\(workout.exercises.count) exercises", systemImage: "figure.strengthtraining.traditional")
                            metric(SharedFormatters.volumeWithUnit(workout.totalVolume), systemImage: "scalemass")
                        }
                        .font(Theme.Typography.captionBold)
                        .padding(.top, 4)

                        if let data = healthManager.getHealthData(for: workout.id) {
                            HealthDataSummaryView(healthData: data)
                                .padding(.top, Theme.Spacing.xs)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(workout.name), \(workout.date.formatted(date: .abbreviated, time: .shortened)), "
                    + "\(workout.duration), \(workout.exercises.count) exercises, "
                    + "\(SharedFormatters.volumeWithUnit(workout.totalVolume))"
                )
                .accessibilityHint("Double tap for workout details, swipe left to repeat")
            }
            .buttonStyle(.plain)

            Button {
                Haptics.selection()
                repeatThisWorkout()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(Theme.Typography.caption2Bold)
                    .foregroundColor(Theme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.accentTint)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat \(workout.name)")
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Haptics.selection()
                repeatThisWorkout()
            } label: {
                Label("Repeat", systemImage: "arrow.counterclockwise")
            }
            .tint(Theme.Colors.accent)
        }
    }

    private func metric(_ value: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(Theme.Typography.captionStrong)
                .foregroundStyle(Theme.Colors.accentSecondary)
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(value)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var gymLabel: String {
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
        if let name = gymProfilesManager.gymName(for: gymId) {
            return name
        }
        return gymId == nil ? "Unassigned" : "Deleted gym"
    }

    private var gymBadgeStyle: GymBadgeStyle {
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
        if gymId == nil {
            return .unassigned
        }
        return gymProfilesManager.gymName(for: gymId) == nil ? .deleted : .assigned
    }

    private func repeatThisWorkout() {
        let exercises = workout.exercises.map { $0.name }
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId

        sessionManager.startSession(
            name: workout.name,
            gymProfileId: gymId
        )

        let increment = weightIncrement > 0 ? weightIncrement : 2.5
        for exerciseName in exercises {
            let tags = ExerciseMetadataManager.shared.resolvedTags(for: exerciseName)
            let isCardio = tags.contains(where: { $0.builtInGroup == .cardio })

            if isCardio {
                sessionManager.addExercise(name: exerciseName)
            } else {
                let history = dataManager.getExerciseHistory(for: exerciseName)
                let rec = ExerciseRecommendationEngine.recommend(
                    exerciseName: exerciseName,
                    history: history,
                    weightIncrement: increment
                )
                let midReps = (rec.repRange.lowerBound + rec.repRange.upperBound) / 2
                sessionManager.addExercise(
                    name: exerciseName,
                    initialSetPrefill: SetPrefill(weight: rec.suggestedWeight, reps: midReps)
                )
            }
        }

        sessionManager.isPresentingSessionUI = true
        Haptics.notify(.success)
    }
}
