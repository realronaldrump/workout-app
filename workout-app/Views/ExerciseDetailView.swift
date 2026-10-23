import Combine
import SwiftUI

struct ExerciseDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var showingQuickStart = false
    @State private var selectedProgressRange: ProgressRange = .allTime
    @State private var customProgressStartDate = Date()
    @State private var customProgressEndDate = Date()
    @State private var showingCustomProgressRangePicker = false
    @State private var didInitializeProgressRange = false
    @State private var selectedVariantWorkout: Workout?
    @State private var scopedHistory: [(date: Date, sets: [WorkoutSet])] = []
    @State private var scopedHistorySessions: [ExerciseHistorySession] = []
    @State private var exerciseWorkouts: [Workout] = []
    @State private var isLoadingExerciseDetail = false
    @State private var exerciseDetailError: String?
    @State private var exerciseDetailTask: Task<Void, Never>?
    @State private var cachedCardioConfig: ResolvedCardioMetricConfiguration?
    @State private var availableChartTypes: [ChartType] = [.weight, .volume, .oneRepMax, .reps]
    @State private var progressReview: ExerciseProgressReview?
    @State private var isLoadingProgressReview = false
    @State private var progressReviewTask: Task<Void, Never>?
    @State private var progressReviewGeneration: UInt64 = 0
    @State private var relationshipEditorRequest: ExerciseRelationshipEditorRequest?
    @State private var sectionTracker = StatsSectionTracker()

    enum ChartType: String, CaseIterable, Hashable {
        case weight = "Max weight"
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
        let replacingExerciseName: String?

        init(
            exerciseName: String,
            parentName: String?,
            laterality: ExerciseLaterality,
            mode: Mode,
            replacingExerciseName: String? = nil
        ) {
            self.exerciseName = exerciseName
            self.parentName = parentName
            self.laterality = laterality
            self.mode = mode
            self.replacingExerciseName = replacingExerciseName
        }

        enum Mode {
            case assignExisting
            case createVariant
        }
    }

    private struct ExercisePerformanceTrack: Identifiable {
        let name: String
        let label: String
        let sessions: [ExerciseHistorySession]

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
        let matching = insightsEngine.insights.filter { $0.exerciseName == exerciseName }
        return Self.collapsingEquipmentBaselines(in: matching)
    }

    /// The engine emits one baseline insight per new gym, which stacked up as six
    /// identical "New Equipment Baseline" rows for anyone who trains in more than
    /// one place. They say more as a single row that names the count and the gyms,
    /// and that also explains why the loads are not comparable.
    private static func collapsingEquipmentBaselines(in insights: [Insight]) -> [Insight] {
        let baselines = insights.filter { $0.type == .baseline }
        guard baselines.count > 1 else { return insights }

        var gyms: [String] = []
        for insight in baselines.sorted(by: { $0.date < $1.date }) {
            // Messages are formatted "<exercise> | <gym>".
            let gym = insight.message
                .split(separator: "|", maxSplits: 1)
                .last
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? insight.message
            if !gym.isEmpty, !gyms.contains(gym) { gyms.append(gym) }
        }

        guard let latest = baselines.max(by: { $0.date < $1.date }), gyms.count > 1 else {
            return insights
        }

        let combined = Insight(
            id: latest.id,
            type: .baseline,
            title: "Logged at \(gyms.count) gyms",
            message: gyms.joined(separator: ", ")
                + ". Machine loads rarely match between gyms, so compare within one location.",
            exerciseName: latest.exerciseName,
            date: latest.date,
            priority: latest.priority,
            actionLabel: latest.actionLabel,
            metric: nil
        )

        return insights.filter { $0.type != .baseline } + [combined]
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

    private var observedRelationshipExerciseNames: [String] {
        let relationshipNames = relationshipManager.relationships.values.flatMap { [$0.exerciseName, $0.parentName] }
        let names = dataManager.allExerciseNames()
            + relationshipNames
            + [exerciseName]
        return Array(Set(names))
            .map { ExerciseIdentityResolver.trimmedName($0) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var inferredRelationshipSuggestion: ExerciseRelationshipSuggestion? {
        relationshipManager.suggestedRelationship(
            for: exerciseName,
            knownExerciseNames: Set(observedRelationshipExerciseNames)
        ) ?? relationshipManager.suggestedRelationship(
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
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .frame(minHeight: 44)
                        .surfaceButtonChrome(
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
        filteredHistorySessions(
            for: targetName,
            includingVariants: includingVariants
        )
        .map { (date: $0.date, sets: $0.sets) }
    }

    private func filteredHistorySessions(
        for targetName: String,
        includingVariants: Bool
    ) -> [ExerciseHistorySession] {
        let sourceHistory = exerciseWorkouts.isEmpty
            ? dataManager.exerciseHistorySessions(for: targetName, includingVariants: includingVariants)
            : historySessions(from: exerciseWorkouts, targetName: targetName, includingVariants: includingVariants)

        return sourceHistory
            .filter { matchesSelectedGymScope(workoutId: $0.workoutId) }
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
        scopedHistorySessions = filteredHistorySessions(
            for: exerciseName,
            includingVariants: !isVariantPage
        )
        scopedHistory = scopedHistorySessions.map { (date: $0.date, sets: $0.sets) }

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
            let sessions = filteredHistorySessions(for: track.name, includingVariants: false)
            guard !sessions.isEmpty else { return nil }
            return ExercisePerformanceTrack(name: track.name, label: track.label, sessions: sessions)
        }
    }

    private var exerciseAnalysisGymScope: ExerciseAnalysisGymScope {
        switch selectedGymScope {
        case .all: return .all
        case .unassigned: return .unassigned
        case .gym(let id): return .gym(id)
        }
    }

    private func analysisScope(for performanceTrackName: String) -> ExerciseAnalysisScope {
        ExerciseAnalysisScope(
            exerciseName: exerciseName,
            performanceTrackName: performanceTrackName,
            gym: exerciseAnalysisGymScope
        )
    }

    private func exactTrackNamesForBreakdown() -> [(name: String, label: String)] {
        if isVariantPage {
            return [(exerciseName, displayIdentity.sideLabel ?? "Variant")]
        }

        // A base track can contain alternating or single-limb sets without a recorded side.
        var tracks: [(name: String, label: String)] = [(exerciseName, "Base exercise")]
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
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Side of \(displayIdentity.aggregateName)")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Records here count toward both this side and the combined lift.")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.sm)
                TagLabel(text: displayIdentity.sideLabel ?? "Variant", tint: Theme.Colors.textPrimary)
            }

            HStack(spacing: Theme.Spacing.sm) {
                AppPillButton(title: "Edit link", systemImage: "slider.horizontal.3", variant: .neutral) {
                    relationshipEditorRequest = ExerciseRelationshipEditorRequest(
                        exerciseName: exerciseName,
                        parentName: displayIdentity.aggregateName,
                        laterality: displayIdentity.laterality ?? .left,
                        mode: .assignExisting
                    )
                }

                AppPillButton(title: "Unlink", systemImage: "xmark", variant: .danger) {
                    relationshipManager.removeRelationship(for: exerciseName)
                    dataManager.refreshExerciseIdentityDerivedState()
                    refreshScopedHistory()
                    scheduleExerciseDetailRefresh(debounceNs: 0)
                }
            }
        }
        .ledgerRow()
    }

    private var parentBreakdownCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(title: "Side breakdown", subtitle: sideBalanceSummary)

            VStack(spacing: 0) {
                ForEach(Array(sideBreakdowns.enumerated()), id: \.element.id) { index, breakdown in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(breakdown.label)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(breakdown.name)
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: Theme.Spacing.sm)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(SharedFormatters.volumeWithUnit(breakdown.volume))
                                .font(Theme.Typography.numberSmall)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(SharedFormatters.count(breakdown.sets, "set"))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .ledgerRow(showsRule: index < sideBreakdowns.count - 1)
                    .accessibilityElement(children: .combine)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                if canSplitIntoStandardSides {
                    AppPillButton(title: "Split L/R", systemImage: "arrow.left.and.right", variant: .accent) {
                        splitIntoStandardSides()
                    }
                }
                AppPillButton(title: "Add a side", systemImage: "plus", variant: .neutral) {
                    relationshipEditorRequest = addSideEditorRequest(parentName: exerciseName)
                }
            }
        }
    }

    private var createVariantCard: some View {
        let suggestion = inferredRelationshipSuggestion
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.map { "Looks like a side of \($0.parentName)" } ?? "Left and right")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(suggestion == nil
                     ? "Track each side of this lift on its own, then see them together."
                     : "Link it to keep its records with the combined lift.")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Theme.Spacing.sm) {
                if canSplitIntoStandardSides, suggestion == nil {
                    AppPillButton(title: "Split L/R", systemImage: "arrow.left.and.right", variant: .accent) {
                        splitIntoStandardSides()
                    }
                }

                AppPillButton(
                    title: suggestion == nil ? "Add a side" : "Link it",
                    systemImage: suggestion == nil ? "plus" : "link",
                    variant: suggestion == nil ? .neutral : .accent
                ) {
                    if let suggestion {
                        relationshipEditorRequest = ExerciseRelationshipEditorRequest(
                            exerciseName: suggestion.exerciseName,
                            parentName: suggestion.parentName,
                            laterality: suggestion.laterality,
                            mode: .assignExisting
                        )
                    } else {
                        relationshipEditorRequest = addSideEditorRequest(parentName: exerciseName)
                    }
                }
            }
        }
        .ledgerRow()
    }

    @ViewBuilder
    private var personalRecordsSection: some View {
        if showsAggregateBreakdown && !performanceTracks.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Personal records")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(performanceTracks) { track in
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text(track.label)
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textSecondary)
                        PersonalRecordsView(
                            exerciseName: track.name,
                            sessions: track.sessions,
                            scope: analysisScope(for: track.name),
                            title: ""
                        )
                    }
                }
            }
        } else {
            PersonalRecordsView(
                exerciseName: exerciseName,
                sessions: scopedHistorySessions,
                scope: analysisScope(for: exerciseName)
            )
        }
    }

    private func defaultVariantName(parentName: String, laterality: ExerciseLaterality) -> String {
        ExerciseRelationshipManager.standardVariantName(parentName: parentName, laterality: laterality)
    }

    private func suggestedSideRelationships(forParentName parentName: String) -> [ExerciseRelationshipSuggestion] {
        let observedSuggestions = relationshipManager.suggestedRelationships(
            forParent: parentName,
            knownExerciseNames: Set(observedRelationshipExerciseNames)
        )
        if !observedSuggestions.isEmpty {
            return observedSuggestions
        }

        return relationshipManager.suggestedRelationships(
            forParent: parentName,
            knownExerciseNames: Set(availableRelationshipExerciseNames)
        )
    }

    private func addSideEditorRequest(parentName: String) -> ExerciseRelationshipEditorRequest {
        let suggestions = suggestedSideRelationships(forParentName: parentName)
        let suggestedSide = suggestions.first { suggestion in
            missingSide(forParentName: parentName) == suggestion.laterality ||
                relationshipNameForReplacement(
                    parentName: parentName,
                    laterality: suggestion.laterality
                ) != nil
        } ?? suggestions.first
        let laterality = suggestedSide?.laterality ?? missingSide(forParentName: parentName) ?? .left
        let replacementName = relationshipNameForReplacement(
            parentName: parentName,
            laterality: laterality
        )

        if let suggestedSide {
            return ExerciseRelationshipEditorRequest(
                exerciseName: suggestedSide.exerciseName,
                parentName: parentName,
                laterality: suggestedSide.laterality,
                mode: .assignExisting,
                replacingExerciseName: replacementName
            )
        }

        return ExerciseRelationshipEditorRequest(
            exerciseName: replacementName ?? defaultVariantName(parentName: parentName, laterality: laterality),
            parentName: parentName,
            laterality: laterality,
            mode: .createVariant,
            replacingExerciseName: replacementName
        )
    }

    private func missingSide(forParentName parentName: String) -> ExerciseLaterality? {
        let existingSides = Set(resolver.children(of: parentName).map(\.laterality))
        return [ExerciseLaterality.left, .right].first { !existingSides.contains($0) }
    }

    private func relationshipNameForReplacement(
        parentName: String,
        laterality: ExerciseLaterality
    ) -> String? {
        ExerciseRelationshipManager.replacementCandidateForSideAssignment(
            parentName: parentName,
            laterality: laterality,
            children: resolver.children(of: parentName)
        ) { exerciseName in
            !dataManager.exerciseHistorySessions(
                for: exerciseName,
                includingVariants: false
            ).isEmpty
        }?.exerciseName
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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.xl) {
                        exerciseHeader

                        if isLoadingExerciseDetail && scopedHistory.isEmpty {
                            HStack(spacing: Theme.Spacing.sm) {
                                ProgressView()
                                Text("Loading exercise history")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let exerciseDetailError, scopedHistory.isEmpty {
                            ErrorCard(message: "Couldn't load exercise history. \(exerciseDetailError)") {
                                scheduleExerciseDetailRefresh()
                            }
                        } else if scopedHistory.isEmpty {
                            emptyHistoryState
                            relationshipPanel
                        }

                        if !scopedHistory.isEmpty {
                            ExerciseStatsCards(
                                exerciseName: exerciseName,
                                sessions: scopedHistorySessions,
                                scope: analysisScope(for: exerciseName),
                                showsPerformanceStats: !showsAggregateBreakdown
                            )
                            .statsSection(ExerciseDetailSection.overview.rawValue, tracker: $sectionTracker)

                            personalRecordsSection
                                .statsSection(ExerciseDetailSection.records.rawValue, tracker: $sectionTracker)

                            relationshipPanel

                            progressSection
                                .statsSection(ExerciseDetailSection.progress.rawValue, tracker: $sectionTracker)

                            if !isCardio && !showsAggregateBreakdown {
                                ExerciseRangeBreakdown(
                                    exerciseName: exerciseName,
                                    sessions: scopedHistorySessions,
                                    scope: analysisScope(for: exerciseName)
                                )
                                .statsSection(ExerciseDetailSection.ranges.rawValue, tracker: $sectionTracker)
                            }

                            if !exerciseInsights.isEmpty || !exerciseContextPatterns.isEmpty {
                                insightsSection
                                    .statsSection(ExerciseDetailSection.insights.rawValue, tracker: $sectionTracker)
                            }

                            if !isCardio && !showsAggregateBreakdown {
                                progressReviewContent
                                    .statsSection(ExerciseDetailSection.review.rawValue, tracker: $sectionTracker)
                            }

                            RecentSetsView(
                                exerciseName: exerciseName,
                                sessions: scopedHistorySessions
                            )
                            .statsSection(ExerciseDetailSection.sets.rawValue, tracker: $sectionTracker)
                        }
                    }
                    .padding(.horizontal, Theme.Layout.screenGutter)
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xxl)
                    .contentColumn()
                }
                // A safe-area bar so the scroll edge effect runs under the jump bar too.
                .safeAreaBar(edge: .top, spacing: 0) {
                    if jumpSections.count >= 3 {
                        SectionJumpBar(
                            sections: jumpSections,
                            activeID: sectionTracker.activeID(in: jumpSections),
                            onSelect: { id in
                                withAnimation(reduceMotion ? nil : Theme.Animation.smooth) {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                            }
                        )
                        .contentColumn()
                        .padding(.horizontal, Theme.Layout.screenGutter)
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
        }
        .collapsingTitle(exerciseName)
        .accessibilityIdentifier("exercise-detail-\(exerciseName)")
        .navigationDestination(item: $selectedVariantWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
        .sheet(isPresented: $showingQuickStart) {
            QuickStartView(exerciseName: exerciseName)
        }
        .sheet(isPresented: $showingCustomProgressRangePicker) {
            BrutalistDateRangeSheet(
                title: "Chart range",
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
                availableExerciseNames: availableRelationshipExerciseNames,
                suggestedExerciseNames: suggestedSideRelationships(
                    forParentName: request.parentName ?? exerciseName
                ).map(\.exerciseName)
            ) { childName, parentName, laterality in
                    let didSave = relationshipManager.setRelationship(
                        exerciseName: childName,
                        parentName: parentName,
                        laterality: laterality,
                        replacingExerciseName: request.replacingExerciseName ?? request.exerciseName
                    )
                    guard didSave else { return false }
                    dataManager.refreshExerciseIdentityDerivedState()
                    refreshScopedHistory()
                    scheduleExerciseDetailRefresh(debounceNs: 0)
                    return true
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
        .onChange(of: metadataManager.muscleAssignmentOverrides) { _, _ in
            refreshScopedHistory()
            scheduleExerciseDetailRefresh()
            scheduleProgressReviewRefresh()
        }
        .onChange(of: metricManager.cardioOverrides) { _, _ in
            refreshScopedHistory()
            scheduleExerciseDetailRefresh()
            scheduleProgressReviewRefresh()
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
        .onDisappear {
            exerciseDetailTask?.cancel()
            progressReviewTask?.cancel()
            progressReviewGeneration &+= 1
        }
    }

    // MARK: - Page sections

    private enum ExerciseDetailSection: String, CaseIterable {
        case overview
        case records
        case progress
        case ranges
        case insights
        case review
        case sets

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .records: return "Records"
            case .progress: return "Progress"
            case .ranges: return "Rep ranges"
            case .insights: return "Highlights"
            case .review: return "Review"
            case .sets: return "Sessions"
            }
        }
    }

    private var jumpSections: [StatsSectionAnchor] {
        guard !scopedHistory.isEmpty else { return [] }
        return ExerciseDetailSection.allCases.compactMap { section -> StatsSectionAnchor? in
            switch section {
            case .ranges, .review:
                guard !isCardio && !showsAggregateBreakdown else { return nil }
            case .insights:
                guard !exerciseInsights.isEmpty || !exerciseContextPatterns.isEmpty else { return nil }
            case .overview, .records, .progress, .sets:
                break
            }
            return StatsSectionAnchor(id: section.rawValue, title: section.title)
        }
    }

    private var primaryMuscleTag: MuscleTag? {
        let assignments = metadataManager.resolvedAssignments(for: exerciseName)
        return assignments.first(where: { $0.role == .primary })?.tag ?? assignments.first?.tag
    }

    private var headerEyebrow: String {
        if isVariantPage { return "Variant" }
        if isCardio { return "Cardio" }
        return primaryMuscleTag?.displayName ?? "Exercise"
    }

    private var headerSubtitle: String? {
        let dates = scopedHistory.map(\.date)
        guard let latest = dates.max(), let earliest = dates.min() else {
            return isLoadingExerciseDetail ? nil : "No sessions logged"
        }
        var sentence = SharedFormatters.count(dates.count, "session")
        if dates.count > 1 {
            sentence += " since \(earliest.formatted(.dateTime.month(.wide).year()))"
        }
        return sentence + ". Last trained \(latest.formatted(.relative(presentation: .named)))."
    }

    private var emptyHistoryState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(selectedGymScope == .all ? "No sessions yet" : "No sessions at this gym")
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(selectedGymScope == .all
                 ? "Log this exercise once and its records, progress, and sets start here."
                 : "Switch to all gyms to see every session.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if selectedGymScope != .all {
                AppPillButton(title: "Show all gyms", variant: .neutral) {
                    selectedGymScope = .all
                    Haptics.selection()
                }
            }
            AppPrimaryButton(title: "Start a workout with this") {
                showingQuickStart = true
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            StatsPageHeader(
                eyebrow: headerEyebrow,
                title: exerciseName,
                subtitle: headerSubtitle,
                systemImage: isCardio ? "heart.fill" : "dumbbell.fill"
            )

            let assignments = metadataManager.resolvedAssignments(for: exerciseName)
            if !assignments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(assignments) { assignment in
                            MuscleTagBadge(tag: assignment.tag, role: assignment.role)
                        }
                    }
                }
                .scrollClipDisabled()
            }

            // Location scopes every stat, record, chart, and set on this page, so it
            // lives up here rather than inside the chart's controls.
            locationMenu

            if isDeletedScope {
                Label("Deleted gym. Select a valid location.", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(title: "Progress", subtitle: progressRangeDetailLabel)

            if availableChartTypes.count > 1 {
                TimeRangePillPicker(
                    options: availableChartTypes,
                    selected: $selectedChart,
                    label: { $0.displayName(for: exerciseName) },
                    selectionHint: "Charts this measure",
                    controlTitle: "Chart measure",
                    controlIcon: "chart.xyaxis.line"
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Chart measure")
            }

            TimeRangePillPicker(
                options: ProgressRange.allCases,
                selected: $selectedProgressRange,
                label: { $0.shortLabel },
                isSpecialOption: { $0 == .custom },
                onCustomTap: { openCustomProgressRangePicker() }
            )
            .disabled(scopedHistory.isEmpty)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Chart date range")

            progressChartCard
        }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            if !exerciseInsights.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SectionHeading(title: "Highlights")

                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(exerciseInsights) { insight in
                            InsightCardView(insight: insight)
                        }
                    }
                }
            }

            if !exerciseContextPatterns.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SectionHeading(
                        title: "Across similar workouts",
                        help: "Compares this exercise across similar workouts with different exercise orders, durations, times, or gyms."
                    )

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
        }
    }

    @ViewBuilder
    private var progressReviewContent: some View {
        if let progressReview {
            ProgressReviewSection(
                review: progressReview,
                gymNameProvider: { gymId in
                    gymProfilesManager.gymName(for: gymId)
                }
            )
        } else if isLoadingProgressReview {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeading(title: "Progress review")

                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                    Text("Loading review…")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softCard()
            }
        }
    }

    private var locationMenu: some View {
        Button {
            showingLocationPicker = true
            Haptics.selection()
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text("At")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)
                Text(locationLabel)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundColor(isDeletedScope ? Theme.Colors.warning : Theme.Colors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.microLabel)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 40)
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.Colors.rule, lineWidth: 1.5))
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(AppInteractionButtonStyle())
        .accessibilityLabel("Location, \(locationLabel)")
        .accessibilityHint("Filters every stat on this page to one gym")
        .sheet(isPresented: $showingLocationPicker) {
            GymSelectionSheet(
                title: "Location",
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

    private func refreshProgressReview(generation: UInt64) async {
        guard generation == progressReviewGeneration, !Task.isCancelled else { return }
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

        guard generation == progressReviewGeneration, !Task.isCancelled else { return }

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
        progressReviewGeneration &+= 1
        let generation = progressReviewGeneration
        progressReviewTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await refreshProgressReview(generation: generation)
        }
    }
}

