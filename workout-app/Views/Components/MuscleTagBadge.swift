import SwiftUI

struct MuscleTagBadge: View {
    let tag: MuscleTag
    var role: ExerciseMuscleRole?

    var body: some View {
        HStack(spacing: 5) {
            // Identity rides on the dot; the label stays in ink so light muscle
            // hues (shoulders, calves) never become unreadable text.
            Circle()
                .fill(tag.tint)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(tag.displayName)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
            if let role {
                Text(role == .primary ? "Primary" : "Secondary")
                    .font(Theme.Typography.microLabel)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tag.tint.opacity(0.10))
        )
        .overlay(
            Capsule()
                .strokeBorder(tag.tint.opacity(0.25), lineWidth: 1)
        )
        .accessibilityLabel(
            role.map { "\(tag.displayName), \($0.displayName) muscle" } ?? tag.displayName
        )
    }
}
