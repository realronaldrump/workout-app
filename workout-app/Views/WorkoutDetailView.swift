import SwiftUI

private nonisolated struct WorkoutDetailComparison: Hashable, Sendable {
    let workoutName: String
    let volumeDelta: TrendDelta?
    let durationDelta: TrendDelta?
}

private nonisolated struct WorkoutDetailPRInput: Sendable {
    let exercise: Exercise
    let priorSessions: [WorkoutDetailPriorExerciseSession]
}

private nonisolated struct WorkoutDetailPriorExerciseSession: Sendable {
    let date: Date
    let sets: [WorkoutSet]
}

private nonisolated struct WorkoutDetailDerivedState: Sendable {
    let summary: ExerciseAggregation.Summary
    let comparison: WorkoutDetailComparison?
    let personalRecordExerciseIDs: Set<UUID>
    let personalRecordSetIDs: Set<UUID>
}

private nonisolated enum WorkoutDetailDerivedStateBuilder {
    static func build(
        workout: Workout,
        allWorkouts: [Workout],
        resolver: ExerciseIdentityResolver,
        personalRecordInputs: [WorkoutDetailPRInput]
    ) -> WorkoutDetailDerivedState {
        let summary = ExerciseAggregation.summary(for: workout, resolver: resolver)
        let previous = allWorkouts
            .filter {
                $0.date < workout.date
                    && ExerciseIdentityResolver.normalizedName($0.name)
                        == ExerciseIdentityResolver.normalizedName(workout.name)
            }
            .max { $0.date < $1.date }

        let comparison: WorkoutDetailComparison?
        if let previous {
            let previousSummary = ExerciseAggregation.summary(for: previous, resolver: resolver)
            comparison = WorkoutDetailComparison(
                workoutName: previous.name,
                volumeDelta: TrendDelta(
                    current: summary.volume,
                    previous: previousSummary.volume,
                    higherIsBetter: true
                ),
                durationDelta: TrendDelta(
                    current: Double(workout.estimatedDurationMinutes()),
                    previous: Double(previous.estimatedDurationMinutes()),
                    higherIsBetter: true
                )
            )
        } else {
            comparison = nil
        }

        var recordExerciseIDs: Set<UUID> = []
        var recordSetIDs: Set<UUID> = []

        for input in personalRecordInputs {
            let exercise = input.exercise
            let currentWeights = exercise.sets
                .map(\.weight)
                .filter { ExerciseLoad.isTrackedWeight($0, exerciseName: exercise.name) }
            guard let currentBest = ExerciseLoad.bestWeight(
                in: currentWeights,
                exerciseName: exercise.name
            ) else { continue }

            let priorWeights = input.priorSessions
                .filter { $0.date < workout.date }
                .flatMap(\.sets)
                .map(\.weight)
                .filter { ExerciseLoad.isTrackedWeight($0, exerciseName: exercise.name) }
            let priorBest = ExerciseLoad.bestWeight(in: priorWeights, exerciseName: exercise.name)
            let isRecord = priorBest == nil
                || ExerciseLoad.isBetter(currentBest, than: priorBest ?? currentBest, exerciseName: exercise.name)
            guard isRecord else { continue }

            recordExerciseIDs.insert(exercise.id)
            if let bestSet = exercise.sets.first(where: {
                abs(
                    ExerciseLoad.comparisonValue(for: $0.weight, exerciseName: exercise.name)
                        - ExerciseLoad.comparisonValue(for: currentBest, exerciseName: exercise.name)
                ) < 0.0001
            }) {
                recordSetIDs.insert(bestSet.id)
            }
        }

        return WorkoutDetailDerivedState(
            summary: summary,
            comparison: comparison,
            personalRecordExerciseIDs: recordExerciseIDs,
            personalRecordSetIDs: recordSetIDs
        )
    }
}

struct WorkoutDetailView: View {
    let workout: Workout
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @EnvironmentObject var variantEngine: WorkoutVariantEngine
    @EnvironmentObject var similarityEngine: WorkoutSimilarityEngine
    @EnvironmentObject var sessionManager: WorkoutSessionManager
    // Removed local healthData state to use source of truth
    @State private var showingSyncError = false
    @State private var syncErrorMessage = ""
    @State private var selectedExercise: ExerciseSelection?
    @State private var showingQuickStart = false
    @State private var quickStartExercise: String?
    @State private var showingSessionInsights = false
    @State private var showingWorkoutHealthInsights = false
    @State private var showingEdit = false
    @State private var selectedSimilarityComparison: WorkoutSimilarityComparisonSelection?
    @State private var cachedResolvedWorkout: Workout?
    @State private var cachedSimilarityReview: WorkoutSimilarityReview?
    @State private var cachedVariantReview: WorkoutVariantWorkoutReview?
    @State private var cachedHealthData: WorkoutHealthData?
    @State private var cachedSummary: ExerciseAggregation.Summary?
    @State private var cachedComparison: WorkoutDetailComparison?
    @State private var personalRecordExerciseIDs: Set<UUID> = []
    @State private var personalRecordSetIDs: Set<UUID> = []
    @State private var derivedRefreshTask: Task<Void, Never>?
    @State private var pendingRepeatWorkout: Workout?
    @AppStorage("weightIncrement") private var weightIncrement = 2.5
    @Environment(\.dismiss) private var dismiss

