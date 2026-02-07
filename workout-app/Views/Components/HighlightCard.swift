import SwiftUI

struct HighlightItem: Identifiable {
    let id = UUID()
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
                .buttonStyle(PlainButtonStyle())
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: item.icon)
                    .foregroundColor(item.tint)
                Text(item.title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
            }

            Text(item.value)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(2)

            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(elevation: 2)
    }
}

struct HighlightsSectionView: View {
    let title: String
    let items: [HighlightItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(title)
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            if items.isEmpty {
                EmptyHighlightsView()
            } else {
                VStack(spacing: Theme.Spacing.md) {
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
