import SwiftUI

/// Custom toggle styling to avoid the stock iOS switch look and stay consistent with the app theme.
struct BrutalistToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
            Haptics.selection()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                configuration.label
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer(minLength: 0)

                BrutalistSwitch(isOn: configuration.isOn)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .glassBackground(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
    }
}

private struct BrutalistSwitch: View {
    let isOn: Bool

    var body: some View {
        let trackWidth: CGFloat = 46
        let trackHeight: CGFloat = 26
        let inset: CGFloat = 3
        let thumbSize: CGFloat = trackHeight - (inset * 2)

        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .fill(isOn ? Theme.Colors.accent : Theme.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                )

            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .fill(Theme.Colors.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                )
                .frame(width: thumbSize, height: thumbSize)
                .padding(inset)
                .shadow(
                    color: Color.black.opacity(Theme.Colors.shadowOpacity),
                    radius: 0,
                    x: 2,
                    y: 2
                )
        }
        .frame(width: trackWidth, height: trackHeight)
        .animation(Theme.Animation.quick, value: isOn)
        .accessibilityHidden(true)
    }
}

