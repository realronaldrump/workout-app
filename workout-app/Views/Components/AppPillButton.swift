import SwiftUI

/// Small brutalist pill buttons used in toolbars and headers to avoid the default
/// iOS "blue text" button look and match the app's theme (border + hard shadow).
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(iconColor)
                }

                Text(title)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(textColor)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Capsule().fill(backgroundColor))
            .overlay(
                Capsule()
                    .strokeBorder(Theme.Colors.border, lineWidth: 2)
            )
            .shadow(
                color: Color.black.opacity(Theme.Colors.shadowOpacity),
                radius: 0,
                x: 2,
                y: 2
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Capsule().fill(Theme.Colors.surface))
                .overlay(
                    Capsule()
                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                )
                .shadow(
                    color: Color.black.opacity(Theme.Colors.shadowOpacity),
                    radius: 0,
                    x: 2,
                    y: 2
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

