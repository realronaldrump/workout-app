import SwiftUI

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.captionBold)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Colors.accent : Theme.Colors.surface)
                .foregroundColor(isSelected ? .white : Theme.Colors.textPrimary)
                .cornerRadius(Theme.CornerRadius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.border, lineWidth: 1)
                )
        }
    }
}
