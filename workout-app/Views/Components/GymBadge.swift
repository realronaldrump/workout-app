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
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(Theme.Typography.metricLabel)
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .strokeBorder(tint.opacity(0.6), lineWidth: 2)
        )
    }
}
