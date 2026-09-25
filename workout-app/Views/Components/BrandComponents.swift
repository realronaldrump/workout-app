import Foundation
import SwiftUI

// MARK: - Brand Band

/// The app icon's signature move: tight uppercase type knocked out of an
/// electric-blue band. Reserved for small, high-signal labels.
struct BrandBandLabel: View {
    let text: String
    var systemImage: String?
    var fill: Color = Theme.Colors.brandBand
    var textColor: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.microLabel)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Theme.Typography.bandLabel)
                .textCase(.uppercase)
                .tracking(1.1)
                .lineLimit(1)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(fill, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

// MARK: - Hero Card Background

/// Deep brand gradient with a soft highlight and an optional oversized symbol
/// watermark. White content sits on top.
struct HeroCardBackground: View {
    var cornerRadius: CGFloat = Theme.CornerRadius.xlarge
    var watermark: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // Decorations live in overlays so they never influence layout, and a single
        // clip keeps the oversized watermark inside the card's corners.
        shape
            .fill(Theme.heroGradient)
            .overlay {
                RadialGradient(
                    colors: [Color.white.opacity(0.28), .clear],
                    center: UnitPoint(x: 0.9, y: 0.05),
                    startRadius: 0,
                    endRadius: 220
                )
            }
            .overlay(alignment: .bottomTrailing) {
                if let watermark {
                    Image(systemName: watermark)
                        .font(.system(size: 150, weight: .black))
                        .foregroundStyle(Color.white.opacity(0.07))
                        .rotationEffect(.degrees(-12))
                        .offset(x: 34, y: 34)
                }
            }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: Theme.Colors.accent.opacity(0.28), radius: 18, x: 0, y: 10)
            .accessibilityHidden(true)
    }
}

// MARK: - Icon Tile

/// A gradient-filled rounded square carrying a white SF Symbol, in the spirit of
/// Settings icons but with a little more light.
struct IconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [tint.opacity(0.78), tint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: tint.opacity(0.3), radius: 4, x: 0, y: 2)
            .accessibilityHidden(true)
    }
}

// MARK: - Progress Ring

/// Animated circular progress with round caps. Progress above 1 stays full and
/// picks up a glow so over-achievement reads as a win instead of a clamp.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    var tint: Color = Theme.Colors.accent
    var trackTint: Color = Theme.Colors.border.opacity(0.5)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedProgress: Double = 0

    private var clamped: Double {
        min(max(progress.isFinite ? progress : 0, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackTint, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: displayedProgress)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.65), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(displayedProgress, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: progress >= 1 ? tint.opacity(0.55) : .clear, radius: lineWidth * 0.6)
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                displayedProgress = clamped
            } else {
                withAnimation(Theme.Animation.chartAppear.delay(0.15)) {
                    displayedProgress = clamped
                }
            }
        }
        .onChange(of: clamped) { _, newValue in
            withAnimation(reduceMotion ? nil : Theme.Animation.spring) {
                displayedProgress = newValue
            }
        }
    }
}

// MARK: - Live Pulse

/// A small "live" indicator: a solid dot with a soft expanding halo.
/// Static under Reduce Motion.
struct LivePulseDot: View {
    var color: Color = Theme.Colors.success
    var size: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.45))
                .frame(width: size, height: size)
                .scaleEffect(isPulsing ? 2.6 : 1)
                .opacity(isPulsing ? 0 : 0.9)

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2.6, height: size * 2.6)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Confetti

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let velocityX: Double
    let velocityY: Double
    let spin: Double
    let width: Double
    let height: Double
    let isCircle: Bool
    let colorIndex: Int
    let delay: Double

    static func random(colorCount: Int) -> ConfettiParticle {
        // Launch in an upward cone, then let gravity bring everything back down.
        let angle = Double.random(in: (-155.0)...(-25.0)) * .pi / 180
        let speed = Double.random(in: 380...820)
        let isCircle = Double.random(in: 0...1) < 0.3
        let width = isCircle ? Double.random(in: 6...9) : Double.random(in: 6...10)
        return ConfettiParticle(
            velocityX: cos(angle) * speed,
            velocityY: sin(angle) * speed,
            spin: Double.random(in: -540...540),
            width: width,
            height: isCircle ? width : Double.random(in: 10...16),
            isCircle: isCircle,
            colorIndex: Int.random(in: 0..<max(colorCount, 1)),
            delay: Double.random(in: 0...0.12)
        )
    }
}

/// A one-shot confetti burst drawn with a single Canvas. Increment `trigger`
/// to fire. Does nothing under Reduce Motion and never intercepts touches.
struct ConfettiBurst: View {
    let trigger: Int
    var colors: [Color] = [
        Theme.Colors.accent,
        Theme.Colors.gold,
        Theme.Colors.success,
        Theme.Colors.accentSecondary,
        Theme.Colors.accentTertiary,
        Theme.Colors.triceps
    ]
    var particleCount: Int = 44
    var duration: Double = 2.2
    /// Vertical launch point as a fraction of the available height.
    var originY: Double = 0.32

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles: [ConfettiParticle] = []
    @State private var startDate: Date?
    @State private var burstID = 0

    var body: some View {
        let start = startDate
        let currentParticles = particles
        let palette = colors
        let totalDuration = duration
        let launchY = originY

        TimelineView(.animation(minimumInterval: nil, paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let elapsed = timeline.date.timeIntervalSince(start)
                guard elapsed >= 0, elapsed <= totalDuration, !palette.isEmpty else { return }
                let originX = Double(size.width) / 2
                let originYPoint = Double(size.height) * launchY
                let gravity = 1_100.0

                for particle in currentParticles {
                    let time = max(elapsed - particle.delay, 0)
                    let x = originX + particle.velocityX * time
                    let y = originYPoint + particle.velocityY * time + 0.5 * gravity * time * time
                    let fadeStart = totalDuration * 0.55
                    let fade = elapsed < fadeStart
                        ? 1.0
                        : max(0, 1 - (elapsed - fadeStart) / (totalDuration - fadeStart))

                    var particleContext = context
                    particleContext.opacity = fade
                    particleContext.translateBy(x: CGFloat(x), y: CGFloat(y))
                    particleContext.rotate(by: .degrees(particle.spin * time))
                    let rect = CGRect(
                        x: -particle.width / 2,
                        y: -particle.height / 2,
                        width: particle.width,
                        height: particle.height
                    )
                    let path = particle.isCircle
                        ? Path(ellipseIn: rect)
                        : Path(roundedRect: rect, cornerRadius: 1.5)
                    particleContext.fill(path, with: .color(palette[particle.colorIndex % palette.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            fire()
        }
    }

    private func fire() {
        guard !reduceMotion else { return }
        burstID += 1
        let currentBurst = burstID
        particles = (0..<particleCount).map { _ in ConfettiParticle.random(colorCount: colors.count) }
        startDate = Date()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration + 0.2))
            guard burstID == currentBurst else { return }
            startDate = nil
            particles = []
        }
    }
}

// MARK: - Section Heading

/// Consistent section title with an optional trailing accessory.
struct SectionHeading<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.sectionHeader2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            accessory()
        }
    }
}

extension SectionHeading where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = { EmptyView() }
    }
}

// MARK: - Pressable Card Style

/// Press feedback for large tappable cards: a gentle squish and dim.
struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
