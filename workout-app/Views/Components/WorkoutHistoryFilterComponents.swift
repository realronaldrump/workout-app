import SwiftUI

enum HistoryFilterSheet: String, Identifiable {
    case location
    case exercise
    case duration

    var id: String { rawValue }
}

enum HistoryDateWindow: CaseIterable, Hashable {
    case allTime
    case last30Days
    case last90Days
    case lastYear

    var title: String {
        switch self {
        case .allTime: return "All Time"
        case .last30Days: return "30 Days"
        case .last90Days: return "90 Days"
        case .lastYear: return "1 Year"
        }
    }

    var summaryLabel: String {
        switch self {
        case .allTime: return "All-time archive"
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

struct HistoryLocationOption: Identifiable, Hashable {
    enum Kind: Hashable {
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

struct HistoryExerciseOption: Identifiable, Hashable {
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

enum HistoryDurationBand: CaseIterable, Identifiable, Hashable {
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
        case .longHaul: return "Long Haul"
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

struct HistorySummaryMetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title.uppercased())
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(tint)
                .tracking(0.8)

            Text(value)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

struct HistoryFilterLauncherCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(isActive ? 0.18 : 0.1))
                            .frame(width: 38, height: 38)

                        Image(systemName: systemImage)
                            .font(Theme.Iconography.mediumStrong)
                            .foregroundStyle(tint)
                    }

                    Spacer(minLength: Theme.Spacing.sm)

                    if isActive {
                        Text("On")
                            .font(Theme.Typography.metricLabel)
                            .foregroundStyle(tint)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(
                                Capsule()
                                    .fill(tint.opacity(0.12))
                            )
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title.uppercased())
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(0.9)

                    Text(value)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                    .fill(isActive ? tint.opacity(0.08) : Theme.Colors.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                    .strokeBorder(
                        isActive ? tint.opacity(0.28) : Theme.Colors.border.opacity(0.55),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(AppInteractionButtonStyle())
    }
}
