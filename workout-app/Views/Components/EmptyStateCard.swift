import SwiftUI

/// Unified empty-state panel: what is missing and what to do about it, left aligned
/// like the rest of the log. An optional symbol sits above the title.
struct EmptyStateCard: View {
    let title: String
    let message: String
    let icon: String?
    let tint: Color
    let elevation: CGFloat

    init(
        title: String,
        message: String,
        icon: String? = nil,
        tint: Color = Theme.Colors.textTertiary,
        elevation: CGFloat = 1
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.tint = tint
        self.elevation = elevation
    }

    init(
        icon: String,
        tint: Color,
        title: String,
        message: String,
        elevation: CGFloat = 1
    ) {
        self.init(
            title: title,
            message: message,
            icon: icon,
            tint: tint,
            elevation: elevation
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let icon {
                Image(systemName: icon)
                    .font(Theme.Iconography.title2)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Typography.sectionHeader2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .softCard(elevation: elevation)
        .accessibilityElement(children: .combine)
    }
}