private struct ExerciseRelationshipEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let availableExerciseNames: [String]
    let suggestedExerciseNames: [String]
    let updatesDefaultNameOnSideChange: Bool
    let onSave: (String, String, ExerciseLaterality) -> Bool

    @State private var draftExerciseName: String
    @State private var draftParentName: String
    @State private var draftLaterality: ExerciseLaterality
    @State private var generatedName: String
    @State private var exerciseSearchText = ""
    @State private var saveError: String?

    init(
        initialExerciseName: String,
        initialParentName: String,
        initialLaterality: ExerciseLaterality,
        updatesDefaultNameOnSideChange: Bool,
        availableExerciseNames: [String],
        suggestedExerciseNames: [String] = [],
        onSave: @escaping (String, String, ExerciseLaterality) -> Bool
    ) {
        let trimmedExercise = ExerciseIdentityResolver.trimmedName(initialExerciseName)
        let trimmedParent = ExerciseIdentityResolver.trimmedName(initialParentName)
        self.availableExerciseNames = availableExerciseNames
        self.suggestedExerciseNames = suggestedExerciseNames
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

    private var selectableExerciseNames: [String] {
        let parentKey = ExerciseIdentityResolver.normalizedName(draftParentName)
        return availableExerciseNames.filter { name in
            let key = ExerciseIdentityResolver.normalizedName(name)
            return !key.isEmpty && key != parentKey
        }
    }

    private var dynamicSuggestedExerciseNames: [String] {
        ExerciseIdentityResolver.inferredSuggestions(
            forParent: draftParentName,
            knownExerciseNames: Set(availableExerciseNames)
        )
        .map(\.exerciseName)
    }

    private var prioritizedExerciseNames: [String] {
        orderedUnique(suggestedExerciseNames + dynamicSuggestedExerciseNames)
            .filter { candidate in
                selectableExerciseNames.contains {
                    ExerciseIdentityResolver.normalizedName($0) ==
                        ExerciseIdentityResolver.normalizedName(candidate)
                }
            }
    }

    private var exerciseSearchResults: [String] {
        let query = ExerciseIdentityResolver.trimmedName(exerciseSearchText)
        let source: [String]
        if query.isEmpty {
            source = prioritizedExerciseNames
        } else {
            source = selectableExerciseNames.filter {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
        return Array(orderedUnique(source).prefix(8))
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
                        fieldCard(title: "Variant name") {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                TextField("Exercise name", text: $draftExerciseName)
                                    .textInputAutocapitalization(.words)
                                    .disableAutocorrection(true)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .padding(Theme.Spacing.md)
                                    .background(Theme.Colors.surfaceRaised)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))

                                TextField("Search existing exercises", text: $exerciseSearchText)
                                    .textInputAutocapitalization(.words)
                                    .disableAutocorrection(true)
                                    .font(Theme.Typography.callout)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .padding(Theme.Spacing.md)
                                    .background(Theme.Colors.surfaceRaised)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))

                                if !exerciseSearchResults.isEmpty {
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                        Text(exerciseSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Suggested matches" : "Existing exercises")
                                            .font(Theme.Typography.metricLabel)
                                            .foregroundStyle(Theme.Colors.textTertiary)

                                        ForEach(exerciseSearchResults, id: \.self) { name in
                                            Button {
                                                selectExerciseName(name)
                                            } label: {
                                                HStack(spacing: Theme.Spacing.sm) {
                                                    Image(systemName: name == draftExerciseName ? "checkmark.circle.fill" : "circle")
                                                        .font(Theme.Typography.callout)
                                                        .foregroundStyle(name == draftExerciseName ? Theme.Colors.accent : Theme.Colors.textTertiary)

                                                    Text(name)
                                                        .font(Theme.Typography.callout)
                                                        .foregroundColor(Theme.Colors.textPrimary)
                                                        .lineLimit(2)
                                                        .multilineTextAlignment(.leading)

                                                    Spacer()
                                                }
                                                .frame(minHeight: Theme.Layout.minimumTapTarget)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                } else if !exerciseSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("No existing exercise matches")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }

                        fieldCard(title: "Parent exercise") {
                            Picker("Parent exercise", selection: $draftParentName) {
                                ForEach(parentCandidates, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        fieldCard(title: "Side") {
                            AppSegmentedPicker(
                                title: "Side",
                                selection: $draftLaterality,
                                options: ExerciseLaterality.allCases.map { ($0.displayName, $0) }
                            )
                        }

                        if let saveError {
                            Text(saveError)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.error)
                        }

                        AppPrimaryButton(title: "Save variant", isEnabled: canSave, action: save)
                    }
                    .padding(Theme.Spacing.xl)
                    .contentColumn(maxWidth: 640)
                }
            }
            .navigationTitle("Exercise variant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
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
            content()
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func save() {
        guard canSave else { return }
        saveError = nil
        let didSave = onSave(
            ExerciseIdentityResolver.trimmedName(draftExerciseName),
            ExerciseIdentityResolver.trimmedName(draftParentName),
            draftLaterality
        )
        guard didSave else {
            saveError = "Couldn't save this variant. This side may already be linked to another exercise."
            return
        }
        Haptics.selection()
        dismiss()
    }

    private func selectExerciseName(_ name: String) {
        draftExerciseName = name
        generatedName = ""

        if let suggestion = ExerciseIdentityResolver.inferredSuggestion(
            for: name,
            knownExerciseNames: Set(availableExerciseNames)
        ), ExerciseIdentityResolver.normalizedName(suggestion.parentName) ==
            ExerciseIdentityResolver.normalizedName(draftParentName) {
            draftLaterality = suggestion.laterality
        }

        Haptics.selection()
    }

    private func orderedUnique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names
            .map(ExerciseIdentityResolver.trimmedName)
            .filter { !$0.isEmpty }
            .filter { seen.insert(ExerciseIdentityResolver.normalizedName($0)).inserted }
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
