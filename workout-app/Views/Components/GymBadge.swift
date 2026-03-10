import SwiftUI

enum GymBadgeStyle {
    case assigned
    case unassigned
    case deleted
}

struct GymBadge: View {
    let text: String
    let style: GymBadgeStyle

    private var tint: Color {
        switch style {
        case .assigned:
            return Theme.Colors.accent
        case .unassigned:
            return Theme.Colors.textTertiary
        case .deleted:
            return Theme.Colors.warning
        }
    }

    private var icon: String {
        switch style {
        case .assigned:
            return "mappin.and.ellipse"
        case .unassigned:
            return "mappin.slash"
        case .deleted:
            return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(Theme.Typography.microLabel)
            Text(text)
                .font(Theme.Typography.metricLabel)
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tint.opacity(0.10))
        )
        .overlay(
            Capsule()
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }
}
