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

/// Shimmer animation modifier.
struct SkeletonModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            Theme.Colors.surface.opacity(0.6),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: -geo.size.width * 0.3 + phase * (geo.size.width * 1.6))
                    .clipped()
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
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
