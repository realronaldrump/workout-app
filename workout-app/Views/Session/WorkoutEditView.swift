import SwiftUI

struct WorkoutEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var logStore: WorkoutLogStore
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared

    let workoutId: UUID

    @State private var draft: LoggedWorkout?
    @State private var original: LoggedWorkout?
    @State private var showingDeleteAlert = false
    @State private var showingDiscardChangesAlert = false
    @State private var exercisePendingRemoval: LoggedExercise?
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                if let draft {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                Text("Workout Name")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textTertiary)

                                TextField("Workout name", text: bindingForName)
                                    .textInputAutocapitalization(.words)
                                    .disableAutocorrection(true)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .padding(Theme.Spacing.md)
                                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                            .fill(Theme.Colors.surface.opacity(0.35))
                                    )
                            }
                            .padding(Theme.Spacing.lg)
                            .softCard(elevation: 1)

                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                Text("Exercises")
                                    .font(Theme.Typography.sectionHeader)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .tracking(1.0)

                                LazyVStack(spacing: Theme.Spacing.md) {
                                    ForEach(draft.exercises) { exercise in
                                        LoggedExerciseEditorCard(
                                            exercise: exercise,
                                            setBinding: { setId in
                                                bindingForSet(exerciseId: exercise.id, setId: setId)
                                            },
                                            onAddSet: {
                                                addSet(exerciseId: exercise.id)
                                            },
                                            onDeleteSet: { setId in
                                                deleteSet(exerciseId: exercise.id, setId: setId)
                                            },
                                            onRemoveExercise: {
                                                exercisePendingRemoval = exercise
                                            }
                                        )
                                    }
                                }
                            }

                            if let errorMessage {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text(errorMessage)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                }
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.error)
                                .padding(Theme.Spacing.lg)
                                .softCard(elevation: 1)
                            }

                            Button(role: .destructive) {
                                showingDeleteAlert = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Delete Workout")
                                        .font(Theme.Typography.bodyBold)
                                    Spacer()
                                }
                                .padding()
                                .softCard(elevation: 1)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.Colors.error)
                        }
                        .padding(Theme.Spacing.xl)
                        .contentColumn()
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    EmptyStateCard(
                        icon: "exclamationmark.triangle.fill",
                        tint: Theme.Colors.error,
                        title: "Workout Not Found",
                        message: "This workout may have been deleted."
                    )
                    .padding(.horizontal, Theme.Spacing.xl)
                }
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                        if hasUnsavedChanges {
                            showingDiscardChangesAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if draft != nil {
                    AppPrimaryButton(
                        title: isSaving ? "Saving…" : "Save Changes",
                        systemImage: "checkmark",
                        isEnabled: !isSaving && hasUnsavedChanges
                    ) {
                        save()
                    }
                    .contentColumn(maxWidth: 640, alignment: .center)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(.bar)
                }
            }
            .alert("Delete Workout?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) { deleteWorkout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the logged workout.")
            }
            .alert("Discard Changes?", isPresented: $showingDiscardChangesAlert) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("Your edits to this workout haven't been saved.")
            }
            .alert(
                "Remove Exercise?",
                isPresented: Binding(
                    get: { exercisePendingRemoval != nil },
                    set: { if !$0 { exercisePendingRemoval = nil } }
                ),
                presenting: exercisePendingRemoval
            ) { exercise in
                Button("Remove", role: .destructive) {
                    draft?.exercises.removeAll { $0.id == exercise.id }
                    exercisePendingRemoval = nil
                    Haptics.selection()
                }
                Button("Cancel", role: .cancel) { exercisePendingRemoval = nil }
            } message: { exercise in
                Text("\(exercise.name) and its sets will be removed when you save.")
            }
            .interactiveDismissDisabled(hasUnsavedChanges || isSaving)
            .onAppear {
                guard draft == nil else { return }
                let loaded = logStore.workout(id: workoutId)
                draft = loaded
                original = loaded
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        guard let draft else { return false }
        return draft != original
    }

    private var bindingForName: Binding<String> {
        Binding(
            get: { draft?.name ?? "" },
            set: { newValue in
                draft?.name = newValue
            }
        )
    }

    private func bindingForSet(exerciseId: UUID, setId: UUID) -> Binding<LoggedSet> {
        let fallbackSet = LoggedSet(order: 1, weight: 0, reps: 0, distance: nil, seconds: nil)

        return Binding(
            get: {
                guard let exerciseIndex = draft?.exercises.firstIndex(where: { $0.id == exerciseId }),
                      let setIndex = draft?.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
                    return fallbackSet
                }
                return draft?.exercises[exerciseIndex].sets[setIndex] ?? fallbackSet
            },
            set: { newValue in
                guard let exerciseIndex = draft?.exercises.firstIndex(where: { $0.id == exerciseId }),
                      let setIndex = draft?.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
                    return
                }
                draft?.exercises[exerciseIndex].sets[setIndex] = newValue
            }
        )
    }

    private func addSet(exerciseId: UUID) {
        guard let exerciseIndex = draft?.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let nextOrder = (draft?.exercises[exerciseIndex].sets.map(\.order).max() ?? 0) + 1
        draft?.exercises[exerciseIndex].sets.append(
            LoggedSet(order: nextOrder, weight: 0, reps: 0, distance: nil, seconds: nil)
        )
    }

    private func deleteSet(exerciseId: UUID, setId: UUID) {
        guard let exerciseIndex = draft?.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = draft?.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return
        }
        draft?.exercises[exerciseIndex].sets.remove(at: setIndex)
        renumberSets(exerciseId: exerciseId)
    }

    private func renumberSets(exerciseId: UUID) {
        guard let exerciseIndex = draft?.exercises.firstIndex(where: { $0.id == exerciseId }),
              let sets = draft?.exercises[exerciseIndex].sets else {
            return
        }
        let sorted = sets.sorted { $0.order < $1.order }
        var updated: [LoggedSet] = []
        updated.reserveCapacity(sorted.count)
        for (idx, set) in sorted.enumerated() {
            var copy = set
            copy.order = idx + 1
            updated.append(copy)
        }
        draft?.exercises[exerciseIndex].sets = updated
    }

    private func save() {
        guard var workout = draft else { return }
        guard !isSaving else { return }

        let trimmedName = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        workout.name = trimmedName.isEmpty ? (original?.name ?? workout.name) : trimmedName

        // Exercises whose sets were all deleted would otherwise be saved as empty entries.
        workout.exercises.removeAll { $0.sets.isEmpty }

        let setCount = workout.exercises.flatMap(\.sets).count
        if setCount == 0 {
            errorMessage = "Workout must contain at least one set. To remove it entirely, use Delete Workout."
            return
        }

        for exercise in workout.exercises {
            let isCardio = metadataManager
                .resolvedTags(for: exercise.name)
                .contains(where: { $0.builtInGroup == .cardio })

            for set in exercise.sets {
                if isCardio {
                    let count = max(set.reps, 0)
                    let distance = max(set.distance ?? 0, 0)
                    let seconds = max(set.seconds ?? 0, 0)
                    if count <= 0 && distance <= 0 && seconds <= 0 {
                        errorMessage = "\(exercise.name), set \(set.order) needs a distance, time, or count."
                        return
                    }
                } else {
                    if set.weight < 0 || set.reps <= 0 {
                        errorMessage = "\(exercise.name), set \(set.order) needs a weight and at least 1 rep."
                        return
                    }
                }
            }
        }

        isSaving = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await logStore.save(workout)
            } catch {
                isSaving = false
                errorMessage = "Couldn't save changes: \(error.localizedDescription)"
                Haptics.notify(.error)
                return
            }
            await dataManager.setLoggedWorkoutsOffMain(logStore.workouts)
            isSaving = false
            Haptics.notify(.success)
            dismiss()
        }
    }

    private func deleteWorkout() {
        Task { @MainActor in
            await logStore.delete(id: workoutId)
            await dataManager.setLoggedWorkoutsOffMain(logStore.workouts)
            Haptics.notify(.success)
            dismiss()
        }
    }
}

