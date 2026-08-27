import SwiftUI

/// Interaction primitives for the analytics drill-down features.
/// Presentation uses the existing Warm Precision card and button treatments.
enum MetricInteractionRole: String, Hashable {
    case navigate
    case focus
    case revealSource

    var affordanceSymbol: String {
        switch self {
        case .navigate: return "chevron.right"
        case .focus: return "scope"
        case .revealSource: return "arrow.up.forward.square"
        }
    }

    func defaultHint(destination: String) -> String {
        switch self {
        case .navigate, .revealSource:
            return "Opens \(destination)."
        case .focus:
            return "Focuses this page on \(destination)."
        }
    }
}

struct AnalysisTile<Content: View>: View {
    let role: MetricInteractionRole
    let destination: String
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var isSelected = false
    var tint: Color?
    var radius: CGFloat = Theme.CornerRadius.large
    var padding: CGFloat = Theme.Spacing.md
    var showsAffordance = true
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsAffordance {
                    Image(systemName: role.affordanceSymbol)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Theme.Layout.minimumTapTarget)
        }
        .buttonStyle(AppInteractionButtonStyle())
        .softCard(cornerRadius: radius, elevation: 1)
        .overlay {
            if isSelected || tint != nil {
                let resolvedTint = tint ?? Theme.Colors.accent
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        isSelected ? resolvedTint : resolvedTint.opacity(0.35),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel ?? destination)
        .accessibilityHint(accessibilityHint ?? role.defaultHint(destination: destination))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
