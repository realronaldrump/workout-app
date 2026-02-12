import SwiftUI

struct WorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var logStore: WorkoutLogStore
    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager

    private let weightUnit = "lbs"
    @AppStorage("weightIncrement") private var weightIncrement: Double = 2.5

    @State private var showingExercisePicker = false
    @State private var showingFinishSheet = false
    @State private var showingDiscardAlert = false
    @State private var finishErrorMessage: String?
    @State private var isFinishing = false

    private let allowedWeightIncrements: [Double] = [1.25, 2.5, 5.0]

    private func sessionDateTimeToolbarText(for date: Date) -> String {
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
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                if let session = sessionManager.activeSession {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            headerCard(session)

                            if !muscleGroupSuggestions(for: session).isEmpty {
                                muscleSuggestionSection(session)
                            }

                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                Text("Exercises")
                                    .font(Theme.Typography.sectionHeader)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .tracking(1.0)

	                                VStack(spacing: Theme.Spacing.md) {
	                                    ForEach(session.exercises) { exercise in
	                                        SessionExerciseCard(
	                                            sessionId: session.id,
	                                            exercise: exercise,
	                                            weightUnit: weightUnit,
	                                            weightIncrement: resolvedWeightIncrement
	                                        )
	                                    }
	                                }
                            }

                            Button {
                                showingExercisePicker = true
                                Haptics.selection()
                            } label: {
                                HStack(spacing: Theme.Spacing.md) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Theme.Colors.accent)
                                    Text("Add Exercise")
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                                .padding(Theme.Spacing.lg)
                                .softCard(elevation: 1)
                            }
                            .buttonStyle(.plain)

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
                            .disabled(isFinishing || !canFinishSession)
                            .opacity((isFinishing || !canFinishSession) ? 0.7 : 1.0)

                            if !canFinishSession {
                                Text("Complete at least one valid set before finishing.")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        .padding(Theme.Spacing.xl)
                    }
                } else {
                    ContentUnavailableView(
                        "No active session",
                        systemImage: "bolt.slash",
                        description: Text("Start a session from Home to begin logging.")
                    )
                    .padding(.horizontal, Theme.Spacing.xl)
                }
            }
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        sessionManager.isPresentingSessionUI = false
                        dismiss()
                        Haptics.selection()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .fill(Theme.Colors.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .strokeBorder(Theme.Colors.border, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Minimize session")
                }
                if let session = sessionManager.activeSession {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Text(sessionDateTimeToolbarText(for: session.startedAt))
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .fill(Theme.Colors.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .strokeBorder(Theme.Colors.border, lineWidth: 2)
                            )
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showingDiscardAlert = true
                        Haptics.selection()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.error)
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .fill(Theme.Colors.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .strokeBorder(Theme.Colors.border, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(sessionManager.activeSession == nil || isFinishing)
                    .accessibilityLabel("Discard session")
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { selected in
                    sessionManager.addExercise(name: selected)
                }
            }
            .sheet(isPresented: $showingFinishSheet) {
                FinishSessionSheet(
                    isFinishing: isFinishing,
                    summary: currentSummary,
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
            .onAppear {
                // Keep increment options aligned with pounds-only behavior.
                let isAllowed = allowedWeightIncrements.contains { abs($0 - weightIncrement) < 0.0001 }
                if weightIncrement <= 0 || !isAllowed {
                    weightIncrement = 2.5
                }
            }
        }
    }

    private var resolvedWeightIncrement: Double {
        let inc = weightIncrement
        let isAllowed = allowedWeightIncrements.contains { abs($0 - inc) < 0.0001 }
        return (inc > 0 && isAllowed) ? inc : 2.5
    }

    private var canFinishSession: Bool {
        guard let session = sessionManager.activeSession else { return false }

        var completedSetCount = 0
        for exercise in session.exercises {
            let isCardio = ExerciseMetadataManager.shared
                .resolvedTags(for: exercise.name)
                .contains(where: { $0.builtInGroup == .cardio })

            for set in exercise.sets where set.isCompleted {
                if isCardio {
                    let reps = max(set.reps ?? 0, 0)
                    let distance = max(set.distance ?? 0, 0)
                    let seconds = max(set.seconds ?? 0, 0)
                    guard reps > 0 || distance > 0 || seconds > 0 else {
                        return false
                    }
                } else {
                    guard let weight = set.weight,
                          let reps = set.reps,
                          weight >= 0,
                          reps > 0 else {
                        return false
                    }
                }
                completedSetCount += 1
            }
        }

        return completedSetCount > 0
    }

    private func headerCard(_ session: ActiveWorkoutSession) -> some View {
        TimelineView(.periodic(from: Date(), by: 1.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(session.startedAt))
            let elapsedLabel = formatElapsed(elapsed)

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
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.Colors.success)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFinishing || !canFinishSession)
                    .opacity((isFinishing || !canFinishSession) ? 0.55 : 1.0)
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

    private func muscleSuggestionSection(_ session: ActiveWorkoutSession) -> some View {
        let suggestions = muscleGroupSuggestions(for: session)

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
                            sessionManager.addExercise(name: name)
                            Haptics.selection()
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

    private func muscleGroupSuggestions(for session: ActiveWorkoutSession) -> [MuscleGroupSuggestion] {
        let workoutsSnapshot = dataManager.workouts
        guard !workoutsSnapshot.isEmpty else { return [] }

        let exerciseNames = Set(workoutsSnapshot.flatMap { $0.exercises.map(\.name) })
        let tagMappings = ExerciseMetadataManager.shared.resolvedMappings(for: exerciseNames)
        let groupMappings: [String: [MuscleGroup]] = tagMappings.mapValues { tags in
            tags.compactMap { $0.builtInGroup }
        }

        var covered = Set<MuscleGroup>()
        for exercise in session.exercises {
            for group in groupMappings[exercise.name] ?? [] {
                covered.insert(group)
            }
        }

        let dismissed = Set(session.dismissedMuscleGroupSuggestions.compactMap { MuscleGroup(rawValue: $0) })
        let excluded = covered.union(dismissed)

        return MuscleRecencySuggestionEngine.suggestions(
            workouts: workoutsSnapshot,
            muscleGroupsByExerciseName: groupMappings,
            excluding: excluded
        )
    }

    private var currentSummary: FinishSessionSummary {
        guard let session = sessionManager.activeSession else {
            return FinishSessionSummary(
                startedAt: Date(),
                exerciseCount: 0,
                completedSetCount: 0,
                strengthVolume: 0,
                cardioDistance: 0,
                cardioSeconds: 0,
                cardioCount: 0
            )
        }

        let metadata = ExerciseMetadataManager.shared
        var completedCount = 0
        var strengthVolume = 0.0
        var cardioDistance = 0.0
        var cardioSeconds = 0.0
        var cardioCount = 0

        for exercise in session.exercises {
            let isCardio = metadata
                .resolvedTags(for: exercise.name)
                .contains(where: { $0.builtInGroup == .cardio })

            let completedSets = exercise.sets.filter { $0.isCompleted }
            completedCount += completedSets.count

            if isCardio {
                cardioDistance += completedSets.reduce(0.0) { $0 + ($1.distance ?? 0) }
                cardioSeconds += completedSets.reduce(0.0) { $0 + ($1.seconds ?? 0) }
                cardioCount += completedSets.reduce(0) { $0 + ($1.reps ?? 0) }
            } else {
                strengthVolume += completedSets.reduce(0.0) { sum, set in
                    guard let weight = set.weight, let reps = set.reps else { return sum }
                    return sum + (weight * Double(reps))
                }
            }
        }

        return FinishSessionSummary(
            startedAt: session.startedAt,
            exerciseCount: session.exercises.count,
            completedSetCount: completedCount,
            strengthVolume: strengthVolume,
            cardioDistance: cardioDistance,
            cardioSeconds: cardioSeconds,
            cardioCount: cardioCount
        )
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
                dataManager.setLoggedWorkouts(logStore.workouts)

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

                Haptics.notify(.success)
                showingFinishSheet = false
            } catch {
                finishErrorMessage = error.localizedDescription
            }
        }
    }

    private func gymLabel(for gymId: UUID?) -> String {
        if let name = gymProfilesManager.gymName(for: gymId) {
            return name
        }
        return gymId == nil ? "Unassigned" : "Deleted gym"
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Exercise Card

private struct SessionExerciseCard: View {
    let sessionId: UUID
    let exercise: ActiveExercise
    let weightUnit: String
    let weightIncrement: Double

    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared

    @State private var showingHistory = false

	    var body: some View {
	        let history = dataManager.getExerciseHistory(for: exercise.name)
            let tags = metadataManager.resolvedTags(for: exercise.name)
            let isCardio = tags.contains(where: { $0.builtInGroup == .cardio })
            let historySets = history.flatMap(\.sets)
            let cardioConfig = isCardio
                ? metricManager.resolvedCardioConfiguration(for: exercise.name, historySets: historySets)
                : nil

	        let rec = isCardio ? nil : ExerciseRecommendationEngine.recommend(
	            exerciseName: exercise.name,
	            history: history,
	            weightIncrement: weightIncrement
	        )

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
                    } else {
                        Text("Cardio")
                            .font(Theme.Typography.captionBold)
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
                        sessionManager.removeExercise(id: exercise.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(exercise.sets.sorted { $0.order < $1.order }) { set in
                    SessionSetRow(
                        exerciseId: exercise.id,
                        exerciseName: exercise.name,
                        set: set,
                        weightUnit: weightUnit,
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
                    Haptics.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add Set")
                            .font(Theme.Typography.subheadline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.accentSecondary)
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
    let weightUnit: String
    let cardioConfig: ResolvedCardioMetricConfiguration?

    @EnvironmentObject private var sessionManager: WorkoutSessionManager

    @State private var weightText: String
    @State private var repsText: String
    @State private var distanceText: String
    @State private var durationText: String
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
        weightUnit: String,
        cardioConfig: ResolvedCardioMetricConfiguration?
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.set = set
        self.weightUnit = weightUnit
        self.cardioConfig = cardioConfig
        _weightText = State(initialValue: set.weight.map(WorkoutValueFormatter.weightText) ?? "")
        _repsText = State(initialValue: set.reps.map { String($0) } ?? "")
        _distanceText = State(initialValue: set.distance.map(WorkoutValueFormatter.distanceText) ?? "")
        _durationText = State(initialValue: set.seconds.map(WorkoutValueFormatter.durationText) ?? "")
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                sessionManager.toggleSetComplete(exerciseId: exerciseId, setId: set.id)
                Haptics.selection()
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(set.isCompleted ? Theme.Colors.success : Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)

            Text("#\(set.order)")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 34, alignment: .leading)
                .monospacedDigit()

            if let cardioConfig {
                cardioField(kind: cardioConfig.primary, countLabel: cardioConfig.countLabel)
                cardioField(kind: cardioConfig.secondary, countLabel: cardioConfig.countLabel)
            } else {
                field(title: weightUnit, text: $weightText, keyboard: .decimalPad, focus: .weight)
                    .onChange(of: weightText) { _, _ in
                        commit()
                    }

                field(title: "reps", text: $repsText, keyboard: .numberPad, focus: .reps)
                    .onChange(of: repsText) { _, _ in
                        commit()
                    }
            }

            Menu {
                Button("Delete Set", role: .destructive) {
                    sessionManager.deleteSet(exerciseId: exerciseId, setId: set.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(Theme.Colors.surface.opacity(0.35))
                    .cornerRadius(Theme.CornerRadius.small)
            }
            .buttonStyle(.plain)
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
                .monospacedDigit()
        }
        .frame(width: width)
    }

    @ViewBuilder
    private func cardioField(kind: CardioMetricKind, countLabel: String) -> some View {
        switch kind {
        case .distance:
            field(title: "dist", text: $distanceText, keyboard: .decimalPad, focus: .distance, width: 84)
                .onChange(of: distanceText) { _, _ in commit() }
        case .duration:
            field(title: "time", text: $durationText, keyboard: .numbersAndPunctuation, focus: .duration, width: 92)
                .onChange(of: durationText) { _, _ in commit() }
        case .count:
            field(title: countLabel, text: $repsText, keyboard: .numberPad, focus: .reps, width: 72)
                .onChange(of: repsText) { _, _ in commit() }
        }
    }

    private func commit() {
        if cardioConfig != nil {
            let distance = parseDouble(distanceText)
            let seconds = WorkoutValueFormatter.parseDurationSeconds(durationText)
            let reps = parseInt(repsText)
            sessionManager.updateSet(
                exerciseId: exerciseId,
                setId: set.id,
                prefill: SetPrefill(weight: nil, reps: reps, distance: distance, seconds: seconds)
            )
        } else {
            let weight = parseDouble(weightText)
            let reps = parseInt(repsText)
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
                        .font(.system(size: 16, weight: .semibold))
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
                        .font(.system(size: 18))
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

// MARK: - Finish Sheet

private struct FinishSessionSummary: Hashable {
    let startedAt: Date
    let exerciseCount: Int
    let completedSetCount: Int
    let strengthVolume: Double
    let cardioDistance: Double
    let cardioSeconds: Double
    let cardioCount: Int
}

private struct FinishSessionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isFinishing: Bool
    let summary: FinishSessionSummary
    let errorMessage: String?
    let onFinish: () -> Void
    let onDismissError: () -> Void

    var body: some View {
        ZStack {
            AdaptiveBackground()

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Finish Session")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("Save your workout and (optionally) sync Apple Health.")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    AppPillButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }

                VStack(spacing: Theme.Spacing.sm) {
                    statRow(title: "Elapsed", value: elapsedLabel(from: summary.startedAt))
                    statRow(title: "Exercises", value: "\(summary.exerciseCount)")
                    statRow(title: "Completed sets", value: "\(summary.completedSetCount)")
                    if summary.strengthVolume > 0 {
                        statRow(title: "Volume", value: formatVolume(summary.strengthVolume))
                    }
                    if summary.cardioDistance > 0 {
                        statRow(
                            title: "Distance",
                            value: "\(WorkoutValueFormatter.distanceText(summary.cardioDistance)) dist"
                        )
                    }
                    if summary.cardioSeconds > 0 {
                        statRow(
                            title: "Cardio time",
                            value: WorkoutValueFormatter.durationText(seconds: summary.cardioSeconds)
                        )
                    }
                    if summary.cardioCount > 0 {
                        statRow(title: "Count", value: "\(summary.cardioCount)")
                    }
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 1)

                if let errorMessage {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMessage)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        AppPillButton(title: "Dismiss", systemImage: "xmark", variant: .danger) {
                            onDismissError()
                        }
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.error)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
                }

                Button {
                    onFinish()
                } label: {
                    HStack {
                        Spacer()
                        Text(isFinishing ? "Finishing..." : "Finish & Save")
                            .font(Theme.Typography.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    .background(Theme.Colors.success)
                    .cornerRadius(Theme.CornerRadius.large)
                }
                .buttonStyle(.plain)
                .disabled(isFinishing)
                .opacity(isFinishing ? 0.7 : 1.0)

                Spacer()
            }
            .padding(Theme.Spacing.xl)
        }
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }

    private func elapsedLabel(from startedAt: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(startedAt))
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secondsComponent = totalSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secondsComponent) }
        return String(format: "%d:%02d", minutes, secondsComponent)
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
}
