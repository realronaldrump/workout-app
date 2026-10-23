import SwiftUI

struct QuickStartView: View {
    let exerciseName: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager

    @State private var workoutName: String
    @State private var selectedGymId: UUID?
    @State private var showingGymPicker = false
    @State private var showingReplaceAlert = false
    @State private var selectedWorkout: Workout?
    @State private var isStartingSession = false
    @FocusState private var isNameFocused: Bool

    init(exerciseName: String?) {
        self.exerciseName = exerciseName
        _workoutName = State(initialValue: Self.defaultWorkoutName(for: exerciseName))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    if let active = sessionManager.activeSession {
                        activeSessionSection(active)
                    } else {
                        readySection
                        if exerciseName == nil && !recentWorkouts.isEmpty { repeatSection }
                        customizationSection
                    }
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xl)
                .contentColumn(maxWidth: 640)
            }
            .background(AdaptiveBackground())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(sessionManager.activeSession == nil ? "New workout" : "Workout in progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isNameFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Spacing.sm) {
                    AppPrimaryButton(
                        title: sessionManager.activeSession == nil ? "Start workout" : "Resume workout",
                        isEnabled: !isStartingSession && !sessionManager.isFinishing
                    ) {
                        if sessionManager.activeSession == nil {
                            startNewSession()
                        } else {
                            resumeCurrentSession()
                        }
                    }

                    if sessionManager.activeSession != nil {
                        Button {
                            showingReplaceAlert = true
                        } label: {
                            Text("Start a new workout instead")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.error)
                                .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .contentColumn(maxWidth: 640, alignment: .center)
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xs)
                .background(Theme.Colors.ground)
            }
        }
        .disabled(isStartingSession || sessionManager.isFinishing)
        .interactiveDismissDisabled(isStartingSession)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Colors.ground)
        .onAppear {
            if selectedGymId == nil {
                selectedGymId = gymProfilesManager.lastUsedGymProfileId
            }
        }
        .sheet(isPresented: $showingGymPicker) {
            gymPicker
        }
        .alert("Replace active session?", isPresented: $showingReplaceAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                startNewSession()
            }
        } message: {
            Text("This permanently discards your current in-progress session and starts \(resolvedWorkoutName).")
        }
    }

    private func activeSessionSection(_ active: ActiveWorkoutSession) -> some View {
        let exerciseCount = active.exercises.count
        let setCount = active.exercises.reduce(0) { $0 + $1.sets.count }

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                LivePulseDot(color: Theme.Colors.success, size: 6)
                    .frame(width: 12, height: 12)
                Text("In progress")
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.success)
            }

            Text(active.name)
                .font(Theme.Typography.displayHero)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.lg) {
                Text(active.startedAt, style: .timer)
                    .font(Theme.Typography.timer)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityLabel("Elapsed time")
                Text("\(SharedFormatters.count(exerciseCount, "exercise")), \(SharedFormatters.count(setCount, "set"))")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var recentWorkouts: [Workout] {
        var seen = Set<String>()
        return dataManager.workouts.sorted { $0.date > $1.date }.filter {
            !$0.exercises.isEmpty && seen.insert($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted
        }.prefix(4).map { $0 }
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(
                title: "Start from",
                help: "Repeating copies the exercises and sets. Mark each set complete as you finish it."
            )

            VStack(spacing: 0) {
                startOption(
                    title: "A blank workout",
                    detail: "Add exercises as you go",
                    isSelected: selectedWorkout == nil,
                    showsRule: false
                ) {
                    selectedWorkout = nil
                    workoutName = Self.defaultWorkoutName(for: exerciseName)
                }

                ForEach(recentWorkouts) { workout in
                    startOption(
                        title: workout.name,
                        detail: "\(SharedFormatters.count(workout.exercises.count, "exercise")), "
                            + "\(SharedFormatters.count(workout.totalSets, "set")), "
                            + workout.date.formatted(date: .abbreviated, time: .omitted),
                        isSelected: selectedWorkout?.id == workout.id,
                        showsRule: true
                    ) {
                        selectedWorkout = workout
                        workoutName = workout.name
                    }
                }
            }
        }
    }

    private func startOption(
        title: String,
        detail: String,
        isSelected: Bool,
        showsRule: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            Haptics.selection()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.sm)
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Theme.Colors.ink : Theme.Colors.rule, lineWidth: 2)
                    if isSelected {
                        Circle()
                            .fill(Theme.Colors.ink)
                            .padding(5)
                    }
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            }
            .ledgerRow(showsRule: showsRule)
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var readySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(resolvedWorkoutName)
                .font(Theme.Typography.displayHero)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(readyDetail)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var readyDetail: String {
        var parts = [selectedGymId == nil ? "No gym set" : "At \(selectedGymLabel)"]
        if let exerciseName, !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("starting with \(exerciseName)")
        }
        return parts.joined(separator: ", ") + "."
    }

    private var customizationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(title: "Details")

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    Text("Name")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 56, alignment: .leading)
                    TextField("Workout name", text: $workoutName)
                        .font(Theme.Typography.headline)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .onSubmit { isNameFocused = false }
                }
                .frame(minHeight: Theme.Layout.minimumTapTarget)
                .ledgerRow(showsRule: false, verticalPadding: Theme.Spacing.sm)

                Button {
                    isNameFocused = false
                    showingGymPicker = true
                    Haptics.selection()
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        Text("Gym")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: 56, alignment: .leading)
                        Text(selectedGymLabel)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer(minLength: Theme.Spacing.sm)
                        Image(systemName: "chevron.right")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                    .ledgerRow(verticalPadding: Theme.Spacing.sm)
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityHint("Opens gym selection")
            }
        }
    }

    private var gymPicker: some View {
        GymSelectionSheet(
            title: "Choose gym",
            gyms: gymProfilesManager.sortedGyms,
            selected: selectedGymId.map { GymSelection.gym($0) } ?? .unassigned,
            showAllGyms: false,
            showUnassigned: true,
            lastUsedGymId: gymProfilesManager.lastUsedGymProfileId,
            showLastUsed: gymProfilesManager.lastUsedGymProfileId != nil,
            showAddNew: false,
            onSelect: { selection in
                switch selection {
                case .unassigned, .allGyms:
                    selectedGymId = nil
                case .gym(let id):
                    selectedGymId = id
                }
            },
            onAddNew: nil
        )
    }

    private var resolvedWorkoutName: String {
        let trimmed = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultWorkoutName(for: exerciseName) : trimmed
    }

    private var selectedGymLabel: String {
        guard let selectedGymId,
              let name = gymProfilesManager.gymName(for: selectedGymId) else {
            return "None"
        }
        return name
    }

    private func resumeCurrentSession() {
        sessionManager.isPresentingSessionUI = true
        Haptics.selection()
        dismiss()
    }

    private func startNewSession() {
        guard !isStartingSession, !sessionManager.isFinishing else { return }
        isStartingSession = true
        isNameFocused = false
        Task { @MainActor in
            defer { isStartingSession = false }
            if sessionManager.activeSession != nil {
                guard await sessionManager.discardDraft() else { return }
            }
            if let selectedWorkout {
                WorkoutRepeatHelper.repeatWorkout(
                    selectedWorkout,
                    gymProfileId: selectedGymId,
                    weightIncrement: 2.5,
                    sessionManager: sessionManager,
                    dataManager: dataManager
                )
                sessionManager.updateSessionName(resolvedWorkoutName)
            } else {
                let lastSet = exerciseName.flatMap { name in
                    dataManager.getExerciseHistory(for: name).max(by: { $0.date < $1.date })?
                        .sets.min { $0.setOrder < $1.setOrder }
                }
                sessionManager.startSession(
                    name: resolvedWorkoutName,
                    gymProfileId: selectedGymId,
                    preselectedExercise: exerciseName,
                    initialSetPrefill: lastSet.map {
                        SetPrefill(weight: $0.weight, reps: $0.reps > 0 ? $0.reps : nil,
                                   distance: $0.distance > 0 ? $0.distance : nil,
                                   seconds: $0.seconds > 0 ? $0.seconds : nil)
                    }
                )
            }
            sessionManager.saveImmediately()
            sessionManager.isPresentingSessionUI = true
            Haptics.notify(.success)
            dismiss()
        }
    }

    private static func defaultWorkoutName(for exerciseName: String?) -> String {
        if let exerciseName {
            let trimmed = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Morning Workout"
        case 12..<17: return "Afternoon Workout"
        case 17..<22: return "Evening Workout"
        default: return "Workout"
        }
    }
}
