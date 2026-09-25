import Combine
import SwiftUI

// swiftlint:disable file_length
private struct SessionExerciseContext {
    let history: [(date: Date, sets: [WorkoutSet])]
    let isCardio: Bool
    let cardioConfig: ResolvedCardioMetricConfiguration?
    let recommendation: ExerciseRecommendation?
}

struct WorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var logStore: WorkoutLogStore
    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared

    private let weightUnit = "lbs"
    @AppStorage("weightIncrement") private var weightIncrement: Double = 2.5

    @State private var showingExercisePicker = false
    @State private var showingFinishSheet = false
    @State private var showingDiscardAlert = false
    @State private var showingUncheckedSetAlert = false
    @State private var showingRestSettings = false
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var showingGymPicker = false
    @State private var finishErrorMessage: String?
    @State private var isFinishing = false
    @State private var finishDidSave = false
    /// Snapshot shown on the success screen; the live summary resets once the session ends.
    @State private var finishedSummary: FinishSessionSummary?
    @State private var pendingUncheckedSetCount = 0
    @State private var exerciseCardContexts: [String: SessionExerciseContext] = [:]
    @State private var cachedMuscleSuggestions: [MuscleGroupSuggestion] = []
    @State private var cachedCanFinishSession = false
    @State private var cachedUncheckedSetCount = 0
    @State private var cachedSummary = FinishSessionSummary(
        startedAt: Date(),
        exerciseCount: 0,
        completedSetCount: 0,
        strengthVolume: 0,
        cardioDistance: 0,
        cardioSeconds: 0,
        cardioCount: 0
    )

    private let allowedWeightIncrements: [Double] = [1.25, 2.5, 5.0]

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                if let session = sessionManager.activeSession {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            headerCard(session)

                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                SectionHeading(
                                    title: "Exercises",
                                    subtitle: session.exercises.isEmpty ? nil : exercisesSubtitle(session)
                                )

                                if session.exercises.isEmpty {
                                    EmptyStateCard(
                                        icon: "dumbbell.fill",
                                        tint: Theme.Colors.accent,
                                        title: "Let's Get Moving",
                                        message: "Add your first exercise to start logging sets."
                                    )
                                } else {
                                    LazyVStack(spacing: Theme.Spacing.lg) {
                                        ForEach(session.exercises) { exercise in
                                            SessionExerciseCard(
                                                exercise: exercise,
                                                context: exerciseCardContexts[exercise.name],
                                                weightUnit: weightUnit,
                                                weightIncrement: resolvedWeightIncrement,
                                                dataManager: dataManager,
                                                annotationsManager: annotationsManager,
                                                gymProfilesManager: gymProfilesManager,
                                                sessionManager: sessionManager
                                            )
                                            .transition(.asymmetric(
                                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity.combined(with: .scale(scale: 0.96))
                                            ))
                                        }
                                    }
                                    .animation(Theme.Animation.spring, value: session.exercises.map(\.id))
                                }
                            }

                            // Add sits after the list so the next exercise is added where the
                            // lifter already is, instead of scrolling back to the top.
                            addExerciseButton

                            if !cachedMuscleSuggestions.isEmpty {
                                muscleSuggestionSection(cachedMuscleSuggestions)
                            }
                        }
                        .padding(Theme.Spacing.xl)
                        .contentColumn()
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    EmptyStateCard(
                        icon: "bolt.slash",
                        tint: Theme.Colors.textTertiary,
                        title: "No Active Session",
                        message: "Start a session from Home to begin logging."
                    )
                    .padding(.horizontal, Theme.Spacing.xl)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .analyticsScreen("WorkoutSession")
            .safeAreaInset(edge: .top, spacing: 0) {
                sessionTopBar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if sessionManager.activeSession != nil {
                    VStack(spacing: 0) {
                        // The rest timer rides above the finish bar so it stays visible no
                        // matter how far down the exercise list the lifter has scrolled.
                        RestTimerCard(
                            timer: sessionManager.restTimer,
                            onExtendThirtySeconds: {
                                sessionManager.extendRestTimer(by: 30)
                                Haptics.selection()
                            },
                            onShowSettings: {
                                showingRestSettings = true
                                Haptics.selection()
                            },
                            onCancel: {
                                sessionManager.cancelRestTimer()
                                Haptics.selection()
                            }
                        )
                        .contentColumn(maxWidth: 640, alignment: .center)
                        .padding(.horizontal, Theme.Spacing.lg)

                        finishBar
                    }
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(
                    alreadyAdded: Set(sessionManager.activeSession?.exercises.map(\.name) ?? [])
                ) { selected in
                    addExerciseWithPrefill(name: selected)
                }
            }
            .sheet(isPresented: $showingFinishSheet) {
                FinishSessionSheet(
                    isFinishing: isFinishing,
                    didSave: finishDidSave,
                    summary: finishedSummary ?? cachedSummary,
                    errorMessage: finishErrorMessage,
                    onFinish: { finishSession() },
                    onDismissError: { finishErrorMessage = nil },
                    onDone: { completeFinishedSessionPresentation() }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(isFinishing || finishDidSave)
            }
            .alert("Discard Session?", isPresented: $showingDiscardAlert) {
                Button("Keep", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    Task { @MainActor in
                        await sessionManager.discardDraft()
                        Haptics.notify(.warning)
                        dismiss()
                    }
                }
            } message: {
                Text("This will permanently delete your in-progress session and all sets.")
            }
            .alert("Uncompleted Sets?", isPresented: $showingUncheckedSetAlert) {
                Button("Keep Editing", role: .cancel) {}
                if cachedSummary.completedSetCount > 0 {
                    Button("Discard Uncompleted", role: .destructive) {
                        showingFinishSheet = true
                        Haptics.selection()
                    }
                }
                Button("Mark as Complete") {
                    sessionManager.markIncompleteSetsWithEnteredDataCompleted()
                    refreshDerivedSessionState(rebuildContexts: false)
                    showingFinishSheet = true
                    Haptics.selection()
                }
            } message: {
                Text(uncheckedSetAlertMessage)
            }
            .alert("Rename Workout", isPresented: $showingRenameAlert) {
                TextField("Workout name", text: $renameText)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    sessionManager.updateSessionName(renameText)
                }
            }
            .sheet(isPresented: $showingGymPicker) {
                GymSelectionSheet(
                    title: "Choose Gym",
                    gyms: gymProfilesManager.sortedGyms,
                    selected: sessionManager.activeSession?.gymProfileId.map { GymSelection.gym($0) } ?? .unassigned,
                    showAllGyms: false,
                    showUnassigned: true,
                    lastUsedGymId: gymProfilesManager.lastUsedGymProfileId,
                    showLastUsed: gymProfilesManager.lastUsedGymProfileId != nil,
                    showAddNew: false,
                    onSelect: { selection in
                        switch selection {
                        case .unassigned, .allGyms:
                            sessionManager.setGymProfileId(nil)
                        case .gym(let id):
                            sessionManager.setGymProfileId(id)
                        }
                    },
                    onAddNew: nil
                )
            }
            .sheet(isPresented: $showingRestSettings) {
                RestTimerSettingsSheet(
                    timer: sessionManager.restTimer,
                    onSelectDuration: { seconds in
                        sessionManager.setRestTimerDuration(seconds)
                        Haptics.selection()
                    }
                )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                sessionManager.restTimer.syncDurationFromDefaults()
                // Keep increment options aligned with pounds-only behavior.
                let isAllowed = allowedWeightIncrements.contains { abs($0 - weightIncrement) < 0.0001 }
                if weightIncrement <= 0 || !isAllowed {
                    weightIncrement = 2.5
                }
                refreshDerivedSessionState()
            }
            .onChange(of: sessionManager.activeSession) { oldSession, newSession in
                let oldExercises = oldSession?.exercises.map { "\($0.id.uuidString):\($0.name)" } ?? []
                let newExercises = newSession?.exercises.map { "\($0.id.uuidString):\($0.name)" } ?? []
                refreshDerivedSessionState(rebuildContexts: oldExercises != newExercises)
            }
            .onChange(of: weightIncrement) { _, _ in
                refreshDerivedSessionState()
            }
            .onReceive(
                dataManager.$workouts
                    .dropFirst()
                    .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            ) { _ in
                refreshDerivedSessionState()
            }
            .onReceive(
                Publishers.Merge(
                    metadataManager.objectWillChange.map { _ in () },
                    metricManager.objectWillChange.map { _ in () }
                )
                .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            ) { _ in
                refreshDerivedSessionState()
            }
        }
    }

    private var sessionTopBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                sessionManager.isPresentingSessionUI = false
                dismiss()
                Haptics.selection()
            } label: {
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.bodyStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Theme.Colors.surfaceRaised)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.Colors.border.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Minimize session")

            Spacer(minLength: Theme.Spacing.sm)

            if let session = sessionManager.activeSession {
                HStack(spacing: Theme.Spacing.xs) {
                    LivePulseDot(color: Theme.Colors.success, size: 7)
                        .frame(width: 14, height: 14)
                    Text(session.startedAt, style: .timer)
                        .font(Theme.Typography.headline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: 36)
                .background(Capsule().fill(Theme.Colors.surfaceRaised))
                .overlay(Capsule().strokeBorder(Theme.Colors.border.opacity(0.5), lineWidth: 1))
                .frame(minHeight: Theme.Layout.minimumTapTarget)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Elapsed time")
            }

            Spacer(minLength: Theme.Spacing.sm)

            Button(role: .destructive) {
                showingDiscardAlert = true
                Haptics.selection()
            } label: {
                Image(systemName: "trash")
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.error)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Theme.Colors.error.opacity(0.06))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.Colors.error.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(sessionManager.activeSession == nil || isFinishing)
            .accessibilityLabel("Discard session")
        }
        .contentColumn()
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.sm)
        .background(.bar)
    }

    private var finishBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            AppPrimaryButton(
                title: isFinishing ? "Saving Workout…" : "Finish Workout",
                systemImage: "checkmark.circle.fill",
                isEnabled: !isFinishing && cachedCanFinishSession
            ) {
                presentFinishFlow()
                Haptics.selection()
            }

            if !cachedCanFinishSession {
                Text("Complete at least one valid set to finish.")
                    .font(Theme.Typography.microcopy)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .contentColumn(maxWidth: 640, alignment: .center)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.bar)
    }

    private var resolvedWeightIncrement: Double {
        let inc = weightIncrement
        let isAllowed = allowedWeightIncrements.contains { abs($0 - inc) < 0.0001 }
        return (inc > 0 && isAllowed) ? inc : 2.5
    }

    private var addExerciseButton: some View {
        Button {
            showingExercisePicker = true
            Haptics.selection()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "plus")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.accentGradient))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Exercise")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Search, pick a favorite, or create a new one")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                    .fill(Theme.Colors.accentTint.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                    .strokeBorder(
                        Theme.Colors.accent.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardButtonStyle())
    }

    private func exercisesSubtitle(_ session: ActiveWorkoutSession) -> String {
        let totalSets = session.exercises.reduce(0) { $0 + $1.sets.count }
        let doneSets = session.exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.isCompleted).count
        }
        return "\(doneSets) of \(SharedFormatters.count(totalSets, "set")) done"
    }

    // MARK: - Auto-Prefill Helper

    private func addExerciseWithPrefill(name: String) {
        let tags = ExerciseMetadataManager.shared.resolvedTags(for: name)
        let isCardio = tags.contains(where: { $0.builtInGroup == .cardio })

        if isCardio {
            sessionManager.addExercise(name: name)
        } else {
            let history = dataManager.getExerciseHistory(for: name)
            let rec = ExerciseRecommendationEngine.recommend(
                exerciseName: name,
                history: history,
                weightIncrement: resolvedWeightIncrement
            )
            let midReps = (rec.repRange.lowerBound + rec.repRange.upperBound) / 2
            sessionManager.addExercise(
                name: name,
                initialSetPrefill: SetPrefill(weight: rec.suggestedWeight, reps: midReps)
            )
        }
        Haptics.added()
    }

    private func headerCard(_ session: ActiveWorkoutSession) -> some View {
        let totalSets = session.exercises.reduce(0) { $0 + $1.sets.count }
        let doneSets = session.exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.isCompleted).count
        }
        let fraction = totalSets > 0 ? Double(doneSets) / Double(totalSets) : 0

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                BrandBandLabel(text: "Live session", systemImage: "bolt.fill")

                Spacer(minLength: Theme.Spacing.sm)

                Button {
                    showingGymPicker = true
                    Haptics.selection()
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "mappin.and.ellipse")
                            .accessibilityHidden(true)
                        Text(gymLabel(for: session.gymProfileId))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(Theme.Typography.microLabel)
                            .accessibilityHidden(true)
                    }
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.sm + 2)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Colors.surfaceRaised))
                    .overlay(Capsule().strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 1))
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gym, \(gymLabel(for: session.gymProfileId))")
                .accessibilityHint("Changes the gym for this workout")
            }

            Button {
                renameText = session.name
                showingRenameAlert = true
                Haptics.selection()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(session.name)
                        .font(Theme.Typography.displayHeroCompact)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "pencil")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Theme.Layout.minimumTapTarget)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Workout name, \(session.name)")
            .accessibilityHint("Renames this workout")

            HStack(spacing: Theme.Spacing.sm) {
                sessionStat(
                    title: "Sets",
                    value: totalSets > 0 ? "\(doneSets)/\(totalSets)" : "0",
                    numeric: Double(doneSets)
                )
                sessionStat(
                    title: "Volume",
                    value: cachedSummary.strengthVolume > 0
                        ? SharedFormatters.volumeCompact(cachedSummary.strengthVolume)
                        : "0",
                    numeric: cachedSummary.strengthVolume
                )
                sessionStat(
                    title: "Exercises",
                    value: "\(session.exercises.count)",
                    numeric: Double(session.exercises.count)
                )
            }

            if totalSets > 0 {
                SessionProgressBar(fraction: fraction)
                    .accessibilityElement()
                    .accessibilityLabel("Session progress")
                    .accessibilityValue("\(doneSets) of \(totalSets) sets complete")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func sessionStat(title: String, value: String, numeric: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(value: numeric))
                .animation(Theme.Animation.spring, value: numeric)
            Text(title)
                .sectionHeaderStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                .fill(Theme.Colors.surfaceRaised)
        )
        .accessibilityElement(children: .combine)
    }

    private func muscleSuggestionSection(_ suggestions: [MuscleGroupSuggestion]) -> some View {
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                SectionHeading(title: "Up Next Ideas", subtitle: "Muscles you haven't hit lately")

                Button("Dismiss all") {
                    for suggestion in suggestions {
                        sessionManager.dismissMuscleGroupSuggestion(suggestion.group)
                    }
                    Haptics.selection()
                }
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .buttonStyle(.plain)
                .frame(minHeight: Theme.Layout.minimumTapTarget)
            }

            VStack(spacing: Theme.Spacing.md) {
                ForEach(suggestions) { suggestion in
                    MuscleSuggestionCard(
                        suggestion: suggestion,
                        onAddExercise: { name in
                            addExerciseWithPrefill(name: name)
                        },
                        onDismiss: {
                            sessionManager.dismissMuscleGroupSuggestion(suggestion.group)
                            Haptics.selection()
                        }
                    )
                }
            }
        }
    }

    private func finishSession() {
        guard !isFinishing else { return }
        isFinishing = true
        finishErrorMessage = nil

        Task { @MainActor in
            defer { isFinishing = false }

            do {
                // Save before ending the session so a failed write never loses the workout:
                // the draft is only deleted once the finished workout is stored.
                let logged = try sessionManager.prepareFinishedWorkout()
                do {
                    try await logStore.save(logged)
                } catch {
                    throw WorkoutFinishSaveError(underlying: error)
                }
                finishedSummary = FinishSessionSummary(
                    startedAt: logged.startedAt,
                    exerciseCount: logged.exercises.count,
                    completedSetCount: cachedSummary.completedSetCount,
                    strengthVolume: cachedSummary.strengthVolume,
                    cardioDistance: cachedSummary.cardioDistance,
                    cardioSeconds: cachedSummary.cardioSeconds,
                    cardioCount: cachedSummary.cardioCount,
                    endedAt: logged.endedAt
                )
                await sessionManager.completeFinish(logged)
                await dataManager.setLoggedWorkoutsOffMain(logStore.workouts)

                annotationsManager.setGym(for: logged.id, gymProfileId: logged.gymProfileId)
                gymProfilesManager.setLastUsedGymProfileId(logged.gymProfileId)

                // Kick HealthKit sync in the background if possible.
                if healthManager.authorizationStatus == .authorized,
                   let workout = dataManager.workouts.first(where: { $0.id == logged.id }) {
                    Task {
                        do {
                            _ = try await healthManager.syncHealthDataForWorkout(workout)
                        } catch {
                            healthManager.syncError = "Workout saved, but Health sync failed: \(error.localizedDescription)"
                        }
                    }
                }

                Haptics.workoutFinished()
                finishDidSave = true
            } catch {
                finishErrorMessage = error.localizedDescription
                AppAnalytics.shared.track(
                    AnalyticsSignal.sessionFinishFailed,
                    payload: ["Session.errorDomain": String(describing: type(of: error))]
                )
            }
        }
    }

    private func completeFinishedSessionPresentation() {
        showingFinishSheet = false
        finishDidSave = false
        finishedSummary = nil
        sessionManager.isPresentingSessionUI = false
        dismiss()
    }

    private func presentFinishFlow() {
        let uncheckedSetCount = cachedUncheckedSetCount
        if uncheckedSetCount > 0 {
            pendingUncheckedSetCount = uncheckedSetCount
            showingUncheckedSetAlert = true
            return
        }

        showingFinishSheet = true
    }

    private var uncheckedSetAlertMessage: String {
        if pendingUncheckedSetCount == 1 {
            return "You have 1 set with data entered but not marked complete. Mark it as complete before saving, or discard it from the finished workout."
        }

        return "You have \(pendingUncheckedSetCount) sets with data entered but not marked complete. Mark them as complete before saving, or discard them from the finished workout."
    }

    private func hasEnteredData(_ set: ActiveSet, isCardio: Bool) -> Bool {
        if isCardio {
            let reps = max(set.reps ?? 0, 0)
            let distance = max(set.distance ?? 0, 0)
            let seconds = max(set.seconds ?? 0, 0)
            return reps > 0 || distance > 0 || seconds > 0
        }

        guard let weight = set.weight, let reps = set.reps else {
            return false
        }
        return weight >= 0 && reps > 0
    }

    private func gymLabel(for gymId: UUID?) -> String {
        if let name = gymProfilesManager.gymName(for: gymId) {
            return name
        }
        return gymId == nil ? "Unassigned" : "Deleted gym"
    }

    private func refreshDerivedSessionState(rebuildContexts: Bool = true) {
        guard let session = sessionManager.activeSession else {
            exerciseCardContexts = [:]
            cachedMuscleSuggestions = []
            cachedCanFinishSession = false
            cachedUncheckedSetCount = 0
            cachedSummary = FinishSessionSummary(
                startedAt: Date(),
                exerciseCount: 0,
                completedSetCount: 0,
                strengthVolume: 0,
                cardioDistance: 0,
                cardioSeconds: 0,
                cardioCount: 0
            )
            return
        }

        let sessionExerciseNames = Set(session.exercises.map(\.name))
        let shouldRebuildContexts = rebuildContexts || Set(exerciseCardContexts.keys) != sessionExerciseNames
        var contexts = exerciseCardContexts

        if shouldRebuildContexts {
            contexts.removeAll(keepingCapacity: true)
            contexts.reserveCapacity(session.exercises.count)

            for exercise in session.exercises {
                let history = dataManager.getExerciseHistory(for: exercise.name)
                let tags = metadataManager.resolvedTags(for: exercise.name)
                let isCardio = tags.contains(where: { $0.builtInGroup == .cardio })
                let historySets = history.flatMap(\.sets)
                let cardioConfig = isCardio
                    ? metricManager.resolvedCardioConfiguration(for: exercise.name, historySets: historySets)
                    : nil
                let recommendation = isCardio
                    ? nil
                    : ExerciseRecommendationEngine.recommend(
                        exerciseName: exercise.name,
                        history: history,
                        weightIncrement: resolvedWeightIncrement
                    )

                contexts[exercise.name] = SessionExerciseContext(
                    history: history,
                    isCardio: isCardio,
                    cardioConfig: cardioConfig,
                    recommendation: recommendation
                )
            }
        }

        var completedSetCount = 0
        var strengthVolume = 0.0
        var cardioDistance = 0.0
        var cardioSeconds = 0.0
        var cardioCount = 0
        var uncheckedSetCount = 0
        var canFinish = true

        for exercise in session.exercises {
            let isCardio = contexts[exercise.name]?.isCardio
                ?? metadataManager.resolvedTags(for: exercise.name).contains(where: { $0.builtInGroup == .cardio })

            for set in exercise.sets where !set.isCompleted {
                if hasEnteredData(set, isCardio: isCardio) {
                    uncheckedSetCount += 1
                }
            }

            for set in exercise.sets where set.isCompleted {
                if isCardio {
                    let reps = max(set.reps ?? 0, 0)
                    let distance = max(set.distance ?? 0, 0)
                    let seconds = max(set.seconds ?? 0, 0)
                    if reps == 0 && distance == 0 && seconds == 0 {
                        canFinish = false
                    }
                    cardioDistance += Double(distance)
                    cardioSeconds += Double(seconds)
                    cardioCount += reps
                } else {
                    guard let weight = set.weight, let reps = set.reps, weight >= 0, reps > 0 else {
                        canFinish = false
                        continue
                    }
                    strengthVolume += weight * Double(reps)
                }
                completedSetCount += 1
            }
        }

        if shouldRebuildContexts {
            let allExerciseNames = Set(dataManager.allExerciseNames())
            let resolver = ExerciseIdentityResolver.current
            let assignmentMappings = metadataManager.resolvedAssignmentMappings(
                for: allExerciseNames,
                resolver: resolver
            )
            exerciseCardContexts = contexts
            cachedMuscleSuggestions = buildMuscleSuggestions(
                for: session,
                assignmentMappings: assignmentMappings
            )
        }
        cachedUncheckedSetCount = uncheckedSetCount
        cachedCanFinishSession = canFinish && (completedSetCount > 0 || uncheckedSetCount > 0)
        cachedSummary = FinishSessionSummary(
            startedAt: session.startedAt,
            exerciseCount: session.exercises.count,
            completedSetCount: completedSetCount,
            strengthVolume: strengthVolume,
            cardioDistance: cardioDistance,
            cardioSeconds: cardioSeconds,
            cardioCount: cardioCount
        )
    }

    private func buildMuscleSuggestions(
        for session: ActiveWorkoutSession,
        assignmentMappings: [String: [ExerciseMuscleAssignment]]
    ) -> [MuscleGroupSuggestion] {
        guard !dataManager.workouts.isEmpty else { return [] }

        let resolver = ExerciseIdentityResolver.current
        var plannedEffectiveSets: [MuscleGroup: Double] = [:]
        for exercise in session.exercises {
            let aggregateName = resolver.aggregateName(for: exercise.name)
            let assignments = assignmentMappings[exercise.name] ?? assignmentMappings[aggregateName] ?? []
            for assignment in assignments {
                guard let group = assignment.tag.builtInGroup else { continue }
                plannedEffectiveSets[group, default: 0] += MuscleContributionPolicy.effectiveSets(
                    setCount: max(exercise.sets.count, 1),
                    assignment: assignment
                )
            }
        }
        let covered = Set(
            plannedEffectiveSets.compactMap { group, effectiveSets in
                effectiveSets >= 1 ? group : nil
            }
        )

        let dismissed = Set(session.dismissedMuscleGroupSuggestions.compactMap(MuscleGroup.init(rawValue:)))
        return MuscleRecencySuggestionEngine.suggestions(
            workouts: dataManager.workouts,
            muscleAssignmentsByExerciseName: assignmentMappings,
            excluding: covered.union(dismissed),
            resolver: resolver
        )
    }

}

