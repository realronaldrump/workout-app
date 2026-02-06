import SwiftUI
import UIKit

/// Centralized theme system - bold, bright, vibrant.
/// Light mode: warm, sunny canvas.
/// Dark mode: cool, neon canvas.
enum Theme {
    
    // MARK: - Colors
    
    enum Colors {
        // Palette
        // - Light: warm cream + sun-washed highlights
        // - Dark: deep cobalt + neon ice highlights
        //
        // Keep the "electric blue" brand moment from LaunchScreen as the primary accent.

        // Core surfaces
        static let background = Color.uiColor(light: UIColor(hex: 0xFFF4E6), dark: UIColor(hex: 0x060A1A))
        static let surface = Color.uiColor(light: UIColor(hex: 0xFFFCF7), dark: UIColor(hex: 0x0B1330))
        static let elevated = Color.uiColor(light: UIColor(hex: 0xFFFFFF), dark: UIColor(hex: 0x101C3D))
        static let cardBackground = Color.uiColor(light: UIColor(hex: 0xFFFEFB), dark: UIColor(hex: 0x0C1633))
        static let border = Color.uiColor(light: UIColor(hex: 0xEED5C2), dark: UIColor(hex: 0x23325E))
        
        // Text hierarchy
        static let textPrimary = Color.uiColor(light: UIColor(hex: 0x1B1612), dark: UIColor(hex: 0xF3F7FF))
        static let textSecondary = Color.uiColor(light: UIColor(hex: 0x5B5148), dark: UIColor(hex: 0xB8C7E6))
        static let textTertiary = Color.uiColor(light: UIColor(hex: 0x8C8075), dark: UIColor(hex: 0x7E8FB8))
        
        // Accent colors - vibrant and energetic
        static let accent = Color(uiColor: UIColor(hex: 0x125BFF))  // Electric blue (matches LaunchBackground)
        static let accentSecondary = Color.uiColor(
            light: UIColor(hex: 0xFF5A1F), // Tangerine heat (light mode)
            dark: UIColor(hex: 0x00D4FF)   // Neon ice (dark mode)
        )
        static let accentTertiary = Color(uiColor: UIColor(hex: 0x8B5CF6))  // Violet punch
        
        // Semantic colors - brighter, more saturated
        static let success = Color(uiColor: UIColor(hex: 0x22C55E))  // Vibrant green
        static let warning = Color(uiColor: UIColor(hex: 0xFFB020))  // Hot amber
        static let error = Color(uiColor: UIColor(hex: 0xFF3B30))    // Vivid red
        static let info = accent
        
        // PR/Achievement - brighter gold
        static let gold = Color(uiColor: UIColor(hex: 0xFFD166))

        // Muscle groups - vibrant, distinguishable colors
        static let chest = Color(uiColor: UIColor(hex: 0xFF2D55))  // Hot pink-red
        static let back = Color(uiColor: UIColor(hex: 0x125BFF))   // Electric blue
        static let shoulders = Color(uiColor: UIColor(hex: 0xFFB020))  // Amber
        static let biceps = Color(uiColor: UIColor(hex: 0xA855F7))  // Purple
        static let triceps = Color(uiColor: UIColor(hex: 0xEC4899))  // Pink
        static let quads = Color(uiColor: UIColor(hex: 0x22C55E))  // Green
        static let hamstrings = Color(uiColor: UIColor(hex: 0x14B8A6))  // Teal
        static let glutes = Color(uiColor: UIColor(hex: 0x8B5CF6))  // Violet
        static let calves = Color(uiColor: UIColor(hex: 0x00D4FF))  // Cyan
        static let core = Color(uiColor: UIColor(hex: 0xFFD166))  // Yellow-gold
        static let cardio = Color(uiColor: UIColor(hex: 0x00D4FF))  // Cyan

        // Glassmorphism
        static let glass = Color.uiColor(
            light: UIColor(hex: 0xFFF7EE).withAlphaComponent(0.72),
            dark: UIColor(hex: 0x0B1330).withAlphaComponent(0.35)
        )
        static let glassBorder = Color.uiColor(
            light: UIColor(hex: 0x1B1612).withAlphaComponent(0.08),
            dark: UIColor(hex: 0xF3F7FF).withAlphaComponent(0.12)
        )
    }

    // MARK: - UIKit Colors (for UIAppearance)

    enum UIColors {
        static let background = UIColor.dynamic(light: 0xFFF4E6, dark: 0x060A1A)
        static let surface = UIColor.dynamic(light: 0xFFFCF7, dark: 0x0B1330)
        static let elevated = UIColor.dynamic(light: 0xFFFFFF, dark: 0x101C3D)
        static let cardBackground = UIColor.dynamic(light: 0xFFFEFB, dark: 0x0C1633)
        static let border = UIColor.dynamic(light: 0xEED5C2, dark: 0x23325E)

        static let textPrimary = UIColor.dynamic(light: 0x1B1612, dark: 0xF3F7FF)
        static let textSecondary = UIColor.dynamic(light: 0x5B5148, dark: 0xB8C7E6)
        static let textTertiary = UIColor.dynamic(light: 0x8C8075, dark: 0x7E8FB8)

