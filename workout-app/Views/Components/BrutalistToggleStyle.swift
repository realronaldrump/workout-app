import SwiftUI

/// A themed wrapper around the native switch so accessibility retains the Switch trait,
/// keyboard behavior, and platform-standard interaction feedback.
struct AppToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) {
            configuration.label
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(Theme.Colors.accent)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .softCard(elevation: 0)
    }
}
