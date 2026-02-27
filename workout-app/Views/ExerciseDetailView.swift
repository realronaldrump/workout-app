import SwiftUI
import Charts

struct ExerciseDetailView: View {
    let exerciseName: String
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var annotationsManager: WorkoutAnnotationsManager
    @ObservedObject var gymProfilesManager: GymProfilesManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared
    @StateObject private var insightsEngine: InsightsEngine
    @State private var selectedChart = ChartType.weight
    @State private var selectedGymScope: GymScope = .all
    @State private var showingLocationPicker = false
    @State private var selectedProgressRange: ProgressRange = .allTime
    @State private var customProgressStartDate = Date()
    @State private var customProgressEndDate = Date()
    @State private var showingCustomProgressRangePicker = false
    @State private var didInitializeProgressRange = false

    enum ChartType: String, CaseIterable, Hashable {
        case weight = "Max Weight"
        case volume = "Volume"
        case oneRepMax = "1RM"
        case reps = "Reps"
        case distance = "Distance"
        case duration = "Duration"
        case count = "Count"
    }

    enum GymScope: Hashable {
        case all
        case unassigned
        case gym(UUID)
    }

    enum ProgressRange: Hashable, CaseIterable {
        case sixWeeks
        case threeMonths
        case sixMonths
        case year
        case allTime
        case custom

        var shortLabel: String {
            switch self {
            case .sixWeeks: return "6W"
            case .threeMonths: return "3M"
            case .sixMonths: return "6M"
            case .year: return "1Y"
            case .allTime: return "All"
            case .custom: return "Custom"
            }
        }

        var menuTitle: String {
            switch self {
            case .sixWeeks: return "Last 6 weeks"
            case .threeMonths: return "Last 3 months"
            case .sixMonths: return "Last 6 months"
            case .year: return "Last year"
            case .allTime: return "All time"
            case .custom: return "Custom range"
            }
        }

        static var presets: [ProgressRange] { [.sixWeeks, .threeMonths, .sixMonths, .year, .allTime] }
    }

    init(
        exerciseName: String,
        dataManager: WorkoutDataManager,
        annotationsManager: WorkoutAnnotationsManager,
        gymProfilesManager: GymProfilesManager
    ) {
        self.exerciseName = exerciseName
        self.dataManager = dataManager
        self.annotationsManager = annotationsManager
        self.gymProfilesManager = gymProfilesManager
        _insightsEngine = StateObject(
            wrappedValue: InsightsEngine(
                dataManager: dataManager,
                annotationsProvider: { annotationsManager.annotations },
                gymNameProvider: { gymProfilesManager.gymNameSnapshot() }
            )
        )
    }

    private var scopedHistory: [(date: Date, sets: [WorkoutSet])] {
        var history: [(date: Date, sets: [WorkoutSet])] = []
        for workout in dataManager.workouts {
            guard let exercise = workout.exercises.first(where: { $0.name == exerciseName }) else { continue }
            let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
            let matches: Bool
            switch selectedGymScope {
            case .all:
                matches = true
            case .unassigned:
                matches = gymId == nil
            case .gym(let targetId):
                matches = gymId == targetId
            }
            if matches {
                history.append((date: workout.date, sets: exercise.sets))
            }
        }
        return history.sorted { $0.date < $1.date }
    }

    private var exerciseInsights: [Insight] {
        insightsEngine.insights.filter { $0.exerciseName == exerciseName }
    }

    private var isCardio: Bool {
        metadataManager
            .resolvedTags(for: exerciseName)
            .contains(where: { $0.builtInGroup == .cardio })
    }

    private var cardioConfig: ResolvedCardioMetricConfiguration {
        let sets = scopedHistory.flatMap(\.sets)
        return metricManager.resolvedCardioConfiguration(for: exerciseName, historySets: sets)
    }

    private var availableChartTypes: [ChartType] {
        if !isCardio {
            return [.weight, .volume, .oneRepMax, .reps]
        }

        let sets = scopedHistory.flatMap(\.sets)
        let hasDistance = sets.contains(where: { $0.distance > 0 })
        let hasDuration = sets.contains(where: { $0.seconds > 0 })
        let hasCount = sets.contains(where: { $0.reps > 0 })

        var types: [ChartType] = []
        if hasDistance { types.append(.distance) }
        if hasDuration { types.append(.duration) }
        if hasCount { types.append(.count) }

        return types.isEmpty ? [.duration] : types
    }

    private var locationLabel: String {
        switch selectedGymScope {
        case .all:
            return "All gyms"
        case .unassigned:
            return "Unassigned"
        case .gym(let id):
            return gymProfilesManager.gymName(for: id) ?? "Deleted gym"
        }
    }

