import Combine
import SwiftUI

struct ExerciseDetailView: View {
    let exerciseName: String
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var annotationsManager: WorkoutAnnotationsManager
    @ObservedObject var gymProfilesManager: GymProfilesManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared
    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var insightsEngine: InsightsEngine
    @EnvironmentObject private var variantEngine: WorkoutVariantEngine
    @State private var selectedChart = ChartType.weight
    @State private var selectedGymScope: GymScope = .all
    @State private var showingLocationPicker = false
    @State private var selectedProgressRange: ProgressRange = .allTime
    @State private var customProgressStartDate = Date()
    @State private var customProgressEndDate = Date()
    @State private var showingCustomProgressRangePicker = false
    @State private var didInitializeProgressRange = false
    @State private var selectedVariantWorkout: Workout?
    @State private var scopedHistory: [(date: Date, sets: [WorkoutSet])] = []
    @State private var cachedCardioConfig: ResolvedCardioMetricConfiguration?
    @State private var availableChartTypes: [ChartType] = [.weight, .volume, .oneRepMax, .reps]
    @State private var progressReview: ExerciseProgressReview?
    @State private var isLoadingProgressReview = false
    @State private var progressReviewTask: Task<Void, Never>?

    enum ChartType: String, CaseIterable, Hashable {
        case weight = "Max Weight"
        case volume = "Volume"
        case oneRepMax = "1RM"
        case reps = "Reps"
        case distance = "Distance"
        case duration = "Duration"
        case count = "Count"

        func displayName(for exerciseName: String) -> String {
            switch self {
            case .weight:
                return ExerciseLoad.weightMetricTitle(for: exerciseName)
            case .oneRepMax:
                return ExerciseLoad.chartOneRepMaxTitle(for: exerciseName)
            default:
                return rawValue
            }
        }
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
    }

    private var exerciseInsights: [Insight] {
        insightsEngine.insights.filter { $0.exerciseName == exerciseName }
    }

    private var exerciseContextPatterns: [WorkoutVariantPattern] {
        Array(variantEngine.patterns(for: exerciseName).prefix(3))
    }

    private var isCardio: Bool {
        metadataManager
            .resolvedTags(for: exerciseName)
            .contains(where: { $0.builtInGroup == .cardio })
    }

    private var isAssisted: Bool {
        ExerciseLoad.isAssistedExercise(exerciseName)
    }