    private var resolvedWorkout: Workout {
        cachedResolvedWorkout ?? dataManager.workouts.first(where: { $0.id == workout.id }) ?? workout
    }

    private var isLoggedWorkout: Bool {
        dataManager.loggedWorkoutIds.contains(workout.id)
    }

    private var similarityReview: WorkoutSimilarityReview? {
        cachedSimilarityReview
    }

    private func workoutDateTimeToolbarText(for date: Date) -> String {
        // Keep this compact so it fits in the nav-bar trailing container across screens/split views.
        let calendar = Calendar.current
        let now = Date()
        let includeYear = calendar.component(.year, from: date) != calendar.component(.year, from: now)

        let datePart = includeYear
            ? date.formatted(.dateTime.year().month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day())

        let timePart = date.formatted(.dateTime.hour().minute())
        return "\(datePart) | \(timePart)"
    }

    var body: some View {
        let workout = resolvedWorkout
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    workoutHeader(workout)

                    summaryCard(for: workout)

                    if healthManager.isHealthKitAvailable() {
                        healthDataSection
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Exercises")
                            .font(Theme.Typography.sectionHeader2)
                            .foregroundColor(Theme.Colors.textPrimary)

                        ForEach(workout.exercises) { exercise in
                            ExerciseCard(
                                exercise: exercise,
                                personalRecordDate: personalRecordExerciseIDs.contains(exercise.id)
                                    ? workout.date
                                    : nil,
                                highlightedSetIDs: personalRecordSetIDs,
                                onViewHistory: { exerciseName in
                                    selectedExercise = ExerciseSelection(id: exerciseName)
                                },
                                onQuickStart: { exerciseName in
                                    quickStartExercise = exerciseName
                                    showingQuickStart = true
                                }
                            )
                        }
                    }

                    GymAssignmentCard(workout: workout)

                    if let review = cachedVariantReview {
                        variantReviewSection(review: review)
                    }

                    if let similarityReview {
                        WorkoutSimilaritySection(review: similarityReview) { match in
                            selectedSimilarityComparison = WorkoutSimilarityComparisonSelection(
                                selectedWorkoutId: workout.id,
                                priorWorkoutId: match.priorWorkoutId
                            )
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            workoutTopBar
        }
        .onAppear {
            refreshCachedWorkoutState()
        }
        .onChange(of: dataManager.workouts) { _, _ in
            refreshCachedWorkoutState()
        }
        .onReceive(healthManager.$healthDataStore) { _ in
            cachedHealthData = healthManager.getHealthData(for: workout.id)
        }
        .onReceive(variantEngine.$library) { _ in
            cachedVariantReview = variantEngine.review(for: workout.id)
        }
        .onReceive(similarityEngine.$library) { _ in
            cachedSimilarityReview = similarityEngine.review(for: resolvedWorkout.id)
        }
        .onDisappear {
            derivedRefreshTask?.cancel()
        }
        .alert("Sync Error", isPresented: $showingSyncError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncErrorMessage)
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
        .sheet(isPresented: $showingEdit) {
            WorkoutEditView(workoutId: workout.id)
        }
        .navigationDestination(isPresented: $showingSessionInsights) {
            WorkoutSessionInsightsView(workout: workout)
        }
        .navigationDestination(isPresented: $showingWorkoutHealthInsights) {
            WorkoutHealthInsightsView(workout: workout)
        }
        .navigationDestination(item: $selectedSimilarityComparison) { selection in
            WorkoutSimilarityCompareView(selection: selection)
        }
    }

    private var workoutTopBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            AppToolbarIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Back",
                variant: .subtle
            ) {
                dismiss()
            }

            Spacer()

            if isLoggedWorkout {
                AppToolbarButton(title: "Edit", systemImage: "pencil", variant: .subtle) {
                    showingEdit = true
                    Haptics.selection()
                }
            }

