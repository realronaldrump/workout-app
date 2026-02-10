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

    init(exerciseName: String?) {
        self.exerciseName = exerciseName
        _workoutName = State(initialValue: exerciseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Quick Start")
                                .font(Theme.Typography.title)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(exerciseName == nil ? "Start a session" : "Build a session around \(exerciseName ?? "")")
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        Spacer()

                        AppPillButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                            dismiss()
                        }
                    }

                    if let active = sessionManager.activeSession {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Session in progress")
                                        .font(Theme.Typography.captionBold)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                    Text(active.name)
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button {
                                    sessionManager.isPresentingSessionUI = true
                                    Haptics.selection()
                                    dismiss()
                                } label: {
                                    Text("Resume")
                                        .font(Theme.Typography.captionBold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, Theme.Spacing.md)
                                        .padding(.vertical, Theme.Spacing.xs)
                                        .background(Capsule().fill(Theme.Colors.accent))
                                }
                                .buttonStyle(.plain)
                            }

                            Text("Starting a new session will discard the current one.")
                                .font(Theme.Typography.microcopy)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 2)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Workout Name")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)

                        TextField("e.g. Upper Body", text: $workoutName)
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
                    .softCard(elevation: 2)

                    Button {
                        showingGymPicker = true
                        Haptics.selection()
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.Colors.accent)
                                .cornerRadius(Theme.CornerRadius.small)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Gym")
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Text(selectedGymLabel)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 2)
                    }
                    .buttonStyle(.plain)

                    Button {
                        let trimmedName = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if sessionManager.activeSession != nil {
                            showingReplaceAlert = true
                            return
                        }
                        startNewSession(name: trimmedName)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Start Session")
                                .font(Theme.Typography.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding()
                        .background(Theme.Colors.accent)
                        .cornerRadius(Theme.CornerRadius.large)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if selectedGymId == nil {
                selectedGymId = gymProfilesManager.lastUsedGymProfileId
            }
            if workoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                workoutName = "Workout"
            }
        }
        .sheet(isPresented: $showingGymPicker) {
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
                    case .unassigned:
                        selectedGymId = nil
                    case .gym(let id):
                        selectedGymId = id
                    case .allGyms:
                        selectedGymId = nil
                    }
                },
                onAddNew: nil
            )
        }
        .alert("Replace active session?", isPresented: $showingReplaceAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                let trimmedName = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
                startNewSession(name: trimmedName)
            }
        } message: {
            Text("This will discard your current in-progress session.")
        }
    }

    private var selectedGymLabel: String {
        if let id = selectedGymId, let name = gymProfilesManager.gymName(for: id) {
            return name
        }
        return "Unassigned"
    }

    private func startNewSession(name: String) {
        Task { @MainActor in
            await sessionManager.discardDraft()
            sessionManager.startSession(
                name: name,
                gymProfileId: selectedGymId,
                preselectedExercise: exerciseName
            )
            sessionManager.isPresentingSessionUI = true
            Haptics.notify(.success)
            dismiss()
        }
    }
}