    private var cardioConfig: ResolvedCardioMetricConfiguration {
        cachedCardioConfig ?? metricManager.resolvedCardioConfiguration(for: exerciseName, historySets: [])
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

    private var scopedProgressReviewWorkouts: [Workout] {
        dataManager.workouts.filter { workout in
            guard workout.exercises.contains(where: { $0.name == exerciseName }) else { return false }

            let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
            switch selectedGymScope {
            case .all:
                return true
            case .unassigned:
                return gymId == nil
            case .gym(let targetId):
                return gymId == targetId
            }
        }
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
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)

                Text("Range \(selectedProgressRange.shortLabel)")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Image(systemName: "chevron.down")
                    .font(Theme.Typography.captionBold)
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
                    exerciseName: exerciseName,
                    history: progressChartHistory,
                    chartType: selectedChart,
                    countLabel: isCardio ? cardioConfig.countLabel : nil
                )
            }
        }
        .frame(height: Theme.ChartHeight.expanded)
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    @ViewBuilder
    private func progressChartPlaceholder(message: String, showResetButton: Bool) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(Theme.Iconography.title2Bold)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)

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

    private func refreshScopedHistory() {
        let historySessions = dataManager.exerciseHistorySessions(for: exerciseName).filter { session in
            let gymId = annotationsManager.annotation(for: session.workoutId)?.gymProfileId
            switch selectedGymScope {
            case .all:
                return true
            case .unassigned:
                return gymId == nil
            case .gym(let targetId):
                return gymId == targetId
            }
        }

        scopedHistory = historySessions.map { (date: $0.date, sets: $0.sets) }

        let sets = scopedHistory.flatMap(\.sets)
        if isCardio {
            cachedCardioConfig = metricManager.resolvedCardioConfiguration(for: exerciseName, historySets: sets)

            let hasDistance = sets.contains(where: { $0.distance > 0 })
            let hasDuration = sets.contains(where: { $0.seconds > 0 })
            let hasCount = sets.contains(where: { $0.reps > 0 })

            var types: [ChartType] = []
            if hasDistance { types.append(.distance) }
            if hasDuration { types.append(.duration) }
            if hasCount { types.append(.count) }
            availableChartTypes = types.isEmpty ? [.duration] : types
        } else {
            cachedCardioConfig = nil
            availableChartTypes = isAssisted ? [.weight, .oneRepMax, .reps] : [.weight, .volume, .oneRepMax, .reps]
        }

        if !availableChartTypes.contains(selectedChart) {
            selectedChart = availableChartTypes.first ?? (isCardio ? .duration : .weight)
        }

        if selectedProgressRange == .custom {
            clampCustomProgressRangeToScope()
        }
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
                                    Text(type.displayName(for: exerciseName)).tag(type)
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
                        ExerciseRangeBreakdown(exerciseName: exerciseName, history: scopedHistory)
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

                    if !exerciseContextPatterns.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Text("Context Patterns")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.textPrimary)

                            Text("Where this lift tends to change when the surrounding workout changes.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)

                            ForEach(exerciseContextPatterns) { pattern in
                                MetricTileButton(
                                    action: { selectedVariantWorkout = pattern.representativeWorkout },
                                    content: {
                                        WorkoutVariantPatternCard(pattern: pattern, maxEvidence: 1)
                                    }
                                )
                            }
                        }
                    }

                    if !isCardio {
                        if let progressReview {
                            ProgressReviewSection(
                                review: progressReview,
                                gymNameProvider: { gymId in
                                    gymProfilesManager.gymName(for: gymId)
                                }
                            )
                        } else if isLoadingProgressReview {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                Text("Progress Review")
                                    .font(Theme.Typography.title3)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                HStack(spacing: Theme.Spacing.sm) {
                                    ProgressView()
                                    Text("Comparing the last two blocks for this lift.")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                .padding(Theme.Spacing.lg)
                                .softCard(elevation: 1)
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
        .navigationDestination(item: $selectedVariantWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
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
            refreshScopedHistory()
            initializeProgressRangeIfNeeded()
            if !availableChartTypes.contains(selectedChart) {
                selectedChart = availableChartTypes.first ?? (isCardio ? .duration : .weight)
            }
            scheduleProgressReviewRefresh()
        }
        .onChange(of: selectedGymScope) { _, _ in
            refreshScopedHistory()
            scheduleProgressReviewRefresh()
        }
        .onChange(of: availableChartTypes) { _, newValue in
            if !newValue.contains(selectedChart) {
                selectedChart = newValue.first ?? selectedChart
            }
        }
        .onChange(of: dataManager.workouts) { _, _ in
            refreshScopedHistory()
            scheduleProgressReviewRefresh()
        }
        .onReceive(annotationsManager.$annotations) { _ in
            refreshScopedHistory()
            scheduleProgressReviewRefresh()
        }
        .onReceive(metadataManager.objectWillChange) { _ in
            refreshScopedHistory()
        }
        .onReceive(metricManager.objectWillChange) { _ in
            refreshScopedHistory()
        }
        .onChange(of: healthManager.authorizationStatus) { _, _ in
            scheduleProgressReviewRefresh()
        }
        .onChange(of: selectedChart) { _, _ in
            Haptics.selection()
        }
        .onDisappear {
            progressReviewTask?.cancel()
        }
    }

    private var locationMenu: some View {
        Button {
            showingLocationPicker = true
        } label: {
            HStack(spacing: 6) {
                GymBadge(text: locationLabel, style: locationBadgeStyle)
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.caption)
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

    private func refreshProgressReview() async {
        guard !isCardio else {
            progressReview = nil
            isLoadingProgressReview = false
            return
        }

        let workouts = scopedProgressReviewWorkouts
        guard let earliestWorkoutDate = workouts.map(\.date).min() else {
            progressReview = nil
            isLoadingProgressReview = false
            return
        }

        isLoadingProgressReview = true

        let bodyMassSamples: [BodyRawSample]
        if healthManager.authorizationStatus == .authorized {
            let range = DateInterval(start: earliestWorkoutDate, end: Date())
            do {
                let samples = try await healthManager.fetchMetricSamples(metric: .bodyMass, range: range)
                bodyMassSamples = samples.map { sample in
                    BodyRawSample(
                        timestamp: sample.timestamp,
                        value: HealthMetric.bodyMass.displayValue(from: sample.value)
                    )
                }
            } catch {
                bodyMassSamples = []
            }
        } else {
            bodyMassSamples = []
        }

        progressReview = ProgressReviewEngine.review(
            for: exerciseName,
            workouts: workouts,
            annotations: annotationsManager.annotations,
            bodyMassSamples: bodyMassSamples
        )
        isLoadingProgressReview = false
    }

    private func scheduleProgressReviewRefresh(debounceNs: UInt64 = 200_000_000) {
        progressReviewTask?.cancel()
        progressReviewTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await refreshProgressReview()
        }
    }
}
