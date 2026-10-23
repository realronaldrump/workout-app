import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String?
    let icon: String
    let color: Color
    var onTap: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Keep tiles visually consistent while giving text enough vertical room
    // (prevents top/bottom clipping on metric screens).
    private let tileHeight: CGFloat = 104

    var body: some View {
        Group {
            if let onTap {
                MetricTileButton(action: onTap, content: { cardContent })
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) { valueContent }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) { valueContent }
            }

            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Theme.Spacing.lg + 2)
        .padding(.trailing, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(minHeight: tileHeight, alignment: .bottomLeading)
        .statChipChrome(tint: color, cornerRadius: Theme.CornerRadius.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var valueContent: some View {
        Text(value)
            .font(Theme.Typography.metric)
            .foregroundColor(Theme.Colors.textPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
            .allowsTightening(true)
            .contentTransition(.numericText())

        if let subtitle = subtitle {
            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilityLabel: String {
        if let subtitle {
            return "\(title), \(value) \(subtitle)"
        }
        return "\(title), \(value)"
    }
}