private struct WorkoutFinishSaveError: LocalizedError {
    let underlying: Error

    var errorDescription: String? {
        "Couldn't save your workout (\(underlying.localizedDescription)). Your session is still here, so try again."
    }
}

// MARK: - Rest Timer UI

private struct RestTimerCard: View {
    @ObservedObject var timer: RestTimerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onExtendThirtySeconds: () -> Void
    let onShowSettings: () -> Void
    let onCancel: () -> Void

    private var isEnding: Bool {
        timer.secondsRemaining <= 10
    }

    private var tint: Color {
        isEnding ? Theme.Colors.accentSecondary : Theme.Colors.accent
    }

    private var progress: Double {
        guard timer.currentTotal > 0 else { return 0 }
        return min(1, Double(timer.secondsRemaining) / Double(timer.currentTotal))
    }

    var body: some View {
        ZStack {
            if timer.isActive {
                ViewThatFits(in: .horizontal) {
                    dock(compact: false)
                    dock(compact: true)
                }
                .padding(.bottom, Theme.Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: timer.isActive)
    }

    private func dock(compact: Bool) -> some View {
        HStack(spacing: compact ? Theme.Spacing.sm : Theme.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 1), value: timer.secondsRemaining)
                Image(systemName: "timer")
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: isEnding && !reduceMotion)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                if !compact {
                    Text(isEnding ? "Almost up" : "Resting")
                        .font(Theme.Typography.caption2Bold)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(tint)
                }
                Text(restTimerFormatted(timer.secondsRemaining))
                    .font(Theme.Typography.title2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : .snappy, value: timer.secondsRemaining)
            }
            .fixedSize()

