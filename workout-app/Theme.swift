import SwiftUI
import UIKit

/// Centralized theme system — Brutalist / Neubrutalist.
/// Bold borders, hard shadows, flat color blocks, Bebas Neue headings, sharp corners.
/// Single universal theme. The splash screen is the north star.
enum Theme {

    // MARK: - Colors

    enum Colors {
        // Brutalist palette: stark, high-contrast, flat.
        // Electric blue brand moment from LaunchScreen remains the primary accent.

        // Core surfaces — cool near-white, flat, no warmth
        static let background = Color(uiColor: UIColor(hex: 0xF5F5F5))
        static let surface = Color(uiColor: UIColor(hex: 0xFFFFFF))
        static let elevated = Color(uiColor: UIColor(hex: 0xFFFFFF))
        static let cardBackground = Color(uiColor: UIColor(hex: 0xFFFFFF))
        static let border = Color(uiColor: UIColor(hex: 0x1B1612))  // Near-black — bold brutalist borders

        // Text hierarchy — high contrast
        static let textPrimary = Color(uiColor: UIColor(hex: 0x1B1612))
        static let textSecondary = Color(uiColor: UIColor(hex: 0x4A4A4A))
        static let textTertiary = Color(uiColor: UIColor(hex: 0x7A7A7A))

        // Accent colors — vibrant and energetic
        static let accent = Color(uiColor: UIColor(hex: 0x125BFF))  // Electric blue (matches LaunchBackground)
        static let accentSecondary = Color(uiColor: UIColor(hex: 0xFF5A1F)) // Tangerine heat
        static let accentTertiary = Color(uiColor: UIColor(hex: 0x8B5CF6))  // Violet punch

        // Semantic colors — bold, saturated
        static let success = Color(uiColor: UIColor(hex: 0x22C55E))
        static let warning = Color(uiColor: UIColor(hex: 0xFFB020))
        static let error = Color(uiColor: UIColor(hex: 0xFF3B30))
        static let info = accent
        static let shadowOpacity: Double = 0.05

        // PR/Achievement
        static let gold = Color(uiColor: UIColor(hex: 0xFFD166))

        // Muscle groups — vibrant, distinguishable
        static let chest = Color(uiColor: UIColor(hex: 0xFF2D55))
        static let back = Color(uiColor: UIColor(hex: 0x125BFF))
        static let shoulders = Color(uiColor: UIColor(hex: 0xFFB020))
        static let biceps = Color(uiColor: UIColor(hex: 0xA855F7))
        static let triceps = Color(uiColor: UIColor(hex: 0xEC4899))
        static let quads = Color(uiColor: UIColor(hex: 0x22C55E))
        static let hamstrings = Color(uiColor: UIColor(hex: 0x14B8A6))
        static let glutes = Color(uiColor: UIColor(hex: 0x8B5CF6))
        static let calves = Color(uiColor: UIColor(hex: 0x00D4FF))
        static let core = Color(uiColor: UIColor(hex: 0xFFD166))
        static let cardio = Color(uiColor: UIColor(hex: 0x00D4FF))
    }

    // MARK: - UIKit Colors (for UIAppearance)

    enum UIColors {
        static let background = UIColor(hex: 0xF5F5F5)
        static let surface = UIColor(hex: 0xFFFFFF)
        static let elevated = UIColor(hex: 0xFFFFFF)
        static let cardBackground = UIColor(hex: 0xFFFFFF)
        static let border = UIColor(hex: 0x1B1612)

        static let textPrimary = UIColor(hex: 0x1B1612)
        static let textSecondary = UIColor(hex: 0x4A4A4A)
        static let textTertiary = UIColor(hex: 0x7A7A7A)

        static let accent = UIColor(hex: 0x125BFF)
        static let accentSecondary = UIColor(hex: 0xFF5A1F)
    }

