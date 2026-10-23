import Foundation
import SwiftUI

// MARK: - Label Tag

/// A small stamped label for status and context ("Live session", "Workout saved").
/// Sentence case, never tracked out.
struct BrandBandLabel: View {
    let text: String
    var systemImage: String?
    var fill: Color = Theme.Colors.ink
    var textColor: Color = Theme.Colors.onAccent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.microLabel)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Theme.Typography.bandLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.tag, style: .continuous))
    }
}

// MARK: - Hero Panel Background

/// A flat ink panel for the rare surface that should read inverted. Content on top
/// uses `Theme.Colors.onAccent`.
struct HeroCardBackground: View {
    var cornerRadius: CGFloat = Theme.CornerRadius.xlarge
    var watermark: String?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Colors.ink)
            .accessibilityHidden(true)
    }
}

// MARK: - Icon Mark

/// A plain symbol in its meaning color. Tiles, gradients, and glows are gone; the
/// frame keeps rows aligned where icons used to sit in squares.
struct IconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Progress Ring

/// Circular progress with square caps, drawn in a single flat tone.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    var tint: Color = Theme.Colors.accent
    var trackTint: Color = Theme.Colors.panelStrong

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
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                displayedProgress = clamped
            } else {
                withAnimation(Theme.Animation.chartAppear.delay(0.1)) {
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
    let colorIndex: Int
    let delay: Double

    static func random(colorCount: Int) -> ConfettiParticle {
        // Launch in an upward cone, then let gravity bring everything back down.
        let angle = Double.random(in: (-155.0)...(-25.0)) * .pi / 180
        let speed = Double.random(in: 380...820)
        let width = Double.random(in: 4...6)
        return ConfettiParticle(
            velocityX: cos(angle) * speed,
            velocityY: sin(angle) * speed,
            spin: Double.random(in: -540...540),
            width: width,
            height: Double.random(in: 12...18),
            colorIndex: Int.random(in: 0..<max(colorCount, 1)),
            delay: Double.random(in: 0...0.12)
        )
    }
}

/// A one-shot burst of tiny bumper plates drawn with a single Canvas. Increment
/// `trigger` to fire. Does nothing under Reduce Motion and never intercepts touches.
struct ConfettiBurst: View {
    let trigger: Int
    var colors: [Color] = [
        Theme.Colors.plateRed,
        Theme.Colors.plateBlue,
        Theme.Colors.plateYellow,
        Theme.Colors.plateGreen,
        Theme.Colors.ink
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
                    let path = Path(roundedRect: rect, cornerRadius: 1.5)
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

/// A section title in the display face with an optional trailing accessory.
struct SectionHeading<Accessory: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var subtitle: String?
    var help: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: Theme.Spacing.sm))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.sectionHeader2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.sm) }
            if let help { AppHelpButton(title: title, message: help) }
            accessory()
        }
    }
}

extension SectionHeading where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, help: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.help = help
        self.accessory = { EmptyView() }
    }
}

// MARK: - Pressable Style

/// Press feedback for large tappable surfaces: a quick dim and a small settle.
struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: configuration.isPressed)
    }
}
