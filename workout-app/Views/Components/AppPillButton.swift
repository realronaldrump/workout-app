import SwiftUI

/// Full-width primary action used at the end of focused flows.
struct AppPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .font(Theme.Typography.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(BrandPrimaryButtonStyle())
        .disabled(!isEnabled)
    }
}

/// Brand gradient fill with a soft colored glow that settles when pressed.
struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
        let isPressed = configuration.isPressed && isEnabled
        configuration.label
            .foregroundStyle(isEnabled ? Color.white : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.lg)
            .background {
                if isEnabled {
                    shape
                        .fill(Theme.accentGradient)
                        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                        .shadow(
                            color: Theme.Colors.accent.opacity(isPressed ? 0.14 : 0.3),
                            radius: isPressed ? 5 : 12,
                            x: 0,
                            y: isPressed ? 2 : 6
                        )
                } else {
                    shape.fill(Theme.Colors.border.opacity(0.5))
                }
            }
            .contentShape(shape)
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: isEnabled)
    }
}

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
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .surfaceButtonChrome(
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
                .frame(
                    minWidth: Theme.Layout.minimumTapTarget,
                    minHeight: Theme.Layout.minimumTapTarget
                )
                .surfaceButtonChrome(
                    fill: Theme.Colors.surface,
                    cornerRadius: Theme.CornerRadius.large
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Navigation-bar content that keeps the app's lightweight toolbar treatment
/// instead of inheriting iOS's automatic glass button container.
struct AppToolbarItem<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    private let content: Content

    init(
        placement: ToolbarItemPlacement,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.content = content()
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            content
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// Grouped navigation-bar content with the same containerless treatment.
struct AppToolbarItemGroup<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    private let content: Content

    init(
        placement: ToolbarItemPlacement,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.content = content()
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: placement) {
            content
        }
        .sharedBackgroundVisibility(.hidden)
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