        static let accent = UIColor(hex: 0x125BFF)
        static let accentSecondary = UIColor.dynamic(light: 0xFF5A1F, dark: 0x00D4FF)
    }

    static func configureGlobalAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        nav.backgroundColor = UIColor { traits in
            let base = traits.userInterfaceStyle == .dark ? UIColor(hex: 0x0B1330) : UIColor(hex: 0xFFFCF7)
            return base.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.65 : 0.75)
        }
        nav.shadowColor = UIColor.clear

        nav.titleTextAttributes = [
            .foregroundColor: Theme.UIColors.textPrimary,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: Theme.UIColors.textPrimary,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = nav
        navBar.scrollEdgeAppearance = nav
        navBar.compactAppearance = nav
        navBar.tintColor = Theme.UIColors.accent

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        tab.backgroundColor = UIColor { traits in
            let base = traits.userInterfaceStyle == .dark ? UIColor(hex: 0x0B1330) : UIColor(hex: 0xFFFCF7)
            return base.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.52 : 0.70)
        }
        tab.shadowColor = UIColor { traits in
            let base = traits.userInterfaceStyle == .dark ? UIColor(hex: 0x23325E) : UIColor(hex: 0xEED5C2)
            return base.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.55 : 0.45)
        }

        let stacked = tab.stackedLayoutAppearance
        stacked.normal.iconColor = Theme.UIColors.textTertiary
        stacked.normal.titleTextAttributes = [.foregroundColor: Theme.UIColors.textTertiary]
        stacked.selected.iconColor = Theme.UIColors.accent
        stacked.selected.titleTextAttributes = [.foregroundColor: Theme.UIColors.accent]

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tab
        tabBar.scrollEdgeAppearance = tab
        tabBar.tintColor = Theme.UIColors.accent
    }
    
    // MARK: - Typography
    
    enum Typography {
        // Brand wordmark (Bebas Neue). Use sparingly: splash + onboarding + hero moments only.
        static let wordmarkHuge = Font.custom("BebasNeue-Regular", size: 52, relativeTo: .largeTitle)
        static let wordmarkBig = Font.custom("BebasNeue-Regular", size: 36, relativeTo: .title)
        static let heroTitle = Font.system(size: 32, weight: .heavy, design: .rounded)

        static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 22, weight: .bold, design: .rounded)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 17, weight: .bold, design: .rounded)
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
            // Dark mode: Deep cobalt canvas with neon ice glow
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: [
                        Theme.Colors.background,
                        Theme.Colors.surface,
                        Theme.Colors.elevated
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Electric blue glow - top right
                RadialGradient(
                    colors: [
                        Theme.Colors.accent.opacity(0.16 + (luminance * 0.12)),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 60,
                    endRadius: 520
                )
                
                // Neon ice glow - bottom left
                RadialGradient(
                    colors: [
                        Theme.Colors.accentSecondary.opacity(0.14 + (luminance * 0.10)),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 80,
                    endRadius: 560
                )

                // Violet punch - top left (kept subtle, mostly for depth)
                RadialGradient(
                    colors: [
                        Theme.Colors.accentTertiary.opacity(0.10 + (luminance * 0.06)),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 520
                )
            }
            .ignoresSafeArea()
        } else {
            // Light mode: Warm cream canvas with bold, sunny glow
            ZStack {
                LinearGradient(
                    colors: [
                        Theme.Colors.background,
                        Theme.Colors.surface
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Warm sun glow - top left
                RadialGradient(
                    colors: [
                        Theme.Colors.gold.opacity(0.20 + (luminance * 0.10)),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 540
                )

                // Electric blue tint - top right (ties to the launch moment)
                RadialGradient(
                    colors: [
                        Theme.Colors.accent.opacity(0.14 + (luminance * 0.10)),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 30,
                    endRadius: 560
                )
                
                // Tangerine heat - bottom left
                RadialGradient(
                    colors: [
                        Theme.Colors.accentSecondary.opacity(0.22 + (luminance * 0.10)),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 60,
                    endRadius: 640
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
            // Keep the launch moment: a bold electric-blue field, then layered glows.
            LinearGradient(
                colors: [
                    Theme.Colors.accent,
                    Theme.Colors.accent.blended(with: Theme.Colors.background, amount: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Frost/heat glow (mode-dependent via accentSecondary)
            RadialGradient(
                colors: [
                    Theme.Colors.accentSecondary.opacity(colorScheme == .dark ? 0.20 : 0.16),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 560
            )

            // Bright highlight so the lockup reads crisply (less in dark)
            RadialGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.20),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 30,
                endRadius: 700
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
        let highlightOpacity = colorScheme == .dark ? 0.16 : 0.10

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
            )
            .overlay(
                // Subtle chroma edge so cards feel "alive" on bold backgrounds, without turning into gradients.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Theme.Colors.accent.opacity(0.9),
                                Theme.Colors.accentSecondary.opacity(0.85),
                                Theme.Colors.accentTertiary.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .opacity(highlightOpacity)
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

    static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light, alpha: alpha)
        }
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
