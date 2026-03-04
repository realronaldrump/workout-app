import SwiftUI

/// Surfaces key data-driven insights from the DataCorrelationEngine
/// directly on the home screen. All insights are purely data-derived.
struct DataInsightCards: View {
    let plateaus: [PlateauAlert]
    let frequencyInsights: [FrequencyInsight]
    let onExerciseTap: (String) -> Void

    var body: some View {
        let items = buildInsightItems()
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("DATA INSIGHTS")
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .tracking(1.2)
                    .padding(.leading, 4)

                ForEach(items) { item in
                    DataInsightRow(item: item)
                }
            }
        }
    }

    private func buildInsightItems() -> [DataInsightItem] {
        var items: [DataInsightItem] = []

        // Plateau alerts (high priority — actionable)
        for plateau in plateaus.prefix(2) {
            items.append(DataInsightItem(
                icon: "chart.line.flattrend.xyaxis",
                tint: Theme.Colors.warning,
                title: "\(plateau.exerciseName) plateau",
                detail: "e1RM flat at ~\(Int(plateau.currentE1RM)) lbs for \(plateau.weeksSinceProgress)w (\(plateau.sessionCount) sessions)",
                action: { onExerciseTap(plateau.exerciseName) }
            ))
        }

        // Under-trained muscle groups
        let underTrained = frequencyInsights.filter { $0.coveragePercent < 50 }.prefix(1)
        for insight in underTrained {
            items.append(DataInsightItem(
                icon: "exclamationmark.triangle",
                tint: Theme.Colors.accentSecondary,
                title: "\(insight.muscleGroup) trained \(insight.weeksHit)/\(insight.totalWeeks) weeks",
                detail: "\(String(format: "%.1f", insight.frequencyPerWeek))x/week — below 1x threshold",
                action: nil
            ))
        }

        return Array(items.prefix(3))
    }
}

private struct DataInsightItem: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let action: (() -> Void)?
}

private struct DataInsightRow: View {
    let item: DataInsightItem

    var body: some View {
        Group {
            if let action = item.action {
                Button(action: {
                    Haptics.selection()
                    action()
                }) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(item.tint)
                .frame(width: 30, height: 30)
                .background(item.tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(item.detail)
                    .font(Theme.Typography.microcopy)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            if item.action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.detail)")
        .accessibilityAddTraits(item.action != nil ? .isButton : [])
    }
}
