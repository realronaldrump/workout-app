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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        return "\(datePart) at \(timePart)"
    }

    var body: some View {
        let workout = resolvedWorkout
        ZStack {
            AdaptiveBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    workoutHeader(workout)

                    summaryCard(for: workout)

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        SectionHeading(title: "Exercises")

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

                    if healthManager.isHealthKitAvailable() {
                        healthDataSection
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
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xxl)
                .contentColumn()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(workout.date.formatted(.dateTime.month(.abbreviated).day().year()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            AppToolbarItemGroup(placement: .topBarTrailing) {
                if isLoggedWorkout {
                    AppToolbarButton(title: "Edit", systemImage: "pencil", variant: .neutral) {
                        showingEdit = true
                        Haptics.selection()
                    }
                    .accessibilityHint("Edit this workout")
                }

                AppToolbarButton(title: "Repeat", systemImage: "arrow.counterclockwise", variant: .neutral) {
                    repeatThisWorkout()
                    Haptics.selection()
                }
                .accessibilityHint("Start a new session based on this workout")
            }
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
        .alert("Couldn't sync Health data", isPresented: $showingSyncError) {
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
        .accessibilityIdentifier("workout-detail")
    }

    private func workoutHeader(_ workout: Workout) -> some View {
        let parts = SharedFormatters.workoutTitleParts(workout.name)
        let recordCount = personalRecordExerciseIDs.count
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: 6) {
                    PlateMark(category: plateCategory(for: workout), height: 16)
                    Text(plateCategory(for: workout).title)
                        .font(Theme.Typography.caption2Bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.tag, style: .continuous)
                        .fill(Theme.Colors.panelStrong)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(plateCategory(for: workout).title) session")

                if recordCount > 0 {
                    PRTag(text: recordCount == 1 ? "1 PR" : "\(recordCount) PRs")
                        .accessibilityLabel(recordCount == 1 ? "1 personal record" : "\(recordCount) personal records")
                }
            }

            Text(parts.title)
                .font(Theme.Typography.displayHero)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(headerMeta(for: workout, place: parts.place))
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headerMeta(for workout: Workout, place: String?) -> String {
        let when = workoutDateTimeToolbarText(for: workout.date)
        guard let place else { return when + "." }
        return "\(place). \(when)."
    }

    /// What the session mostly trained, for the plate tag.
    private func plateCategory(for workout: Workout) -> PlateCategory {
        let names = Set(workout.exercises.map(\.name))
        let assignments = ExerciseMetadataManager.shared.resolvedAssignmentMappings(for: names)
        return PlateCategory.classify(workout, assignments: assignments)
    }

    private func summaryCard(for workout: Workout) -> some View {
        Button {
            showingSessionInsights = true
            Haptics.selection()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                let statsLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
                    : AnyLayout(StatColumns())
                statsLayout {
                    summaryStat(
                        title: "time",
                        value: SharedFormatters.durationMinutes(Double(workout.estimatedDurationMinutes()))
                    )
                    summaryStat(
                        title: cachedSummary?.exerciseCount == 1 ? "exercise" : "exercises",
                        value: cachedSummary.map { "\($0.exerciseCount)" } ?? "—"
                    )
                    summaryStat(
                        title: cachedSummary?.setCount == 1 ? "set" : "sets",
                        value: cachedSummary.map { "\($0.setCount)" } ?? "—"
                    )
                    summaryStat(
                        title: "lbs lifted",
                        value: cachedSummary.map {
                            $0.volume > 0 ? SharedFormatters.volumeCompact($0.volume) : "—"
                        } ?? "—"
                    )
                }

                if let comparison = cachedComparison {
                    Rectangle()
                        .fill(Theme.Colors.rule)
                        .frame(height: 1)

                    ViewThatFits(in: .horizontal) {
                        comparisonContent(comparison, stacked: false)
                        comparisonContent(comparison, stacked: true)
                    }
                }

                HStack(spacing: 3) {
                    Text("Session breakdown")
                        .font(Theme.Typography.subheadlineStrong)
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.microLabel)
                }
                .foregroundStyle(Theme.Colors.textPrimary)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard()
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityHint("Opens volume by exercise, stats, and heart rate")
    }

    private func summaryStat(title: String, value: String) -> some View {
        DisplayStat(value: value, label: title)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func comparisonContent(
        _ comparison: WorkoutDetailComparison,
        stacked: Bool
    ) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                comparisonTitle(comparison)
                comparisonDeltas(comparison)
            }
        } else {
            HStack(spacing: Theme.Spacing.sm) {
                comparisonTitle(comparison)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
                comparisonDeltas(comparison)
            }
        }
    }

    private func comparisonTitle(_ comparison: WorkoutDetailComparison) -> some View {
        Text("Against the last \(SharedFormatters.workoutTitleParts(comparison.workoutName).title)")
            .font(Theme.Typography.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func comparisonDeltas(_ comparison: WorkoutDetailComparison) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
        return layout {
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

    // MARK: - Health Data Section

    private func variantReviewSection(review: WorkoutVariantWorkoutReview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(title: "What changed") {
                NavigationLink {
                    WorkoutVariantReviewView(focusWorkoutId: workout.id)
                } label: {
                    TextLinkLabel(title: "Full review")
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
            SectionHeading(title: "Heart and recovery") {
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
                }
                Text(healthManager.isSyncing ? "Syncing…" : (hasData ? "Sync again" : "Sync"))
                    .font(Theme.Typography.subheadlineStrong)
                    .underline(!healthManager.isSyncing)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(AppInteractionButtonStyle())
        .disabled(healthManager.isSyncing)
        .accessibilityLabel(healthManager.isSyncing ? "Syncing Apple Health data" : "Sync Apple Health data")
    }

    private var noHealthDataCard: some View {
        Text("No heart rate or energy saved for this workout yet. Sync to pull it from Apple Health.")
            .font(Theme.Typography.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .ledgerRow()
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
