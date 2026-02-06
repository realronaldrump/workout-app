import SwiftUI
import UIKit

/// Centralized theme system - Electric Gym (bold, vibrant, modern fitness aesthetic)
enum Theme {
    
    // MARK: - Colors
    
    enum Colors {
        // Electric Gym palette - bold, vibrant, premium fitness aesthetic
        //
        // Light: Cool white base with electric accents
        // Dark: Deep ink with glowing accents
        //
        // Primary: Electric Indigo #6366F1
        // Secondary: Hot Rose #F43F5E
        
        static let background = Color.uiColor(light: UIColor(hex: 0xFAFBFF), dark: UIColor(hex: 0x090B10))
        static let surface = Color.uiColor(light: UIColor(hex: 0xFFFFFF), dark: UIColor(hex: 0x12151C))
        static let elevated = Color.uiColor(light: UIColor(hex: 0xFFFFFF), dark: UIColor(hex: 0x1A1E28))
        static let cardBackground = Color.uiColor(light: UIColor(hex: 0xFFFFFF), dark: UIColor(hex: 0x12151C))
        static let border = Color.uiColor(light: UIColor(hex: 0xE5E8F0), dark: UIColor(hex: 0x2A3040))
        
        // Text hierarchy
        static let textPrimary = Color.uiColor(light: UIColor(hex: 0x0F172A), dark: UIColor(hex: 0xF8FAFC))
        static let textSecondary = Color.uiColor(light: UIColor(hex: 0x475569), dark: UIColor(hex: 0xCBD5E1))
        static let textTertiary = Color.uiColor(light: UIColor(hex: 0x94A3B8), dark: UIColor(hex: 0x64748B))
        
        // Accent colors - vibrant and energetic
        static let accent = Color(uiColor: UIColor(hex: 0x6366F1))  // Electric indigo
        static let accentSecondary = Color(uiColor: UIColor(hex: 0xF43F5E))  // Hot rose
        
        // Semantic colors - brighter, more saturated
        static let success = Color(uiColor: UIColor(hex: 0x10B981))  // Vibrant emerald
        static let warning = Color(uiColor: UIColor(hex: 0xF59E0B))  // Rich amber
        static let error = Color(uiColor: UIColor(hex: 0xEF4444))  // Bright red
        static let info = accent
        
        // PR/Achievement - brighter gold
        static let gold = Color(uiColor: UIColor(hex: 0xFBBF24))
        
        // Muscle groups - vibrant, distinguishable colors
        static let chest = Color(uiColor: UIColor(hex: 0xF43F5E))  // Rose
        static let back = Color(uiColor: UIColor(hex: 0x6366F1))   // Indigo
        static let shoulders = Color(uiColor: UIColor(hex: 0xF59E0B))  // Amber
        static let biceps = Color(uiColor: UIColor(hex: 0xA855F7))  // Purple
        static let triceps = Color(uiColor: UIColor(hex: 0xEC4899))  // Pink
        static let quads = Color(uiColor: UIColor(hex: 0x10B981))  // Emerald
        static let hamstrings = Color(uiColor: UIColor(hex: 0x14B8A6))  // Teal
        static let glutes = Color(uiColor: UIColor(hex: 0x8B5CF6))  // Violet
        static let calves = Color(uiColor: UIColor(hex: 0x06B6D4))  // Cyan
        static let core = Color(uiColor: UIColor(hex: 0xFBBF24))  // Yellow
        static let cardio = Color(uiColor: UIColor(hex: 0x0EA5E9))  // Sky
        
        // Glassmorphism
        static let glass = Color.uiColor(
            light: UIColor.white.withAlphaComponent(0.65),
            dark: UIColor.white.withAlphaComponent(0.06)
        )
        static let glassBorder = Color.uiColor(
            light: UIColor.black.withAlphaComponent(0.06),
            dark: UIColor.white.withAlphaComponent(0.10)
        )
    }
    
