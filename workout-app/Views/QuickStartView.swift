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

        return Section {
            QuickStartHero(band: "In progress", bandIcon: "bolt.fill", title: active.name) {
                HStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: 6) {
                        LivePulseDot(color: Theme.Colors.success, size: 6)
                            .frame(width: 12, height: 12)
                        Text(active.startedAt, style: .timer)
                            .monospacedDigit()
                    }
                    .modifier(QuickStartHeroChip())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Elapsed time")

                    Text("\(SharedFormatters.count(exerciseCount, "exercise")) · \(SharedFormatters.count(setCount, "set"))")
                        .modifier(QuickStartHeroChip())
                }
            }
            .quickStartHeroRow()
        }
    }

    private var readySection: some View {
        Section {
            QuickStartHero(band: "Ready to go", bandIcon: "flame.fill", title: resolvedWorkoutName) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.sm) {
                        readyChips
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        readyChips
                    }
                }
            }
            .quickStartHeroRow()
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var readyChips: some View {
        Label(selectedGymLabel, systemImage: "mappin.and.ellipse")
            .modifier(QuickStartHeroChip())

        if let exerciseName, !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label("Starts with \(exerciseName)", systemImage: "dumbbell.fill")
                .modifier(QuickStartHeroChip())
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

/// Brand hero shown at the top of Quick Start.
private struct QuickStartHero<Detail: View>: View {
    let band: String
    let bandIcon: String
    let title: String
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            BrandBandLabel(
                text: band,
                systemImage: bandIcon,
                fill: .white,
                textColor: Theme.Colors.onHeroAccent
            )

            Text(title)
                .font(Theme.Typography.displayHeroCompact)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)

            detail()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(HeroCardBackground(watermark: "bolt.fill"))
    }
}

private struct QuickStartHeroChip: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Typography.captionBold)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.22)))
    }
}

private extension View {
    /// Lets the hero sit edge-to-edge in the form instead of inside a grouped cell.
    func quickStartHeroRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .padding(.vertical, Theme.Spacing.xs)
    }
}
