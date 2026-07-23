import Charts
import SwiftUI

nonisolated struct HistoryRowMetrics: Hashable, Sendable {
    let volume: Double
    let exerciseCount: Int
    let gymName: String?
    let gymIsDeleted: Bool
}

nonisolated struct HistoryRowModel: Identifiable, Hashable, Sendable {
    let workout: Workout
    let metrics: HistoryRowMetrics

    var id: UUID { workout.id }
}

nonisolated struct HistoryMonthSection: Identifiable, Hashable, Sendable {
    let id: Date
    let title: String
    let count: Int
    let volume: Double
    let delta: TrendDelta?
    let rows: [HistoryRowModel]
}

nonisolated struct HistoryMonthChartPoint: Identifiable, Hashable, Sendable {
    let monthStart: Date
    let count: Int

    var id: Date { monthStart }
}

nonisolated struct HistoryDerivedState: Sendable {
    let monthSections: [HistoryMonthSection]
    let locationOptions: [HistoryLocationOption]
    let exerciseOptions: [HistoryExerciseOption]
    let locationBreakdown: [HistoryLocationBreakdownItem]
    let monthlyChart: [HistoryMonthChartPoint]
    let filteredCount: Int
    let totalCount: Int
    let totalVolume: Double
    let averageDurationMinutes: Double
    let firstWorkoutDate: Date?
    let isReady: Bool

    static let empty = HistoryDerivedState(
        monthSections: [],
        locationOptions: [],
        exerciseOptions: [],
        locationBreakdown: [],
        monthlyChart: [],
        filteredCount: 0,
        totalCount: 0,
        totalVolume: 0,
        averageDurationMinutes: 0,
        firstWorkoutDate: nil,
        isReady: false
    )
}

private nonisolated struct HistoryGymSnapshot: Hashable, Sendable {
    let name: String
    let address: String?
}

private nonisolated struct HistoryRowMetricsInput: Hashable, Sendable {
    let workout: Workout
    let resolver: ExerciseIdentityResolver
    let gymID: UUID?
    let gymName: String?
}

private nonisolated struct HistoryDerivedSnapshot: Sendable {
    let workouts: [Workout]
    let searchText: String
    let dateWindow: HistoryDateWindow
    let selectedLocations: Set<HistoryLocationOption>?
    let selectedExercises: Set<HistoryExerciseOption>?
    let selectedDurationBands: Set<HistoryDurationBand>?
    let gymIDByWorkout: [UUID: UUID]
    let gymsByID: [UUID: HistoryGymSnapshot]
    let resolver: ExerciseIdentityResolver
    let referenceDate: Date
}

private nonisolated struct HistorySectionDraft: Sendable {
    let date: Date
    let title: String
    let volume: Double
    let rows: [HistoryRowModel]
}

