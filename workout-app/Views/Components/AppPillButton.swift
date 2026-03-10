import SwiftUI

/// In-content pill buttons used for compact secondary actions.
struct AppPillButton: View {
    enum Variant {
        case neutral
        case subtle
        case accent
        case danger
    }

    let title: String
    var systemImage: String? = nil
    var variant: Variant = .neutral
    var action: () -> Void

    private var backgroundColor: Color {
        switch variant {
        case .accent:
            return Theme.Colors.accent
        default:
            return Theme.Colors.surface
        }
    }

    private var textColor: Color {
        switch variant {
        case .accent:
            return .white
        case .subtle:
            return Theme.Colors.textSecondary
        case .danger:
            return Theme.Colors.error
        case .neutral:
            return Theme.Colors.textPrimary
        }
    }

    private var iconColor: Color {
        switch variant {
        case .accent:
            return .white
        case .danger:
            return Theme.Colors.error
        case .subtle:
            return Theme.Colors.textTertiary
        case .neutral:
            return Theme.Colors.accent
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(iconColor)
                }

                Text(title)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(textColor)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .brutalistButtonChrome(
                fill: backgroundColor,
                cornerRadius: Theme.CornerRadius.large
            )
        }
        .buttonStyle(.plain)
    }
}

struct AppPillIconButton: View {
    let systemImage: String
    var accessibilityLabel: String
    var tint: Color = Theme.Colors.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Typography.subheadlineBold)
                .foregroundStyle(tint)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .brutalistButtonChrome(
                    fill: Theme.Colors.surface,
                    cornerRadius: Theme.CornerRadius.large
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct AppToolbarButton: View {
    enum Variant {
        case neutral
        case subtle
        case accent
        case danger
    }

    let title: String
    var systemImage: String? = nil
    var variant: Variant = .neutral
    var action: () -> Void

    private var palette: AppToolbarButtonPalette {
        switch variant {
        case .accent:
            return AppToolbarButtonPalette(
                fill: Theme.Colors.accentTint.blended(with: Theme.Colors.surface, amount: 0.2),
                border: Theme.Colors.accent.opacity(0.22),
                text: Theme.Colors.accent,
                icon: Theme.Colors.accent
            )
        case .danger:
            return AppToolbarButtonPalette(
                fill: Theme.Colors.error.opacity(0.08).blended(with: Theme.Colors.surface, amount: 0.14),
                border: Theme.Colors.error.opacity(0.18),
                text: Theme.Colors.error,
                icon: Theme.Colors.error
            )
        case .subtle:
            return AppToolbarButtonPalette(
                fill: Theme.Colors.surface.blended(with: Theme.Colors.background, amount: 0.34),
                border: Theme.Colors.border.opacity(0.9),
                text: Theme.Colors.textSecondary,
                icon: Theme.Colors.textSecondary
            )
        case .neutral:
            return AppToolbarButtonPalette(
                fill: Theme.Colors.surface.blended(with: Theme.Colors.background, amount: 0.2),
                border: Theme.Colors.border.opacity(0.88),
                text: Theme.Colors.textPrimary,
                icon: Theme.Colors.accent
            )
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(palette.icon)
                }

                Text(title)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(palette.text)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 38)
            .toolbarButtonChrome(fill: palette.fill, border: palette.border)
        }
        .buttonStyle(AppInteractionButtonStyle())
    }
}

struct AppToolbarIconButton: View {
    let systemImage: String
    var accessibilityLabel: String
    var variant: AppToolbarButton.Variant = .neutral
    var action: () -> Void

    private var palette: AppToolbarButtonPalette {
        switch variant {
        case .accent:
            return AppToolbarButtonPalette(
                fill: Theme.Colors.accentTint.blended(with: Theme.Colors.surface, amount: 0.2),
                border: Theme.Colors.accent.opacity(0.22),
                text: Theme.Colors.accent,
                icon: Theme.Colors.accent
            )
        case .danger:
            return AppToolbarButtonPalette(
                fill: Theme.Colors.error.opacity(0.08).blended(with: Theme.Colors.surface, amount: 0.14),
                border: Theme.Colors.error.opacity(0.18),
                text: Theme.Colors.error,
                icon: Theme.Colors.error
            )
        case .subtle:
            return AppToolbarButtonPalette(
                fill: Theme.Colors.surface.blended(with: Theme.Colors.background, amount: 0.34),
                border: Theme.Colors.border.opacity(0.9),
                text: Theme.Colors.textSecondary,
                icon: Theme.Colors.textSecondary
            )
        case .neutral:
            return AppToolbarButtonPalette(
                fill: Theme.Colors.surface.blended(with: Theme.Colors.background, amount: 0.2),
                border: Theme.Colors.border.opacity(0.88),
                text: Theme.Colors.textPrimary,
                icon: Theme.Colors.accent
            )
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Typography.subheadlineBold)
                .foregroundStyle(palette.icon)
                .frame(width: 38, height: 38)
                .toolbarButtonChrome(fill: palette.fill, border: palette.border)
        }
        .buttonStyle(AppInteractionButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct AppToolbarButtonPalette {
    let fill: Color
    let border: Color
    let text: Color
    let icon: Color
}
