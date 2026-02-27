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
        let trackWidth: CGFloat = 48
        let trackHeight: CGFloat = 28
        let inset: CGFloat = 3
        let thumbSize: CGFloat = trackHeight - (inset * 2)

        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Theme.Colors.accent : Theme.Colors.border.opacity(0.3))

            Circle()
                .fill(Color.white)
                .frame(width: thumbSize, height: thumbSize)
                .padding(inset)
                .shadow(
                    color: Color.black.opacity(0.12),
                    radius: 2,
                    y: 1
                )
        }
        .frame(width: trackWidth, height: trackHeight)
        .animation(Theme.Animation.quick, value: isOn)
        .accessibilityHidden(true)
    }
}

