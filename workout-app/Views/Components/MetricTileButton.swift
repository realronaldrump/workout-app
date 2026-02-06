import SwiftUI

/// A standardized tappable wrapper for metric tiles/cards.
/// - Full-card hit target
/// - Neubrutalist press-into-shadow animation
/// - Haptic feedback on tap
/// - Optional chevron affordance (no copy)
struct MetricTileButton<Content: View>: View {
    enum ChevronPlacement {
        case none
        case topTrailing
        case bottomTrailing
    }

    let isEnabled: Bool
    let chevronPlacement: ChevronPlacement
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        isEnabled: Bool = true,
        chevronPlacement: ChevronPlacement = .topTrailing,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isEnabled = isEnabled
        self.chevronPlacement = chevronPlacement
        self.action = action
        self.content = content
    }

    var body: some View {
        Button {
            guard isEnabled else { return }
            Haptics.selection()
            action()
        } label: {
            content()
                .overlay(alignment: chevronAlignment) {
                    if chevronPlacement != .none {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .padding(Theme.Spacing.md)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(MetricTilePressStyle(isEnabled: isEnabled))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .disabled(!isEnabled)
    }

    private var chevronAlignment: Alignment {
        switch chevronPlacement {
        case .none:
            return .topTrailing
        case .topTrailing:
            return .topTrailing
        case .bottomTrailing:
            return .bottomTrailing
        }
    }
}

/// Neubrutalist press style: card translates into its own shadow on press.
private struct MetricTilePressStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled
        configuration.label
            .offset(
                x: isPressed ? 2 : 0,
                y: isPressed ? 2 : 0
            )
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}
