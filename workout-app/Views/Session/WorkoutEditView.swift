import SwiftUI

struct WorkoutEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var logStore: WorkoutLogStore
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared

    let workoutId: UUID

    @State private var draft: LoggedWorkout?
    @State private var showingDeleteAlert = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                if let draft {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
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

                                VStack(spacing: Theme.Spacing.md) {
                                    ForEach(draft.exercises.indices, id: \.self) { eIndex in
                                        LoggedExerciseEditorCard(
                                            exerciseIndex: eIndex,
                                            exercise: draft.exercises[eIndex],
                                            setBinding: { sIndex in
                                                bindingForSet(exerciseIndex: eIndex, setIndex: sIndex)
                                            },
                                            onAddSet: {
                                                addSet(exerciseIndex: eIndex)
                                            },
                                            onDeleteSet: { sIndex in
                                                deleteSet(exerciseIndex: eIndex, setIndex: sIndex)
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

                            Button {
                                save()
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(isSaving ? "Saving..." : "Save Changes")
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding()
                                .background(Theme.Colors.accent)
                                .cornerRadius(Theme.CornerRadius.large)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                            .opacity(isSaving ? 0.7 : 1.0)

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
                    }
                } else {
                    ContentUnavailableView(
                        "Workout not found",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("This workout may have been deleted.")
                    )
                    .padding(.horizontal, Theme.Spacing.xl)
                }
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppPillButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }
            }
            .alert("Delete Workout?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) { deleteWorkout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the logged workout.")
            }
            .onAppear {
                draft = logStore.workout(id: workoutId)
            }
        }
    }

    private var bindingForName: Binding<String> {
        Binding(
            get: { draft?.name ?? "" },
            set: { newValue in
                draft?.name = newValue
            }
        )
    }

    private func bindingForSet(exerciseIndex: Int, setIndex: Int) -> Binding<LoggedSet> {
        Binding(
            get: { draft?.exercises[exerciseIndex].sets[setIndex] ?? LoggedSet(order: 1, weight: 0, reps: 0, distance: nil, seconds: nil) },
            set: { newValue in
                guard draft != nil else { return }
                draft!.exercises[exerciseIndex].sets[setIndex] = newValue
            }
        )
    }

    private func addSet(exerciseIndex: Int) {
        guard draft != nil else { return }
        let nextOrder = (draft!.exercises[exerciseIndex].sets.map(\.order).max() ?? 0) + 1
        draft!.exercises[exerciseIndex].sets.append(LoggedSet(order: nextOrder, weight: 0, reps: 0, distance: nil, seconds: nil))
    }

    private func deleteSet(exerciseIndex: Int, setIndex: Int) {
        guard draft != nil else { return }
        draft!.exercises[exerciseIndex].sets.remove(at: setIndex)
        renumberSets(exerciseIndex: exerciseIndex)
    }

    private func renumberSets(exerciseIndex: Int) {
        guard draft != nil else { return }
        let sorted = draft!.exercises[exerciseIndex].sets.sorted { $0.order < $1.order }
        var updated: [LoggedSet] = []
        updated.reserveCapacity(sorted.count)
        for (idx, set) in sorted.enumerated() {
            var copy = set
            copy.order = idx + 1
            updated.append(copy)
        }
        draft!.exercises[exerciseIndex].sets = updated
    }

    private func save() {
        guard var workout = draft else { return }
        guard !isSaving else { return }

        let trimmedName = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        workout.name = trimmedName.isEmpty ? workout.name : trimmedName

        let setCount = workout.exercises.flatMap(\.sets).count
        if setCount == 0 {
            errorMessage = "Workout must contain at least one set."
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
                        errorMessage = "All completed cardio sets must have distance, time, or count."
                        return
                    }
                } else {
                    if set.weight < 0 || set.reps <= 0 {
                        errorMessage = "All sets must have weight and reps."
                        return
                    }
                }
            }
        }

        isSaving = true
        errorMessage = nil

        Task { @MainActor in
            await logStore.upsert(workout)
            dataManager.setLoggedWorkouts(logStore.workouts)
            isSaving = false
            Haptics.notify(.success)
            dismiss()
        }
    }

    private func deleteWorkout() {
        Task { @MainActor in
            await logStore.delete(id: workoutId)
            dataManager.setLoggedWorkouts(logStore.workouts)
            Haptics.notify(.success)
            dismiss()
        }
    }
}

private struct LoggedExerciseEditorCard: View {
    let exerciseIndex: Int
    let exercise: LoggedExercise
    let setBinding: (Int) -> Binding<LoggedSet>
    let onAddSet: () -> Void
    let onDeleteSet: (Int) -> Void

    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
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

                Button {
                    onAddSet()
                    Haptics.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Set")
                            .font(Theme.Typography.captionBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Capsule().fill(Theme.Colors.accentSecondary))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(exercise.sets.indices, id: \.self) { sIndex in
                    LoggedSetEditorRow(
                        order: exercise.sets[sIndex].order,
                        set: setBinding(sIndex),
                        weightUnit: weightUnit,
                        cardioConfig: config,
                        onDelete: {
                            onDeleteSet(sIndex)
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
        HStack(spacing: Theme.Spacing.sm) {
            Text("#\(order)")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 34, alignment: .leading)
                .monospacedDigit()

            if let cardioConfig {
                cardioField(kind: cardioConfig.primary, countLabel: cardioConfig.countLabel)
                cardioField(kind: cardioConfig.secondary, countLabel: cardioConfig.countLabel)
            } else {
                field(title: weightUnit, text: $weightText, keyboard: .decimalPad, focus: .weight)
                    .onChange(of: weightText) { _, _ in commit() }

                field(title: "reps", text: $repsText, keyboard: .numberPad, focus: .reps)
                    .onChange(of: repsText) { _, _ in commit() }
            }

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.error)
                    .frame(width: 28, height: 28)
                    .background(Theme.Colors.error.opacity(0.12))
                    .cornerRadius(Theme.CornerRadius.small)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.surface.opacity(0.20))
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
