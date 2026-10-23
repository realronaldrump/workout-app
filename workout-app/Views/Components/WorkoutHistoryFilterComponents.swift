import SwiftUI

enum HistoryFilterSheet: String, Identifiable {
    case location
    case exercise
    case duration

    var id: String { rawValue }
}

enum HistorySummarySheet: String, Identifiable {
    case locations

    var id: String { rawValue }
}

nonisolated enum HistoryDateWindow: CaseIterable, Hashable, Sendable {
    case allTime
    case last30Days
    case last90Days
    case lastYear

    var title: String {
        switch self {
        case .allTime: return "All time"
        case .last30Days: return "30 Days"
        case .last90Days: return "90 Days"
        case .lastYear: return "1 Year"
        }
    }

    var summaryLabel: String {
        switch self {
        case .allTime: return "All time"
        case .last30Days: return "Last 30 days"
        case .last90Days: return "Last 90 days"
        case .lastYear: return "Last 12 months"
        }
    }

    func contains(_ date: Date, referenceDate: Date, calendar: Calendar) -> Bool {
        guard self != .allTime else { return true }

        let component: Calendar.Component
        let value: Int

        switch self {
        case .allTime:
            return true
        case .last30Days:
            component = .day
            value = -30
        case .last90Days:
            component = .day
            value = -90
        case .lastYear:
            component = .year
            value = -1
        }

        guard let cutoff = calendar.date(byAdding: component, value: value, to: referenceDate) else {
            return true
        }
        return date >= cutoff
    }
}

nonisolated struct HistoryLocationOption: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case gym(UUID)
        case unassigned
        case deleted
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let sortOrder: Int

    var id: String {
        switch kind {
        case .gym(let id):
            return "gym-\(id.uuidString)"
        case .unassigned:
            return "unassigned"
        case .deleted:
            return "deleted"
        }
    }

    static func == (lhs: HistoryLocationOption, rhs: HistoryLocationOption) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated struct HistoryExerciseOption: Identifiable, Hashable, Sendable {
    let name: String
    let workoutCount: Int
    let subtitle: String

    var id: String { name.lowercased() }

    static func == (lhs: HistoryExerciseOption, rhs: HistoryExerciseOption) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated enum HistoryDurationBand: CaseIterable, Identifiable, Hashable, Sendable {
    case quick
    case standard
    case extended
    case longHaul

    var id: String { title }

    var title: String {
        switch self {
        case .quick: return "Quick"
        case .standard: return "Standard"
        case .extended: return "Extended"
        case .longHaul: return "Long haul"
        }
    }

    var subtitle: String {
        switch self {
        case .quick: return "Up to 30 minutes"
        case .standard: return "31 to 60 minutes"
        case .extended: return "61 to 90 minutes"
        case .longHaul: return "Over 90 minutes"
        }
    }

    func contains(minutes: Int) -> Bool {
        switch self {
        case .quick:
            return minutes <= 30
        case .standard:
            return (31...60).contains(minutes)
        case .extended:
            return (61...90).contains(minutes)
        case .longHaul:
            return minutes > 90
        }
    }
}

nonisolated struct HistoryLocationBreakdownItem: Identifiable, Hashable, Sendable {
    let option: HistoryLocationOption
    let workoutCount: Int
    let lastWorkoutDate: Date

    var id: String { option.id }
}

struct HistoryLocationBreakdownSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let items: [HistoryLocationBreakdownItem]

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                if items.isEmpty {
                    EmptyStateCard(
                        icon: "mappin.slash",
                        tint: Theme.Colors.textTertiary,
                        title: "No locations in view",
                        message: "Try a different date range or clear filters."
                    )
                } else {
                    List {
                        ForEach(items) { item in
                            let layout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
                                : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.md))
                            layout {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text(item.option.title)
                                        .font(Theme.Typography.bodyBold)
                                        .foregroundStyle(Theme.Colors.textPrimary)

                                    Text(workoutCountLabel(item.workoutCount))
                                        .font(Theme.Typography.captionBold)
                                        .foregroundStyle(Theme.Colors.accentSecondary)

                                    if !item.option.subtitle.isEmpty {
                                        Text(item.option.subtitle)
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }

                                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.sm) }

                                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: Theme.Spacing.xs) {
                                    Text("Last workout")
                                        .font(Theme.Typography.metricLabel)
                                        .foregroundStyle(Theme.Colors.textTertiary)

                                    Text(item.lastWorkoutDate.formatted(.dateTime.month(.abbreviated).day().year()))
                                        .font(Theme.Typography.captionBold)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .padding(.vertical, Theme.Spacing.xs)
                            .listRowBackground(Theme.Colors.elevated)
                            .listRowSeparatorTint(Theme.Colors.border)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Done", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func workoutCountLabel(_ count: Int) -> String {
        "\(count) workout" + (count == 1 ? "" : "s")
    }
}
