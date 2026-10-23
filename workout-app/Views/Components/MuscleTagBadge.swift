import SwiftUI

struct MuscleTagBadge: View {
    let tag: MuscleTag
    var role: ExerciseMuscleRole?

    var body: some View {
        HStack(spacing: 5) {
            // Identity rides on the dot; the label stays in ink so light muscle
            // hues (shoulders, calves) never become unreadable text.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tag.tint)
                .frame(width: 4, height: 12)
                .accessibilityHidden(true)
            Text(tag.displayName)
                .font(Theme.Typography.caption2Bold)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
            if let role {
                Text(role == .primary ? "Primary" : "Secondary")
                    .font(Theme.Typography.microLabel)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.tag, style: .continuous)
                .fill(Theme.Colors.panelStrong)
        )
        .accessibilityLabel(
            role.map { "\(tag.displayName), \($0.displayName) muscle" } ?? tag.displayName
        )
    }
}