            Spacer(minLength: 0)

            Button(action: onExtendThirtySeconds) {
                Text("+30s")
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Theme.Colors.accentTint))
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(AppInteractionButtonStyle())
            .accessibilityLabel("Add 30 seconds")

            Button(action: onShowSettings) {
                Image(systemName: "gearshape.fill")
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: compact ? 36 : Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(AppInteractionButtonStyle())
            .accessibilityLabel("Rest timer settings")

            Button(action: onCancel) {
                Group {
                    if compact {
                        Image(systemName: "forward.end.fill")
                    } else {
                        Text("Skip")
                    }
                }
                .font(Theme.Typography.subheadlineBold)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, compact ? 0 : Theme.Spacing.xs)
                .frame(minWidth: compact ? 36 : Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
                .contentShape(.rect)
            }
            .buttonStyle(AppInteractionButtonStyle())
            .accessibilityLabel("Skip rest")
        }
        .padding(.leading, Theme.Spacing.sm)
        .padding(.trailing, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xs)
        .glassBackground(
            opacity: 0.22,
            cornerRadius: Theme.CornerRadius.xlarge,
            elevation: 2,
            interactive: true
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge, style: .continuous)
                .strokeBorder(tint.opacity(isEnding ? 0.5 : 0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer, \(restTimerFormatted(timer.secondsRemaining)) remaining")
    }
}

