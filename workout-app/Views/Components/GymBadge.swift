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
            return Theme.Colors.textPrimary
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
                .font(Theme.Typography.caption2Bold)
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.tag, style: .continuous)
                .fill(style == .assigned ? Theme.Colors.panelStrong : tint.opacity(Theme.Opacity.mediumFill))
        )
    }
}
