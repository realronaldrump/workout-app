import SwiftUI
import UIKit

/// Centralized theme system - Dark-ish, Bold, Minimalist with Glassmorphism
enum Theme {
    
    // MARK: - Colors
    
    enum Colors {
        // Background hierarchy (dark-ish, not pure black)
        static let background = Color(red: 0.08, green: 0.08, blue: 0.10)
        static let surface = Color(red: 0.12, green: 0.12, blue: 0.14)
        static let elevated = Color(red: 0.16, green: 0.16, blue: 0.18)
        static let cardBackground = Color(red: 0.14, green: 0.14, blue: 0.16)
        
        // Text hierarchy
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.6)
        static let textTertiary = Color.white.opacity(0.4)
        
        // Accent colors (solid, no gradients)
        static let accent = Color.blue
        static let accentSecondary = Color.cyan
        
        // Semantic colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
        
        // PR/Achievement
        static let gold = Color.yellow
        
        // Muscle groups (solid colors)
        static let push = Color.red
        static let pull = Color.blue
        static let legs = Color.green
        static let core = Color.orange
        static let cardio = Color.purple
        
        // Glassmorphism
        static let glass = Color.white.opacity(0.08)
        static let glassBorder = Color.white.opacity(0.12)
    }
    
    // MARK: - Typography
    
    enum Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 22, weight: .bold, design: .default)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .default)
        static let headline = Font.system(size: 17, weight: .bold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let bodyBold = Font.system(size: 17, weight: .semibold, design: .default)
        static let callout = Font.system(size: 16, weight: .medium, design: .default)
        static let subheadline = Font.system(size: 15, weight: .medium, design: .default)
        static let footnote = Font.system(size: 13, weight: .medium, design: .default)
        static let caption = Font.system(size: 12, weight: .medium, design: .default)
        static let captionBold = Font.system(size: 12, weight: .bold, design: .default)
        
        // Monospaced for numbers
        static let number = Font.system(size: 28, weight: .bold, design: .monospaced)
        static let numberLarge = Font.system(size: 42, weight: .bold, design: .monospaced)
        static let numberSmall = Font.system(size: 17, weight: .bold, design: .monospaced)
        static let metricLarge = Font.system(size: 48, weight: .heavy, design: .monospaced)
        static let metric = Font.system(size: 30, weight: .bold, design: .monospaced)
        static let condensed = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let microcopy = Font.system(size: 13, weight: .regular, design: .rounded)
    }
    
    // MARK: - Animation
    
    enum Animation {
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let chartAppear = SwiftUI.Animation.spring(response: 0.6, dampingFraction: 0.7)
    }
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    
    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xlarge: CGFloat = 24
    }
}

// MARK: - Adaptive Luminance

struct AdaptiveLuminanceKey: EnvironmentKey {
    static let defaultValue: Double = 0.3
}

extension EnvironmentValues {
    var adaptiveLuminance: Double {
        get { self[AdaptiveLuminanceKey.self] }
        set { self[AdaptiveLuminanceKey.self] = newValue }
    }
}

struct AdaptiveBackground: View {
    @Environment(\.adaptiveLuminance) private var luminance
    
    var body: some View {
        let base = Theme.Colors.background
            .blended(with: .white, amount: 0.06 + (luminance * 0.08))
        let highlight = Theme.Colors.elevated
            .blended(with: Theme.Colors.accentSecondary, amount: 0.06 + (luminance * 0.1))
        
        ZStack {
            LinearGradient(
                colors: [base, highlight],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            RadialGradient(
                colors: [
                    Theme.Colors.accent.opacity(0.18 + (luminance * 0.1)),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 320
            )
            
            RadialGradient(
                colors: [
                    Theme.Colors.accentSecondary.opacity(0.12 + (luminance * 0.08)),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glassmorphism Modifier

struct GlassBackground: ViewModifier {
    var opacity: Double = 0.08
    var cornerRadius: CGFloat = Theme.CornerRadius.medium
    var elevation: CGFloat = 1
    @Environment(\.adaptiveLuminance) private var luminance
    
    func body(content: Content) -> some View {
        let baseFill = Theme.Colors.glass
            .blended(with: .white, amount: 0.08 + (luminance * 0.18))
        let border = Theme.Colors.glassBorder
            .blended(with: .white, amount: 0.05 + (luminance * 0.12))
        let shadowOpacity = min(0.35, 0.12 + Double(elevation) * 0.06)
        
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(0.75)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(baseFill.opacity(opacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(border, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: 8 * elevation,
                x: 0,
                y: 6 * elevation
            )
    }
}

extension View {
    func glassBackground(
        opacity: Double = 0.08,
        cornerRadius: CGFloat = Theme.CornerRadius.medium,
        elevation: CGFloat = 1
    ) -> some View {
        modifier(GlassBackground(opacity: opacity, cornerRadius: cornerRadius, elevation: elevation))
    }
    
    func cardStyle() -> some View {
        self
            .padding(Theme.Spacing.lg)
            .glassBackground(elevation: 2)
    }
    
    func animateOnAppear(delay: Double = 0) -> some View {
        modifier(AnimateOnAppearModifier(delay: delay))
    }
}

// MARK: - Color Helpers

extension Color {
    func blended(with color: Color, amount: Double) -> Color {
        let clamped = min(max(amount, 0), 1)
        let (r1, g1, b1, a1) = rgbaComponents()
        let (r2, g2, b2, a2) = color.rgbaComponents()
        
        return Color(
            red: r1 + (r2 - r1) * clamped,
            green: g1 + (g2 - g1) * clamped,
            blue: b1 + (b2 - b1) * clamped,
            opacity: a1 + (a2 - a1) * clamped
        )
    }
    
    private func rgbaComponents() -> (Double, Double, Double, Double) {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue), Double(alpha))
    }
}

struct AnimateOnAppearModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
            .animation(Theme.Animation.spring.delay(delay), value: isVisible)
            .onAppear {
                isVisible = true
            }
    }
}

// MARK: - PR Marker View

struct PRMarkerView: View {
    let date: Date
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.caption2)
            Text("PR")
                .font(Theme.Typography.captionBold)
        }
        .foregroundColor(Theme.Colors.gold)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassBackground(opacity: 0.15, cornerRadius: 6)
    }
}

// MARK: - MuscleGroup Extensions

extension MuscleGroup {
    var color: Color {
        switch self {
        case .push: return Theme.Colors.push
        case .pull: return Theme.Colors.pull
        case .legs: return Theme.Colors.legs
        case .core: return Theme.Colors.core
        case .cardio: return Theme.Colors.cardio
        }
    }
}
