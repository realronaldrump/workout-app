import SwiftUI

/// Surfaces key data-driven insights from the DataCorrelationEngine
/// directly on the home screen. All insights are purely data-derived.
struct DataInsightCards: View {
    let frequencyInsights: [FrequencyInsight]

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
        let mostFrequent = frequencyInsights.max(by: { $0.frequencyPerWeek < $1.frequencyPerWeek })
        let leastFrequent = frequencyInsights.min(by: { $0.frequencyPerWeek < $1.frequencyPerWeek })

        if let mostFrequent {
            items.append(DataInsightItem(
                icon: "chart.bar.xaxis",
                tint: Theme.Colors.accent,
                title: "Most frequent muscle group",
                detail: "\(mostFrequent.muscleGroup): \(mostFrequent.weeksHit)/\(mostFrequent.totalWeeks) weeks (\(String(format: "%.1f", mostFrequent.frequencyPerWeek))x/week)"
            ))
        }

        if let leastFrequent,
           leastFrequent.muscleGroup != mostFrequent?.muscleGroup {
            items.append(DataInsightItem(
                icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                tint: Theme.Colors.accentSecondary,
                title: "Least frequent muscle group",
                detail: "\(leastFrequent.muscleGroup): \(leastFrequent.weeksHit)/\(leastFrequent.totalWeeks) weeks (\(String(format: "%.1f", leastFrequent.frequencyPerWeek))x/week)"
            ))
        }

        if let sampleWindow = frequencyInsights.first?.totalWeeks, !frequencyInsights.isEmpty {
            items.append(DataInsightItem(
                icon: "list.bullet.rectangle",
                tint: Theme.Colors.textSecondary,
                title: "Frequency coverage",
                detail: "\(frequencyInsights.count) muscle groups tracked across the last \(sampleWindow) weeks"
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
}

private struct DataInsightRow: View {
    let item: DataInsightItem

    var body: some View {
        content
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
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.detail)")
    }
}
