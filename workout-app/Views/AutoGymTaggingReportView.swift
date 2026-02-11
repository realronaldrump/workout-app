import SwiftUI

struct AutoGymTaggingReport: Identifiable {
    let id = UUID()
    let attempted: Int
    let assigned: Int
    let skippedNoMatchingWorkout: Int
    let skippedNoRoute: Int
    let skippedNoGymMatch: Int
    let skippedGymsMissingLocation: Int
    let items: [AutoGymTaggingItem]
}

struct AutoGymTaggingItem: Identifiable {
    enum Status: Hashable {
        case assigned(gymName: String, distanceMeters: Int)
        case skipped(reason: String)
    }

    let id: UUID
    let workoutName: String
    let workoutDate: Date
    let status: Status

    static func assigned(workout: Workout, gymName: String, distanceMeters: Int) -> AutoGymTaggingItem {
        AutoGymTaggingItem(
            id: workout.id,
            workoutName: workout.name,
            workoutDate: workout.date,
            status: .assigned(gymName: gymName, distanceMeters: distanceMeters)
        )
    }

    static func skipped(workout: Workout, reason: String) -> AutoGymTaggingItem {
        AutoGymTaggingItem(
            id: workout.id,
            workoutName: workout.name,
            workoutDate: workout.date,
            status: .skipped(reason: reason)
        )
    }
}

struct AutoGymTaggingReportView: View {
    @Environment(\.dismiss) private var dismiss
    let report: AutoGymTaggingReport

    private var skippedItems: [AutoGymTaggingItem] {
        report.items.filter {
            if case .skipped = $0.status { return true }
            return false
        }
    }

    private var assignedItems: [AutoGymTaggingItem] {
        report.items.filter {
            if case .assigned = $0.status { return true }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        summaryCard

                        if !skippedItems.isEmpty {
                            resultsSection(title: "Needs Attention", items: skippedItems)
                        }

                        if !assignedItems.isEmpty {
                            resultsSection(title: "Tagged", items: assignedItems)
                        }
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationTitle("Auto Tag Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppPillButton(title: "Done", systemImage: "checkmark", variant: .subtle) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Summary")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                Text("\(report.assigned) / \(report.attempted) tagged")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
            }

            VStack(spacing: Theme.Spacing.sm) {
                summaryRow(label: "Tagged", value: report.assigned)
                summaryRow(label: "No matching Apple Watch workout", value: report.skippedNoMatchingWorkout)
                summaryRow(label: "No route/start location (or route permission unavailable)", value: report.skippedNoRoute)
                summaryRow(label: "No gym within range", value: report.skippedNoGymMatch)
                summaryRow(label: "Gyms missing location data", value: report.skippedGymsMissingLocation)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func summaryRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text("\(value)")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }

    private func resultsSection(title: String, items: [AutoGymTaggingItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(items) { item in
                    row(for: item)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func row(for item: AutoGymTaggingItem) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon(for: item.status))
                .foregroundStyle(color(for: item.status))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.workoutName)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(item.workoutDate.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text(detailText(for: item.status))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .glassBackground(cornerRadius: Theme.CornerRadius.large, elevation: 1)
    }

    private func icon(for status: AutoGymTaggingItem.Status) -> String {
        switch status {
        case .assigned:
            return "checkmark.circle.fill"
        case .skipped:
            return "exclamationmark.triangle.fill"
        }
    }

    private func color(for status: AutoGymTaggingItem.Status) -> Color {
        switch status {
        case .assigned:
            return Theme.Colors.success
        case .skipped:
            return Theme.Colors.warning
        }
    }

    private func detailText(for status: AutoGymTaggingItem.Status) -> String {
        switch status {
        case .assigned(let gymName, let distanceMeters):
            return "Tagged: \(gymName) (\(distanceMeters)m)"
        case .skipped(let reason):
            return reason
        }
    }
}
