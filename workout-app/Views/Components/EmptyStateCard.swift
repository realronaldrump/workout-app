import SwiftUI

/// Unified empty-state card used throughout the app.
/// Two display modes: icon variant (with colored icon box) and simple variant (text only).
/// Uses brand typography for a polished, intentional look.
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
                VStack(spacing: Theme.Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [tint.opacity(0.16), tint.opacity(0.02)],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: 46
                                )
                            )
                            .frame(width: 88, height: 88)
                        Circle()
                            .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                            .frame(width: 64, height: 64)
                        Image(systemName: icon)
                            .font(Theme.Iconography.title2Strong)
                            .foregroundStyle(tint)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityHidden(true)

                    textContent
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            } else {
                textContent
            }
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: elevation)
        .accessibilityElement(children: .combine)
    }

    private var textContent: some View {
        VStack(alignment: icon != nil ? .center : .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(2)
        }
    }
}