    private var isDeletedScope: Bool {
        if case .gym(let id) = selectedGymScope {
            return gymProfilesManager.gymName(for: id) == nil
        }
        return false
    }

    private var locationBadgeStyle: GymBadgeStyle {
        switch selectedGymScope {
        case .all:
            return .assigned
        case .unassigned:
            return .unassigned
        case .gym(let id):
            return gymProfilesManager.gymName(for: id) == nil ? .deleted : .assigned
        }
    }

    private var earliestScopedWorkoutDate: Date? {
        scopedHistory.map(\.date).min()
    }

    private var progressChartHistory: [(date: Date, sets: [WorkoutSet])] {
        guard let bounds = progressChartRangeBounds(for: selectedProgressRange) else { return scopedHistory }
        return scopedHistory.filter { $0.date >= bounds.start && $0.date <= bounds.end }
    }

    private var progressRangeDetailLabel: String? {
        guard !scopedHistory.isEmpty else { return nil }
        guard let bounds = progressChartRangeBounds(for: selectedProgressRange) else { return nil }

        let calendar = Calendar.current
        let startYear = calendar.component(.year, from: bounds.start)
        let endYear = calendar.component(.year, from: bounds.end)
        let includeYear = selectedProgressRange == .allTime || selectedProgressRange == .year || selectedProgressRange == .custom || startYear != endYear

        var style = Date.FormatStyle()
            .month(.abbreviated)
            .day()
        if includeYear {
            style = style.year()
        }

        let startText = bounds.start.formatted(style)
        let endText = bounds.end.formatted(style)
        if startText == endText { return startText }
        return "\(startText) - \(endText)"
    }

    private var progressChartRangeControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            progressRangeMenu

