import SwiftUI

struct HighlightItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let tint: Color
    let action: (() -> Void)?
}

struct HighlightCardView: View {
    let item: HighlightItem

    var body: some View {
        Group {
            if let action = item.action {
                Button(
                    action: {
                        Haptics.selection()
                        action()
                    },
                    label: {
                        content
                    }
                )
                .buttonStyle(PressableCardButtonStyle())
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                IconTile(systemImage: item.icon, tint: item.tint, size: 26)
                Text(item.title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
            }

            Text(item.value)
                .font(Theme.Typography.title4)
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            // Tinted leading edge ties the card to the insight's color.
            LinearGradient(
                colors: [item.tint.opacity(0.10), item.tint.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))
        }
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title): \(item.value)\(item.subtitle.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(item.action != nil ? .isButton : [])
        .accessibilityHint(item.action != nil ? "Double tap for details" : "")
    }
}

struct HighlightsSectionView: View {
    let title: String
    let items: [HighlightItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(title.uppercased())
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .tracking(1.2)
                .padding(.leading, 4)

            if items.isEmpty {
                EmptyHighlightsView()
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(items) { item in
                        HighlightCardView(item: item)
                    }
                }
            }
        }
    }
}

struct EmptyHighlightsView: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Highlights appear after a few sessions.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}
