import SwiftUI

struct GymProfilesView: View {
    @EnvironmentObject var gymProfilesManager: GymProfilesManager

    @State private var showingAddSheet = false
    @State private var editingGym: GymProfile?
    @State private var showingDeleteAlert = false
    @State private var gymToDelete: GymProfile?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Keep Progress Clean")
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("Tag workouts by gym to avoid misleading trends caused by different equipment.")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)

                    NavigationLink(destination: GymBulkAssignView()) {
                        HStack {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.Colors.accent)
                                .cornerRadius(6)

                            VStack(alignment: .leading) {
                                Text("Bulk Assign Gyms")
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("Tag historical workouts")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding()
                        .softCard(elevation: 1)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if gymProfilesManager.gyms.isEmpty {
                        ContentUnavailableView(
                            "No gyms yet",
                            systemImage: "mappin.and.ellipse",
                            description: Text("Add your first gym profile.")
                        )
                        .padding(.top, Theme.Spacing.xl)
                    } else {
                        VStack(spacing: Theme.Spacing.md) {
                            ForEach(gymProfilesManager.sortedGyms) { gym in
                                gymRow(for: gym)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle("Gym Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            GymProfileEditorView(mode: .create) { name, address, latitude, longitude in
                _ = gymProfilesManager.addGym(
                    name: name,
                    address: address,
                    latitude: latitude,
                    longitude: longitude
                )
            }
        }
        .sheet(item: $editingGym) { gym in
            GymProfileEditorView(mode: .edit(gym)) { name, address, latitude, longitude in
                gymProfilesManager.updateGym(
                    id: gym.id,
                    name: name,
                    address: address,
                    latitude: latitude,
                    longitude: longitude
                )
            }
        }
        .alert("Delete Gym?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let gym = gymToDelete {
                    gymProfilesManager.deleteGym(gym)
                }
                gymToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                gymToDelete = nil
            }
        } message: {
            Text("Deleting this gym will unassign workouts currently tagged with it.")
        }
    }

    private func gymRow(for gym: GymProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(gym.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                if let address = gym.address, !address.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text(address)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }

            Spacer()

            Menu {
                Button("Edit") {
                    editingGym = gym
                }
                Button("Delete", role: .destructive) {
                    gymToDelete = gym
                    showingDeleteAlert = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}

private struct GymProfileEditorView: View {
    enum Mode: Identifiable {
        case create
        case edit(GymProfile)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let gym): return gym.id.uuidString
            }
        }

        var title: String {
            switch self {
            case .create: return "New Gym"
            case .edit: return "Edit Gym"
            }
        }
    }

    @Environment(\.dismiss) var dismiss
    let mode: Mode
    let onSave: (String, String?, Double?, Double?) -> Void

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var latitude: String = ""
    @State private var longitude: String = ""

    init(mode: Mode, onSave: @escaping (String, String?, Double?, Double?) -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let gym) = mode {
            _name = State(initialValue: gym.name)
            _address = State(initialValue: gym.address ?? "")
            _latitude = State(initialValue: gym.latitude.map { String($0) } ?? "")
            _longitude = State(initialValue: gym.longitude.map { String($0) } ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    TextField("Gym name", text: $name)
                        .textInputAutocapitalization(.words)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.surface.opacity(0.6))
                        .cornerRadius(Theme.CornerRadius.medium)

                    TextField("Address (optional)", text: $address)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.surface.opacity(0.6))
                        .cornerRadius(Theme.CornerRadius.medium)

                    HStack(spacing: Theme.Spacing.md) {
                        TextField("Latitude", text: $latitude)
                            .keyboardType(.decimalPad)
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.surface.opacity(0.6))
                            .cornerRadius(Theme.CornerRadius.medium)

                        TextField("Longitude", text: $longitude)
                            .keyboardType(.decimalPad)
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.surface.opacity(0.6))
                            .cornerRadius(Theme.CornerRadius.medium)
                    }

                    Button {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }
                        onSave(trimmedName, sanitized(address), parseDouble(latitude), parseDouble(longitude))
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
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func sanitized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}