            AppToolbarButton(
                title: "Repeat",
                systemImage: "arrow.counterclockwise",
                variant: .accent
            ) {
                repeatThisWorkout()
                Haptics.selection()
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Colors.background)
    }

    private func workoutHeader(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(workout.name)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(workoutDateTimeToolbarText(for: workout.date))
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func summaryCard(for workout: Workout) -> some View {
        MetricTileButton(
            action: { showingSessionInsights = true },
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: Theme.Spacing.md
                    ) {
                        summaryStat(
                            title: "Duration",
                            value: SharedFormatters.durationMinutes(
                                Double(workout.estimatedDurationMinutes())
                            )
                        )
                        summaryStat(
                            title: "Exercises",
                            value: cachedSummary.map { "\($0.exerciseCount)" } ?? "—"
                        )
                        summaryStat(
                            title: "Sets",
                            value: cachedSummary.map { "\($0.setCount)" } ?? "—"
                        )
                        summaryStat(
                            title: "Total volume",
                            value: cachedSummary.map {
                                $0.volume > 0 ? SharedFormatters.volumeWithUnit($0.volume) : "—"
                            } ?? "—"
                        )
                    }

                    if let comparison = cachedComparison {
                        Divider()
                            .overlay(Theme.Colors.border)

                        HStack(spacing: Theme.Spacing.sm) {
                            Text("vs last \(comparison.workoutName)")
                                .font(Theme.Typography.captionStrong)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)

                            Spacer(minLength: Theme.Spacing.xs)

                            if let volumeDelta = comparison.volumeDelta {
                                DeltaTag(delta: volumeDelta, suffix: "volume")
                            }

                            if let durationDelta = comparison.durationDelta {
                                DeltaTag(
                                    delta: durationDelta,
                                    suffix: "time",
                                    tintOverride: Theme.Colors.textSecondary
                                )
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        )
    }

    private func summaryStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Health Data Section

    private func variantReviewSection(review: WorkoutVariantWorkoutReview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Variant Review")
                    .font(Theme.Typography.sectionHeader2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                NavigationLink {
                    WorkoutVariantReviewView(focusWorkoutId: workout.id)
                } label: {
                    Text("Full View")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
            }

            NavigationLink {
                WorkoutVariantReviewView(focusWorkoutId: workout.id)
            } label: {
                WorkoutVariantSummaryCard(review: review, maxDifferences: 2)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var healthDataSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Health Data")
                    .font(Theme.Typography.sectionHeader2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                syncButton
            }

            if let data = cachedHealthData {
                MetricTileButton(
                    action: {
                        showingWorkoutHealthInsights = true
                    },
                    content: {
                        HealthDataView(healthData: data)
                    }
                )
            } else {
                noHealthDataCard
            }
        }
    }

    private var syncButton: some View {
        let hasData = cachedHealthData != nil

        return Button(action: syncHealthData) {
            HStack(spacing: 6) {
                if healthManager.isSyncing {
                    SyncPulse()
                } else {
                    Image(systemName: hasData ? "arrow.triangle.2.circlepath" : "heart.text.square")
                        .font(Theme.Iconography.medium)
                }

                Text(hasData ? "Re-sync" : "Sync")
                    .font(Theme.Typography.subheadline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .brutalistButtonChrome(
                fill: Theme.Colors.accent,
                cornerRadius: Theme.CornerRadius.large
            )
        }
        .buttonStyle(.plain)
        .disabled(healthManager.isSyncing)
        .opacity(healthManager.isSyncing ? 0.7 : 1.0)
    }

    private var noHealthDataCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "heart.text.square")
                .font(Theme.Iconography.feature)
                .foregroundColor(Theme.Colors.textTertiary)

            Text("No health data yet")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textSecondary)

            Text("Sync this workout to load heart rate, sleep, and recovery context.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 2)
    }

    // MARK: - Actions

    private func syncHealthData() {
        Task {
            do {
                // Request authorization if needed
                if healthManager.authorizationStatus != .authorized {
                    try await healthManager.requestAuthorization()
                }

                _ = try await healthManager.syncHealthDataForWorkout(resolvedWorkout)
                Haptics.notify(.success)
            } catch {
                syncErrorMessage = error.localizedDescription
                showingSyncError = true
            }
        }
    }

    private func refreshCachedWorkoutState() {
        let resolved = dataManager.workouts.first(where: { $0.id == workout.id }) ?? workout
        cachedResolvedWorkout = resolved
        cachedSimilarityReview = similarityEngine.review(for: resolved.id)
        cachedVariantReview = variantEngine.review(for: resolved.id)
        cachedHealthData = healthManager.getHealthData(for: resolved.id)

        let allWorkouts = dataManager.workouts
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()
        let personalRecordInputs = resolved.exercises.map { exercise in
            WorkoutDetailPRInput(
                exercise: exercise,
                priorSessions: dataManager.getExerciseHistory(for: exercise.name).map {
                    WorkoutDetailPriorExerciseSession(date: $0.date, sets: $0.sets)
                }
            )
        }

        derivedRefreshTask?.cancel()
        derivedRefreshTask = Task { @MainActor in
            let state = await Task.detached(priority: .userInitiated) {
                WorkoutDetailDerivedStateBuilder.build(
                    workout: resolved,
                    allWorkouts: allWorkouts,
                    resolver: resolver,
                    personalRecordInputs: personalRecordInputs
                )
            }.value
            guard !Task.isCancelled else { return }
            cachedSummary = state.summary
            cachedComparison = state.comparison
            personalRecordExerciseIDs = state.personalRecordExerciseIDs
            personalRecordSetIDs = state.personalRecordSetIDs
        }
    }

    private func repeatThisWorkout() {
        let workout = resolvedWorkout
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

}

struct ExerciseCard: View {
    let exercise: Exercise
    var personalRecordDate: Date?
    var highlightedSetIDs: Set<UUID> = []
    var onViewHistory: ((String) -> Void)?
    var onQuickStart: ((String) -> Void)?
    @State private var isExpanded = false
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared

    private var isCardio: Bool {
        metadataManager
            .resolvedTags(for: exercise.name)
            .contains(where: { $0.builtInGroup == .cardio })
    }

    private var cardioConfig: ResolvedCardioMetricConfiguration {
        metricManager.resolvedCardioConfiguration(for: exercise.name, historySets: exercise.sets)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(
                action: {
                    withAnimation { isExpanded.toggle() }
                    Haptics.selection()
                },
                label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Text(exercise.name)
                                    .font(Theme.Typography.condensed)
                                    .tracking(-0.2)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                if let personalRecordDate {
                                    PRMarkerView(date: personalRecordDate)
                                }
                            }

                            HStack(spacing: 16) {
                                Label("\(exercise.sets.count) sets", systemImage: "number")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)

                                if isCardio {
                                    cardioSummaryChips
                                } else {
                                    Label(SharedFormatters.volumeCompact(exercise.totalVolume), systemImage: "scalemass")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
            )
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                        HStack {
                            Text("Set \(index + 1)")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .frame(width: 50, alignment: .leading)

                            if isCardio {
                                Text(cardioSetSummary(set))
                                    .font(Theme.Typography.body)

                                Spacer()
                            } else {
                                Text("\(Int(set.weight)) lbs × \(set.reps)")
                                    .font(Theme.Typography.body)

                                Spacer()

                                Text("\(Int(set.weight * Double(set.reps))) lbs")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                .fill(
                                    highlightedSetIDs.contains(set.id)
                                        ? Theme.Colors.accentTint
                                        : Color.clear
                                )
                        )

                        if index < exercise.sets.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
        .contextMenu {
            Button("View History") {
                onViewHistory?(exercise.name)
            }
            Button("Quick Start") {
                onQuickStart?(exercise.name)
            }
        }
        .accessibilityHint("Long press for more options: View History, Quick Start")
    }

    private var cardioSummaryChips: some View {
        let totalDistance = exercise.sets.reduce(0.0) { $0 + $1.distance }
        let totalSeconds = exercise.sets.reduce(0.0) { $0 + $1.seconds }
        let totalCount = exercise.sets.reduce(0) { $0 + $1.reps }

        return HStack(spacing: 10) {
            if totalDistance > 0 {
                Label("\(WorkoutValueFormatter.distanceText(totalDistance)) dist", systemImage: "location.fill")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            if totalSeconds > 0 {
                Label(WorkoutValueFormatter.durationText(seconds: totalSeconds), systemImage: "clock.fill")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            if totalCount > 0 {
                Label("\(totalCount) \(cardioConfig.countLabel)", systemImage: "number")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private func cardioSetSummary(_ set: WorkoutSet) -> String {
        var parts: [String] = []
        if set.distance > 0 {
            parts.append("\(WorkoutValueFormatter.distanceText(set.distance)) dist")
        }
        if set.seconds > 0 {
            parts.append(WorkoutValueFormatter.durationText(seconds: set.seconds))
        }
        if parts.isEmpty, set.reps > 0 {
            parts.append("\(set.reps) \(cardioConfig.countLabel)")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " | ")
    }

}

struct SyncPulse: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.4 : 0.8)
            .opacity(isPulsing ? 0.6 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
