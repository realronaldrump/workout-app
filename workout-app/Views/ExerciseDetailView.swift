import Combine
import SwiftUI

struct ExerciseDetailView: View {
    let exerciseName: String
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var annotationsManager: WorkoutAnnotationsManager
    @ObservedObject var gymProfilesManager: GymProfilesManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared
    @ObservedObject private var relationshipManager = ExerciseRelationshipManager.shared
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
    @State private var exerciseWorkouts: [Workout] = []
    @State private var isLoadingExerciseDetail = false
    @State private var exerciseDetailError: String?
    @State private var exerciseDetailTask: Task<Void, Never>?
    @State private var cachedCardioConfig: ResolvedCardioMetricConfiguration?
    @State private var availableChartTypes: [ChartType] = [.weight, .volume, .oneRepMax, .reps]
    @State private var progressReview: ExerciseProgressReview?
    @State private var isLoadingProgressReview = false
    @State private var progressReviewTask: Task<Void, Never>?
    @State private var relationshipEditorRequest: ExerciseRelationshipEditorRequest?

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

    private struct ExerciseRelationshipEditorRequest: Identifiable {
        let id = UUID()
        let exerciseName: String
        let parentName: String?
        let laterality: ExerciseLaterality
        let mode: Mode

        enum Mode {
            case assignExisting
            case createVariant
        }
    }

    private struct ExercisePerformanceTrack: Identifiable {
        let name: String
        let label: String
        let history: [(date: Date, sets: [WorkoutSet])]

        var id: String { name }
    }

    private struct ExerciseSideBreakdown: Identifiable {
        let name: String
        let label: String
        let sessions: Int
        let sets: Int
        let volume: Double
        let lastPerformed: Date?

        var id: String { name }
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

    private var resolver: ExerciseIdentityResolver {
        relationshipManager.resolverSnapshot()
    }

    private var displayIdentity: ExerciseDisplayIdentity {
        resolver.displayIdentity(for: exerciseName)
    }

    private var isVariantPage: Bool {
        displayIdentity.isVariant
    }

    private var childRelationships: [ExerciseRelationship] {
        resolver.children(of: exerciseName)
    }

    private var showsAggregateBreakdown: Bool {
        !isVariantPage && !childRelationships.isEmpty
    }

    private var missingStandardSideVariants: [ExerciseLaterality] {
        guard !isVariantPage, inferredRelationshipSuggestion == nil else { return [] }
        let existingSides = Set(childRelationships.map(\.laterality))
        return [ExerciseLaterality.left, .right].filter { side in
            guard !existingSides.contains(side) else { return false }
            let childName = ExerciseRelationshipManager.standardVariantName(
                parentName: exerciseName,
                laterality: side
            )
            return resolver.relationship(for: childName) == nil
        }
    }

    private var canSplitIntoStandardSides: Bool {
        !missingStandardSideVariants.isEmpty
    }

