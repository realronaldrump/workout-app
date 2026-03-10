import SwiftUI

/// Unified empty-state card used throughout the app.
/// Two display modes: icon variant (with colored icon box) and simple variant (text only).
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
        Group {
            if let icon {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Image(systemName: icon)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(tint)
                        .cornerRadius(Theme.CornerRadius.large)
                        .accessibilityHidden(true)

                    textContent

                    Spacer(minLength: 0)
                }
            } else {
                textContent
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: elevation)
        .accessibilityElement(children: .combine)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}
