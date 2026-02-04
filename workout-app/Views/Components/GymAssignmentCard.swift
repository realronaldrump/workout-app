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

    private var badgeStyle: GymBadgeStyle {
        if currentGymName != nil {
            return .assigned
        }
        return isDeletedGym ? .deleted : .unassigned
    }

    private var helperText: String {
        if isDeletedGym {
            return "This gym was deleted. Reassign to keep history scoped."
        }
        if currentGymName == nil {
            return "Assign a gym to keep progress clean across locations."
        }
        return "Tagged for location-specific tracking."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Gym")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button {
                    showingGymPicker = true
                } label: {
                    HStack(spacing: 6) {
                        GymBadge(text: selectionLabel, style: badgeStyle)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            Text(helperText)
                .font(Theme.Typography.caption)
                .foregroundColor(isDeletedGym ? Theme.Colors.warning : Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 2)
        .sheet(isPresented: $showingGymPicker) {
            GymSelectionSheet(
                title: "Select Gym",
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
                    Text("New Gym")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)

                    TextField("Gym name", text: $name)
                        .textInputAutocapitalization(.words)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.surface.opacity(0.6))
                        .cornerRadius(Theme.CornerRadius.medium)

                    Button {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(Theme.Typography.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.Colors.accent)
                            .foregroundColor(.white)
                            .cornerRadius(Theme.CornerRadius.large)
                    }
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("Add Gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