private struct LoggedExerciseEditorCard: View {
    let exercise: LoggedExercise
    let setBinding: (UUID) -> Binding<LoggedSet>
    let onAddSet: () -> Void
    let onDeleteSet: (UUID) -> Void
    let onRemoveExercise: () -> Void

    private let weightUnit = "lbs"
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared

    var body: some View {
        let isCardio = metadataManager
            .resolvedTags(for: exercise.name)
            .contains(where: { $0.builtInGroup == .cardio })
        let config = isCardio
            ? metricManager.resolvedCardioConfiguration(for: exercise.name, historySets: exercise.sets.map { set in
                WorkoutSet(
                    date: Date(),
                    workoutName: "",
                    duration: "",
                    exerciseName: exercise.name,
                    setOrder: set.order,
                    weight: set.weight,
                    reps: set.reps,
                    distance: set.distance ?? 0,
                    seconds: set.seconds ?? 0
                )
            })
            : nil

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(exercise.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button(role: .destructive) {
                    onRemoveExercise()
                } label: {
                    Image(systemName: "minus.circle")
                        .font(Theme.Typography.subheadlineBold)
                        .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.error)
                .accessibilityLabel("Remove \(exercise.name)")

                Button {
                    onAddSet()
                    Haptics.selection()
                } label: {
                    Label("Add Set", systemImage: "plus")
                        .font(Theme.Typography.captionBold)
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.Colors.accentSecondary)
            }

            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(exercise.sets) { set in
                    LoggedSetEditorRow(
                        order: set.order,
                        set: setBinding(set.id),
                        weightUnit: weightUnit,
                        cardioConfig: config,
                        onDelete: {
                            onDeleteSet(set.id)
                            Haptics.selection()
                        }
                    )
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

private struct LoggedSetEditorRow: View {
    let order: Int
    @Binding var set: LoggedSet
    let weightUnit: String
    let cardioConfig: ResolvedCardioMetricConfiguration?
    let onDelete: () -> Void

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
        order: Int,
        set: Binding<LoggedSet>,
        weightUnit: String,
        cardioConfig: ResolvedCardioMetricConfiguration?,
        onDelete: @escaping () -> Void
    ) {
        self.order = order
        _set = set
        self.weightUnit = weightUnit
        self.cardioConfig = cardioConfig
        self.onDelete = onDelete
        _weightText = State(initialValue: WorkoutValueFormatter.weightText(set.wrappedValue.weight))
        _repsText = State(initialValue: String(set.wrappedValue.reps))
        _distanceText = State(initialValue: set.wrappedValue.distance.map(WorkoutValueFormatter.distanceText) ?? "")
        _durationText = State(initialValue: set.wrappedValue.seconds.map(WorkoutValueFormatter.durationText) ?? "")
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Text("Set \(order)")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(Theme.Typography.subheadlineBold)
                        .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.error)
                .accessibilityLabel("Delete set \(order)")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.sm) { metricFields }
                VStack(spacing: Theme.Spacing.sm) { metricFields }
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.surface.opacity(0.20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.border.opacity(0.7), lineWidth: 1)
        )
        .toolbar {
            // Only the row being edited contributes keyboard items, so the keyboard shows a
            // single "Done" button instead of one per set row.
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
    }