/// Thin gradient bar that fills as sets are completed; turns green when all are done.
private struct SessionProgressBar: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double {
        min(max(fraction.isFinite ? fraction : 0, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.border.opacity(0.45))
                Capsule()
                    .fill(clamped >= 1 ? AnyShapeStyle(Theme.successGradient) : AnyShapeStyle(Theme.accentGradient))
                    .frame(width: clamped > 0 ? max(proxy.size.width * CGFloat(clamped), 8) : 0)
            }
        }
        .frame(height: 8)
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: clamped)
    }
}

/// Set number that flips to a green check when the set is logged.
private struct SetCompletionBadge: View {
    let order: Int
    let isCompleted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let completedFill = LinearGradient(
        colors: [
            Color(uiColor: UIColor(hex: 0x22C55E)),
            Color(uiColor: UIColor(hex: 0x15803D))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            Circle()
                .fill(isCompleted ? AnyShapeStyle(Self.completedFill) : AnyShapeStyle(Color.clear))
            if !isCompleted {
                Circle()
                    .strokeBorder(
                        Theme.Colors.textTertiary.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2, dash: [3, 3])
                    )
            }
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                Text("\(order)")
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .transition(.opacity)
            }
        }
        .frame(width: 36, height: 36)
        .scaleEffect(isCompleted || reduceMotion ? 1 : 0.94)
        .shadow(
            color: isCompleted ? Color(uiColor: UIColor(hex: 0x16A34A)).opacity(0.35) : .clear,
            radius: 6,
            x: 0,
            y: 3
        )
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.55), value: isCompleted)
        .accessibilityHidden(true)
    }
}

