import SwiftUI

enum GymSelection: Hashable {
    case allGyms
    case unassigned
    case gym(UUID)
}

struct GymSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let gyms: [GymProfile]
    let selected: GymSelection
    let showAllGyms: Bool
    let showUnassigned: Bool
    let lastUsedGymId: UUID?
    let showLastUsed: Bool
    let showAddNew: Bool
    let onSelect: (GymSelection) -> Void
    let onAddNew: (() -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        if showAllGyms {
                            optionRow(
                                title: "All gyms",
                                subtitle: "Combine all locations",
                                icon: "globe.americas.fill",
                                tint: Theme.Colors.accentSecondary,
                                selection: .allGyms
                            )
                        }

                        if showUnassigned {
                            optionRow(
                                title: "Unassigned",
                                subtitle: "No gym tagged",
                                icon: "mappin.slash",
                                tint: Theme.Colors.textTertiary,
                                selection: .unassigned
                            )
                        }

                        if showLastUsed,
                           let lastUsedGymId,
                           let lastUsedGym = gyms.first(where: { $0.id == lastUsedGymId }) {
                            optionRow(
                                title: "Last used",
                                subtitle: lastUsedGym.name,
                                icon: "clock.fill",
                                tint: Theme.Colors.accent,
                                selection: .gym(lastUsedGym.id)
                            )
                        }

                        if !gyms.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("Gyms")
                                    .font(Theme.Typography.captionBold)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .padding(.horizontal, Theme.Spacing.sm)

                                ForEach(gyms) { gym in
                                    optionRow(
                                        title: gym.name,
                                        subtitle: gym.address,
                                        icon: "mappin.and.ellipse",
                                        tint: Theme.Colors.accent,
                                        selection: .gym(gym.id)
                                    )
                                }
                            }
                        } else if !showAddNew {
                            ContentUnavailableView(
                                "No gyms yet",
                                systemImage: "mappin.and.ellipse",
                                description: Text("Add a gym profile first.")
                            )
                        }

                        if showAddNew {
                            Button {
                                onAddNew?()
                            } label: {
                                HStack(spacing: Theme.Spacing.md) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(Theme.Colors.accent)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Add New Gym")
                                            .font(Theme.Typography.headline)
                                            .foregroundColor(Theme.Colors.textPrimary)
                                        Text("Create a profile and assign immediately")
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.textSecondary)
                                    }

                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                                .padding(Theme.Spacing.lg)
                                .glassBackground(elevation: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func optionRow(
        title: String,
        subtitle: String?,
        icon: String,
        tint: Color,
        selection: GymSelection
    ) -> some View {
        Button {
            onSelect(selection)
            dismiss()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                Spacer()

                if selected == selection {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.Colors.accent)
                }
            }
            .padding(Theme.Spacing.lg)
            .glassBackground(elevation: 1)
        }
        .buttonStyle(.plain)
    }
}
