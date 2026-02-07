import SwiftUI

struct InsightMoment: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let icon: String
    let tint: Color
    let value: String?
}

struct InsightsStreamView: View {
    let insights: [Insight]
    let moments: [InsightMoment]
    var onInsightTap: ((Insight) -> Void)?

    private var streamItems: [StreamItem] {
        var items: [StreamItem] = []
        let maxCount = max(insights.count, moments.count)

        for index in 0..<maxCount {
            if index < moments.count {
                items.append(.moment(moments[index]))
            }
            if index < insights.count {
                items.append(.insight(insights[index]))
            }
        }

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Insights")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                if !insights.isEmpty {
                    Text("\(insights.count) insights")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.surface.opacity(0.6))
                        .cornerRadius(10)
                }
            }

            if streamItems.isEmpty {
                EmptyInsightsView()
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(streamItems.enumerated()), id: \.offset) { _, item in
                        switch item {
                        case .moment(let moment):
                            InsightMomentCard(moment: moment)
                        case .insight(let insight):
                            InsightCardView(insight: insight) {
                                onInsightTap?(insight)
                            }
                        }
                    }
                }
            }
        }
    }

    private enum StreamItem {
        case moment(InsightMoment)
        case insight(Insight)
    }
}

struct InsightMomentCard: View {
    let moment: InsightMoment

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: moment.icon)
                    .foregroundColor(moment.tint)
                Text(moment.title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                if let value = moment.value {
                    Text(value)
                        .font(Theme.Typography.numberSmall)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
            }

            Text(moment.message)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}
