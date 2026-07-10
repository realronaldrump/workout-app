import SwiftUI

nonisolated struct TrendDelta: Hashable, Sendable {
    let current: Double
    let previous: Double
    let higherIsBetter: Bool

    init?(current: Double, previous: Double, higherIsBetter: Bool = true) {
        guard previous != 0, current.isFinite, previous.isFinite else { return nil }
        self.current = current
        self.previous = previous
        self.higherIsBetter = higherIsBetter
    }

    var percentChange: Double {
        ((current - previous) / abs(previous)) * 100
    }

    var isFlat: Bool {
        abs(percentChange) < 0.5
    }

    @MainActor var tint: Color {
        guard !isFlat else { return Theme.Colors.textTertiary }
        let improved = higherIsBetter ? percentChange > 0 : percentChange < 0
        return improved ? Theme.Colors.success : Theme.Colors.warning
    }

    var arrowName: String {
        guard !isFlat else { return "arrow.right" }
        return percentChange > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    var label: String {
        guard !isFlat else { return "0%" }
        let rounded = Int(percentChange.rounded())
        return rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
    }
}

struct DeltaTag: View {
    let delta: TrendDelta
    var suffix: String? = nil
    var tintOverride: Color? = nil

    private var tint: Color { tintOverride ?? delta.tint }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: delta.arrowName)
                .accessibilityHidden(true)

            Text(delta.label)

            if let suffix, !suffix.isEmpty {
                Text(suffix)
                    .foregroundStyle(tint.opacity(0.82))
            }
        }
        .font(Theme.Typography.caption2Bold)
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Capsule().fill(tint.opacity(Theme.Opacity.mediumFill)))
        .accessibilityElement(children: .combine)
    }
}

struct Sparkline: View {
    let values: [Double]
    var tint: Color = Theme.Colors.accent
    var areaFill = true

    var body: some View {
        GeometryReader { geometry in
            let points = normalizedPoints(in: geometry.size)

            if points.count >= 2 {
                if areaFill {
                    areaPath(points: points, size: geometry.size)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.20), tint.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                linePath(points: points)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let finiteValues = values.filter(\.isFinite)
        guard finiteValues.count >= 2,
              let minimum = finiteValues.min(),
              let maximum = finiteValues.max(),
              size.width > 0,
              size.height > 0 else {
            return []
        }

        let span = maximum - minimum
        let step = size.width / CGFloat(finiteValues.count - 1)

        return finiteValues.enumerated().map { index, value in
            let normalized = span == 0 ? 0.5 : (value - minimum) / span
            return CGPoint(
                x: CGFloat(index) * step,
                y: size.height - (CGFloat(normalized) * size.height)
            )
        }
    }

    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func areaPath(points: [CGPoint], size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}

struct InlineStat: View {
    let icon: String
    let value: String
    var label: String? = nil
    var tint: Color = Theme.Colors.textTertiary

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(Theme.Typography.caption)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(value)
                .font(Theme.Typography.captionStrong)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? value)
        .accessibilityValue(label == nil ? "" : value)
    }
}