    // MARK: - Typography
    
    enum Typography {
        // Brand wordmark (Bebas Neue). Use sparingly: splash + onboarding + hero moments only.
        static let wordmarkHuge = Font.custom("BebasNeue-Regular", size: 52, relativeTo: .largeTitle)
        static let wordmarkBig = Font.custom("BebasNeue-Regular", size: 36, relativeTo: .title)
        static let heroTitle = Font.system(size: 32, weight: .bold, design: .default)

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
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        if colorScheme == .dark {
            // Dark mode: Deep ink canvas with vibrant electric glow
            ZStack {
                // Base gradient - deep ink, no muddy blending
                LinearGradient(
                    colors: [
                        Theme.Colors.background,
                        Theme.Colors.elevated
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Electric indigo glow - top right
                RadialGradient(
                    colors: [
                        Theme.Colors.accent.opacity(0.12 + (luminance * 0.08)),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 60,
                    endRadius: 400
                )
                
                // Hot rose glow - bottom left
                RadialGradient(
                    colors: [
                        Theme.Colors.accentSecondary.opacity(0.08 + (luminance * 0.06)),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 80,
                    endRadius: 450
                )
            }
            .ignoresSafeArea()
        } else {
            // Light mode: Clean white with subtle accent wash
            ZStack {
                Theme.Colors.background
                
                // Subtle indigo tint in corner
                RadialGradient(
                    colors: [
                        Theme.Colors.accent.opacity(0.05),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 500
                )
                
                // Hint of warmth from rose
                RadialGradient(
                    colors: [
                        Theme.Colors.accentSecondary.opacity(0.03),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 40,
                    endRadius: 500
                )
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Splash Background

struct SplashBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                AdaptiveBackground()
            } else {
                // Light mode splash: Bold electric glow for impact
                Theme.Colors.background
                
                RadialGradient(
                    colors: [
                        Theme.Colors.accent.opacity(0.15),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 500
                )

                RadialGradient(
                    colors: [
                        Theme.Colors.accentSecondary.opacity(0.10),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 60,
                    endRadius: 500
                )
            }
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
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        let baseFill = Theme.Colors.glass
            .blended(with: .white, amount: 0.08 + (luminance * 0.18))
        let border = Theme.Colors.glassBorder
            .blended(with: .white, amount: 0.05 + (luminance * 0.12))
        let shadowOpacity = min(0.35, 0.12 + Double(elevation) * 0.06)
        let material: Material = colorScheme == .dark ? .ultraThinMaterial : .thinMaterial
        
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(material)
                    .opacity(colorScheme == .dark ? 0.75 : 0.9)
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

// MARK: - Soft Card Modifier (Default Surface)

struct SoftCardBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.CornerRadius.large
    var elevation: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shadowColor = colorScheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.08)
        let shadowRadius = colorScheme == .dark ? 10 * elevation : 20 * elevation
        let shadowY = colorScheme == .dark ? 8 * elevation : 12 * elevation

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
            )
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowY
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

    func softCard(
        cornerRadius: CGFloat = Theme.CornerRadius.large,
        elevation: CGFloat = 1
    ) -> some View {
        modifier(SoftCardBackground(cornerRadius: cornerRadius, elevation: elevation))
    }
    
    func cardStyle() -> some View {
        self
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
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

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

extension Color {
    static func uiColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
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
        case .chest: return Theme.Colors.chest
        case .back: return Theme.Colors.back
        case .shoulders: return Theme.Colors.shoulders
        case .biceps: return Theme.Colors.biceps
        case .triceps: return Theme.Colors.triceps
        case .quads: return Theme.Colors.quads
        case .hamstrings: return Theme.Colors.hamstrings
        case .glutes: return Theme.Colors.glutes
        case .calves: return Theme.Colors.calves
        case .core: return Theme.Colors.core
        case .cardio: return Theme.Colors.cardio
        }
    }
}