            if let label = progressRangeDetailLabel {
                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var progressRangeMenu: some View {
        Menu {
            ForEach(ProgressRange.presets, id: \.self) { range in
                Button {
                    selectedProgressRange = range
                    Haptics.selection()
                } label: {
                    if selectedProgressRange == range {
                        Label(range.menuTitle, systemImage: "checkmark")
                    } else {
                        Text(range.menuTitle)
                    }
                }
            }

            Divider()

            Button {
                openCustomProgressRangePicker()
            } label: {
                if selectedProgressRange == .custom {
                    Label("Edit Custom Range…", systemImage: "slider.horizontal.3")
                } else {
                    Text("Custom Range…")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)

                Text("Range \(selectedProgressRange.shortLabel)")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: 44)
            .brutalistButtonChrome(
                fill: Theme.Colors.surface,
                cornerRadius: Theme.CornerRadius.large
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        }
        .buttonStyle(.plain)
        .disabled(scopedHistory.isEmpty)
        .accessibilityLabel("Chart date range")
        .accessibilityValue(selectedProgressRange.menuTitle)
    }

    @ViewBuilder
    private var progressChartCard: some View {
        Group {
            if scopedHistory.isEmpty {
                progressChartPlaceholder(message: "No sessions yet", showResetButton: false)
            } else if progressChartHistory.isEmpty {
                progressChartPlaceholder(message: "No sessions in this range", showResetButton: selectedProgressRange != .allTime)
            } else {
                ExerciseProgressChart(
                    history: progressChartHistory,
                    chartType: selectedChart,
                    countLabel: isCardio ? cardioConfig.countLabel : nil
                )
            }
        }
        .frame(height: 250)
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    @ViewBuilder
    private func progressChartPlaceholder(message: String, showResetButton: Bool) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)

            Text(message)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            if showResetButton {
                Button {
                    selectedProgressRange = .allTime
                    Haptics.selection()
                } label: {
                    Text("Show all time")
                        .font(Theme.Typography.captionBold)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .frame(minHeight: 44)
                        .brutalistButtonChrome(
                            fill: Theme.Colors.surface,
                            cornerRadius: Theme.CornerRadius.large
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progressChartRangeBounds(for range: ProgressRange) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let now = Date()

        switch range {
        case .sixWeeks:
            let start = calendar.date(byAdding: .day, value: -42, to: now) ?? now
            return (calendar.startOfDay(for: start), now)
        case .threeMonths:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return (calendar.startOfDay(for: start), now)
        case .sixMonths:
            let start = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return (calendar.startOfDay(for: start), now)
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return (calendar.startOfDay(for: start), now)
        case .allTime:
            let oldest = earliestScopedWorkoutDate ?? now
            return (calendar.startOfDay(for: oldest), now)
        case .custom:
            let startDay = calendar.startOfDay(for: customProgressStartDate)
            let endDay = calendar.startOfDay(for: customProgressEndDate)
            let start = min(startDay, endDay)
            let end = max(startDay, endDay)
            let inclusiveEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
            return (start, inclusiveEnd)
        }
    }

    private func clampCustomProgressRangeToScope() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let minDate = earliestScopedWorkoutDate.map { calendar.startOfDay(for: $0) } ?? today

        customProgressStartDate = min(max(customProgressStartDate, minDate), today)
        customProgressEndDate = min(max(customProgressEndDate, minDate), today)

        if customProgressEndDate < customProgressStartDate {
            let oldStart = customProgressStartDate
            customProgressStartDate = customProgressEndDate
            customProgressEndDate = oldStart
        }
    }

    private func openCustomProgressRangePicker() {
        let calendar = Calendar.current
        if selectedProgressRange != .custom, let bounds = progressChartRangeBounds(for: selectedProgressRange) {
            customProgressStartDate = calendar.startOfDay(for: bounds.start)
            customProgressEndDate = calendar.startOfDay(for: bounds.end)
        }

        clampCustomProgressRangeToScope()
        selectedProgressRange = .custom
        showingCustomProgressRangePicker = true
        Haptics.selection()
    }

    private func initializeProgressRangeIfNeeded() {
        guard !didInitializeProgressRange else { return }
        didInitializeProgressRange = true

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let oldest = earliestScopedWorkoutDate.map { calendar.startOfDay(for: $0) } ?? today
        customProgressStartDate = oldest
        customProgressEndDate = today
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    ExerciseStatsCards(exerciseName: exerciseName, history: scopedHistory)

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Progress Chart")
                                .font(Theme.Typography.title2)
                                .foregroundColor(Theme.Colors.textPrimary)

                            Spacer()

                            locationMenu

                            Picker("Chart Type", selection: $selectedChart) {
                                ForEach(availableChartTypes, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if isDeletedScope {
                            Text("Deleted gym. Select a valid location.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.warning)
                        }

                        progressChartRangeControls

                        progressChartCard
                    }

                    if !isCardio {
                        ExerciseRangeBreakdown(history: scopedHistory)
                    }

                    if !exerciseInsights.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Text("Insights")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.textPrimary)

                            VStack(spacing: Theme.Spacing.md) {
                                ForEach(exerciseInsights) { insight in
                                    InsightCardView(insight: insight)
                                }
                            }
                        }
                    }

                    PersonalRecordsView(
                        exerciseName: exerciseName,
                        history: scopedHistory
                    )

                    RecentSetsView(
                        exerciseName: exerciseName,
                        history: scopedHistory
                    )
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingCustomProgressRangePicker) {
            BrutalistDateRangeSheet(
                title: "Chart Range",
                startDate: $customProgressStartDate,
                endDate: $customProgressEndDate,
                earliestSelectableDate: earliestScopedWorkoutDate.map { Calendar.current.startOfDay(for: $0) },
                latestSelectableDate: Date()
            )
        }
        .onAppear {
            initializeProgressRangeIfNeeded()
            if !availableChartTypes.contains(selectedChart) {
                selectedChart = availableChartTypes.first ?? (isCardio ? .duration : .weight)
            }
            Task {
                await insightsEngine.generateInsights()
            }
        }
        .onChange(of: selectedGymScope) { _, _ in
            if selectedProgressRange == .custom {
                clampCustomProgressRangeToScope()
            }
        }
        .onChange(of: availableChartTypes) { _, newValue in
            if !newValue.contains(selectedChart) {
                selectedChart = newValue.first ?? selectedChart
            }
        }
        .onChange(of: selectedChart) { _, _ in
            Haptics.selection()
        }
    }

    private var locationMenu: some View {
        Button {
            showingLocationPicker = true
        } label: {
            HStack(spacing: 6) {
                GymBadge(text: locationLabel, style: locationBadgeStyle)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingLocationPicker) {
            GymSelectionSheet(
                title: "Location Scope",
                gyms: gymProfilesManager.sortedGyms,
                selected: currentScopeSelection,
                showAllGyms: true,
                showUnassigned: true,
                lastUsedGymId: nil,
                showLastUsed: false,
                showAddNew: false,
                onSelect: handleScopeSelection,
                onAddNew: nil
            )
        }
    }

    private var currentScopeSelection: GymSelection {
        switch selectedGymScope {
        case .all:
            return .allGyms
        case .unassigned:
            return .unassigned
        case .gym(let id):
            return .gym(id)
        }
    }

    private func handleScopeSelection(_ selection: GymSelection) {
        switch selection {
        case .allGyms:
            selectedGymScope = .all
        case .unassigned:
            selectedGymScope = .unassigned
        case .gym(let id):
            selectedGymScope = .gym(id)
        }
    }
}
