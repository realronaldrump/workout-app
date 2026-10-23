import Combine
import SwiftUI

// swiftlint:disable file_length
struct WorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

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
    @AppStorage("sessionsPerWeekGoal") private var sessionsPerWeekGoal: Int = 4
    @AppStorage("keepScreenAwakeDuringWorkout") private var keepScreenAwake = true
    @State private var previousIdleTimerDisabled = false

    @State private var showingExercisePicker = false
    @State private var requestedExerciseID: UUID?
    @State private var didOfferExercisePicker = false
    @State private var showingSuggestions = false
    @State private var finishedWorkout: LoggedWorkout?
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
    @State private var finishSheetDetent: PresentationDetent = .medium
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

    private var isFinishingSession: Bool {
        isFinishing || sessionManager.isFinishing
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                if let session = sessionManager.activeSession {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                                headerCard(session)
                                if session.exercises.count > 1 { exerciseNavigator(session) }

                                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                    if !session.exercises.isEmpty {
                                        SectionHeading(
                                            title: "Exercises",
                                            subtitle: exercisesSubtitle(session)
                                        )
                                    }

                                    if session.exercises.isEmpty {
                                        EmptyStateCard(
                                            title: "Load the first exercise",
                                            message: "Add an exercise and its sets come in from last time, ready to check off."
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
                                                .id(exercise.id)
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
                                    DisclosureGroup("Ideas for the next exercise", isExpanded: $showingSuggestions) {
                                        muscleSuggestionSection(cachedMuscleSuggestions)
                                            .padding(.top, Theme.Spacing.md)
                                    }
                                    .font(Theme.Typography.headline)
                                    .tint(Theme.Colors.textPrimary)
                                }
                            }
                            .padding(.horizontal, Theme.Layout.screenGutter)
                            .padding(.top, Theme.Spacing.md)
                            .padding(.bottom, Theme.Spacing.xl)
                            .contentColumn()
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: requestedExerciseID) { _, id in
                            guard let id else { return }
                            withAnimation(reduceMotion ? nil : Theme.Animation.smooth) {
                                proxy.scrollTo(id, anchor: .top)
                            }
                            requestedExerciseID = nil
                        }
                    }
                } else {
                    EmptyStateCard(
                        title: "No workout running",
                        message: "Start a workout from Today to begin logging."
                    )
                    .padding(.horizontal, Theme.Layout.screenGutter)
                }
            }
            .disabled(isFinishingSession)
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
                        .padding(.horizontal, Theme.Layout.screenGutter)

                        finishBar
                    }
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(
                    alreadyAdded: Set(sessionManager.activeSession?.exercises.map(\.name) ?? []),
                    allowsMultipleSelection: true
                ) { selected in
                    addExerciseWithPrefill(name: selected)
                }
            }
            .sheet(isPresented: $showingFinishSheet) {
                FinishSessionSheet(
                    isFinishing: isFinishingSession,
                    didSave: finishDidSave,
                    summary: finishedSummary ?? cachedSummary,
                    errorMessage: finishErrorMessage,
                    onFinish: { finishSession() },
                    onDismissError: { finishErrorMessage = nil },
                    onDone: { completeFinishedSessionPresentation() },
                    savedWorkout: finishedWorkout,
                    gymName: gymProfilesManager.gymName(for: finishedWorkout?.gymProfileId),
                    weekPlates: finishWeekPlates,
                    weeklyGoal: min(max(sessionsPerWeekGoal, 1), 14)
                )
                .presentationDetents([.medium, .large], selection: $finishSheetDetent)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(isFinishingSession || finishDidSave)
                .onChange(of: finishDidSave) { _, saved in
                    // The saved moment needs the whole sheet: the bar, the numbers, Done.
                    if saved { finishSheetDetent = .large }
                }
                .onAppear { finishSheetDetent = .medium }
            }
            .alert("Discard session?", isPresented: $showingDiscardAlert) {
                Button("Keep", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    Task { @MainActor in
                        guard await sessionManager.discardDraft() else { return }
                        Haptics.notify(.warning)
                        dismiss()
                    }
                }
            } message: {
                Text("This will permanently delete your in-progress session and all sets.")
            }
            .alert("Leave unchecked sets out?", isPresented: $showingUncheckedSetAlert) {
                Button("Keep logging", role: .cancel) {}
                Button("Save \(cachedSummary.completedSetCount) completed sets") {
                    showingFinishSheet = true
                    Haptics.selection()
                }
            } message: {
                Text(uncheckedSetAlertMessage)
            }
            .alert("Rename workout", isPresented: $showingRenameAlert) {
                TextField("Workout name", text: $renameText)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    sessionManager.updateSessionName(renameText)
                }
            }
            .sheet(isPresented: $showingGymPicker) {
                GymSelectionSheet(
                    title: "Choose gym",
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
                    },
                    onAutomaticStartChanged: { sessionManager.setRestTimerAutomaticStartEnabled($0) },
                    onStartRest: { sessionManager.startRestTimer() }
                )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
                updateScreenAwake()
                sessionManager.restTimer.syncDurationFromDefaults()
                // Keep increment options aligned with pounds-only behavior.
                let isAllowed = allowedWeightIncrements.contains { abs($0 - weightIncrement) < 0.0001 }
                if weightIncrement <= 0 || !isAllowed {
                    weightIncrement = 2.5
                }
                refreshDerivedSessionState()
                if sessionManager.activeSession?.exercises.isEmpty == true && !didOfferExercisePicker {
                    didOfferExercisePicker = true
                    showingExercisePicker = true
                }
            }
            .onDisappear {
                sessionManager.saveImmediately()
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            }
            .onChange(of: keepScreenAwake) { _, _ in updateScreenAwake() }
            .onChange(of: scenePhase) { _, _ in updateScreenAwake() }
            .onChange(of: sessionManager.activeSession) { oldSession, newSession in
                let oldExercises = oldSession?.exercises.map { "\($0.id.uuidString):\($0.name)" } ?? []
                let newExercises = newSession?.exercises.map { "\($0.id.uuidString):\($0.name)" } ?? []
                let oldCounts = oldSession?.exercises.map { $0.sets.count } ?? []
                let newCounts = newSession?.exercises.map { $0.sets.count } ?? []
                let suggestionsChanged = oldSession?.dismissedMuscleGroupSuggestions != newSession?.dismissedMuscleGroupSuggestions
                refreshDerivedSessionState(rebuildContexts: oldExercises != newExercises || oldCounts != newCounts || suggestionsChanged)
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
        .interactiveDismissDisabled(isFinishingSession)
    }

}

