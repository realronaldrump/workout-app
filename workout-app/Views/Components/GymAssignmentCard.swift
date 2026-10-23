import SwiftUI

struct GymAssignmentCard: View {
    let workout: Workout
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager

    @State private var showingAddGym = false
    @State private var showingGymPicker = false

    private var currentGymId: UUID? {
        annotationsManager.annotation(for: workout.id)?.gymProfileId
    }

    private var currentGymName: String? {
        gymProfilesManager.gymName(for: currentGymId)
    }

    private var isDeletedGym: Bool {
        currentGymId != nil && currentGymName == nil
    }

    private var selectionLabel: String {
        if let name = currentGymName {
            return name
        }
        return isDeletedGym ? "Deleted gym" : "Unassigned"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(title: "Gym")

            Button {
                showingGymPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentGymName ?? (isDeletedGym ? "Deleted gym" : "None assigned"))
                            .font(Theme.Typography.headline)
                            .foregroundStyle(isDeletedGym ? Theme.Colors.warning : Theme.Colors.textPrimary)
                        Text(isDeletedGym
                             ? "Choose a replacement for the deleted gym."
                             : "Assign a gym to compare workouts by location.")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Theme.Spacing.sm)

                    Text(currentGymName == nil ? "Assign" : "Change")
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .underline()
                }
                .ledgerRow()
            }
            .buttonStyle(PressableCardButtonStyle())
            .accessibilityLabel("Gym, \(selectionLabel)")
            .accessibilityHint("Changes the gym for this workout")
        }
        .sheet(isPresented: $showingGymPicker) {
            GymSelectionSheet(
                title: "Select gym",
                gyms: gymProfilesManager.sortedGyms,
                selected: currentSelection,
                showAllGyms: false,
                showUnassigned: true,
                lastUsedGymId: gymProfilesManager.lastUsedGymProfileId,
                showLastUsed: true,
                showAddNew: true,
                onSelect: handleSelection,
                onAddNew: { showingAddGym = true }
            )
        }
        .sheet(isPresented: $showingAddGym) {
            GymQuickAddSheet { name in
                let newGym = gymProfilesManager.addGym(name: name)
                assignGym(newGym.id)
            }
        }
    }

    private var currentSelection: GymSelection {
        if let id = currentGymId {
            return .gym(id)
        }
        return .unassigned
    }

    private func handleSelection(_ selection: GymSelection) {
        switch selection {
        case .unassigned:
            assignGym(nil)
        case .gym(let id):
            assignGym(id)
        case .allGyms:
            break
        }
    }

    private func assignGym(_ gymId: UUID?) {
        annotationsManager.setGym(for: workout.id, gymProfileId: gymId)
        if gymId != nil {
            gymProfilesManager.setLastUsedGymProfileId(gymId)
        }
    }
}

private struct GymQuickAddSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var name: String = ""
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("New gym")
                        .font(Theme.Typography.displayHeroCompact)
                        .foregroundColor(Theme.Colors.textPrimary)

                    TextField("Gym name", text: $name)
                        .font(Theme.Typography.headline)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .frame(minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                                .fill(Theme.Colors.panelInset)
                        )

                    AppPrimaryButton(
                        title: "Save gym",
                        isEnabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    }

                    Spacer()
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Cancel", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }
            }
        }
    }
}
