import SwiftUI

struct FrequencyCoverageLeaderboard: View {
    let insights: [FrequencyInsight]
    let highlightedMuscleGroup: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                FrequencyCoverageRow(
                    insight: insight,
                    rank: index + 1,
                    isHighlighted: insight.muscleGroup == highlightedMuscleGroup
                )
            }
        }
    }
}

private struct FrequencyCoverageRow: View {
    let insight: FrequencyInsight
    let rank: Int
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("#\(rank)")
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(isHighlighted ? Theme.Colors.accent : Theme.Colors.textTertiary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill((isHighlighted ? Theme.Colors.accent : Theme.Colors.surfaceRaised).opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.muscleGroup)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(insight.recencyDescription)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(insight.coverageSummary)
                        .font(Theme.Typography.monoSmall)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("\(Int(insight.coveragePercent.rounded()))% coverage")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            GeometryReader { geo in
                let fillWidth = max(6, geo.size.width * insight.coverageRatio)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Theme.Colors.surfaceRaised)

                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHighlighted ? Theme.Colors.accent : Theme.Colors.accentSecondary)
                        .frame(width: fillWidth)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
            }
            .frame(height: 12)
        }
        .padding(Theme.Spacing.md)
        .background(isHighlighted ? Theme.Colors.accentTint : Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .stroke(
                    isHighlighted ? Theme.Colors.accent.opacity(0.18) : Theme.Colors.border,
                    lineWidth: 1
                )
        )
    }
}
