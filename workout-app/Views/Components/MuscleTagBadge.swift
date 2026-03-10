import SwiftUI

struct MuscleTagBadge: View {
    let tag: MuscleTag

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tag.iconName)
                .font(Theme.Typography.microLabel)
            Text(tag.displayName)
                .font(Theme.Typography.metricLabel)
                .lineLimit(1)
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
    }
}
