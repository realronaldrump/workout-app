import SwiftUI

struct QuickStartView: View {
    let exerciseName: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager

    @State private var workoutName: String
    @State private var selectedGymId: UUID?
    @State private var showingGymPicker = false
    @State private var showingReplaceAlert = false
    @State private var isCustomizing = false
    @FocusState private var isNameFocused: Bool

    init(exerciseName: String?) {
        self.exerciseName = exerciseName
        _workoutName = State(initialValue: Self.defaultWorkoutName(for: exerciseName))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let active = sessionManager.activeSession {
                    activeSessionSection(active)
                } else {
                    readySection
                }

                customizationSection

                if sessionManager.activeSession != nil {
                    Section {
                        Button("Start New Instead", systemImage: "arrow.triangle.2.circlepath", role: .destructive) {
                            showingReplaceAlert = true
                        }
                    } footer: {
                        Text("Starting over permanently discards the current in-progress session.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AdaptiveBackground())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(sessionManager.activeSession == nil ? "Quick Start" : "Workout in Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isNameFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                AppPrimaryButton(
                    title: sessionManager.activeSession == nil ? "Start Workout" : "Resume Workout",
                    systemImage: sessionManager.activeSession == nil ? "bolt.fill" : "play.fill"
                ) {
                    if sessionManager.activeSession == nil {
                        startNewSession()
                    } else {
                        resumeCurrentSession()
                    }
                }
                .contentColumn(maxWidth: 640, alignment: .center)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(.bar)
            }
        }
        .presentationDragIndicator(.visible)
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

        return Section("Current Session") {
            LabeledContent {
                Text(active.startedAt, style: .timer)
                    .monospacedDigit()
            } label: {
                Label(active.name, systemImage: "bolt.fill")
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            LabeledContent("Progress", value: "\(exerciseCount) exercises · \(setCount) sets")
        }
    }

    private var readySection: some View {
        Section("Ready to Go") {
            LabeledContent("Workout", value: resolvedWorkoutName)

            if let exerciseName, !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LabeledContent("First Exercise", value: exerciseName)
            }

            LabeledContent("Gym", value: selectedGymLabel)
        }
    }

    private var customizationSection: some View {
        Section {
            DisclosureGroup("Customize Workout", isExpanded: $isCustomizing) {
                TextField("Workout name", text: $workoutName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { isNameFocused = false }

                Button {
                    isNameFocused = false
                    showingGymPicker = true
                    Haptics.selection()
                } label: {
                    LabeledContent {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(selectedGymLabel)
                            Image(systemName: "chevron.right")
                                .font(Theme.Typography.caption)
                                .accessibilityHidden(true)
                        }
                    } label: {
                        Label("Gym", systemImage: "mappin.and.ellipse")
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: Theme.Layout.minimumTapTarget)
                .accessibilityHint("Opens gym selection")
            }
        } footer: {
            Text("You can change the workout name and gym later from the active workout.")
        }
    }

    private var gymPicker: some View {
        GymSelectionSheet(
            title: "Choose Gym",
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
            return "No Gym"
        }
        return name
    }

    private func resumeCurrentSession() {
        sessionManager.isPresentingSessionUI = true
        Haptics.selection()
        dismiss()
    }

    private func startNewSession() {
        isNameFocused = false
        Task { @MainActor in
            if sessionManager.activeSession != nil {
                await sessionManager.discardDraft()
            }
            sessionManager.startSession(
                name: resolvedWorkoutName,
                gymProfileId: selectedGymId,
                preselectedExercise: exerciseName
            )
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