private extension WorkoutSessionView {
    var sessionTopBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                endEditing()
                sessionManager.saveImmediately()
                sessionManager.isPresentingSessionUI = false
                dismiss()
                Haptics.selection()
            } label: {
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.bodyStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(Theme.Colors.rule, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Minimize session")

            Spacer(minLength: Theme.Spacing.sm)

            if let session = sessionManager.activeSession {
                HStack(spacing: Theme.Spacing.xs) {
                    LivePulseDot(color: Theme.Colors.success, size: 7)
                        .frame(width: 14, height: 14)
                    Text(session.startedAt, style: .timer)
                        .font(Theme.Typography.title4Bold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .frame(minHeight: Theme.Layout.minimumTapTarget)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Elapsed time")
                .accessibilityValue(Text(session.startedAt, style: .timer))
            }

            Spacer(minLength: Theme.Spacing.sm)

            Menu {
                Button("Add exercises", systemImage: "plus") { showingExercisePicker = true }
                Button("Rest timer settings", systemImage: "timer") { showingRestSettings = true }
                Toggle("Keep screen awake", systemImage: "sun.max", isOn: $keepScreenAwake)
                Button("Rename workout", systemImage: "pencil") {
                    renameText = sessionManager.activeSession?.name ?? ""
                    showingRenameAlert = true
                }
                Divider()
                Button("Discard workout", systemImage: "trash", role: .destructive) {
                    showingDiscardAlert = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(Theme.Colors.rule, lineWidth: 1.5))
            }
            .accessibilityLabel("Workout actions")
            .disabled(sessionManager.activeSession == nil || isFinishingSession)
        }
        .disabled(isFinishingSession)
        .contentColumn()
        .padding(.horizontal, Theme.Layout.screenGutter)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Colors.ground)
    }

    private var finishBar: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(SharedFormatters.count(cachedSummary.completedSetCount, "set") + " logged")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let next = nextExercise {
                    Button {
                        endEditing()
                        requestedExerciseID = next.id
                        Haptics.selection()
                    } label: {
                        Text("Next up: \(next.name)")
                            .font(Theme.Typography.subheadline)
                            .underline(color: Theme.Colors.rule)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(minHeight: Theme.Layout.minimumTapTarget, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Jumps to the next unchecked set's exercise")
                } else {
                    Text(cachedSummary.completedSetCount > 0 ? "Every set is checked off" : "Check off a set to log it")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                presentFinishFlow()
                Haptics.selection()
            } label: {
                Text(isFinishingSession ? "Saving…" : "Finish")
                    .font(Theme.Typography.title4Bold)
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                    .frame(minHeight: 52)
            }
            .buttonStyle(BrandPrimaryButtonStyle())
            .disabled(isFinishingSession || !cachedCanFinishSession)
            .accessibilityLabel("Finish and review workout")
        }
        .contentColumn(maxWidth: 640, alignment: .center)
        .padding(.horizontal, Theme.Layout.screenGutter)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.ground)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Colors.rule).frame(height: 1)
        }
    }

    /// This week's sessions as plates, with the just-saved workout last.
    private var finishWeekPlates: [LoadedPlate] {
        guard let finishedWorkout else { return [] }
        let weekStart = SharedFormatters.startOfWeekSunday(for: Date())
        var workouts = dataManager.workouts.filter { $0.date >= weekStart && $0.id != finishedWorkout.id }
        workouts.append(finishedWorkout.analyticsWorkout)
        let names = Set(workouts.flatMap { $0.exercises.map(\.name) })
        let assignments = metadataManager.resolvedAssignmentMappings(for: names)
        return workouts
            .sorted { $0.date < $1.date }
            .map { LoadedPlate(id: $0.id, date: $0.date, category: PlateCategory.classify($0, assignments: assignments)) }
    }

    private var nextExercise: ActiveExercise? {
        sessionManager.activeSession?.exercises.first { $0.sets.contains { !$0.isCompleted } }
    }

    private func exerciseNavigator(_ session: ActiveWorkoutSession) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                    let done = !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isCompleted)
                    Button {
                        endEditing()
                        requestedExerciseID = exercise.id
                        Haptics.selection()
                    } label: {
                        HStack(spacing: 6) {
                            Text(done ? "✓" : "\(index + 1)")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(done ? Theme.Colors.success : Theme.Colors.textSecondary)
                            Text(exercise.name)
                                .font(Theme.Typography.subheadlineStrong)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .frame(minHeight: 40)
                        .overlay(Capsule().strokeBorder(done ? Theme.Colors.success : Theme.Colors.rule, lineWidth: 1.5))
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to \(exercise.name)\(done ? ", all sets complete" : "")")
                }
            }
        }
    }

    private func updateScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && keepScreenAwake
    }

    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "plus")
                    .font(Theme.Typography.headline)
                    .accessibilityHidden(true)
                Text("Add exercise")
                    .font(Theme.Typography.title4Bold)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.primaryControlHeight)
        }
        .buttonStyle(BrandSecondaryButtonStyle())
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
        let latest = dataManager.getExerciseHistory(for: name).max { $0.date < $1.date }
        let firstSet = latest?.sets.min { $0.setOrder < $1.setOrder }
        let prefill = firstSet.map {
            SetPrefill(weight: $0.weight, reps: $0.reps > 0 ? $0.reps : nil,
                       distance: $0.distance > 0 ? $0.distance : nil,
                       seconds: $0.seconds > 0 ? $0.seconds : nil)
        }
        sessionManager.addExercise(name: name, initialSetPrefill: prefill)
        Haptics.added()
    }

    private func headerCard(_ session: ActiveWorkoutSession) -> some View {
        let totalSets = session.exercises.reduce(0) { $0 + $1.sets.count }
        let doneSets = session.exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.isCompleted).count
        }
        let fraction = totalSets > 0 ? Double(doneSets) / Double(totalSets) : 0

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    renameText = session.name
                    showingRenameAlert = true
                    Haptics.selection()
                } label: {
                    Text(session.name)
                        .font(Theme.Typography.displayHero)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.7)
                        .frame(minHeight: Theme.Layout.minimumTapTarget, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Workout name, \(session.name)")
                .accessibilityHint("Renames this workout")

                Button {
                    showingGymPicker = true
                    Haptics.selection()
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(session.gymProfileId == nil ? "Choose a gym" : gymLabel(for: session.gymProfileId))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(Theme.Typography.microLabel)
                            .accessibilityHidden(true)
                    }
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gym, \(gymLabel(for: session.gymProfileId))")
                .accessibilityHint("Changes the gym for this workout")
            }

            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
                : AnyLayout(StatColumns())) {
                sessionStat(
                    title: totalSets > 0 ? "of \(SharedFormatters.count(totalSets, "set"))" : "sets",
                    value: "\(doneSets)",
                    numeric: Double(doneSets)
                )
                sessionStat(
                    title: "lbs lifted",
                    value: cachedSummary.strengthVolume > 0
                        ? SharedFormatters.volumeCompact(cachedSummary.strengthVolume)
                        : "0",
                    numeric: cachedSummary.strengthVolume
                )
                sessionStat(
                    title: session.exercises.count == 1 ? "exercise" : "exercises",
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

            SessionSaveStatusView(sessionManager: sessionManager)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sessionStat(title: String, value: String, numeric: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(Theme.Typography.number)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                .contentTransition(.numericText(value: numeric))
                .animation(reduceMotion ? nil : Theme.Animation.spring, value: numeric)
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func muscleSuggestionSection(_ suggestions: [MuscleGroupSuggestion]) -> some View {
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                SectionHeading(title: "Due for work", help: "Based on time since each muscle group was last trained.")

                Button("Dismiss all") {
                    for suggestion in suggestions {
                        sessionManager.dismissMuscleGroupSuggestion(suggestion.group)
                    }
                    Haptics.selection()
                }
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .buttonStyle(.plain)
                .frame(minHeight: Theme.Layout.minimumTapTarget)
            }

            VStack(spacing: 0) {
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
        guard !isFinishingSession else { return }
        isFinishing = true
        finishErrorMessage = nil

        Task { @MainActor in
            defer { isFinishing = false }

            do {
                let summary = cachedSummary
                let logged = try await sessionManager.finish { workout in
                    do {
                        try await logStore.save(workout)
                    } catch {
                        throw WorkoutFinishSaveError(underlying: error)
                    }
                }
                finishedWorkout = logged
                finishedSummary = FinishSessionSummary(
                    startedAt: logged.startedAt,
                    exerciseCount: logged.exercises.count,
                    completedSetCount: logged.exercises.reduce(0) { $0 + $1.sets.count },
                    strengthVolume: summary.strengthVolume,
                    cardioDistance: summary.cardioDistance,
                    cardioSeconds: summary.cardioSeconds,
                    cardioCount: summary.cardioCount,
                    endedAt: logged.endedAt
                )
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
                await dataManager.setLoggedWorkoutsOffMain(logStore.workouts)
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
        finishedWorkout = nil
        sessionManager.isPresentingSessionUI = false
        dismiss()
    }

    private func presentFinishFlow() {
        endEditing()
        sessionManager.saveImmediately()
        refreshDerivedSessionState(rebuildContexts: false)
        let uncheckedSetCount = cachedUncheckedSetCount
        if uncheckedSetCount > 0 {
            pendingUncheckedSetCount = uncheckedSetCount
            showingUncheckedSetAlert = true
            return
        }

        showingFinishSheet = true
    }

    private var uncheckedSetAlertMessage: String {
        "\(SharedFormatters.count(pendingUncheckedSetCount, "unchecked set")) will be left out, including values entered or copied from history. "
            + "Keep logging to complete them, or save only the sets you checked."
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
        var cardioCount = 0.0
        var uncheckedSetCount = 0
        var canFinish = true

        for exercise in session.exercises {
            let isCardio = contexts[exercise.name]?.isCardio
                ?? metadataManager.resolvedTags(for: exercise.name).contains(where: { $0.builtInGroup == .cardio })

            uncheckedSetCount += exercise.sets.filter { !$0.isCompleted }.count

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
                    cardioCount += Double(reps)
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
        cachedCanFinishSession = canFinish && completedSetCount > 0
        cachedSummary = FinishSessionSummary(
            startedAt: session.startedAt,
            exerciseCount: session.exercises.filter { $0.sets.contains(where: \.isCompleted) }.count,
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onExtendThirtySeconds: () -> Void
    let onShowSettings: () -> Void
    let onCancel: () -> Void

    private var isEnding: Bool {
        timer.secondsRemaining <= 10
    }

    /// The bar turns to the red plate for the last ten seconds.
    private var barTint: Color {
        isEnding ? Theme.Colors.plateRed : Theme.Colors.onAccent
    }

    private var progress: Double {
        guard timer.currentTotal > 0 else { return 0 }
        return min(1, Double(timer.secondsRemaining) / Double(timer.currentTotal))
    }

    var body: some View {
        ZStack {
            if timer.isActive {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        dock(compact: true, stacked: true)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            dock(compact: false)
                            dock(compact: true)
                            dock(compact: true, stacked: true)
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: timer.isActive)
    }

    /// An inverted ink panel, like an interval clock on the gym wall.
    private func dock(compact: Bool, stacked: Bool = false) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: compact ? Theme.Spacing.sm : Theme.Spacing.md))
        return VStack(spacing: Theme.Spacing.sm) {
            layout {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    if !compact {
                        Text(isEnding ? "Almost up" : "Rest")
                            .font(Theme.Typography.subheadlineStrong)
                            .foregroundStyle(Theme.Colors.onAccent.opacity(0.7))
                    }
                    Text(restTimerFormatted(timer.secondsRemaining))
                        .font(Theme.Typography.timer)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.onAccent)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .snappy, value: timer.secondsRemaining)
                }
                .fixedSize()

                if !stacked { Spacer(minLength: 0) }

                HStack(spacing: Theme.Spacing.xs) {
                    Button(action: onExtendThirtySeconds) {
                        Text("+30s")
                            .font(Theme.Typography.subheadlineBold)
                            .foregroundStyle(Theme.Colors.onAccent)
                            .padding(.horizontal, Theme.Spacing.md)
                            .frame(minHeight: 36)
                            .overlay(Capsule().strokeBorder(Theme.Colors.onAccent.opacity(0.4), lineWidth: 1.5))
                            .frame(minHeight: Theme.Layout.minimumTapTarget)
                            .contentShape(.rect)
                    }
                    .buttonStyle(AppInteractionButtonStyle())
                    .accessibilityLabel("Add 30 seconds")

                    Button(action: onShowSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(Theme.Typography.subheadlineBold)
                            .foregroundStyle(Theme.Colors.onAccent.opacity(0.7))
                            .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
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
                        .foregroundStyle(Theme.Colors.onAccent)
                        .padding(.horizontal, compact ? 0 : Theme.Spacing.xs)
                        .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(AppInteractionButtonStyle())
                    .accessibilityLabel("Skip rest")
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Colors.onAccent.opacity(0.18))
                    Rectangle()
                        .fill(barTint)
                        .frame(width: proxy.size.width * CGFloat(progress))
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: timer.secondsRemaining)
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
        .padding(.leading, Theme.Spacing.lg)
        .padding(.trailing, Theme.Spacing.sm)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .fill(Theme.Colors.ink)
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
                Rectangle()
                    .fill(Theme.Colors.panelStrong)
                Rectangle()
                    .fill(clamped >= 1 ? Theme.Colors.success : Theme.Colors.ink)
                    .frame(width: clamped > 0 ? max(proxy.size.width * CGFloat(clamped), 4) : 0)
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: clamped)
    }
}

private struct RestTimerSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var timer: RestTimerState
    let onSelectDuration: (Int) -> Void
    let onAutomaticStartChanged: (Bool) -> Void
    let onStartRest: () -> Void

    private let presets = [30, 45, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                HStack {
                    Text("Rest timer")
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    AppHelpButton(title: "Rest timer", message: "Allow notifications to receive the timer alert while your phone is locked.")
                    Spacer()
                    AppToolbarIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "Close rest timer settings",
                        variant: .subtle
                    ) {
                        dismiss()
                    }
                }

                Toggle(isOn: Binding(
                    get: { timer.automaticStartEnabled },
                    set: onAutomaticStartChanged
                )) {
                    Text("Start after logging a strength set")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .tint(Theme.Colors.success)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.sm)],
                    spacing: Theme.Spacing.sm
                ) {
                    ForEach(presets, id: \.self) { seconds in
                        let isSelected = timer.duration == seconds
                        Button {
                            onSelectDuration(seconds)
                        } label: {
                            Text(restTimerFormatted(seconds))
                                .font(Theme.Typography.title4Bold)
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(isSelected ? Theme.Colors.accent : Color.clear)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.rule, lineWidth: 1.5)
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(AppInteractionButtonStyle())
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                AppPrimaryButton(title: "Start rest now") {
                    onStartRest()
                    dismiss()
                }
            }
            .padding(Theme.Spacing.xl)
        }
        .background(Theme.Colors.ground)
    }
}

private func restTimerFormatted(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return remainingSeconds > 0
        ? "\(minutes):\(String(format: "%02d", remainingSeconds))"
        : "\(minutes):00"
}

// MARK: - Muscle Suggestions UI

private struct MuscleSuggestionCard: View {
    let suggestion: MuscleGroupSuggestion
    let onAddExercise: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                PlateMark(category: PlateCategory.region(for: suggestion.group), height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.group.displayName)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Last trained \(suggestion.daysSince) day\(suggestion.daysSince == 1 ? "" : "s") ago")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(Theme.Typography.captionBold)
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
                                    Image(systemName: "plus")
                                        .font(Theme.Typography.microLabel)
                                        .accessibilityHidden(true)
                                    Text(option.name)
                                        .font(Theme.Typography.subheadlineStrong)
                                        .lineLimit(1)
                                    Text(relativeDate(option.lastPerformed))
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                .foregroundColor(Theme.Colors.textPrimary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .frame(minHeight: 40)
                                .overlay(Capsule(style: .continuous).strokeBorder(Theme.Colors.rule, lineWidth: 1.5))
                                .frame(minHeight: Theme.Layout.minimumTapTarget)
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .ledgerRow()
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
