import SwiftUI

/// Renders the observations produced by `MetricNarrative`.
///
/// Each row is a claim plus the evidence behind it, so the section reads as
/// analysis rather than decoration. When the data cannot support any claim the
/// whole section disappears instead of padding the screen with placeholder cards.
struct MetricInsightList: View {

    let insights: [MetricInsight]
    let tint: Color
    var title: String = "What stands out"

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(title)
                    .font(Theme.Typography.sectionHeader2)
                    .foregroundStyle(Theme.Colors.textPrimary)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                        MetricInsightRow(insight: insight, tint: tint)
                            .staggeredAppear(index: index)
                    }
                }
            }
        }
    }
}

struct MetricInsightRow: View {

    let insight: MetricInsight
    let tint: Color

    private var toneColor: Color {
        switch insight.tone {
        case .positive: return Theme.Colors.success
        case .caution: return Theme.Colors.warning
        case .neutral: return tint
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: insight.icon)
                .font(Theme.Iconography.mediumStrong)
                .foregroundStyle(toneColor)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                        .fill(toneColor.opacity(0.13))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.detail)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .fill(Theme.Colors.cardBackground)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.CornerRadius.large,
                bottomLeadingRadius: Theme.CornerRadius.large,
                style: .continuous
            )
            .fill(toneColor.opacity(0.85))
            .frame(width: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .strokeBorder(Theme.Colors.border.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
