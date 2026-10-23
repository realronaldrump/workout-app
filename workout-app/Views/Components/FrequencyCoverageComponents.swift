import SwiftUI

/// Muscle groups ordered by how many tracked weeks they were trained, as ruled rows
/// with a thin ink bar for the share of weeks covered.
struct FrequencyCoverageLeaderboard: View {
    let insights: [FrequencyInsight]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                FrequencyCoverageRow(insight: insight)
                    .ledgerRow(showsRule: index > 0)
            }
        }
    }
}

private struct FrequencyCoverageRow: View {
    let insight: FrequencyInsight

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.muscleGroup)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(insight.recencyDescription)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Text(insight.coverageSummary)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Theme.Colors.rule)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Theme.Colors.textPrimary)
                        .frame(width: max(4, geo.size.width * insight.coverageRatio))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
