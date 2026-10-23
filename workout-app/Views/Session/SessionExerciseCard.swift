import SwiftUI

struct SessionExerciseContext {
    let history: [(date: Date, sets: [WorkoutSet])]
    let isCardio: Bool
    let cardioConfig: ResolvedCardioMetricConfiguration?
    let recommendation: ExerciseRecommendation?
}

/// Set number that flips to a green check when the set is logged.
private struct SetCompletionBadge: View {
    let order: Int
    let isCompleted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(isCompleted ? Theme.Colors.success : Color.clear)
            if !isCompleted {
                Circle()
                    .strokeBorder(Theme.Colors.ink, lineWidth: 2)
            }
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                Text("\(order)")
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .transition(.opacity)
            }
        }
        .frame(width: 36, height: 36)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.6), value: isCompleted)
        .accessibilityHidden(true)
    }
}

// MARK: - Exercise Card

struct SessionExerciseCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @State private var showingCoaching = false

    var body: some View {
        let rec = context?.recommendation
        let isCardio = context?.isCardio ?? false
        let cardioConfig = context?.cardioConfig

        let historicalBest = historicalBestWeight
        let prSetID = personalRecordSetID(historicalBest: historicalBest)

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    let titleLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm))
                    titleLayout {
                        Text(exercise.name)
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if !exercise.sets.isEmpty { setProgressChip }
                    }

                    if let rec {
                        Text(recommendationLine(rec))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if isCardio {
                        Text("Cardio")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.textSecondary)
                    } else {
                        Text("Loading suggestion")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                }

                Spacer()

                if isCardio {
                    AppHelpButton(
                        title: "Cardio entries",
                        message: "Enter time as minutes or m:ss. Use the same distance unit as your previous workouts."
                    )
                }
                Menu {
                    Button("Exercise history", systemImage: "clock.arrow.circlepath") {
                        showingHistory = true
                    }
                    if let position = exercisePosition {
                        if position.index > 0 {
                            Button("Move up", systemImage: "arrow.up") {
                                sessionManager.moveExercise(
                                    from: IndexSet(integer: position.index),
                                    to: position.index - 1
                                )
                                Haptics.selection()
                            }
                        }
                        if position.index < position.count - 1 {
                            Button("Move down", systemImage: "arrow.down") {
                                sessionManager.moveExercise(
                                    from: IndexSet(integer: position.index),
                                    to: position.index + 2
                                )
                                Haptics.selection()
                            }
                        }
                    }
                    Button("Remove exercise", systemImage: "trash", role: .destructive) {
                        showingRemoveExerciseAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(exercise.name) actions")
            }

            if let rec, !rec.rationale.isEmpty || !rec.warmup.isEmpty {
                DisclosureGroup(isExpanded: $showingCoaching) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if !rec.warmup.isEmpty {
                            Text("Warm-up: " + rec.warmup.map { "\(formatWeight($0.weight)) \(weightUnit) × \($0.reps)" }.joined(separator: ", "))
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        Text(rec.rationale)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.top, Theme.Spacing.sm)
                } label: {
                    Text("Warm-up and suggestion")
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .tint(Theme.Colors.textPrimary)
            }

            if !isCardio && !dynamicTypeSize.isAccessibilitySize && !exercise.sets.isEmpty {
                setTableHeader
            }

            LazyVStack(spacing: isCardio || dynamicTypeSize.isAccessibilitySize ? Theme.Spacing.sm : 2) {
                let recentSets = lastSessionSets
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
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(Theme.Typography.captionBold)
                            .accessibilityHidden(true)
                        Text("Add set")
                            .font(Theme.Typography.headline)
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                            .fill(Theme.Colors.panelInset)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(AppInteractionButtonStyle())
            }
        }
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: exercise.sets.map(\.id))
        .padding(Theme.Spacing.md)
        .softCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge, style: .continuous)
                .strokeBorder(Theme.Colors.success.opacity(isAllSetsDone ? 1 : 0), lineWidth: 2)
        )
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: isAllSetsDone)
        .navigationDestination(isPresented: $showingHistory) {
            ExerciseDetailView(
                exerciseName: exercise.name,
                dataManager: dataManager,
                annotationsManager: annotationsManager,
                gymProfilesManager: gymProfilesManager
            )
            .toolbar(.visible, for: .navigationBar)
        }
        .alert("Remove exercise?", isPresented: $showingRemoveExerciseAlert) {
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

    /// Column labels for the set table, aligned with `SessionSetRow`'s compact layout.
    private var setTableHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Set")
                .frame(width: SessionSetColumns.set)
            Text("Last time")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(weightUnit)
                .frame(width: SessionSetColumns.weight)
            Text("Reps")
                .frame(width: SessionSetColumns.reps)
            Color.clear
                .frame(width: SessionSetColumns.check, height: 1)
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
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
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.tag, style: .continuous).fill(
                isAllSetsDone
                    ? Theme.Colors.success.opacity(Theme.Opacity.mediumFill)
                    : Theme.Colors.panelStrong
            )
        )
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: completedSetCount)
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
        let reps = "\(rec.repRange.lowerBound)–\(rec.repRange.upperBound)"
        if let suggestedWeight = rec.suggestedWeight, suggestedWeight > 0 {
            return "Try \(sets) × \(reps) at \(formatWeight(suggestedWeight)) \(weightUnit)"
        }
        return "Try \(sets) × \(reps)"
    }

    private func formatWeight(_ weight: Double) -> String {
        WorkoutValueFormatter.weightText(weight)
    }

    private func defaultReps(_ range: ClosedRange<Int>) -> Int {
        (range.lowerBound + range.upperBound) / 2
    }
}

