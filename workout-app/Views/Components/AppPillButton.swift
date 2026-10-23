import SwiftUI

/// Full-width primary action used at the end of focused flows: an ink capsule.
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
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .font(Theme.Typography.headline)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.primaryControlHeight)
        }
        .buttonStyle(BrandPrimaryButtonStyle())
        .disabled(!isEnabled)
    }
}

/// Solid ink capsule. Disabled drops to the strong neutral step.
struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        let isPressed = configuration.isPressed && isEnabled
        configuration.label
            .foregroundStyle(isEnabled ? Theme.Colors.onAccent : Theme.Colors.textTertiary)
            .padding(.horizontal, Theme.Spacing.lg)
            .background(shape.fill(isEnabled ? Theme.Colors.accent : Theme.Colors.panelStrong))
            .contentShape(shape)
            .opacity(isPressed ? 0.82 : 1)
            .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: isPressed)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: isEnabled)
    }
}

/// Outlined capsule for the second action next to a primary one.
struct BrandSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        configuration.label
            .foregroundStyle(isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            .padding(.horizontal, Theme.Spacing.lg)
            .background(shape.fill(configuration.isPressed ? Theme.Colors.panelStrong : Color.clear))
            .overlay(shape.strokeBorder(Theme.Colors.rule, lineWidth: 1.5))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: configuration.isPressed)
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var backgroundColor: Color {
        switch variant {
        case .accent:
            return Theme.Colors.accent
        case .subtle:
            return Color.clear
        default:
            return Theme.Colors.surface
        }
    }

    private var borderColor: Color {
        switch variant {
        case .accent:
            return Theme.Colors.accent
        case .subtle:
            return Theme.Colors.rule
        default:
            return Theme.Colors.rule
        }
    }

    private var textColor: Color {
        switch variant {
        case .accent:
            return Theme.Colors.onAccent
        case .subtle:
            return Theme.Colors.textSecondary
        case .danger:
            return Theme.Colors.error
        case .neutral:
            return Theme.Colors.textPrimary
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Theme.Typography.captionBold)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(Theme.Typography.subheadlineStrong)
                    .multilineTextAlignment(.center)
            }
            // A pill keeps its words on one line; only accessibility sizes may wrap.
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            .foregroundStyle(textColor)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .surfaceButtonChrome(
                fill: backgroundColor,
                border: borderColor,
                cornerRadius: Theme.CornerRadius.pill
            )
        }
        .buttonStyle(AppInteractionButtonStyle())
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
                    cornerRadius: Theme.CornerRadius.pill
                )
        }
        .buttonStyle(AppInteractionButtonStyle())
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
                icon: Theme.Colors.textPrimary
            )
        }
    }

    var body: some View {
        Button(action: action) {
            labelContent
                .padding(.horizontal, Theme.Spacing.xs)
                .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
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
                icon: Theme.Colors.textPrimary
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