private nonisolated enum HistoryDerivedStateBuilder {
    static func build(from snapshot: HistoryDerivedSnapshot) throws -> HistoryDerivedState {
        let calendar = Calendar.current
        let locationOptions = try buildLocationOptions(from: snapshot)
        let exerciseOptions = try buildExerciseOptions(from: snapshot)
        let query = snapshot.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var filtered: [Workout] = []
        filtered.reserveCapacity(snapshot.workouts.count)
        for (index, workout) in snapshot.workouts.enumerated() {
            try checkCancellation(at: index)
            let names = exerciseFilterNames(for: workout, resolver: snapshot.resolver)
            let isMatch = matchesSearch(workout, names: names, query: query)
                && snapshot.dateWindow.contains(
                    workout.date,
                    referenceDate: snapshot.referenceDate,
                    calendar: calendar
                )
                && matchesLocation(workout, snapshot: snapshot)
                && matchesExercises(names, selected: snapshot.selectedExercises)
                && matchesDuration(workout, selected: snapshot.selectedDurationBands)
            if isMatch {
                filtered.append(workout)
            }
        }

        let grouped = Dictionary(grouping: filtered) { workout in
            calendar.dateInterval(of: .month, for: workout.date)?.start
                ?? calendar.startOfDay(for: workout.date)
        }
        let sortedGroups = grouped.sorted { $0.key > $1.key }

        var sectionDrafts: [HistorySectionDraft] = []
        sectionDrafts.reserveCapacity(sortedGroups.count)

        for (groupIndex, group) in sortedGroups.enumerated() {
            try checkCancellation(at: groupIndex)
            let monthStart = group.key
            let workouts = group.value.sorted { $0.date > $1.date }
            var rows: [HistoryRowModel] = []
            rows.reserveCapacity(workouts.count)
            for (index, workout) in workouts.enumerated() {
                try checkCancellation(at: index)
                let summary = ExerciseAggregation.summary(for: workout, resolver: snapshot.resolver)
                let gymID = snapshot.gymIDByWorkout[workout.id]
                let gym = gymID.flatMap { snapshot.gymsByID[$0] }
                rows.append(
                    HistoryRowModel(
                        workout: workout,
                        metrics: HistoryRowMetrics(
                            volume: summary.volume,
                            exerciseCount: summary.exerciseCount,
                            gymName: gym?.name ?? (gymID == nil ? nil : "Deleted gym"),
                            gymIsDeleted: gymID != nil && gym == nil
                        )
                    )
                )
            }
            sectionDrafts.append(
                HistorySectionDraft(
                    date: monthStart,
                    title: monthStart.formatted(.dateTime.year().month(.wide)),
                    volume: rows.reduce(0) { $0 + $1.metrics.volume },
                    rows: rows
                )
            )
        }

        let sections = sectionDrafts.enumerated().map { index, draft in
            let olderDraft = sectionDrafts.indices.contains(index + 1)
                ? sectionDrafts[index + 1]
                : nil
            let olderVolume: Double? = olderDraft.map { older in
                guard calendar.isDate(draft.date, equalTo: snapshot.referenceDate, toGranularity: .month) else {
                    return older.volume
                }

                let elapsedDay = calendar.component(.day, from: snapshot.referenceDate)
                let olderMonthRange = calendar.range(of: .day, in: .month, for: older.date)
                let comparisonDay = min(elapsedDay, olderMonthRange?.count ?? elapsedDay)
                var components = calendar.dateComponents([.year, .month], from: older.date)
                components.day = comparisonDay
                guard let cutoffDay = calendar.date(from: components),
                      let cutoff = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: cutoffDay) else {
                    return older.volume
                }
                return older.rows
                    .filter { $0.workout.date <= cutoff }
                    .reduce(0) { $0 + $1.metrics.volume }
            }
            return HistoryMonthSection(
                id: draft.date,
                title: draft.title,
                count: draft.rows.count,
                volume: draft.volume,
                delta: olderVolume.flatMap {
                    TrendDelta(current: draft.volume, previous: $0, higherIsBetter: true)
                },
                rows: draft.rows
            )
        }

        let totalVolume = sections.reduce(0) { $0 + $1.volume }
        let averageDuration = filtered.isEmpty
            ? 0
            : Double(filtered.reduce(0) { $0 + $1.estimatedDurationMinutes() }) / Double(filtered.count)
        let locationBreakdown = try buildLocationBreakdown(from: filtered, snapshot: snapshot)

        return HistoryDerivedState(
            monthSections: sections,
            locationOptions: locationOptions,
            exerciseOptions: exerciseOptions,
            locationBreakdown: locationBreakdown,
            monthlyChart: sections.prefix(12).reversed().map {
                HistoryMonthChartPoint(monthStart: $0.id, count: $0.count)
            },
            filteredCount: filtered.count,
            totalCount: snapshot.workouts.count,
            totalVolume: totalVolume,
            averageDurationMinutes: averageDuration,
            firstWorkoutDate: snapshot.workouts.map(\.date).min(),
            isReady: true
        )
    }

    private static func matchesSearch(
        _ workout: Workout,
        names: Set<String>,
        query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }
        return workout.name.localizedCaseInsensitiveContains(query)
            || names.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private static func matchesLocation(
        _ workout: Workout,
        snapshot: HistoryDerivedSnapshot
    ) -> Bool {
        guard let selected = snapshot.selectedLocations else { return true }
        guard !selected.isEmpty else { return false }
        return selected.contains(locationOption(for: workout, snapshot: snapshot))
    }

    private static func matchesExercises(
        _ names: Set<String>,
        selected: Set<HistoryExerciseOption>?
    ) -> Bool {
        guard let selected else { return true }
        guard !selected.isEmpty else { return false }
        let normalizedNames = Set(names.map(ExerciseIdentityResolver.normalizedName))
        return selected.contains {
            normalizedNames.contains(ExerciseIdentityResolver.normalizedName($0.name))
        }
    }

    private static func matchesDuration(
        _ workout: Workout,
        selected: Set<HistoryDurationBand>?
    ) -> Bool {
        guard let selected else { return true }
        guard !selected.isEmpty else { return false }
        let minutes = workout.estimatedDurationMinutes()
        return selected.contains { $0.contains(minutes: minutes) }
    }

    private static func exerciseFilterNames(
        for workout: Workout,
        resolver: ExerciseIdentityResolver
    ) -> Set<String> {
        workout.exercises.reduce(into: Set<String>()) { names, exercise in
            let rawName = ExerciseIdentityResolver.trimmedName(exercise.name)
            guard !rawName.isEmpty else { return }
            names.insert(rawName)
            names.insert(resolver.aggregateName(for: rawName))
        }
    }

    private static func buildLocationOptions(
        from snapshot: HistoryDerivedSnapshot
    ) throws -> [HistoryLocationOption] {
        var countsByID: [String: Int] = [:]
        var optionByID: [String: HistoryLocationOption] = [:]

        for (index, workout) in snapshot.workouts.enumerated() {
            try checkCancellation(at: index)
            let option = locationOption(for: workout, snapshot: snapshot)
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
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private static func buildExerciseOptions(
        from snapshot: HistoryDerivedSnapshot
    ) throws -> [HistoryExerciseOption] {
        var counts: [String: Int] = [:]

        for (index, workout) in snapshot.workouts.enumerated() {
            try checkCancellation(at: index)
            for name in exerciseFilterNames(for: workout, resolver: snapshot.resolver) {
                counts[name, default: 0] += 1
            }
        }

        return counts.map { name, count in
            HistoryExerciseOption(
                name: name,
                workoutCount: count,
                subtitle: optionSubtitle(baseSubtitle: nil, workoutCount: count)
            )
        }
        .sorted { lhs, rhs in
            if lhs.workoutCount != rhs.workoutCount { return lhs.workoutCount > rhs.workoutCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func buildLocationBreakdown(
        from workouts: [Workout],
        snapshot: HistoryDerivedSnapshot
    ) throws -> [HistoryLocationBreakdownItem] {
        var grouped: [HistoryLocationOption: [Workout]] = [:]
        for (index, workout) in workouts.enumerated() {
            try checkCancellation(at: index)
            grouped[locationOption(for: workout, snapshot: snapshot), default: []].append(workout)
        }

        var items: [HistoryLocationBreakdownItem] = []
        items.reserveCapacity(grouped.count)
        for (index, entry) in grouped.enumerated() {
            try checkCancellation(at: index)
            guard let lastDate = entry.value.map(\.date).max() else { continue }
            items.append(
                HistoryLocationBreakdownItem(
                    option: entry.key,
                    workoutCount: entry.value.count,
                    lastWorkoutDate: lastDate
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.workoutCount != rhs.workoutCount { return lhs.workoutCount > rhs.workoutCount }
            if lhs.lastWorkoutDate != rhs.lastWorkoutDate { return lhs.lastWorkoutDate > rhs.lastWorkoutDate }
            if lhs.option.sortOrder != rhs.option.sortOrder {
                return lhs.option.sortOrder < rhs.option.sortOrder
            }
            return lhs.option.title.localizedCaseInsensitiveCompare(rhs.option.title) == .orderedAscending
        }
    }

    private static func locationOption(
        for workout: Workout,
        snapshot: HistoryDerivedSnapshot
    ) -> HistoryLocationOption {
        guard let gymID = snapshot.gymIDByWorkout[workout.id] else {
            return HistoryLocationOption(
                kind: .unassigned,
                title: "Unassigned",
                subtitle: "No gym attached",
                sortOrder: 90
            )
        }

        if let gym = snapshot.gymsByID[gymID] {
            return HistoryLocationOption(
                kind: .gym(gymID),
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

    private static func optionSubtitle(baseSubtitle: String?, workoutCount: Int) -> String {
        let count = "\(workoutCount) workout" + (workoutCount == 1 ? "" : "s")
        guard let baseSubtitle, !baseSubtitle.isEmpty else { return count }
        return "\(baseSubtitle) • \(count)"
    }

    private static func checkCancellation(at index: Int) throws {
        if index.isMultiple(of: 64) {
            try Task.checkCancellation()
        }
    }
}

struct WorkoutHistoryView: View {
    let workouts: [Workout]
    var showsBackButton = false

    @State private var searchText = ""
    @State private var selectedTimeWindow: HistoryDateWindow = .allTime
    @State private var selectedLocations: Set<HistoryLocationOption>?
    @State private var selectedExercises: Set<HistoryExerciseOption>?
    @State private var selectedDurationBands: Set<HistoryDurationBand>?
    @State private var presentedFilterSheet: HistoryFilterSheet?
    @State private var presentedSummarySheet: HistorySummarySheet?
    @State private var derivedState = HistoryDerivedState.empty
    @State private var locallyDeletedWorkoutIDs: Set<UUID> = []
    @State private var recentlyDeletedWorkout: LoggedWorkout?
    @State private var derivedRefreshTask: Task<Void, Never>?
    @State private var derivedWorkerTask: Task<HistoryDerivedState?, Never>?

    @EnvironmentObject private var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var logStore: WorkoutLogStore
    @ObservedObject private var relationshipManager = ExerciseRelationshipManager.shared

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header

                    if derivedState.isReady && derivedState.totalCount > 0 {
                        filterChips
                    }

                    content
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xl)
                .frame(maxWidth: Theme.Layout.maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Workouts or exercises"
        )
        .safeAreaInset(edge: .bottom, spacing: Theme.Spacing.sm) {
            if let recentlyDeletedWorkout {
                deletionUndoBar(recentlyDeletedWorkout)
            }
        }
        .sheet(item: $presentedFilterSheet) { sheet in
            switch sheet {
            case .location:
                MultiSelectSheet(
                    title: "Filter Locations",
                    items: derivedState.locationOptions,
                    selectedItems: $selectedLocations,
                    itemTitle: { $0.title },
                    itemSubtitle: { $0.subtitle }
                )
            case .exercise:
                MultiSelectSheet(
                    title: "Filter Exercises",
                    items: derivedState.exerciseOptions,
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
                HistoryLocationBreakdownSheet(items: derivedState.locationBreakdown)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear { scheduleDerivedStateRefresh(debounceNs: 0) }
        .onChange(of: searchText) { _, _ in scheduleDerivedStateRefresh() }
        .onChange(of: selectedTimeWindow) { _, _ in scheduleDerivedStateRefresh() }
        .onChange(of: selectedLocations) { _, _ in scheduleDerivedStateRefresh() }
        .onChange(of: selectedExercises) { _, _ in scheduleDerivedStateRefresh() }
        .onChange(of: selectedDurationBands) { _, _ in scheduleDerivedStateRefresh() }
        .onChange(of: workouts) { _, newWorkouts in
            locallyDeletedWorkoutIDs.formIntersection(Set(newWorkouts.map(\.id)))
            scheduleDerivedStateRefresh(debounceNs: 0)
        }
        .onReceive(annotationsManager.$annotations) { _ in
            scheduleDerivedStateRefresh(debounceNs: 0)
        }
        .onReceive(gymProfilesManager.$gyms) { _ in
            scheduleDerivedStateRefresh(debounceNs: 0)
        }
        .onChange(of: relationshipManager.relationships) { _, _ in
            scheduleDerivedStateRefresh(debounceNs: 0)
        }
        .onDisappear {
            derivedRefreshTask?.cancel()
            derivedWorkerTask?.cancel()
        }
    }

    private var header: some View {
        Text(historySubtitle)
            .font(Theme.Typography.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historySubtitle: String {
        let count = derivedState.isReady ? derivedState.totalCount : workouts.count
        let workoutLabel = "\(count) workout" + (count == 1 ? "" : "s")
        guard let date = derivedState.firstWorkoutDate else { return workoutLabel }
        return "\(workoutLabel) · since \(date.formatted(.dateTime.month(.abbreviated).year()))"
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.Spacing.sm) {
                Menu {
                    ForEach(HistoryDateWindow.allCases, id: \.self) { window in
                        Button {
                            selectedTimeWindow = window
                            Haptics.selection()
                        } label: {
                            if selectedTimeWindow == window {
                                Label(window.title, systemImage: "checkmark")
                            } else {
                                Text(window.title)
                            }
                        }
                    }
                } label: {
                    HistoryFilterChipLabel(
                        title: selectedTimeWindow.title,
                        systemImage: "calendar",
                        isActive: selectedTimeWindow != .allTime,
                        showsChevron: true
                    )
                }

                filterChip(
                    title: selectionTitle("Location", count: selectedLocations?.count),
                    systemImage: "mappin.and.ellipse",
                    isActive: selectedLocations != nil
                ) {
                    presentedFilterSheet = .location
                }

                filterChip(
                    title: selectionTitle("Exercises", count: selectedExercises?.count),
                    systemImage: "figure.strengthtraining.traditional",
                    isActive: selectedExercises != nil
                ) {
                    presentedFilterSheet = .exercise
                }

                filterChip(
                    title: selectionTitle("Duration", count: selectedDurationBands?.count),
                    systemImage: "clock",
                    isActive: selectedDurationBands != nil
                ) {
                    presentedFilterSheet = .duration
                }

                if hasActiveFilters {
                    Button {
                        clearFilters()
                        Haptics.selection()
                    } label: {
                        Text("Reset")
                            .font(Theme.Typography.captionStrong)
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    private func filterChip(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HistoryFilterChipLabel(
                title: title,
                systemImage: systemImage,
                isActive: isActive
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if !derivedState.isReady {
            ProgressView()
                .tint(Theme.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xxl)
        } else if derivedState.totalCount == 0 {
            EmptyStateCard(
                icon: "clock.badge.exclamationmark",
                tint: Theme.Colors.accent,
                title: "No History Yet",
                message: "Import workouts or finish a session to start your history."
            )
            .padding(.top, Theme.Spacing.lg)
        } else if derivedState.monthSections.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                EmptyStateCard(
                    icon: "line.3.horizontal.decrease.circle",
                    tint: Theme.Colors.accentSecondary,
                    title: "No Matches",
                    message: "Broaden your search or reset the active filters."
                )

                AppPillButton(
                    title: "Reset Filters",
                    systemImage: "arrow.counterclockwise",
                    variant: .accent
                ) {
                    clearFilters()
                    Haptics.selection()
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            overviewStrip

            ForEach(derivedState.monthSections) { section in
                monthSection(section)
            }
        }
    }

    private var overviewStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                overviewSummary
                Spacer(minLength: Theme.Spacing.sm)
                overviewChart
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                overviewSummary
                overviewChart
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }

    private var overviewSummary: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Button {
                    Haptics.selection()
                    presentedSummarySheet = .locations
                } label: {
                    Text("\(derivedState.filteredCount) workout" + (derivedState.filteredCount == 1 ? "" : "s"))
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Show location breakdown")

                Text(
                    "avg \(SharedFormatters.durationMinutes(derivedState.averageDurationMinutes))"
                    + (derivedState.totalVolume > 0
                        ? " · \(SharedFormatters.volumeWithUnit(derivedState.totalVolume))"
                        : "")
                )
                .font(Theme.Typography.captionStrong)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
    }

    private var overviewChart: some View {
            Chart(derivedState.monthlyChart) { point in
                BarMark(
                    x: .value("Month", point.monthStart, unit: .month),
                    y: .value("Workouts", point.count)
                )
                .foregroundStyle(Theme.Colors.accent.gradient)
                .cornerRadius(3)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 124, height: 56)
            .accessibilityLabel("Workouts per month for the current results")
    }

    private func monthSection(_ section: HistoryMonthSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                    monthTitle(section)
                    Spacer(minLength: Theme.Spacing.xs)
                    monthMetadata(section)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    monthTitle(section)
                    monthMetadata(section)
                }
            }

            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(section.rows) { row in
                    WorkoutHistoryRow(
                        workout: row.workout,
                        onDeleted: { loggedWorkoutDeleted($0) },
                        precomputedMetrics: row.metrics
                    )
                }
            }
        }
    }

    private func monthTitle(_ section: HistoryMonthSection) -> some View {
        Text(section.title)
            .font(Theme.Typography.sectionHeader2)
            .foregroundStyle(Theme.Colors.textPrimary)
    }

    private func monthMetadata(_ section: HistoryMonthSection) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(monthSummary(section))
                .font(Theme.Typography.captionStrong)
                .foregroundStyle(Theme.Colors.textSecondary)

            if let delta = section.delta {
                DeltaTag(delta: delta)
            }
        }
    }

    private func monthSummary(_ section: HistoryMonthSection) -> String {
        let count = "\(section.count)"
        guard section.volume > 0 else { return count }
        return "\(count) · \(SharedFormatters.volumeWithUnit(section.volume))"
    }

    private var visibleWorkouts: [Workout] {
        guard !locallyDeletedWorkoutIDs.isEmpty else { return workouts }
        return workouts.filter { !locallyDeletedWorkoutIDs.contains($0.id) }
    }

    private var hasActiveFilters: Bool {
        !searchText.isEmpty
            || selectedTimeWindow != .allTime
            || selectedLocations != nil
            || selectedExercises != nil
            || selectedDurationBands != nil
    }

    private func selectionTitle(_ title: String, count: Int?) -> String {
        guard let count else { return title }
        return "\(title) · \(count)"
    }

    private func durationSubtitle(for band: HistoryDurationBand) -> String {
        let count = visibleWorkouts.filter {
            band.contains(minutes: $0.estimatedDurationMinutes())
        }.count
        return "\(band.subtitle) • \(count) workout" + (count == 1 ? "" : "s")
    }

    private func clearFilters() {
        searchText = ""
        selectedTimeWindow = .allTime
        selectedLocations = nil
        selectedExercises = nil
        selectedDurationBands = nil
        scheduleDerivedStateRefresh(debounceNs: 0)
    }

    private func loggedWorkoutDeleted(_ workout: LoggedWorkout) {
        locallyDeletedWorkoutIDs.insert(workout.id)
        recentlyDeletedWorkout = workout
        scheduleDerivedStateRefresh(debounceNs: 0)
    }

    private func deletionUndoBar(_ workout: LoggedWorkout) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("Deleted \(workout.name)")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)

            Spacer(minLength: Theme.Spacing.sm)

            Button("Undo") {
                undoDeletion(workout)
            }
            .font(Theme.Typography.subheadlineStrong)
            .frame(minHeight: Theme.Layout.minimumTapTarget)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .glassBackground(opacity: 0.24, cornerRadius: Theme.CornerRadius.xlarge, elevation: 1, interactive: true)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func undoDeletion(_ workout: LoggedWorkout) {
        Task { @MainActor in
            await logStore.upsert(workout)
            await dataManager.setLoggedWorkoutsOffMain(logStore.workouts)
            locallyDeletedWorkoutIDs.remove(workout.id)
            recentlyDeletedWorkout = nil
            scheduleDerivedStateRefresh(debounceNs: 0)
            Haptics.notify(.success)
        }
    }

    private func scheduleDerivedStateRefresh(debounceNs: UInt64 = 120_000_000) {
        derivedRefreshTask?.cancel()
        derivedWorkerTask?.cancel()
        derivedRefreshTask = Task { @MainActor in
            if debounceNs > 0 {
                try? await Task.sleep(nanoseconds: debounceNs)
            }
            guard !Task.isCancelled else { return }

            let snapshot = HistoryDerivedSnapshot(
                workouts: visibleWorkouts,
                searchText: searchText,
                dateWindow: selectedTimeWindow,
                selectedLocations: selectedLocations,
                selectedExercises: selectedExercises,
                selectedDurationBands: selectedDurationBands,
                gymIDByWorkout: annotationsManager.annotations.compactMapValues(\.gymProfileId),
                gymsByID: Dictionary(uniqueKeysWithValues: gymProfilesManager.gyms.map {
                    ($0.id, HistoryGymSnapshot(name: $0.name, address: $0.address))
                }),
                resolver: relationshipManager.resolverSnapshot(),
                referenceDate: Date()
            )

            let worker = Task.detached(priority: .userInitiated) {
                try? HistoryDerivedStateBuilder.build(from: snapshot)
            }
            derivedWorkerTask = worker
            guard let state = await worker.value else { return }

            guard !Task.isCancelled else { return }
            derivedWorkerTask = nil
            derivedState = state
            sanitizeSelections()
        }
    }

    private func sanitizeSelections() {
        selectedLocations = sanitizedSelection(
            selectedLocations,
            validItems: derivedState.locationOptions
        )
        selectedExercises = sanitizedSelection(
            selectedExercises,
            validItems: derivedState.exerciseOptions
        )
    }

    private func sanitizedSelection<Item: Hashable>(
        _ selection: Set<Item>?,
        validItems: [Item]
    ) -> Set<Item>? {
        guard let selection else { return nil }
        let valid = Set(validItems)
        guard !valid.isEmpty else { return nil }
        if selection.isEmpty { return [] }
        let sanitized = selection.intersection(valid)
        if sanitized.isEmpty || sanitized.count == valid.count { return nil }
        return sanitized
    }
}

private struct HistoryFilterChipLabel: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var showsChevron = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.microLabel)
                    .accessibilityHidden(true)
            }
        }
        .font(Theme.Typography.captionStrong)
        .foregroundStyle(isActive ? Theme.Colors.accent : Theme.Colors.textSecondary)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: 44)
        .background(
            Capsule().fill(isActive ? Theme.Colors.accentTint : Theme.Colors.surface)
        )
        .overlay(
            Capsule().strokeBorder(
                isActive ? Theme.Colors.accent.opacity(0.24) : Theme.Colors.border.opacity(0.7),
                lineWidth: 1
            )
        )
    }
}

struct WorkoutHistoryRow: View {
    let workout: Workout
    var onDeleted: ((LoggedWorkout) -> Void)?
    let precomputedMetrics: HistoryRowMetrics?

    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager
    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var logStore: WorkoutLogStore
    @ObservedObject private var relationshipManager = ExerciseRelationshipManager.shared
    @AppStorage("weightIncrement") private var weightIncrement = 2.5
    @State private var showingDeleteAlert = false
    @State private var fallbackMetrics: HistoryRowMetrics?
    @State private var pendingRepeatWorkout: Workout?

    init(
        workout: Workout,
        onDeleted: ((LoggedWorkout) -> Void)? = nil,
        precomputedMetrics: HistoryRowMetrics? = nil
    ) {
        self.workout = workout
        self.onDeleted = onDeleted
        self.precomputedMetrics = precomputedMetrics
        _fallbackMetrics = State(initialValue: precomputedMetrics)
    }

    private var metrics: HistoryRowMetrics? {
        precomputedMetrics ?? fallbackMetrics
    }

    private var fallbackMetricsInput: HistoryRowMetricsInput {
        let gymID = annotationsManager.annotation(for: workout.id)?.gymProfileId
        return HistoryRowMetricsInput(
            workout: workout,
            resolver: relationshipManager.resolverSnapshot(),
            gymID: gymID,
            gymName: gymProfilesManager.gymName(for: gymID)
        )
    }

    private var isLoggedWorkout: Bool {
        dataManager.loggedWorkoutIds.contains(workout.id)
    }

    var body: some View {
        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                dateBlock

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(workout.name)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    InlineStat(
                        icon: "clock",
                        value: metricsLine,
                        tint: Theme.Colors.accentSecondary
                    )

                    if let gymName = metrics?.gymName {
                        InlineStat(
                            icon: metrics?.gymIsDeleted == true
                                ? "exclamationmark.triangle.fill"
                                : "mappin.and.ellipse",
                            value: gymName,
                            tint: metrics?.gymIsDeleted == true
                                ? Theme.Colors.warning
                                : Theme.Colors.accent
                        )
                    }

                    if let healthData = healthManager.getHealthData(for: workout.id) {
                        HealthDataSummaryView(healthData: healthData)
                    }
                }

                Spacer(minLength: Theme.Spacing.xs)

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.md)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
        .contextMenu {
            Button {
                Haptics.selection()
                repeatThisWorkout()
            } label: {
                Label("Repeat", systemImage: "arrow.counterclockwise")
            }

            if isLoggedWorkout {
                Button(role: .destructive) {
                    Haptics.selection()
                    showingDeleteAlert = true
                } label: {
                    Label("Delete Workout", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isLoggedWorkout {
                Button(role: .destructive) {
                    Haptics.selection()
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Theme.Colors.error)
            }

            Button {
                Haptics.selection()
                repeatThisWorkout()
            } label: {
                Label("Repeat", systemImage: "arrow.counterclockwise")
            }
            .tint(Theme.Colors.accent)
        }
        .alert("Delete Workout?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) { deleteLoggedWorkout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes this logged workout.")
        }
        .alert(
            "Replace active session?",
            isPresented: repeatReplacementAlertBinding,
            presenting: pendingRepeatWorkout
        ) { workout in
            Button("Cancel", role: .cancel) {
                pendingRepeatWorkout = nil
            }
            Button("Replace", role: .destructive) {
                pendingRepeatWorkout = nil
                replaceActiveSessionAndRepeat(workout)
            }
        } message: { _ in
            Text("This will discard your current in-progress session and repeat this workout.")
        }
        .task(id: fallbackMetricsInput) {
            guard precomputedMetrics == nil else { return }
            let input = fallbackMetricsInput
            let summary = ExerciseAggregation.summary(
                for: input.workout,
                resolver: input.resolver
            )
            fallbackMetrics = HistoryRowMetrics(
                volume: summary.volume,
                exerciseCount: summary.exerciseCount,
                gymName: input.gymName ?? (input.gymID == nil ? nil : "Deleted gym"),
                gymIsDeleted: input.gymID != nil && input.gymName == nil
            )
        }
    }

    private var dateBlock: some View {
        VStack(spacing: 1) {
            Text(workout.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(Theme.Typography.microLabel)
            Text(workout.date.formatted(.dateTime.day()))
                .font(Theme.Typography.title3)
        }
        .foregroundStyle(Theme.Colors.accent)
        .frame(width: 42, height: 42)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.accentTint)
        )
        .accessibilityHidden(true)
    }

    private var metricsLine: String {
        var values = [
            workout.date.formatted(date: .omitted, time: .shortened),
            SharedFormatters.durationMinutes(Double(workout.estimatedDurationMinutes()))
        ]
        if let metrics {
            values.append("\(metrics.exerciseCount) exercise" + (metrics.exerciseCount == 1 ? "" : "s"))
            if metrics.volume > 0 {
                values.append(SharedFormatters.volumeWithUnit(metrics.volume))
            }
        }
        return values.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        "\(workout.name), \(workout.date.formatted(date: .abbreviated, time: .shortened)), \(metricsLine)"
    }

    private var accessibilityHint: String {
        isLoggedWorkout
            ? "Double tap for details, swipe left for repeat or delete, long press for actions"
            : "Double tap for details, swipe left to repeat, long press for actions"
    }

    private func repeatThisWorkout() {
        let outcome = WorkoutRepeatHelper.repeatWorkout(
            workout,
            gymProfileId: annotationsManager.annotation(for: workout.id)?.gymProfileId,
            weightIncrement: weightIncrement,
            sessionManager: sessionManager,
            dataManager: dataManager
        )
        if outcome == .requiresActiveSessionReplacement {
            pendingRepeatWorkout = workout
        }
    }

    private var repeatReplacementAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingRepeatWorkout != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRepeatWorkout = nil
                }
            }
        )
    }

    private func replaceActiveSessionAndRepeat(_ workout: Workout) {
        Task { @MainActor in
            await WorkoutRepeatHelper.replaceActiveSessionAndRepeat(
                workout,
                gymProfileId: annotationsManager.annotation(for: workout.id)?.gymProfileId,
                weightIncrement: weightIncrement,
                sessionManager: sessionManager,
                dataManager: dataManager
            )
        }
    }

    private func deleteLoggedWorkout() {
        Task { @MainActor in
            guard let deletedWorkout = logStore.workout(id: workout.id) else { return }
            await logStore.delete(id: workout.id)
            await dataManager.setLoggedWorkoutsOffMain(logStore.workouts)
            onDeleted?(deletedWorkout)
            Haptics.notify(.success)
        }
    }
}