    @ViewBuilder
    private var metricFields: some View {
        if let cardioConfig {
            cardioField(kind: cardioConfig.primary, countLabel: cardioConfig.countLabel)
            cardioField(kind: cardioConfig.secondary, countLabel: cardioConfig.countLabel)
        } else {
            field(title: "Weight (\(weightUnit))", text: $weightText, keyboard: .decimalPad, focus: .weight)
                .onChange(of: weightText) { _, _ in commit() }

            field(title: "Reps", text: $repsText, keyboard: .numberPad, focus: .reps)
                .onChange(of: repsText) { _, _ in commit() }
        }
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
                .background(Theme.Colors.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func cardioField(kind: CardioMetricKind, countLabel: String) -> some View {
        switch kind {
        case .distance:
            field(title: "Distance", text: $distanceText, keyboard: .decimalPad, focus: .distance)
                .onChange(of: distanceText) { _, _ in commit() }
        case .duration:
            field(title: "Time", text: $durationText, keyboard: .numbersAndPunctuation, focus: .duration)
                .onChange(of: durationText) { _, _ in commit() }
        case .count:
            field(title: countLabel, text: $repsText, keyboard: .numberPad, focus: .reps)
                .onChange(of: repsText) { _, _ in commit() }
        }
    }

    private func commit() {
        if cardioConfig != nil {
            let repsValue = parseInt(repsText) ?? 0
            let distanceValue = parseDouble(distanceText)
            let secondsValue = WorkoutValueFormatter.parseDurationSeconds(durationText)

            set.weight = 0
            set.reps = repsValue
            set.distance = distanceValue
            set.seconds = secondsValue
        } else {
            let weightValue = parseDouble(weightText) ?? 0
            let repsValue = parseInt(repsText) ?? 0

            set.weight = weightValue
            set.reps = repsValue
            set.distance = nil
            set.seconds = nil
        }
    }

    private func parseDouble(_ text: String) -> Double? {
        WorkoutValueFormatter.parseDecimal(text)
    }

    private func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

}
