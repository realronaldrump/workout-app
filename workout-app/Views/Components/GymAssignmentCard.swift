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

    private var statusTint: Color {
        switch badgeStyle {
        case .assigned:
            return Theme.Colors.accent
        case .unassigned:
            return Theme.Colors.textTertiary
        case .deleted:
            return Theme.Colors.warning
        }
    }

    private var statusIcon: String {
        switch badgeStyle {
        case .assigned:
            return "mappin.circle.fill"
        case .unassigned:
            return "mappin.slash.circle.fill"
        case .deleted:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusTitle: String {
        if currentGymName != nil {
            return "Assigned gym"
        }
        return isDeletedGym ? "Gym needs reassignment" : "No gym assigned"
    }

    private var statusDetail: String {
        if isDeletedGym {
            return "The original gym was removed. Pick a current location."
        }
        if currentGymName == nil {
            return "Set one if you want this workout grouped by location."
        }
        return "Included in this location's workout history."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Gym")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Button {
                showingGymPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                            .fill(statusTint.opacity(0.12))
                            .frame(width: 48, height: 48)

                        Image(systemName: statusIcon)
                            .font(Theme.Iconography.title3Strong)
                            .foregroundStyle(statusTint)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text(statusDetail)
                            .font(Theme.Typography.caption)
                            .foregroundColor(
                                isDeletedGym ? Theme.Colors.warning : Theme.Colors.textSecondary
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Theme.Spacing.sm)

                    VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                        GymBadge(text: selectionLabel, style: badgeStyle)
                        Image(systemName: "chevron.down")
                            .font(Theme.Iconography.mediumStrong)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                        .fill(Theme.Colors.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                        .strokeBorder(statusTint.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
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
                    AppToolbarButton(title: "Cancel", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }
            }
        }
    }
}