private struct RestTimerSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var timer: RestTimerState
    let onSelectDuration: (Int) -> Void

    private let presets = [30, 45, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                HStack {
                    Text("Rest Timer")
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    AppToolbarIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "Close rest timer settings",
                        variant: .subtle
                    ) {
                        dismiss()
                    }
                }

                Text(
                    "Choose the default rest time started after a completed set. Your choice is remembered, "
                        + "and you'll get a notification when rest ends if your phone is locked."
                )
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.sm)],
                    spacing: Theme.Spacing.sm
                ) {
                    ForEach(presets, id: \.self) { seconds in
                        Button {
                            onSelectDuration(seconds)
                        } label: {
                            Text(restTimerFormatted(seconds))
                                .font(Theme.Typography.headline)
                                .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: Theme.CornerRadius.large))
                        .tint(timer.duration == seconds ? Theme.Colors.accent : Theme.Colors.textSecondary)
                        .accessibilityAddTraits(timer.duration == seconds ? .isSelected : [])
                    }
                }
            }
            .padding(Theme.Spacing.xl)
        }
        .background(Theme.Colors.background)
    }
}

private func restTimerFormatted(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return remainingSeconds > 0
        ? "\(minutes):\(String(format: "%02d", remainingSeconds))"
        : "\(minutes):00"
}

// MARK: - Exercise Card

private struct SessionExerciseCard: View {
    let exercise: ActiveExercise
    let context: SessionExerciseContext?
    let weightUnit: String
    let weightIncrement: Double
    let dataManager: WorkoutDataManager
    let annotationsManager: WorkoutAnnotationsManager
    let gymProfilesManager: GymProfilesManager
    let sessionManager: WorkoutSessionManager

    @State private var showingHistory = false
    @State private var showingRemoveExerciseAlert = false

    var body: some View {
        let rec = context?.recommendation
        let isCardio = context?.isCardio ?? false
        let cardioConfig = context?.cardioConfig

        let historicalBest = historicalBestWeight
        let prSetID = personalRecordSetID(historicalBest: historicalBest)

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(exercise.name)
                            .font(Theme.Typography.title4Bold)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !exercise.sets.isEmpty {
                            setProgressChip
                        }
                    }