    private var availableRelationshipExerciseNames: [String] {
        let relationshipNames = relationshipManager.relationships.values.flatMap { [$0.exerciseName, $0.parentName] }
        let names = dataManager.allExerciseNames()
            + ExerciseMetadataManager.defaultExerciseNames
            + relationshipNames
            + [exerciseName]
        let uniqueNames = Set(names)
        return Array(uniqueNames)
            .map { ExerciseIdentityResolver.trimmedName($0) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var inferredRelationshipSuggestion: ExerciseRelationshipSuggestion? {
        relationshipManager.suggestedRelationship(
            for: exerciseName,
            knownExerciseNames: Set(availableRelationshipExerciseNames)
        )
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
        exerciseWorkouts.filter { matchesSelectedGymScope(workoutId: $0.id) }
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

    private func historySessions(
        from workouts: [Workout],
        targetName: String = "",
        includingVariants: Bool
    ) -> [ExerciseHistorySession] {
        let resolvedTargetName = targetName.isEmpty ? exerciseName : targetName
        return ExerciseAggregation.historySessions(
            in: workouts,
            for: resolvedTargetName,
            includingVariants: includingVariants,
            resolver: resolver
        )
    }

    private func filteredHistoryTuples(
        for targetName: String,
        includingVariants: Bool
    ) -> [(date: Date, sets: [WorkoutSet])] {
        let sourceHistory = exerciseWorkouts.isEmpty
            ? dataManager.exerciseHistorySessions(for: targetName, includingVariants: includingVariants)
            : historySessions(from: exerciseWorkouts, targetName: targetName, includingVariants: includingVariants)

        return sourceHistory
            .filter { matchesSelectedGymScope(workoutId: $0.workoutId) }
            .map { (date: $0.date, sets: $0.sets) }
    }

    private func matchesSelectedGymScope(workoutId: UUID) -> Bool {
        let gymId = annotationsManager.annotation(for: workoutId)?.gymProfileId
        switch selectedGymScope {
        case .all:
            return true
        case .unassigned:
            return gymId == nil
        case .gym(let targetId):
            return gymId == targetId
        }
    }

    private func refreshScopedHistory() {
        scopedHistory = filteredHistoryTuples(
            for: exerciseName,
            includingVariants: !isVariantPage
        )

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
            if showsAggregateBreakdown {
                availableChartTypes = isAssisted ? [.reps] : [.volume, .reps]
            } else {
                availableChartTypes = isAssisted ? [.weight, .oneRepMax, .reps] : [.weight, .volume, .oneRepMax, .reps]
            }
        }

        if !availableChartTypes.contains(selectedChart) {
            selectedChart = availableChartTypes.first ?? (isCardio ? .duration : .weight)
        }

        if selectedProgressRange == .custom {
            clampCustomProgressRangeToScope()
        }
    }

    private var sideBreakdowns: [ExerciseSideBreakdown] {
        let tracks = exactTrackNamesForBreakdown()
        return tracks.compactMap { track in
            let history = filteredHistoryTuples(for: track.name, includingVariants: false)
            guard !history.isEmpty else { return nil }
            return ExerciseSideBreakdown(
                name: track.name,
                label: track.label,
                sessions: history.count,
                sets: history.reduce(0) { $0 + $1.sets.count },
                volume: history.reduce(0) { partial, session in
                    partial + session.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
                },
                lastPerformed: history.map(\.date).max()
            )
        }
    }

    private var performanceTracks: [ExercisePerformanceTrack] {
        exactTrackNamesForBreakdown().compactMap { track in
            let history = filteredHistoryTuples(for: track.name, includingVariants: false)
            guard !history.isEmpty else { return nil }
            return ExercisePerformanceTrack(name: track.name, label: track.label, history: history)
        }
    }

    private func exactTrackNamesForBreakdown() -> [(name: String, label: String)] {
        if isVariantPage {
            return [(exerciseName, displayIdentity.sideLabel ?? "Variant")]
        }

        var tracks: [(name: String, label: String)] = [(exerciseName, "Bilateral")]
        tracks += childRelationships.map { relationship in
            (relationship.exerciseName, relationship.laterality.displayName)
        }

        var seen = Set<String>()
        return tracks.filter { track in
            seen.insert(ExerciseIdentityResolver.normalizedName(track.name)).inserted
        }
    }

    private var sideBalanceSummary: String? {
        let breakdownsByLabel = sideBreakdowns.reduce(into: [String: ExerciseSideBreakdown]()) { result, breakdown in
            result[breakdown.label] = breakdown
        }
        guard let left = breakdownsByLabel[ExerciseLaterality.left.displayName],
              let right = breakdownsByLabel[ExerciseLaterality.right.displayName] else {
            return nil
        }

        let volumeDelta = abs(left.volume - right.volume)
        let strongerLabel = left.volume >= right.volume ? "Left" : "Right"
        if volumeDelta == 0 {
            return "Left and right logged volume is even."
        }
        return "\(strongerLabel) volume is ahead by \(SharedFormatters.volumeWithUnit(volumeDelta))."
    }

    private func scheduleExerciseDetailRefresh(debounceNs: UInt64 = 0) {
        exerciseDetailTask?.cancel()
        exerciseDetailTask = Task { @MainActor in
            if debounceNs > 0 {
                try? await Task.sleep(nanoseconds: debounceNs)
            }
            guard !Task.isCancelled else { return }

            isLoadingExerciseDetail = true
            exerciseDetailError = nil

            do {
                let snapshot = try await WorkoutRepository.shared.exerciseDetail(name: exerciseName, scope: .all)
                guard !Task.isCancelled else { return }

                exerciseWorkouts = snapshot.workouts
                refreshScopedHistory()
                initializeProgressRangeIfNeeded()
                isLoadingExerciseDetail = false
                scheduleProgressReviewRefresh(debounceNs: 0)
            } catch {
                guard !Task.isCancelled else { return }
                exerciseDetailError = error.localizedDescription
                isLoadingExerciseDetail = false
            }
        }
    }

    @ViewBuilder
    private var relationshipPanel: some View {
        if isVariantPage {
            variantRelationshipCard
        } else if showsAggregateBreakdown {
            parentBreakdownCard
        } else {
            createVariantCard
        }
    }

    private var variantRelationshipCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Variant")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(displayIdentity.aggregateName)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                Text(displayIdentity.sideLabel ?? "Variant")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small, style: .continuous))
            }

            HStack(spacing: Theme.Spacing.sm) {
                AppPillButton(title: "Edit", systemImage: "slider.horizontal.3", variant: .neutral) {
                    relationshipEditorRequest = ExerciseRelationshipEditorRequest(
                        exerciseName: exerciseName,
                        parentName: displayIdentity.aggregateName,
                        laterality: displayIdentity.laterality ?? .left,
                        mode: .assignExisting
                    )
                }

                AppPillButton(title: "Remove", systemImage: "xmark", variant: .danger) {
                    relationshipManager.removeRelationship(for: exerciseName)
                    dataManager.refreshExerciseIdentityDerivedState()
                    refreshScopedHistory()
                    scheduleExerciseDetailRefresh(debounceNs: 0)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private var parentBreakdownCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Side Breakdown")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                HStack(spacing: Theme.Spacing.sm) {
                    if canSplitIntoStandardSides {
                        AppPillButton(title: "Split L/R", systemImage: "arrow.left.and.right", variant: .accent) {
                            splitIntoStandardSides()
                        }
                    }

                    AppPillButton(title: "Add Side", systemImage: "plus", variant: .neutral) {
                        relationshipEditorRequest = ExerciseRelationshipEditorRequest(
                            exerciseName: defaultVariantName(parentName: exerciseName, laterality: .left),
                            parentName: exerciseName,
                            laterality: .left,
                            mode: .createVariant
                        )
                    }
                }
            }

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(sideBreakdowns) { breakdown in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(breakdown.label)
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(breakdown.name)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(SharedFormatters.volumeCompact(breakdown.volume))
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("\(breakdown.sets) sets")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))
                }
            }

            if let sideBalanceSummary {
                Text(sideBalanceSummary)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private var createVariantCard: some View {
        let suggestion = inferredRelationshipSuggestion
        return HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "arrow.left.and.right")
                .font(Theme.Typography.title4)
                .foregroundColor(Theme.Colors.accent)
                .frame(width: 36, height: 36)
                .background(Theme.Colors.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion == nil ? "Side Variants" : "Suggested Variant")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(suggestion?.parentName ?? "Create left, right, or unilateral tracks.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: Theme.Spacing.sm) {
                if canSplitIntoStandardSides {
                    AppPillButton(title: "Split L/R", systemImage: "arrow.left.and.right", variant: .accent) {
                        splitIntoStandardSides()
                    }
                }

                AppToolbarIconButton(systemImage: "plus", accessibilityLabel: "Add side variant", variant: .subtle) {
                    if let suggestion {
                        relationshipEditorRequest = ExerciseRelationshipEditorRequest(
                            exerciseName: suggestion.exerciseName,
                            parentName: suggestion.parentName,
                            laterality: suggestion.laterality,
                            mode: .assignExisting
                        )
                    } else {
                        relationshipEditorRequest = ExerciseRelationshipEditorRequest(
                            exerciseName: defaultVariantName(parentName: exerciseName, laterality: .left),
                            parentName: exerciseName,
                            laterality: .left,
                            mode: .createVariant
                        )
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    @ViewBuilder
    private var personalRecordsSection: some View {
        if showsAggregateBreakdown && !performanceTracks.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Personal Records")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(performanceTracks) { track in
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text(track.label)
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        PersonalRecordsView(
                            exerciseName: track.name,
                            history: track.history,
                            title: ""
                        )
                    }
                }
            }
        } else {
            PersonalRecordsView(
                exerciseName: exerciseName,
                history: scopedHistory
            )
        }
    }

    private func defaultVariantName(parentName: String, laterality: ExerciseLaterality) -> String {
        ExerciseRelationshipManager.standardVariantName(parentName: parentName, laterality: laterality)
    }

    private func splitIntoStandardSides() {
        let result = relationshipManager.createStandardSideVariants(
            parentName: exerciseName,
            sides: missingStandardSideVariants
        )
        guard !result.created.isEmpty else { return }

        dataManager.refreshExerciseIdentityDerivedState()
        refreshScopedHistory()
        scheduleExerciseDetailRefresh(debounceNs: 0)
        Haptics.selection()
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    if isLoadingExerciseDetail && scopedHistory.isEmpty {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView()
                            Text("Loading exercise history")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let exerciseDetailError, scopedHistory.isEmpty {
                        Text("Unable to load exercise history: \(exerciseDetailError)")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ExerciseStatsCards(
                        exerciseName: exerciseName,
                        history: scopedHistory,
                        showsPerformanceStats: !showsAggregateBreakdown
                    )

                    relationshipPanel

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

                    if !isCardio && !showsAggregateBreakdown {
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

                    if !isCardio && !showsAggregateBreakdown {
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

                    personalRecordsSection

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
        .sheet(item: $relationshipEditorRequest) { request in
            ExerciseRelationshipEditorSheet(
                initialExerciseName: request.exerciseName,
                initialParentName: request.parentName ?? exerciseName,
                initialLaterality: request.laterality,
                updatesDefaultNameOnSideChange: request.mode == .createVariant,
                availableExerciseNames: availableRelationshipExerciseNames
            ) { childName, parentName, laterality in
                    let didSave = relationshipManager.setRelationship(
                        exerciseName: childName,
                        parentName: parentName,
                        laterality: laterality,
                        replacingExerciseName: request.exerciseName
                    )
                    guard didSave else { return }
                    dataManager.refreshExerciseIdentityDerivedState()
                    refreshScopedHistory()
                    scheduleExerciseDetailRefresh(debounceNs: 0)
            }
        }
        .onAppear {
            refreshScopedHistory()
            initializeProgressRangeIfNeeded()
            scheduleExerciseDetailRefresh()
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
            scheduleExerciseDetailRefresh(debounceNs: 150_000_000)
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
        .onChange(of: relationshipManager.relationships) { _, _ in
            dataManager.refreshExerciseIdentityDerivedState()
            refreshScopedHistory()
            scheduleExerciseDetailRefresh(debounceNs: 0)
            scheduleProgressReviewRefresh()
        }
        .onChange(of: healthManager.authorizationStatus) { _, _ in
            scheduleProgressReviewRefresh()
        }
        .onChange(of: selectedChart) { _, _ in
            Haptics.selection()
        }
        .onDisappear {
            exerciseDetailTask?.cancel()
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
        guard !isCardio, !showsAggregateBreakdown else {
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

private struct ExerciseRelationshipEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let availableExerciseNames: [String]
    let updatesDefaultNameOnSideChange: Bool
    let onSave: (String, String, ExerciseLaterality) -> Void

    @State private var draftExerciseName: String
    @State private var draftParentName: String
    @State private var draftLaterality: ExerciseLaterality
    @State private var generatedName: String

    init(
        initialExerciseName: String,
        initialParentName: String,
        initialLaterality: ExerciseLaterality,
        updatesDefaultNameOnSideChange: Bool,
        availableExerciseNames: [String],
        onSave: @escaping (String, String, ExerciseLaterality) -> Void
    ) {
        let trimmedExercise = ExerciseIdentityResolver.trimmedName(initialExerciseName)
        let trimmedParent = ExerciseIdentityResolver.trimmedName(initialParentName)
        self.availableExerciseNames = availableExerciseNames
        self.updatesDefaultNameOnSideChange = updatesDefaultNameOnSideChange
        self.onSave = onSave
        _draftExerciseName = State(initialValue: trimmedExercise)
        _draftParentName = State(initialValue: trimmedParent)
        _draftLaterality = State(initialValue: initialLaterality)
        _generatedName = State(initialValue: trimmedExercise)
    }

    private var parentCandidates: [String] {
        let childKey = ExerciseIdentityResolver.normalizedName(draftExerciseName)
        return availableExerciseNames
            .filter { ExerciseIdentityResolver.normalizedName($0) != childKey }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var canSave: Bool {
        let child = ExerciseIdentityResolver.trimmedName(draftExerciseName)
        let parent = ExerciseIdentityResolver.trimmedName(draftParentName)
        return !child.isEmpty &&
            !parent.isEmpty &&
            ExerciseIdentityResolver.normalizedName(child) != ExerciseIdentityResolver.normalizedName(parent)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        fieldCard(title: "Variant Name") {
                            TextField("Exercise name", text: $draftExerciseName)
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(true)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .padding(Theme.Spacing.md)
                                .background(Theme.Colors.surfaceRaised)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))
                        }

                        fieldCard(title: "Parent Exercise") {
                            Picker("Parent Exercise", selection: $draftParentName) {
                                ForEach(parentCandidates, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        fieldCard(title: "Side") {
                            Picker("Side", selection: $draftLaterality) {
                                ForEach(ExerciseLaterality.allCases, id: \.self) { laterality in
                                    Text(laterality.displayName).tag(laterality)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Button(action: save) {
                            Text("Save Relationship")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(Theme.Spacing.md)
                                .background(canSave ? Theme.Colors.accent : Theme.Colors.textTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationTitle("Exercise Variant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Cancel", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }
            }
            .onChange(of: draftLaterality) { oldValue, newValue in
                guard updatesDefaultNameOnSideChange else { return }
                guard draftExerciseName == generatedName || draftExerciseName == defaultName(parent: draftParentName, laterality: oldValue) else {
                    return
                }
                let next = defaultName(parent: draftParentName, laterality: newValue)
                draftExerciseName = next
                generatedName = next
            }
            .onChange(of: draftParentName) { oldValue, newValue in
                guard updatesDefaultNameOnSideChange else { return }
                guard draftExerciseName == generatedName || draftExerciseName == defaultName(parent: oldValue, laterality: draftLaterality) else {
                    return
                }
                let next = defaultName(parent: newValue, laterality: draftLaterality)
                draftExerciseName = next
                generatedName = next
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func fieldCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
            content()
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func save() {
        guard canSave else { return }
        onSave(
            ExerciseIdentityResolver.trimmedName(draftExerciseName),
            ExerciseIdentityResolver.trimmedName(draftParentName),
            draftLaterality
        )
        Haptics.selection()
        dismiss()
    }

    private func defaultName(parent: String, laterality: ExerciseLaterality) -> String {
        switch laterality {
        case .left:
            return "\(parent) - Left"
        case .right:
            return "\(parent) - Right"
        case .unilateral:
            return "\(parent) - Unilateral"
        }
    }
}