// MARK: - Set Row

/// Column widths shared by the set table header and its rows.
enum SessionSetColumns {
    static let set: CGFloat = 30
    static let weight: CGFloat = 84
    static let reps: CGFloat = 60
    static let check: CGFloat = 44
}

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var weightText: String
    @State private var repsText: String
    @State private var distanceText: String
    @State private var durationText: String
    @State private var showingDeleteSetAlert = false
    @State private var completionValidationMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight, reps, distance, duration
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
        _weightText = State(initialValue: set.inputDraft?.weight ?? set.weight.map(WorkoutValueFormatter.weightText) ?? "")
        _repsText = State(initialValue: set.inputDraft?.reps ?? set.reps.map(String.init) ?? "")
        _distanceText = State(initialValue: set.inputDraft?.distance ?? set.distance.map(WorkoutValueFormatter.distanceText) ?? "")
        _durationText = State(initialValue: set.inputDraft?.duration ?? set.seconds.map(WorkoutValueFormatter.durationText) ?? "")
    }

    /// Strength sets log from a single table line; cardio and accessibility sizes
    /// keep the roomier stacked layout with labelled fields.
    private var usesCompactRow: Bool {
        cardioConfig == nil && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        Group {
            if usesCompactRow {
                compactRow
            } else {
                stackedRow
            }
        }
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: set.isCompleted)
        .animation(reduceMotion ? nil : Theme.Animation.bouncy, value: isPersonalBest)
        .toolbar {
            // Only the row with focus contributes to the shared keyboard accessory.
            if focusedField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        focusedField = nil
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Hide keyboard")

                    if focusedField == .weight || (focusedField == .reps && cardioConfig == nil) {
                        let isWeight = focusedField == .weight
                        let step = isWeight ? WorkoutValueFormatter.weightText(weightIncrement) : "1"
                        Button {
                            if isWeight { adjustWeight(by: -weightIncrement) } else { adjustReps(by: -1) }
                            Haptics.impact(.light)
                        } label: {
                            Text("−\(step)")
                                .monospacedDigit()
                        }
                        .accessibilityLabel("Decrease by \(step)")
                        Button {
                            if isWeight { adjustWeight(by: weightIncrement) } else { adjustReps(by: 1) }
                            Haptics.impact(.light)
                        } label: {
                            Text("+\(step)")
                                .monospacedDigit()
                        }
                        .accessibilityLabel("Increase by \(step)")
                    }

                    Spacer()
                    if nextField != nil {
                        Button("Next") { focusedField = nextField }
                    }
                    Button("Log set", action: logSet)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
        .onChange(of: set) { _, updatedSet in
            // A focused input retains its exact text (including a trailing decimal).
            // Every edit has already reached the model synchronously via its Binding.
            guard focusedField == nil else { return }
            synchronizeText(with: updatedSet)
        }
        .alert("Delete set?", isPresented: $showingDeleteSetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                sessionManager.deleteSet(exerciseId: exerciseId, setId: set.id)
            }
        } message: {
            Text("This will remove set #\(set.order) from \(exerciseName).")
        }
    }

    // MARK: Compact row

    /// Set number, last time, weight, reps, check: one line per set, like a log sheet.
    private var compactRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.Spacing.sm) {
                setNumberMenu
                    .frame(width: SessionSetColumns.set)

                lastTimeCell
                    .frame(maxWidth: .infinity, alignment: .leading)

                if set.isCompleted {
                    completedValue(set.weight.map(WorkoutValueFormatter.weightText) ?? "—")
                        .frame(width: SessionSetColumns.weight)
                    completedValue(set.reps.map(String.init) ?? "—")
                        .frame(width: SessionSetColumns.reps)
                } else {
                    compactField(focus: .weight, keyboard: .decimalPad, title: "Weight")
                        .frame(width: SessionSetColumns.weight)
                    compactField(focus: .reps, keyboard: .numberPad, title: "Reps")
                        .frame(width: SessionSetColumns.reps)
                }

                checkButton
                    .frame(width: SessionSetColumns.check)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                    .fill(compactRowFill)
            )

            if let message = completionValidationMessage ?? syntaxIssue?.message {
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, SessionSetColumns.set + Theme.Spacing.sm)
                    .accessibilityIdentifier("set-validation-\(set.id)")
            }
        }
        .contextMenu { setMenuItems }
    }

    private var compactRowFill: Color {
        if isPersonalBest { return Theme.Colors.plateYellow.opacity(0.18) }
        return set.isCompleted ? Theme.Colors.success.opacity(0.1) : Color.clear
    }

    private var setNumberMenu: some View {
        Menu {
            setMenuItems
        } label: {
            Text("\(set.order)")
                .font(Theme.Typography.title3)
                .foregroundStyle(set.isCompleted ? Theme.Colors.success : Theme.Colors.textPrimary)
                .frame(minWidth: SessionSetColumns.set, minHeight: Theme.Layout.minimumTapTarget)
                .contentShape(.rect)
        }
        .accessibilityLabel("Set \(set.order) actions")
    }

    @ViewBuilder
    private var setMenuItems: some View {
        if set.isCompleted {
            Button("Edit set", systemImage: "pencil", action: editSet)
        } else if let previousSet, hasValues(previousSet) {
            Button("Copy set \(previousSet.order)", systemImage: "doc.on.doc") {
                copyFromSet(previousSet)
            }
        }
        if !set.isCompleted, let lastSessionSet, canCopy(lastSessionSet) {
            Button("Use last time: \(summary(lastSessionSet))", systemImage: "clock.arrow.circlepath") {
                applyLastSession(lastSessionSet)
            }
        }
        Button("Delete set", systemImage: "trash", role: .destructive) {
            showingDeleteSetAlert = true
        }
    }

    @ViewBuilder
    private var lastTimeCell: some View {
        if isPersonalBest {
            PRTag()
        } else if let lastSessionSet, canCopy(lastSessionSet), !set.isCompleted {
            Button {
                applyLastSession(lastSessionSet)
            } label: {
                Text(compactSummary(lastSessionSet))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use last session: \(summary(lastSessionSet))")
            .accessibilityHint("Copies the values into set \(set.order)")
        } else if let lastSessionSet, canCopy(lastSessionSet) {
            Text(compactSummary(lastSessionSet))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityLabel("Last time \(summary(lastSessionSet))")
        } else {
            Text("—")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.decorativeSubtle)
                .accessibilityHidden(true)
        }
    }

    private func compactSummary(_ source: WorkoutSet) -> String {
        "\(WorkoutValueFormatter.weightText(source.weight)) × \(source.reps)"
    }

    private func compactField(focus: Field, keyboard: UIKeyboardType, title: String) -> some View {
        TextField("0", text: textBinding(for: focus))
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: focus)
            .submitLabel(focus == fieldOrder.last ? .done : .next)
            .onSubmit {
                if let nextField { focusedField = nextField } else { logSet() }
            }
            .font(Theme.Typography.title4Bold)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small, style: .continuous)
                    .fill(Theme.Colors.panelInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small, style: .continuous)
                    .strokeBorder(focusedField == focus ? Theme.Colors.ink : Color.clear, lineWidth: 2)
            )
            .accessibilityLabel("\(exerciseName), set \(set.order), \(title)")
    }

    private func completedValue(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.title4Bold)
            .monospacedDigit()
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
    }

    /// Empty ring to log the set; a filled green check once logged. Tapping a logged
    /// set reopens it for editing.
    private var checkButton: some View {
        Button {
            if set.isCompleted { editSet() } else { logSet() }
        } label: {
            ZStack {
                Circle()
                    .fill(set.isCompleted ? Theme.Colors.success : Color.clear)
                Circle()
                    .strokeBorder(set.isCompleted ? Theme.Colors.success : Theme.Colors.ink, lineWidth: 2)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(set.isCompleted ? Color.white : Theme.Colors.textPrimary)
                    .opacity(set.isCompleted ? 1 : 0.35)
            }
            .frame(width: 36, height: 36)
            .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
            .contentShape(Circle())
        }
        .buttonStyle(AppInteractionButtonStyle())
        .accessibilityLabel(set.isCompleted ? "Set \(set.order) logged" : "Log set \(set.order)")
        .accessibilityHint(set.isCompleted ? "Reopens this set for editing" : "Saves this set")
    }

    // MARK: Stacked row

    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            rowHeader

            if !set.isCompleted {
                if dynamicTypeSize.isAccessibilitySize {
                    metricFields(vertical: true)
                } else {
                    ViewThatFits(in: .horizontal) {
                        metricFields(vertical: false)
                        metricFields(vertical: true)
                    }
                }

                if let lastSessionSet, canCopy(lastSessionSet) {
                    Button {
                        applyLastSession(lastSessionSet)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                            Text("Last time: \(summary(lastSessionSet))")
                                .multilineTextAlignment(.leading)
                                .underline(color: Theme.Colors.rule)
                            Spacer(minLength: 0)
                        }
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use last session: \(summary(lastSessionSet))")
                    .accessibilityHint("Copies the values into set \(set.order)")
                }

                if let message = completionValidationMessage ?? syntaxIssue?.message {
                    Text(message)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("set-validation-\(set.id)")
                }

                Button(action: logSet) {
                    Text("Log set \(set.order)")
                        .font(Theme.Typography.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .accessibilityHint("Saves this set")
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.md)
        .background(rowFill, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous))
    }

    private var rowHeader: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            SetCompletionBadge(order: set.order, isCompleted: set.isCompleted)
            VStack(alignment: .leading, spacing: 3) {
                Text(set.isCompleted ? "Set \(set.order), logged" : "Set \(set.order)")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(set.isCompleted ? Theme.Colors.success : Theme.Colors.textPrimary)
                if set.isCompleted {
                    Text(summary(set))
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            if isPersonalBest {
                PRMarkerView(date: Date())
                    .accessibilityLabel("New personal record")
            }
            Spacer(minLength: 0)

            if set.isCompleted {
                Button("Edit", action: editSet)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
                    .accessibilityLabel("Edit logged set \(set.order)")
                    .accessibilityHint("Reopens this set. Log it again when finished editing.")
            } else if let previousSet, hasValues(previousSet) {
                Button {
                    copyFromSet(previousSet)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(Theme.Typography.subheadlineBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy previous set")
                .accessibilityHint("Fills set \(set.order) with \(summary(previousSet))")
            }

            Menu {
                if set.isCompleted {
                    Button("Edit set", systemImage: "pencil", action: editSet)
                }
                Button("Delete set", systemImage: "trash", role: .destructive) {
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
    }

    private var rowFill: Color {
        if isPersonalBest { return Theme.Colors.plateYellow.opacity(0.18) }
        return set.isCompleted ? Theme.Colors.success.opacity(0.1) : Theme.Colors.panelInset
    }

    @ViewBuilder
    private func metricFields(vertical: Bool) -> some View {
        if vertical {
            VStack(spacing: Theme.Spacing.sm) { metricFieldViews }
        } else {
            HStack(spacing: Theme.Spacing.sm) { metricFieldViews }
        }
    }

    @ViewBuilder
    private var metricFieldViews: some View {
        if let cardioConfig {
            ForEach(displayedCardioMetrics, id: \.self) { kind in
                cardioField(kind: kind, countLabel: cardioConfig.countLabel)
            }
        } else {
            stepperField(
                title: "Weight (\(weightUnit))", focus: .weight, keyboard: .decimalPad,
                stepDescription: WorkoutValueFormatter.weightText(weightIncrement),
                onStep: { adjustWeight(by: weightIncrement * Double($0)) }
            )
            stepperField(
                title: "Reps", focus: .reps, keyboard: .numberPad,
                stepDescription: "1", onStep: adjustReps
            )
        }
    }

    private func stepperField(
        title: String, focus: Field, keyboard: UIKeyboardType,
        stepDescription: String, onStep: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: 0) {
                stepButton("minus", label: "Decrease \(title) by \(stepDescription)") { onStep(-1) }
                input(title: title, focus: focus, keyboard: keyboard)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: Theme.Layout.minimumTapTarget)
                stepButton("plus", label: "Increase \(title) by \(stepDescription)") { onStep(1) }
            }
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.small, style: .continuous))
            .overlay(fieldBorder(focus))
        }
        .frame(minWidth: Theme.Layout.minimumTapTarget * 3, maxWidth: .infinity)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.impact(.light)
        } label: {
            Image(systemName: symbol)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func input(title: String, focus: Field, keyboard: UIKeyboardType) -> some View {
        TextField(focus == .duration ? "12:30" : "0", text: textBinding(for: focus))
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: focus)
            .submitLabel(focus == fieldOrder.last ? .done : .next)
            .onSubmit {
                if let nextField { focusedField = nextField } else { logSet() }
            }
            .font(Theme.Typography.bodyBold)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .accessibilityLabel("\(exerciseName), set \(set.order), \(title)")
    }

    private func fieldBorder(_ focus: Field) -> some View {
        RoundedRectangle(cornerRadius: Theme.CornerRadius.small, style: .continuous)
            .strokeBorder(
                focusedField == focus ? Theme.Colors.ink : Theme.Colors.rule,
                lineWidth: focusedField == focus ? 2 : 1
            )
    }

    private func field(title: String, hint: String?, focus: Field, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textSecondary)
            input(title: title, focus: focus, keyboard: keyboard)
                .padding(.horizontal, Theme.Spacing.md)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.small, style: .continuous))
                .overlay(fieldBorder(focus))
            if let hint {
                Text(hint)
                    .font(Theme.Typography.microcopy)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(minWidth: 112, maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func cardioField(kind: CardioMetricKind, countLabel: String) -> some View {
        switch kind {
        case .distance:
            field(title: "Distance", hint: "Your usual unit", focus: .distance, keyboard: .decimalPad)
        case .duration:
            field(title: "Time", hint: "Minutes or m:ss", focus: .duration, keyboard: .numbersAndPunctuation)
        case .count:
            field(title: countLabel.capitalized, hint: "Whole number", focus: .reps, keyboard: .numberPad)
        }
    }

    /// A preference changes emphasis, never hides existing data. Keep a cleared
    /// optional field visible until focus leaves so typing can continue normally.
    private var displayedCardioMetrics: [CardioMetricKind] {
        guard let cardioConfig else { return [] }
        let preferred = [cardioConfig.primary, cardioConfig.secondary]
        let additional = CardioMetricKind.allCases.filter { kind in
            let inputField = field(for: kind)
            return !preferred.contains(kind)
                && (!text(for: inputField).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || focusedField == inputField)
        }
        return preferred + additional
    }

    private func field(for kind: CardioMetricKind) -> Field {
        switch kind {
        case .distance: return .distance
        case .duration: return .duration
        case .count: return .reps
        }
    }

    private var fieldOrder: [Field] {
        cardioConfig == nil ? [.weight, .reps] : displayedCardioMetrics.map(field(for:))
    }

    private var nextField: Field? {
        guard let focusedField, let index = fieldOrder.firstIndex(of: focusedField),
              fieldOrder.indices.contains(index + 1) else { return nil }
        return fieldOrder[index + 1]
    }

    /// The model receives each keystroke in the same event as the field. Disk writes
    /// may be coalesced by the manager; the row never holds an unsent numeric edit.
    private func textBinding(for field: Field) -> Binding<String> {
        Binding(get: { text(for: field) }, set: { value in
            switch field {
            case .weight: weightText = value
            case .reps: repsText = value
            case .distance: distanceText = value
            case .duration: durationText = value
            }
            commitImmediately()
            if completionValidationMessage != nil {
                completionValidationMessage = inputIssue?.message
            }
        })
    }

    private func text(for field: Field) -> String {
        switch field {
        case .weight: return weightText
        case .reps: return repsText
        case .distance: return distanceText
        case .duration: return durationText
        }
    }

    private var syntaxIssue: (field: Field, message: String)? {
        for field in fieldOrder {
            let raw = text(for: field).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            switch field {
            case .weight:
                if parseDouble(raw).map({ $0 >= 0 }) != true {
                    return (field, "Enter a weight of 0 or more. Use 0 for bodyweight sets.")
                }
            case .reps:
                if WorkoutValueFormatter.parseWholeNumber(raw) == nil {
                    return (field, "Enter a whole number for \(cardioConfig?.countLabel ?? "reps").")
                }
            case .distance:
                if parseDouble(raw).map({ $0 >= 0 }) != true {
                    return (field, "Enter a distance of 0 or more, in your usual unit.")
                }
            case .duration:
                if WorkoutValueFormatter.parseDurationSeconds(raw) == nil {
                    return (field, "Use minutes (12.5), m:ss (12:30), or h:mm:ss (1:02:30).")
                }
            }
        }
        return nil
    }

    private var inputIssue: (field: Field, message: String)? {
        if let syntaxIssue { return syntaxIssue }
        if cardioConfig != nil {
            if (parseDouble(distanceText) ?? 0) <= 0,
               (WorkoutValueFormatter.parseDurationSeconds(durationText) ?? 0) <= 0,
               (WorkoutValueFormatter.parseWholeNumber(repsText) ?? 0) <= 0 {
                return (fieldOrder[0], "Enter at least one cardio value above 0 to log this set.")
            }
        } else {
            if parseDouble(weightText) == nil {
                return (.weight, "Enter a weight, or 0 for a bodyweight set.")
            }
            if (WorkoutValueFormatter.parseWholeNumber(repsText) ?? 0) <= 0 {
                return (.reps, "Enter at least 1 rep to log this set.")
            }
        }
        return nil
    }

    private func logSet() {
        guard !set.isCompleted else { return }
        if let issue = inputIssue {
            completionValidationMessage = issue.message
            focusedField = issue.field
            Haptics.notify(.warning)
            return
        }
        commitImmediately()
        let wouldSetRecord = beatsPersonalBest()
        switch sessionManager.toggleSetComplete(exerciseId: exerciseId, setId: set.id) {
        case .toggled(let isCompleted):
            if isCompleted {
                focusedField = nil
                completionValidationMessage = nil
                if wouldSetRecord { Haptics.notify(.success) } else { Haptics.setComplete() }
            }
        case .invalid(let message):
            completionValidationMessage = message
            focusedField = fieldOrder.first
            Haptics.notify(.warning)
        case .missingSet:
            break
        }
    }

    private func editSet() {
        guard set.isCompleted else { return }
        if case .toggled = sessionManager.toggleSetComplete(exerciseId: exerciseId, setId: set.id) {
            completionValidationMessage = nil
            focusedField = fieldOrder.first
            Haptics.selection()
        }
    }

    private func beatsPersonalBest() -> Bool {
        guard cardioConfig == nil, let threshold = personalBestThreshold,
              let weight = parseDouble(weightText),
              (WorkoutValueFormatter.parseWholeNumber(repsText) ?? 0) > 0,
              ExerciseLoad.isTrackedWeight(weight, exerciseName: exerciseName) else { return false }
        return ExerciseLoad.isBetter(weight, than: threshold, exerciseName: exerciseName)
    }

    private func adjustWeight(by amount: Double) {
        let current = parseDouble(weightText) ?? 0
        let updated = current + amount
        guard updated.isFinite else { return }
        weightText = WorkoutValueFormatter.weightText(max(0, updated))
        commitImmediately()
    }

    private func adjustReps(by amount: Int) {
        let current = WorkoutValueFormatter.parseWholeNumber(repsText) ?? 0
        let (updated, overflow) = current.addingReportingOverflow(amount)
        guard !overflow else { return }
        repsText = String(max(0, updated))
        commitImmediately()
    }

    private func applyLastSession(_ source: WorkoutSet) {
        weightText = cardioConfig == nil ? WorkoutValueFormatter.weightText(source.weight) : ""
        repsText = source.reps > 0 ? String(source.reps) : ""
        distanceText = source.distance > 0 ? WorkoutValueFormatter.distanceText(source.distance) : ""
        durationText = source.seconds > 0 ? WorkoutValueFormatter.durationText(seconds: source.seconds) : ""
        completionValidationMessage = nil
        commitImmediately()
        Haptics.selection()
    }

    private func copyFromSet(_ source: ActiveSet) {
        synchronizeText(with: source)
        completionValidationMessage = nil
        commitImmediately()
        Haptics.selection()
    }

    private func synchronizeText(with updatedSet: ActiveSet) {
        weightText = updatedSet.inputDraft?.weight ?? updatedSet.weight.map(WorkoutValueFormatter.weightText) ?? ""
        repsText = updatedSet.inputDraft?.reps ?? updatedSet.reps.map(String.init) ?? ""
        distanceText = updatedSet.inputDraft?.distance ?? updatedSet.distance.map(WorkoutValueFormatter.distanceText) ?? ""
        durationText = updatedSet.inputDraft?.duration ?? updatedSet.seconds.map(WorkoutValueFormatter.durationText) ?? ""
    }

    private func commitImmediately() {
        let prefill: SetPrefill
        if cardioConfig != nil {
            prefill = SetPrefill(
                weight: nil, reps: WorkoutValueFormatter.parseWholeNumber(repsText),
                distance: parseDouble(distanceText),
                seconds: WorkoutValueFormatter.parseDurationSeconds(durationText)
            )
        } else {
            prefill = SetPrefill(
                weight: parseDouble(weightText), reps: WorkoutValueFormatter.parseWholeNumber(repsText),
                distance: nil, seconds: nil
            )
        }
        sessionManager.updateSet(
            exerciseId: exerciseId, setId: set.id, prefill: prefill,
            inputDraft: SetInputDraft(
                weight: cardioConfig == nil ? weightText : "", reps: repsText,
                distance: cardioConfig == nil ? "" : distanceText,
                duration: cardioConfig == nil ? "" : durationText
            )
        )
    }

    private func hasValues(_ set: ActiveSet) -> Bool {
        set.weight != nil || set.reps != nil || set.distance != nil || set.seconds != nil
    }

    private func canCopy(_ set: WorkoutSet) -> Bool {
        cardioConfig == nil ? set.reps > 0 : set.reps > 0 || set.distance > 0 || set.seconds > 0
    }

    private func summary(_ set: WorkoutSet) -> String {
        summary(ActiveSet(order: set.setOrder, weight: set.weight, reps: set.reps,
                          distance: set.distance, seconds: set.seconds))
    }

    private func summary(_ set: ActiveSet) -> String {
        guard let cardioConfig else {
            return "\(set.weight.map(WorkoutValueFormatter.weightText) ?? "—") \(weightUnit) × \(set.reps.map(String.init) ?? "—")"
        }
        var parts: [String] = []
        if let distance = set.distance, distance > 0 {
            parts.append("\(WorkoutValueFormatter.distanceText(distance)) distance")
        }
        if let seconds = set.seconds, seconds > 0 {
            parts.append(WorkoutValueFormatter.durationText(seconds: seconds))
        }
        if let reps = set.reps, reps > 0 {
            parts.append("\(reps) \(cardioConfig.countLabel)")
        }
        return parts.isEmpty ? "No values yet" : parts.joined(separator: ", ")
    }

    private func parseDouble(_ text: String) -> Double? {
        WorkoutValueFormatter.parseDecimal(text)
    }
}
