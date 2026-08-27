import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String?
    let icon: String
    let color: Color
    var onTap: (() -> Void)?

    @State private var isAppearing = false

    // Keep tiles visually consistent while giving text enough vertical room
    // (prevents top/bottom clipping on metric screens).
    private let tileHeight: CGFloat = 128

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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Iconography.title3Strong)
                .foregroundColor(color)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.Typography.metric)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .contentTransition(.numericText())

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(height: tileHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(color.opacity(0.06))
        )
        .glassBackground(opacity: 0.1, cornerRadius: Theme.CornerRadius.large, elevation: 2)
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 8)
        .onAppear {
            withAnimation(Theme.Animation.spring) {
                isAppearing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let subtitle {
            return "\(title), \(value) \(subtitle)"
        }
        return "\(title), \(value)"
    }
}
