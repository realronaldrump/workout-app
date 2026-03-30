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
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
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
                text: Theme.Colors.accent,
                icon: Theme.Colors.accent
            )
        case .danger:
            return AppToolbarButtonPalette(
                text: Theme.Colors.error,
                icon: Theme.Colors.error
            )
        case .subtle:
            return AppToolbarButtonPalette(
                text: Theme.Colors.textSecondary,
                icon: Theme.Colors.textSecondary
            )
        case .neutral:
            return AppToolbarButtonPalette(
                text: Theme.Colors.textPrimary,
                icon: Theme.Colors.accent
            )
        }
    }

    var body: some View {
        Button(action: action) {
            labelContent
                .padding(.horizontal, Theme.Spacing.xs)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(AppInteractionButtonStyle())
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var labelContent: some View {
        if let systemImage {
            ViewThatFits(in: .horizontal) {
                toolbarLabel(systemImage: systemImage, showsTitle: true)
                toolbarLabel(systemImage: systemImage, showsTitle: false)
            }
        } else {
            Text(title)
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(palette.text)
                .lineLimit(1)
        }
    }

    private func toolbarLabel(systemImage: String, showsTitle: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(palette.icon)

            if showsTitle {
                Text(title)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
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
                text: Theme.Colors.accent,
                icon: Theme.Colors.accent
            )
        case .danger:
            return AppToolbarButtonPalette(
                text: Theme.Colors.error,
                icon: Theme.Colors.error
            )
        case .subtle:
            return AppToolbarButtonPalette(
                text: Theme.Colors.textSecondary,
                icon: Theme.Colors.textSecondary
            )
        case .neutral:
            return AppToolbarButtonPalette(
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
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(AppInteractionButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct AppToolbarButtonPalette {
    let text: Color
    let icon: Color
}
