import SwiftUI

struct MuscleTagBadge: View {
    let tag: MuscleTag

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tag.iconName)
                .font(.system(size: 11, weight: .semibold))
            Text(tag.displayName)
                .font(Theme.Typography.metricLabel)
                .lineLimit(1)
        }
        .foregroundColor(tag.tint)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .fill(tag.tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .strokeBorder(tag.tint.opacity(0.6), lineWidth: 2)
        )
    }
}