    static func configureGlobalAppearance() {
        // Navigation bar — opaque, Bebas Neue titles, dark shadow
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColors.background
        nav.shadowColor = UIColor(hex: 0x1B1612).withAlphaComponent(Colors.shadowOpacity)

        nav.titleTextAttributes = [
            .foregroundColor: UIColors.textPrimary,
            .font: UIFont(name: "BebasNeue-Regular", size: 20) ?? UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColors.textPrimary,
            .font: UIFont(name: "BebasNeue-Regular", size: 40) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        ]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = nav
        navBar.scrollEdgeAppearance = nav
        navBar.compactAppearance = nav
        navBar.tintColor = UIColors.accent

        // Tab bar — opaque, Bebas Neue labels, dark top border
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColors.background
        tab.shadowColor = UIColor(hex: 0x1B1612)

        let stacked = tab.stackedLayoutAppearance
        stacked.normal.iconColor = UIColors.textTertiary
        stacked.normal.titleTextAttributes = [
            .foregroundColor: UIColors.textTertiary,
            .font: UIFont(name: "BebasNeue-Regular", size: 11) ?? UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        stacked.selected.iconColor = UIColors.accent
        stacked.selected.titleTextAttributes = [
            .foregroundColor: UIColors.accent,
            .font: UIFont(name: "BebasNeue-Regular", size: 11) ?? UIFont.systemFont(ofSize: 10, weight: .medium)
        ]

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tab
        tabBar.scrollEdgeAppearance = tab
        tabBar.tintColor = UIColors.accent
    }

    // MARK: - Typography

    enum Typography {
        // Bebas Neue — used for screen titles, section headers, metric labels, and brand moments.
        static let wordmarkHuge = Font.custom("BebasNeue-Regular", size: 52, relativeTo: .largeTitle)
        static let wordmarkBig = Font.custom("BebasNeue-Regular", size: 36, relativeTo: .title)
        static let screenTitle = Font.custom("BebasNeue-Regular", size: 40, relativeTo: .largeTitle)
        static let sectionHeader = Font.custom("BebasNeue-Regular", size: 28, relativeTo: .title)
        static let sectionHeader2 = Font.custom("BebasNeue-Regular", size: 24, relativeTo: .title2)
        static let cardHeader = Font.custom("BebasNeue-Regular", size: 20, relativeTo: .title3)
        static let metricLabel = Font.custom("BebasNeue-Regular", size: 14, relativeTo: .caption)
        static let tabLabel = Font.custom("BebasNeue-Regular", size: 11, relativeTo: .caption2)
        static let heroTitle = Font.custom("BebasNeue-Regular", size: 36, relativeTo: .title)

        // System fonts — angular (no rounded design)
        static let largeTitle = Font.system(size: 36, weight: .heavy, design: .default)
        static let title = Font.system(size: 30, weight: .heavy, design: .default)
        static let title2 = Font.custom("BebasNeue-Regular", size: 24, relativeTo: .title2)
        static let title3 = Font.custom("BebasNeue-Regular", size: 20, relativeTo: .title3)
        static let headline = Font.system(size: 18, weight: .bold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let bodyBold = Font.system(size: 17, weight: .semibold, design: .default)
        static let callout = Font.system(size: 16, weight: .medium, design: .default)
        static let subheadline = Font.system(size: 15, weight: .medium, design: .default)
        static let footnote = Font.system(size: 13, weight: .medium, design: .default)
        static let caption = Font.system(size: 12, weight: .medium, design: .default)
        static let captionBold = Font.system(size: 12, weight: .bold, design: .default)

        // Monospaced for numbers — raw data aesthetic
        static let number = Font.system(size: 28, weight: .bold, design: .monospaced)
        static let numberLarge = Font.system(size: 42, weight: .bold, design: .monospaced)
        static let numberSmall = Font.system(size: 17, weight: .bold, design: .monospaced)
        static let metricLarge = Font.system(size: 48, weight: .heavy, design: .monospaced)
        static let metric = Font.system(size: 30, weight: .bold, design: .monospaced)
        static let condensed = Font.system(size: 16, weight: .semibold, design: .default)
        static let microcopy = Font.system(size: 13, weight: .regular, design: .default)
    }

    // MARK: - Animation

    enum Animation {
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let chartAppear = SwiftUI.Animation.spring(response: 0.6, dampingFraction: 0.7)
    }

    // MARK: - Spacing — generous whitespace

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 40
    }

    // MARK: - Corner Radius — sharp, angular

    enum CornerRadius {
        static let small: CGFloat = 2
        static let medium: CGFloat = 4
        static let large: CGFloat = 6
        static let xlarge: CGFloat = 8
    }
}

// MARK: - Adaptive Background

struct AdaptiveBackground: View {
    var body: some View {
        Theme.Colors.background
            .ignoresSafeArea()
    }
}

// MARK: - Splash Background

struct SplashBackground: View {
    var body: some View {
        ZStack {
            // Flat electric blue — crisp, high-impact brand moment.
            Theme.Colors.accent
        }
        .ignoresSafeArea()
    }
}

// MARK: - Brutalist Card Modifier (Default Surface)

struct SoftCardBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.CornerRadius.large
    var elevation: CGFloat = 1

    func body(content: Content) -> some View {
        let shadowOffset = 3 * elevation

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.Colors.border, lineWidth: 2)
            )
            .shadow(
                color: Color.black.opacity(Theme.Colors.shadowOpacity),
                radius: 0,
                x: shadowOffset,
                y: shadowOffset
            )
    }
}

// MARK: - Flat Card Modifier (replaces glassmorphism)

struct GlassBackground: ViewModifier {
    var opacity: Double = 0.08
    var cornerRadius: CGFloat = Theme.CornerRadius.medium
    var elevation: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.Colors.border, lineWidth: 2)
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
    private struct RGBAComponents {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    func blended(with color: Color, amount: Double) -> Color {
        let clamped = min(max(amount, 0), 1)
        let first = rgbaComponents()
        let second = color.rgbaComponents()

        return Color(
            red: first.red + (second.red - first.red) * clamped,
            green: first.green + (second.green - first.green) * clamped,
            blue: first.blue + (second.blue - first.blue) * clamped,
            opacity: first.alpha + (second.alpha - first.alpha) * clamped
        )
    }

    private func rgbaComponents() -> RGBAComponents {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGBAComponents(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
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

struct AnimateOnAppearModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 6)
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
                .font(Theme.Typography.metricLabel)
        }
        .foregroundColor(Theme.Colors.gold)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.Colors.gold.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .strokeBorder(Theme.Colors.gold, lineWidth: 2)
        )
        .cornerRadius(Theme.CornerRadius.small)
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

    var iconName: String {
        switch self {
        case .chest: return "heart.fill"
        case .back: return "arrow.left.and.right"
        case .shoulders: return "figure.arms.open"
        case .biceps: return "figure.strengthtraining.functional"
        case .triceps: return "arrow.up.right"
        case .quads: return "figure.walk"
        case .hamstrings: return "figure.run"
        case .glutes: return "figure.cooldown"
        case .calves: return "shoeprints.fill"
        case .core: return "circle.hexagongrid"
        case .cardio: return "heart.text.square"
        }
    }

    var shortName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .quads: return "Quads"
        case .hamstrings: return "Hams"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .core: return "Core"
        case .cardio: return "Cardio"
        }
    }
}
