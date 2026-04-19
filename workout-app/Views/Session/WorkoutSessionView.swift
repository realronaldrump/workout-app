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
    @State private var showingRestSettings = false
    @State private var finishErrorMessage: String?
    @State private var isFinishing = false
    @State private var finishDidSave = false
    @State private var exerciseCardContexts: [String: SessionExerciseContext] = [:]
    @State private var cachedMuscleSuggestions: [MuscleGroupSuggestion] = []
    @State private var cachedCanFinishSession = false
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
                        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            headerCard(session)

                            // Rest timer
                            if sessionManager.restTimerIsActive {
                                restTimerCard
                            }

                            if !cachedMuscleSuggestions.isEmpty {
                                muscleSuggestionSection(cachedMuscleSuggestions)
                            }

                            addExerciseButton

                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                Text("Exercises")
                                    .font(Theme.Typography.sectionHeader)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .tracking(1.0)

                                if session.exercises.isEmpty {
                                    EmptyStateCard(
                                        icon: "plus.circle",
                                        tint: Theme.Colors.accent,
                                        title: "No Exercises Yet",
                                        message: "Add your first exercise to start logging sets."
                                    )
                                    .padding(.top, Theme.Spacing.sm)
                                } else {
                                    VStack(spacing: Theme.Spacing.md) {
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
                                        }
                                    }
                                }
                            }

                            Button {
                                showingFinishSheet = true
                                Haptics.selection()
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Finish Session")
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding()
                                .background(Theme.Colors.accent)
                                .cornerRadius(Theme.CornerRadius.large)
                            }
                            .buttonStyle(.plain)
                            .disabled(isFinishing || !cachedCanFinishSession)
                            .opacity((isFinishing || !cachedCanFinishSession) ? 0.7 : 1.0)

                            if !cachedCanFinishSession {
                                Text("Complete at least one valid set before finishing.")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        .padding(Theme.Spacing.xl)
                    }
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
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { selected in
                    addExerciseWithPrefill(name: selected)
                }
            }
            .sheet(isPresented: $showingFinishSheet) {
                FinishSessionSheet(
                    isFinishing: isFinishing,
                    didSave: finishDidSave,
                    summary: cachedSummary,
                    errorMessage: finishErrorMessage,
                    onFinish: { finishSession() },
                    onDismissError: { finishErrorMessage = nil }
                )
                .presentationDetents([.medium])
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
            .sheet(isPresented: $showingRestSettings) {
                restTimerSettingsSheet
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                // Keep increment options aligned with pounds-only behavior.
                let isAllowed = allowedWeightIncrements.contains { abs($0 - weightIncrement) < 0.0001 }
                if weightIncrement <= 0 || !isAllowed {
                    weightIncrement = 2.5
                }
                refreshDerivedSessionState()
            }
            .onChange(of: sessionManager.activeSession) { _, _ in
                refreshDerivedSessionState()
            }
            .onChange(of: dataManager.workouts) { _, _ in
                refreshDerivedSessionState()
            }
            .onChange(of: weightIncrement) { _, _ in
                refreshDerivedSessionState()
            }
            .onReceive(metadataManager.objectWillChange) { _ in
                refreshDerivedSessionState()
            }
            .onReceive(metricManager.objectWillChange) { _ in
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
                TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(session.startedAt))
                    Text(SharedFormatters.elapsed(elapsed))
                        .font(Theme.Typography.captionBold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.surfaceRaised)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Theme.Colors.border.opacity(0.4), lineWidth: 1)
                        )
                }
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
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Colors.background)
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
                Image(systemName: "plus.circle.fill")
                    .font(Theme.Iconography.action)
                    .foregroundStyle(Theme.Colors.accent)
                Text("Add Exercise")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rest Timer Card

    private var restTimerCard: some View {
        let remaining = sessionManager.restTimerSecondsRemaining
        let total = sessionManager.restTimerDuration
        let progress = total > 0 ? Double(remaining) / Double(total) : 0

        return HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(Theme.Colors.border, lineWidth: 3)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        remaining <= 10 ? Theme.Colors.accentSecondary : Theme.Colors.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                Text("\(remaining)")
                    .font(Theme.Typography.monoMedium)
                    .foregroundColor(remaining <= 10 ? Theme.Colors.accentSecondary : Theme.Colors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("REST")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .tracking(1.2)
                Text(restTimerFormatted(remaining))
                    .font(Theme.Typography.monoMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            Spacer()

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    sessionManager.setRestTimerDuration(sessionManager.restTimerDuration + 30)
                    sessionManager.restTimerSecondsRemaining += 30
                    Haptics.selection()
                } label: {
                    Text("+30s")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(Theme.Colors.surface.opacity(0.35))
                        .cornerRadius(Theme.CornerRadius.large)
                }
                .buttonStyle(.plain)

                Button {
                    showingRestSettings = true
                    Haptics.selection()
                } label: {
                    Image(systemName: "gear")
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.Colors.surface.opacity(0.35))
                        .cornerRadius(Theme.CornerRadius.small)
                }
                .buttonStyle(.plain)

                Button {
                    sessionManager.cancelRestTimer()
                    Haptics.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.Iconography.title3)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var restTimerSettingsSheet: some View {
        let presets = [30, 60, 90, 120, 180, 300]

        return VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Rest Timer")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Default rest between sets")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3), spacing: Theme.Spacing.sm) {
                ForEach(presets, id: \.self) { seconds in
                    Button {
                        sessionManager.setRestTimerDuration(seconds)
                        Haptics.selection()
                    } label: {
                        Text(restTimerFormatted(seconds))
                            .font(Theme.Typography.headline)
                            .foregroundColor(
                                sessionManager.restTimerDuration == seconds
                                    ? .white
                                    : Theme.Colors.textPrimary
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                    .fill(
                                        sessionManager.restTimerDuration == seconds
                                            ? Theme.Colors.accent
                                            : Theme.Colors.surface.opacity(0.35)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                    .strokeBorder(
                                        sessionManager.restTimerDuration == seconds
                                            ? Theme.Colors.accent
                                            : Theme.Colors.border.opacity(0.4),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.Colors.background)
    }

    private func restTimerFormatted(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return remainingSeconds > 0
            ? "\(minutes):\(String(format: "%02d", remainingSeconds))"
            : "\(minutes):00"
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
        TimelineView(.periodic(from: Date(), by: 1.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(session.startedAt))
            let elapsedLabel = SharedFormatters.elapsed(elapsed)

            return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.name)
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(2)

	                        Text(elapsedLabel)
	                            .font(Theme.Typography.caption)
	                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    Button {
                        showingFinishSheet = true
                        Haptics.selection()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Theme.Iconography.action)
                            .foregroundStyle(Theme.Colors.success)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFinishing || !cachedCanFinishSession)
                    .opacity((isFinishing || !cachedCanFinishSession) ? 0.55 : 1.0)
                    .accessibilityLabel("Finish session")
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Theme.Colors.accent)
                    Text(gymLabel(for: session.gymProfileId))
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Spacer()
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
        }
    }

    private func muscleSuggestionSection(_ suggestions: [MuscleGroupSuggestion]) -> some View {
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Suggestions")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .tracking(1.0)

                Spacer()

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
                let logged = try await sessionManager.finish()
                await logStore.upsert(logged)
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
                            print("Health sync failed for logged workout \(logged.id): \(error)")
                        }
                    }
                }

                Haptics.workoutFinished()
                finishDidSave = true
                // Brief delay so the success overlay is visible before sheet dismisses
                try? await Task.sleep(nanoseconds: 900_000_000)
                showingFinishSheet = false
                finishDidSave = false
            } catch {
                finishErrorMessage = error.localizedDescription
                AppAnalytics.shared.track(
                    AnalyticsSignal.sessionFinishFailed,
                    payload: ["Session.errorDomain": String(describing: type(of: error))]
                )
            }
        }
    }

    private func gymLabel(for gymId: UUID?) -> String {
        if let name = gymProfilesManager.gymName(for: gymId) {
            return name
        }
        return gymId == nil ? "Unassigned" : "Deleted gym"
    }

    private func refreshDerivedSessionState() {
        guard let session = sessionManager.activeSession else {
            exerciseCardContexts = [:]
            cachedMuscleSuggestions = []
            cachedCanFinishSession = false
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

        let allExerciseNames = Set(dataManager.allExerciseNames())
        let tagMappings = metadataManager.resolvedMappings(for: allExerciseNames)
        let groupMappings: [String: [MuscleGroup]] = tagMappings.mapValues { tags in
            tags.compactMap(\.builtInGroup)
        }

        var contexts: [String: SessionExerciseContext] = [:]
        contexts.reserveCapacity(session.exercises.count)

        var completedSetCount = 0
        var strengthVolume = 0.0
        var cardioDistance = 0.0
        var cardioSeconds = 0.0
        var cardioCount = 0
        var canFinish = true

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

        exerciseCardContexts = contexts
        cachedMuscleSuggestions = buildMuscleSuggestions(for: session, groupMappings: groupMappings)
        cachedCanFinishSession = canFinish && completedSetCount > 0
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
        groupMappings: [String: [MuscleGroup]]
    ) -> [MuscleGroupSuggestion] {
        guard !dataManager.workouts.isEmpty else { return [] }

        var covered = Set<MuscleGroup>()
        for exercise in session.exercises {
            for group in groupMappings[exercise.name] ?? [] {
                covered.insert(group)
            }
        }

        let dismissed = Set(session.dismissedMuscleGroupSuggestions.compactMap(MuscleGroup.init(rawValue:)))
        return MuscleRecencySuggestionEngine.suggestions(
            workouts: dataManager.workouts,
            muscleGroupsByExerciseName: groupMappings,
            excluding: covered.union(dismissed)
        )
    }

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

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(Theme.Typography.condensed)
                        .tracking(-0.2)
                        .foregroundColor(Theme.Colors.textPrimary)

                    if let rec {
                        Text(recommendationLine(rec))
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textSecondary)
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
                                ForEach(Array(rec.warmup.enumerated()), id: \.offset) { _, item in
                                    Text("\(formatWeight(item.weight)) × \(item.reps)")
                                        .font(Theme.Typography.microcopy)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                        .padding(.horizontal, Theme.Spacing.sm)
                                        .padding(.vertical, 6)
                                        .background(Theme.Colors.surface.opacity(0.35))
                                        .cornerRadius(Theme.CornerRadius.large)
                                }
                            }
                        }
                    }

                    if let rec {
                        Text(rec.rationale)
                            .font(Theme.Typography.microcopy)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .lineLimit(2)
                    } else if let cardioConfig {
                        Text(cardioRationale(cardioConfig))
                            .font(Theme.Typography.microcopy)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Menu {
                    Button("History") {
                        showingHistory = true
                    }
                    Button("Remove Exercise", role: .destructive) {
                        showingRemoveExerciseAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(Theme.Iconography.title3)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    SessionSetRow(
                        exerciseId: exercise.id,
                        exerciseName: exercise.name,
                        set: set,
                        previousSet: index > 0 ? exercise.sets[index - 1] : nil,
                        weightUnit: weightUnit,
                        weightIncrement: weightIncrement,
                        cardioConfig: cardioConfig
                    )
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    if let rec {
                        sessionManager.addSet(exerciseId: exercise.id, prefill: SetPrefill(weight: rec.suggestedWeight, reps: defaultReps(rec.repRange)))
                    } else {
                        sessionManager.addSet(exerciseId: exercise.id)
                    }
                    Haptics.added()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(Theme.Typography.captionBold)
                        Text("Add Set")
                            .font(Theme.Typography.subheadline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .brutalistButtonChrome(
                        fill: Theme.Colors.accentSecondary,
                        cornerRadius: Theme.CornerRadius.large
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
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
    let weightUnit: String
    let weightIncrement: Double
    let cardioConfig: ResolvedCardioMetricConfiguration?

    @EnvironmentObject private var sessionManager: WorkoutSessionManager

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
        weightUnit: String,
        weightIncrement: Double,
        cardioConfig: ResolvedCardioMetricConfiguration?
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.set = set
        self.previousSet = previousSet
        self.weightUnit = weightUnit
        self.weightIncrement = weightIncrement
        self.cardioConfig = cardioConfig
        _weightText = State(initialValue: set.weight.map(WorkoutValueFormatter.weightText) ?? "")
        _repsText = State(initialValue: set.reps.map { String($0) } ?? "")
        _distanceText = State(initialValue: set.distance.map(WorkoutValueFormatter.distanceText) ?? "")
        _durationText = State(initialValue: set.seconds.map(WorkoutValueFormatter.durationText) ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                // Completion toggle
                Button {
                    commitImmediately()
                    switch sessionManager.toggleSetComplete(exerciseId: exerciseId, setId: set.id) {
                    case .toggled(let isCompleted):
                        if isCompleted {
                            Haptics.setComplete()
                        } else {
                            Haptics.selection()
                        }
                    case .invalid(let message):
                        completionValidationMessage = message
                        Haptics.notify(.warning)
                    case .missingSet:
                        break
                    }
                } label: {
                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(Theme.Typography.title4)
                        .foregroundStyle(set.isCompleted ? Theme.Colors.success : Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)

                Text("#\(set.order)")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 28, alignment: .leading)

                if let cardioConfig {
                    cardioField(kind: cardioConfig.primary, countLabel: cardioConfig.countLabel)
                    cardioField(kind: cardioConfig.secondary, countLabel: cardioConfig.countLabel)
                } else {
                    // Weight field with steppers
                    stepperField(
                        title: weightUnit,
                        text: $weightText,
                        keyboard: .decimalPad,
                        focus: .weight,
                        onStep: { delta in adjustWeight(by: weightIncrement * Double(delta)) }
                    )
                    .onChange(of: weightText) { _, _ in scheduleCommit() }

                    // Reps field with steppers
                    stepperField(
                        title: "reps",
                        text: $repsText,
                        keyboard: .numberPad,
                        focus: .reps,
                        onStep: adjustReps
                    )
                    .onChange(of: repsText) { _, _ in scheduleCommit() }
                }

                // Actions menu
                Menu {
                    if let prev = previousSet, !set.isCompleted, cardioConfig == nil {
                        Button {
                            copyFromSet(prev)
                        } label: {
                            Label("Copy Previous", systemImage: "doc.on.doc")
                        }
                    }
                    Button("Delete Set", role: .destructive) {
                        showingDeleteSetAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(Theme.Typography.subheadlineBold)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Theme.Colors.surface.opacity(0.35))
                        .cornerRadius(Theme.CornerRadius.small)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.surface.opacity(set.isCompleted ? 0.28 : 0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.border.opacity(0.7), lineWidth: 1)
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)
                .buttonStyle(.plain)
            }
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil {
                commitImmediately()
            }
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

    // MARK: - Stepper Field

    private func stepperField(
        title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        focus: Field,
        onStep: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Button {
                onStep(-1)
                Haptics.impact(.light)
            } label: {
                Image(systemName: "minus")
                    .font(Theme.Typography.microLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .center, spacing: 1) {
                Text(title)
                    .font(Theme.Typography.microcopy)
                    .foregroundColor(Theme.Colors.textTertiary)
                TextField(title, text: text)
                    .keyboardType(keyboard)
                    .focused($focusedField, equals: focus)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 40)
            }

            Button {
                onStep(1)
                Haptics.impact(.light)
            } label: {
                Image(systemName: "plus")
                    .font(Theme.Typography.microLabel)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func field(title: String, text: Binding<String>, keyboard: UIKeyboardType, focus: Field, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.microcopy)
                .foregroundColor(Theme.Colors.textTertiary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .focused($focusedField, equals: focus)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(width: width)
    }

    @ViewBuilder
    private func cardioField(kind: CardioMetricKind, countLabel: String) -> some View {
        switch kind {
        case .distance:
            field(title: "dist", text: $distanceText, keyboard: .decimalPad, focus: .distance, width: 84)
                .onChange(of: distanceText) { _, _ in scheduleCommit() }
        case .duration:
            field(title: "time", text: $durationText, keyboard: .numbersAndPunctuation, focus: .duration, width: 92)
                .onChange(of: durationText) { _, _ in scheduleCommit() }
        case .count:
            field(title: countLabel, text: $repsText, keyboard: .numberPad, focus: .reps, width: 72)
                .onChange(of: repsText) { _, _ in scheduleCommit() }
        }
    }

    // MARK: - Actions

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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
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
                                .padding(.vertical, 10)
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