                    if let rec {
                        Label(recommendationLine(rec), systemImage: "scope")
                            .labelStyle(.titleAndIcon)
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.accent)
                    } else if isCardio {
                        Text("Cardio")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textSecondary)
                    } else {
                        Text("Suggestions loading")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    if let rec, !rec.warmup.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text("Warm-up")
                                    .font(Theme.Typography.caption2Bold)
                                    .foregroundColor(Theme.Colors.accentSecondary)
                                ForEach(Array(rec.warmup.enumerated()), id: \.offset) { _, item in
                                    Text("\(formatWeight(item.weight)) × \(item.reps)")
                                        .font(Theme.Typography.caption2Bold)
                                        .monospacedDigit()
                                        .foregroundColor(Theme.Colors.textSecondary)
                                        .padding(.horizontal, Theme.Spacing.sm)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Theme.Colors.accentSecondary.opacity(Theme.Opacity.subtleFill)))
                                        .overlay(Capsule().strokeBorder(Theme.Colors.accentSecondary.opacity(0.2), lineWidth: 1))
                                }
                            }
                        }
                    }

                    if let rec {
                        Text(rec.rationale)
                            .font(Theme.Typography.microcopy)
                            .foregroundColor(Theme.Colors.textTertiary)
                    } else if let cardioConfig {
                        Text(cardioRationale(cardioConfig))
                            .font(Theme.Typography.microcopy)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }

                Spacer()

                Menu {
                    Button("History", systemImage: "clock.arrow.circlepath") {
                        showingHistory = true
                    }
                    if let position = exercisePosition {
                        if position.index > 0 {
                            Button("Move Up", systemImage: "arrow.up") {
                                sessionManager.moveExercise(
                                    from: IndexSet(integer: position.index),
                                    to: position.index - 1
                                )
                                Haptics.selection()
                            }
                        }
                        if position.index < position.count - 1 {
                            Button("Move Down", systemImage: "arrow.down") {
                                sessionManager.moveExercise(
                                    from: IndexSet(integer: position.index),
                                    to: position.index + 2
                                )
                                Haptics.selection()
                            }
                        }
                    }
                    Button("Remove Exercise", systemImage: "trash", role: .destructive) {
                        showingRemoveExerciseAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(Theme.Iconography.title3)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(exercise.name) actions")
            }

            LazyVStack(spacing: Theme.Spacing.sm) {
                let recentSets: [WorkoutSet] = isCardio ? [] : lastSessionSets
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    SessionSetRow(
                        exerciseId: exercise.id,
                        exerciseName: exercise.name,
                        set: set,
                        previousSet: index > 0 ? exercise.sets[index - 1] : nil,
                        lastSessionSet: recentSets.indices.contains(set.order - 1)
                            ? recentSets[set.order - 1]
                            : nil,
                        weightUnit: weightUnit,
                        weightIncrement: weightIncrement,
                        cardioConfig: cardioConfig,
                        isPersonalBest: prSetID == set.id,
                        personalBestThreshold: personalBestThreshold(excluding: set.id, historicalBest: historicalBest)
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    if let lastEntered = lastEnteredSet {
                        // Most lifters repeat the previous set, so carry its values forward.
                        sessionManager.addSet(
                            exerciseId: exercise.id,
                            prefill: SetPrefill(
                                weight: lastEntered.weight,
                                reps: lastEntered.reps,
                                distance: lastEntered.distance,
                                seconds: lastEntered.seconds
                            )
                        )
                    } else if let rec {
                        sessionManager.addSet(exerciseId: exercise.id, prefill: SetPrefill(weight: rec.suggestedWeight, reps: defaultReps(rec.repRange)))
                    } else {
                        sessionManager.addSet(exerciseId: exercise.id)
                    }
                    Haptics.added()
                } label: {
                    Label("Add Set", systemImage: "plus")
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                                .fill(Theme.Colors.accentTint)
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(AppInteractionButtonStyle())
            }
        }
        .animation(Theme.Animation.spring, value: exercise.sets.map(\.id))
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .strokeBorder(Theme.Colors.success.opacity(isAllSetsDone ? 0.55 : 0), lineWidth: 1.5)
        )
        .animation(Theme.Animation.spring, value: isAllSetsDone)
        .navigationDestination(isPresented: $showingHistory) {
            ExerciseDetailView(
                exerciseName: exercise.name,
                dataManager: dataManager,
                annotationsManager: annotationsManager,
                gymProfilesManager: gymProfilesManager
            )
        }
        .alert("Remove Exercise?", isPresented: $showingRemoveExerciseAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                sessionManager.removeExercise(id: exercise.id)
            }
        } message: {
            Text("This will remove \(exercise.name) and all of its sets from the current session.")
        }
    }

    private var completedSetCount: Int {
        exercise.sets.filter(\.isCompleted).count
    }

    private var isAllSetsDone: Bool {
        !exercise.sets.isEmpty && completedSetCount == exercise.sets.count
    }

    private var setProgressChip: some View {
        HStack(spacing: 3) {
            if isAllSetsDone {
                Image(systemName: "checkmark")
                    .font(Theme.Typography.microLabel)
            }
            Text("\(completedSetCount)/\(exercise.sets.count)")
                .contentTransition(.numericText(value: Double(completedSetCount)))
        }
        .font(Theme.Typography.caption2Bold)
        .monospacedDigit()
        .foregroundStyle(isAllSetsDone ? Theme.Colors.success : Theme.Colors.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                isAllSetsDone
                    ? Theme.Colors.success.opacity(Theme.Opacity.mediumFill)
                    : Theme.Colors.border.opacity(0.4)
            )
        )
        .animation(Theme.Animation.spring, value: completedSetCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completedSetCount) of \(exercise.sets.count) sets complete")
    }

    /// Best tracked load from saved history. Nil for cardio or brand-new exercises,
    /// so a first session never lights up every set as a record.
    private var historicalBestWeight: Double? {
        guard context?.isCardio == false, let history = context?.history else { return nil }
        let weights = history
            .flatMap(\.sets)
            .map(\.weight)
            .filter { ExerciseLoad.isTrackedWeight($0, exerciseName: exercise.name) }
        return ExerciseLoad.bestWeight(in: weights, exerciseName: exercise.name)
    }

    private func completedTrackedWeight(_ set: ActiveSet) -> Double? {
        guard set.isCompleted, (set.reps ?? 0) > 0, let weight = set.weight,
              ExerciseLoad.isTrackedWeight(weight, exerciseName: exercise.name) else { return nil }
        return weight
    }

    /// The single heaviest completed set that beats history (earliest wins ties).
    private func personalRecordSetID(historicalBest: Double?) -> UUID? {
        guard let historicalBest else { return nil }
        var bestID: UUID?
        var bestWeight = historicalBest
        for set in exercise.sets.sorted(by: { $0.order < $1.order }) {
            guard let weight = completedTrackedWeight(set),
                  ExerciseLoad.isBetter(weight, than: bestWeight, exerciseName: exercise.name) else { continue }
            bestWeight = weight
            bestID = set.id
        }
        return bestID
    }

    /// What a set must beat to become the session's new record.
    private func personalBestThreshold(excluding setID: UUID, historicalBest: Double?) -> Double? {
        guard let historicalBest else { return nil }
        let others = exercise.sets
            .filter { $0.id != setID }
            .compactMap { completedTrackedWeight($0) }
        return ExerciseLoad.bestWeight(in: others + [historicalBest], exerciseName: exercise.name)
    }

    /// Sets from the most recent saved session of this exercise, in set order.
    private var lastSessionSets: [WorkoutSet] {
        guard let latest = context?.history.max(by: { $0.date < $1.date }) else { return [] }
        return latest.sets.sorted { $0.setOrder < $1.setOrder }
    }

    private var exercisePosition: (index: Int, count: Int)? {
        guard let exercises = sessionManager.activeSession?.exercises,
              let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return nil }
        return (index, exercises.count)
    }

    private var lastEnteredSet: ActiveSet? {
        exercise.sets
            .sorted { $0.order < $1.order }
            .last { $0.weight != nil || $0.reps != nil || $0.distance != nil || $0.seconds != nil }
    }

    private func recommendationLine(_ rec: ExerciseRecommendation) -> String {
        let sets = rec.suggestedWorkingSets
        let reps = "\(rec.repRange.lowerBound)-\(rec.repRange.upperBound)"
        if let suggestedWeight = rec.suggestedWeight, suggestedWeight > 0 {
            return "Suggested: \(sets)x \(reps) @ \(formatWeight(suggestedWeight)) \(weightUnit)"
        }
        return "Suggested: \(sets)x \(reps)"
    }

    private func cardioRationale(_ config: ResolvedCardioMetricConfiguration) -> String {
        switch config.primary {
        case .distance:
            return "Track distance (+ time optional)."
        case .duration:
            return "Track time (+ distance optional)."
        case .count:
            return "Track \(config.countLabel) (+ time optional)."
        }
    }

    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(weight))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), weight)
    }

    private func defaultReps(_ range: ClosedRange<Int>) -> Int {
        (range.lowerBound + range.upperBound) / 2
    }
}

// MARK: - Set Row

