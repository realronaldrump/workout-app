import SwiftUI

/// A shimmering placeholder view for loading states.
/// Use `.skeleton()` modifier on any view, or use `SkeletonRect` for standalone placeholders.
struct SkeletonRect: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = Theme.CornerRadius.small

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.Colors.border.opacity(0.35))
            .frame(width: width, height: height)
            .skeleton()
    }
}

/// A low-cost placeholder treatment. Loading screens can contain dozens of skeletons, so
/// this intentionally avoids one GeometryReader and one infinite animation per element.
struct SkeletonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .opacity(0.72)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            .accessibilityHidden(true)
    }
}

/// A multi-row skeleton placeholder mimicking a card's content.
struct SkeletonCard: View {
    var lines: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SkeletonRect(width: 120, height: 14)
            ForEach(0..<lines, id: \.self) { i in
                SkeletonRect(
                    width: i == lines - 1 ? 180 : nil,
                    height: 12
                )
                .frame(maxWidth: i == lines - 1 ? 180 : .infinity, alignment: .leading)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

/// A skeleton that mimics a chart placeholder.
struct SkeletonChart: View {
    var height: CGFloat = Theme.ChartHeight.standard

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SkeletonRect(width: 100, height: 14)
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.border.opacity(0.2))
                .frame(height: height - 40)
                .skeleton()
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

extension View {
    func skeleton() -> some View {
        modifier(SkeletonModifier())
    }
}
