import SwiftUI

struct ProgramArchiveListView: View {
    @EnvironmentObject private var programStore: ProgramStore
    @State private var pendingDeletePlan: ProgramPlan?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            if programStore.archivedPlans.isEmpty {
                ContentUnavailableView(
                    "No Archived Programs",
                    systemImage: "archivebox",
                    description: Text("Archived programs will appear here once you replace or archive an active plan.")
                )
                .padding(.horizontal, Theme.Spacing.xl)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(programStore.archivedPlans, id: \.id) { plan in
                            archivedRow(plan)
                        }
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
        }
        .navigationTitle("Archived Plans")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete archived plan?", isPresented: deleteAlertBinding, presenting: pendingDeletePlan) { plan in
            Button("Cancel", role: .cancel) {
                pendingDeletePlan = nil
            }
            Button("Delete", role: .destructive) {
                programStore.deleteArchivedPlan(planId: plan.id)
                pendingDeletePlan = nil
                Haptics.selection()
            }
        } message: { plan in
            Text("This permanently removes “\(plan.name)” from archive history.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletePlan != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletePlan = nil
                }
            }
        )
    }

    private func archivedRow(_ plan: ProgramPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("\(plan.goal.title) • \(plan.daysPerWeek) days/week")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if let archivedAt = plan.archivedAt {
                        Text("Archived \(archivedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(Theme.Typography.microcopy)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(round(plan.adherenceToDate * 100)))%")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("adherence (due)")
                        .font(Theme.Typography.microcopy)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                Button {
                    programStore.restoreArchivedPlan(planId: plan.id)
                    Haptics.selection()
                } label: {
                    Text("Restore Plan")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    pendingDeletePlan = plan
                    Haptics.selection()
                } label: {
                    Text("Delete")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.error)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}
