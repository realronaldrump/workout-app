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
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SectionHeading(title: title)

                VStack(spacing: 0) {
                    ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                        MetricInsightRow(insight: insight, tint: tint, showsRule: index > 0)
                    }
                }
            }
        }
    }
}

struct MetricInsightRow: View {

    let insight: MetricInsight
    let tint: Color
    var showsRule = true

    private var toneColor: Color {
        switch insight.tone {
        case .positive: return Theme.Colors.success
        case .caution: return Theme.Colors.warning
        case .neutral: return tint
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            TintMark(tint: toneColor)
                .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[.bottom] - 2 }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(insight.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if insight.id == "coverage" {
                        AppHelpButton(title: "Missing readings", message: insight.detail)
                    }
                }

                if insight.id != "coverage" {
                    Text(insight.detail)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .ledgerRow(showsRule: showsRule)
        .accessibilityElement(children: .contain)
    }
}
