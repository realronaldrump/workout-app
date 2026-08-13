import SwiftUI

struct MuscleTagBadge: View {
    let tag: MuscleTag
    var role: ExerciseMuscleRole?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tag.iconName)
                .font(Theme.Typography.microLabel)
            Text(tag.displayName)
                .font(Theme.Typography.metricLabel)
                .lineLimit(1)
            if let role {
                Text(role == .primary ? "P" : "S")
                    .font(Theme.Typography.microLabel)
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(tag.tint)
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