private struct SessionSetRow: View {
    let exerciseId: UUID
    let exerciseName: String
    let set: ActiveSet
    let previousSet: ActiveSet?
    let lastSessionSet: WorkoutSet?
    let weightUnit: String
    let weightIncrement: Double
    let cardioConfig: ResolvedCardioMetricConfiguration?
    let isPersonalBest: Bool
    let personalBestThreshold: Double?

    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var weightText: String
    @State private var repsText: String
    @State private var distanceText: String
    @State private var durationText: String
    @State private var commitTask: Task<Void, Never>?
    @State private var showingDeleteSetAlert = false
    @State private var completionValidationMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case weight
        case reps
        case distance
        case duration
    }

    init(
        exerciseId: UUID,
        exerciseName: String,
        set: ActiveSet,
        previousSet: ActiveSet?,
        lastSessionSet: WorkoutSet?,
        weightUnit: String,
        weightIncrement: Double,
        cardioConfig: ResolvedCardioMetricConfiguration?,
        isPersonalBest: Bool = false,
        personalBestThreshold: Double? = nil
    ) {
        self.isPersonalBest = isPersonalBest
        self.personalBestThreshold = personalBestThreshold
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.set = set
        self.previousSet = previousSet
        self.lastSessionSet = lastSessionSet
        self.weightUnit = weightUnit
        self.weightIncrement = weightIncrement
        self.cardioConfig = cardioConfig
        _weightText = State(initialValue: set.weight.map(WorkoutValueFormatter.weightText) ?? "")
        _repsText = State(initialValue: set.reps.map { String($0) } ?? "")
        _distanceText = State(initialValue: set.distance.map(WorkoutValueFormatter.distanceText) ?? "")
        _durationText = State(initialValue: set.seconds.map(WorkoutValueFormatter.durationText) ?? "")
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Button(action: toggleCompletion) {
                    HStack(spacing: Theme.Spacing.sm) {
                        SetCompletionBadge(order: set.order, isCompleted: set.isCompleted)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Set \(set.order)")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(set.isCompleted ? "Logged" : "Tap to log")
                                .font(Theme.Typography.caption2)
                                .foregroundStyle(set.isCompleted ? Theme.Colors.success : Theme.Colors.textTertiary)
                                .contentTransition(.opacity)
                        }
                    }
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(set.isCompleted ? "Set \(set.order), completed" : "Set \(set.order), not completed")
                .accessibilityHint(set.isCompleted ? "Marks this set incomplete" : "Validates and completes this set")

                if isPersonalBest {
                    PRMarkerView(date: Date())
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                        .accessibilityLabel("New personal record")
                }

                Spacer(minLength: Theme.Spacing.sm)

                if let lastSessionSet, cardioConfig == nil, lastSessionSet.reps > 0, !set.isCompleted {
                    Button {
                        applyLastSession(lastSessionSet)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(Theme.Typography.microLabel)
                                .accessibilityHidden(true)
                            Text("\(WorkoutValueFormatter.weightText(lastSessionSet.weight)) × \(lastSessionSet.reps)")
                                .font(Theme.Typography.caption2Bold)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.Colors.border.opacity(0.35)))
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(set.isCompleted)
                    .accessibilityLabel(
                        "Last session, \(WorkoutValueFormatter.weightText(lastSessionSet.weight)) \(weightUnit) for \(lastSessionSet.reps) reps"
                    )
                    .accessibilityHint("Fills this set with last session's weight and reps")
                }

                Menu {
                    if let previousSet, cardioConfig == nil {
                        Button("Copy Previous", systemImage: "doc.on.doc") {
                            copyFromSet(previousSet)
                        }
                    }
                    Button("Delete Set", systemImage: "trash", role: .destructive) {
                        showingDeleteSetAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(Theme.Typography.subheadlineBold)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Set \(set.order) actions")
            }

            ViewThatFits(in: .horizontal) {
                metricFields(axis: .horizontal)
                metricFields(axis: .vertical)
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .strokeBorder(rowStroke, lineWidth: isPersonalBest ? 1.5 : 1)
        )
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: set.isCompleted)
        .animation(reduceMotion ? nil : Theme.Animation.bouncy, value: isPersonalBest)
        .toolbar {
            // Only the row being edited contributes keyboard items; otherwise every visible
            // set row adds its own "Done" button to the shared keyboard toolbar.
            if focusedField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.accent)
                        .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil {
                commitImmediately()
            }
        }
        .onChange(of: set) { _, updatedSet in
            guard focusedField == nil else { return }
            synchronizeText(with: updatedSet)
        }
        .onDisappear {
            commitImmediately()
            commitTask?.cancel()
        }
        .alert("Delete Set?", isPresented: $showingDeleteSetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                sessionManager.deleteSet(exerciseId: exerciseId, setId: set.id)
            }
        } message: {
            Text("This will remove set #\(set.order) from \(exerciseName).")
        }
        .alert(
            "Finish this set first",
            isPresented: Binding(
                get: { completionValidationMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        completionValidationMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(completionValidationMessage ?? "")
        }
    }

    private var rowFill: Color {
        if isPersonalBest { return Theme.Colors.gold.opacity(0.10) }
        return set.isCompleted ? Theme.Colors.success.opacity(0.08) : Theme.Colors.surfaceRaised
    }

    private var rowStroke: Color {
        if isPersonalBest { return Theme.Colors.gold.opacity(0.7) }
        return set.isCompleted ? Theme.Colors.success.opacity(0.3) : Theme.Colors.border.opacity(0.6)
    }

    private enum MetricAxis: Equatable {
        case horizontal
        case vertical
    }

    @ViewBuilder
    private func metricFields(axis: MetricAxis) -> some View {
        let spacing = Theme.Spacing.sm

        if axis == .horizontal {
            HStack(spacing: spacing) {
                metricFieldViews
            }
        } else {
            VStack(spacing: spacing) {
                metricFieldViews
            }
        }
    }

    @ViewBuilder
    private var metricFieldViews: some View {
        if let cardioConfig {
            cardioField(kind: cardioConfig.primary, countLabel: cardioConfig.countLabel)
            cardioField(kind: cardioConfig.secondary, countLabel: cardioConfig.countLabel)
        } else {
            stepperField(
                title: "Weight (\(weightUnit))",
                text: $weightText,
                keyboard: .decimalPad,
                focus: .weight,
                stepDescription: WorkoutValueFormatter.weightText(weightIncrement),
                onStep: { delta in adjustWeight(by: weightIncrement * Double(delta)) }
            )
            .onChange(of: weightText) { _, _ in scheduleCommit() }

            stepperField(
                title: "Reps",
                text: $repsText,
                keyboard: .numberPad,
                focus: .reps,
                stepDescription: "1",
                onStep: adjustReps
            )
            .onChange(of: repsText) { _, _ in scheduleCommit() }
        }
    }

    // MARK: - Stepper Field

    private func stepperField(
        title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        focus: Field,
        stepDescription: String,
        onStep: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: 0) {
                Button {
                    onStep(-1)
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "minus")
                        .font(Theme.Typography.captionBold)
                        .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityLabel("Decrease \(title) by \(stepDescription)")

                TextField(title, text: text)
                    .keyboardType(keyboard)
                    .focused($focusedField, equals: focus)
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 44, minHeight: Theme.Layout.minimumTapTarget)
                    .accessibilityLabel(title)

                Button {
                    onStep(1)
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(Theme.Typography.captionBold)
                        .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityLabel("Increase \(title) by \(stepDescription)")
            }
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                    .strokeBorder(
                        focusedField == focus ? Theme.Colors.accent : Theme.Colors.border.opacity(0.6),
                        lineWidth: focusedField == focus ? 1.5 : 1
                    )
            )
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func field(title: String, text: Binding<String>, keyboard: UIKeyboardType, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .focused($focusedField, equals: focus)
                .font(Theme.Typography.bodyBold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                        .strokeBorder(
                            focusedField == focus ? Theme.Colors.accent : Theme.Colors.border.opacity(0.6),
                            lineWidth: focusedField == focus ? 1.5 : 1
                        )
                )
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func cardioField(kind: CardioMetricKind, countLabel: String) -> some View {
        switch kind {
        case .distance:
            field(title: "Distance", text: $distanceText, keyboard: .decimalPad, focus: .distance)
                .onChange(of: distanceText) { _, _ in scheduleCommit() }
        case .duration:
            field(title: "Time", text: $durationText, keyboard: .numbersAndPunctuation, focus: .duration)
                .onChange(of: durationText) { _, _ in scheduleCommit() }
        case .count:
            field(title: countLabel, text: $repsText, keyboard: .numberPad, focus: .reps)
                .onChange(of: repsText) { _, _ in scheduleCommit() }
        }
    }

    // MARK: - Actions

    private func toggleCompletion() {
        focusedField = nil
        commitImmediately()
        let wouldSetRecord = !set.isCompleted && beatsPersonalBest()
        switch sessionManager.toggleSetComplete(exerciseId: exerciseId, setId: set.id) {
        case .toggled(let isCompleted):
            if isCompleted {
                if wouldSetRecord {
                    Haptics.notify(.success)
                } else {
                    Haptics.setComplete()
                }
            } else {
                Haptics.selection()
            }
        case .invalid(let message):
            completionValidationMessage = message
            Haptics.notify(.warning)
        case .missingSet:
            break
        }
    }

    /// Uses the field text rather than `set`, which can lag one commit behind.
    private func beatsPersonalBest() -> Bool {
        guard cardioConfig == nil,
              let threshold = personalBestThreshold,
              let weight = parseDouble(weightText),
              (parseInt(repsText) ?? 0) > 0,
              ExerciseLoad.isTrackedWeight(weight, exerciseName: exerciseName) else { return false }
        return ExerciseLoad.isBetter(weight, than: threshold, exerciseName: exerciseName)
    }

    private func adjustWeight(by amount: Double) {
        let current = parseDouble(weightText) ?? 0
        let newWeight = max(0, current + amount)
        weightText = WorkoutValueFormatter.weightText(newWeight)
        commitImmediately()
    }

    private func adjustReps(by amount: Int) {
        let current = parseInt(repsText) ?? 0
        let newReps = max(0, current + amount)
        repsText = String(newReps)
        commitImmediately()
    }

    private func applyLastSession(_ source: WorkoutSet) {
        weightText = WorkoutValueFormatter.weightText(source.weight)
        repsText = String(source.reps)
        commitImmediately()
        Haptics.selection()
    }

    private func copyFromSet(_ source: ActiveSet) {
        if let weight = source.weight {
            weightText = WorkoutValueFormatter.weightText(weight)
        }
        if let reps = source.reps {
            repsText = String(reps)
        }
        commitImmediately()
        Haptics.selection()
    }

    private func synchronizeText(with updatedSet: ActiveSet) {
        weightText = updatedSet.weight.map(WorkoutValueFormatter.weightText) ?? ""
        repsText = updatedSet.reps.map(String.init) ?? ""
        distanceText = updatedSet.distance.map(WorkoutValueFormatter.distanceText) ?? ""
        durationText = updatedSet.seconds.map(WorkoutValueFormatter.durationText) ?? ""
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            applyCommit()
        }
    }

    private func commitImmediately() {
        commitTask?.cancel()
        applyCommit()
    }

    private func applyCommit() {
        if cardioConfig != nil {
            let distance = parseDouble(distanceText)
            let seconds = WorkoutValueFormatter.parseDurationSeconds(durationText)
            let reps = parseInt(repsText)
            guard distance != set.distance || seconds != set.seconds || reps != set.reps else { return }
            sessionManager.updateSet(
                exerciseId: exerciseId,
                setId: set.id,
                prefill: SetPrefill(weight: nil, reps: reps, distance: distance, seconds: seconds)
            )
        } else {
            let weight = parseDouble(weightText)
            let reps = parseInt(repsText)
            guard weight != set.weight || reps != set.reps else { return }
            sessionManager.updateSet(
                exerciseId: exerciseId,
                setId: set.id,
                prefill: SetPrefill(weight: weight, reps: reps, distance: nil, seconds: nil)
            )
        }
    }

    private func parseDouble(_ text: String) -> Double? {
        WorkoutValueFormatter.parseDecimal(text)
    }

    private func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Int(trimmed) { return value }
        // Tolerate pasted values such as "8.0".
        guard let decimal = WorkoutValueFormatter.parseDecimal(trimmed), decimal.isFinite,
              decimal >= 0, decimal < Double(Int.max) else { return nil }
        return Int(decimal.rounded())
    }

}

// MARK: - Muscle Suggestions UI

private struct MuscleSuggestionCard: View {
    let suggestion: MuscleGroupSuggestion
    let onAddExercise: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(suggestion.group.color.opacity(0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: suggestion.group.iconName)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(suggestion.group.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.group.displayName)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Last trained \(suggestion.daysSince)d ago")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.Typography.bodyLarge)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss suggestion")
            }

            if !suggestion.options.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(suggestion.options) { option in
                            Button {
                                onAddExercise(option.name)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(option.name)
                                        .font(Theme.Typography.captionBold)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                        .lineLimit(1)
                                    Text(relativeDate(option.lastPerformed))
                                        .font(Theme.Typography.microcopy)
                                        .foregroundColor(Theme.Colors.textTertiary)
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .frame(minHeight: Theme.Layout.minimumTapTarget)
                                .background(Theme.Colors.surface.opacity(0.30))
                                .cornerRadius(Theme.CornerRadius.xlarge)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                                        .strokeBorder(Theme.Colors.border.opacity(0.7), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
