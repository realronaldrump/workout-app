import SwiftUI
import UIKit

/// Centralized theme system — Warm Precision.
/// Refined surfaces, layered shadows, Bebas Neue headings, generous radii.
/// Premium athletic aesthetic with warmth and depth.
enum Theme {

    // MARK: - Colors

    enum Colors {
        // Warm Precision palette: sophisticated, warm neutrals, real depth.
        // Electric blue accent remains the hero color.

        // Core surfaces — warm ivory, layered depth
        static let background = Color(uiColor: UIColor(hex: 0xF6F4F0))
        static let surface = Color(uiColor: UIColor(hex: 0xFFFFFF))
        static let elevated = Color(uiColor: UIColor(hex: 0xFFFFFF))
        static let cardBackground = Color(uiColor: UIColor(hex: 0xFFFFFF))
        static let border = Color(uiColor: UIColor(hex: 0xE0DBD3))  // Warm subtle border

        // Text hierarchy — warm, refined contrast
        static let textPrimary = Color(uiColor: UIColor(hex: 0x1A1714))
        static let textSecondary = Color(uiColor: UIColor(hex: 0x6B6560))
        static let textTertiary = Color(uiColor: UIColor(hex: 0xA39E99))

        // Accent colors — vibrant and confident
        static let accent = Color(uiColor: UIColor(hex: 0x2563EB))  // Royal blue — deeper, richer
        static let accentSecondary = Color(uiColor: UIColor(hex: 0xF97316)) // Warm amber-orange
        static let accentTertiary = Color(uiColor: UIColor(hex: 0x8B5CF6))  // Violet punch

        // Semantic colors — clear, confident
        static let success = Color(uiColor: UIColor(hex: 0x16A34A))
        static let warning = Color(uiColor: UIColor(hex: 0xF59E0B))
        static let error = Color(uiColor: UIColor(hex: 0xEF4444))
        static let info = accent
        static let shadowOpacity: Double = 0.08

        // PR/Achievement
        static let gold = Color(uiColor: UIColor(hex: 0xF59E0B))

        // Muscle groups — vibrant, distinguishable
        static let chest = Color(uiColor: UIColor(hex: 0xEF4444))
        static let back = Color(uiColor: UIColor(hex: 0x2563EB))
        static let shoulders = Color(uiColor: UIColor(hex: 0xF59E0B))
        static let biceps = Color(uiColor: UIColor(hex: 0xA855F7))
        static let triceps = Color(uiColor: UIColor(hex: 0xEC4899))
        static let quads = Color(uiColor: UIColor(hex: 0x16A34A))
        static let hamstrings = Color(uiColor: UIColor(hex: 0x14B8A6))
        static let glutes = Color(uiColor: UIColor(hex: 0x8B5CF6))
        static let calves = Color(uiColor: UIColor(hex: 0x06B6D4))
        static let core = Color(uiColor: UIColor(hex: 0xF59E0B))
        static let cardio = Color(uiColor: UIColor(hex: 0x06B6D4))

        // Surface tints — for section variety and colored backgrounds
        static let accentTint = Color(uiColor: UIColor(hex: 0x2563EB)).opacity(0.06)
        static let warmTint = Color(uiColor: UIColor(hex: 0xF97316)).opacity(0.05)
        static let successTint = Color(uiColor: UIColor(hex: 0x16A34A)).opacity(0.06)
        static let surfaceRaised = Color(uiColor: UIColor(hex: 0xFAF9F7))

        /// Lookup muscle group color by enum value.
        static func muscleGroupColor(for group: MuscleGroup) -> Color {
            switch group {
            case .chest: return chest
            case .back: return back
            case .shoulders: return shoulders
            case .biceps: return biceps
            case .triceps: return triceps
            case .quads: return quads
            case .hamstrings: return hamstrings
            case .glutes: return glutes
            case .calves: return calves
            case .core: return core
            case .cardio: return cardio
            }
        }
    }

    // MARK: - UIKit Colors (for UIAppearance)

    enum UIColors {
        static let background = UIColor(hex: 0xF6F4F0)
        static let surface = UIColor(hex: 0xFFFFFF)
        static let elevated = UIColor(hex: 0xFFFFFF)
        static let cardBackground = UIColor(hex: 0xFFFFFF)
        static let border = UIColor(hex: 0xE0DBD3)

        static let textPrimary = UIColor(hex: 0x1A1714)
        static let textSecondary = UIColor(hex: 0x6B6560)
        static let textTertiary = UIColor(hex: 0xA39E99)

        static let accent = UIColor(hex: 0x2563EB)
        static let accentSecondary = UIColor(hex: 0xF97316)
    }

    static func configureGlobalAppearance() {
        // Navigation bar — clean, warm, refined
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColors.background
        nav.shadowColor = UIColors.border.withAlphaComponent(0.5)

        nav.titleTextAttributes = [
            .foregroundColor: UIColors.textPrimary,
            .font: UIFont(name: "BebasNeue-Regular", size: 20) ?? UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColors.textPrimary,
            .font: UIFont(name: "BebasNeue-Regular", size: 40) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        ]

        let navButton = UIBarButtonItemAppearance(style: .plain)
        navButton.normal.backgroundImage = UIImage()
        navButton.highlighted.backgroundImage = UIImage()
        navButton.disabled.backgroundImage = UIImage()
        navButton.normal.titleTextAttributes = [.foregroundColor: UIColors.accent]
        navButton.highlighted.titleTextAttributes = [.foregroundColor: UIColors.accent]
        navButton.disabled.titleTextAttributes = [.foregroundColor: UIColors.textTertiary]

        nav.buttonAppearance = navButton
        if #unavailable(iOS 26.0) {
            nav.doneButtonAppearance = navButton
        }
        nav.prominentButtonAppearance = navButton
        nav.backButtonAppearance = navButton

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = nav
        navBar.scrollEdgeAppearance = nav
        navBar.compactAppearance = nav
        if #available(iOS 15.0, *) {
            navBar.compactScrollEdgeAppearance = nav
        }
        navBar.tintColor = UIColors.accent

        // Belt-and-suspenders fallback for newer UIKit button containers.
        let clearImage = UIImage()
        let barButton = UIBarButtonItem.appearance(whenContainedInInstancesOf: [UINavigationBar.self])
        barButton.setBackgroundImage(clearImage, for: .normal, barMetrics: .default)
        barButton.setBackgroundImage(clearImage, for: .highlighted, barMetrics: .default)
        barButton.setBackgroundImage(clearImage, for: .disabled, barMetrics: .default)
        barButton.setBackButtonBackgroundImage(clearImage, for: .normal, barMetrics: .default)
        barButton.setBackButtonBackgroundImage(clearImage, for: .highlighted, barMetrics: .default)
        barButton.setBackButtonBackgroundImage(clearImage, for: .disabled, barMetrics: .default)
        barButton.setTitleTextAttributes([.foregroundColor: UIColors.accent], for: .normal)
        barButton.setTitleTextAttributes([.foregroundColor: UIColors.accent], for: .highlighted)
        barButton.setTitleTextAttributes([.foregroundColor: UIColors.textTertiary], for: .disabled)

        // Tab bar — refined with subtle top separator
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColors.surface
        tab.shadowColor = UIColors.border.withAlphaComponent(0.4)

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
        // Bebas Neue — brand headings, section titles, labels
        static let wordmarkHuge = Font.custom("BebasNeue-Regular", size: 56, relativeTo: .largeTitle)
        static let wordmarkHugeCompact = Font.custom("BebasNeue-Regular", size: 44, relativeTo: .largeTitle)
        static let wordmarkBig = Font.custom("BebasNeue-Regular", size: 38, relativeTo: .title)
        static let wordmarkBigCompact = Font.custom("BebasNeue-Regular", size: 30, relativeTo: .title)
        static let eyebrowRounded = Font.system(size: 14, weight: .semibold, design: .rounded)
        static let screenTitle = Font.custom("BebasNeue-Regular", size: 42, relativeTo: .largeTitle)
        static let sectionHeader = Font.custom("BebasNeue-Regular", size: 26, relativeTo: .title)
        static let sectionHeader2 = Font.custom("BebasNeue-Regular", size: 22, relativeTo: .title2)
        static let cardHeader = Font.custom("BebasNeue-Regular", size: 20, relativeTo: .title3)
        static let metricLabel = Font.custom("BebasNeue-Regular", size: 13, relativeTo: .caption)
        static let tabLabel = Font.custom("BebasNeue-Regular", size: 11, relativeTo: .caption2)
        static let heroTitle = Font.custom("BebasNeue-Regular", size: 38, relativeTo: .title)

        // System fonts — clean, modern
        static let largeTitle = Font.system(size: 36, weight: .heavy, design: .default)
        static let title = Font.system(size: 30, weight: .heavy, design: .default)
        static let title2 = Font.custom("BebasNeue-Regular", size: 24, relativeTo: .title2)
        static let title3 = Font.custom("BebasNeue-Regular", size: 20, relativeTo: .title3)
        static let avatarMonogram = Font.system(size: 28, weight: .bold, design: .default)
        static let bodyLarge = Font.system(size: 18, weight: .regular, design: .default)
        static let title4 = Font.system(size: 18, weight: .semibold, design: .default)
        static let title4Bold = Font.system(size: 18, weight: .bold, design: .default)
        static let headline = Font.system(size: 17, weight: .bold, design: .default)
        static let body = Font.system(size: 16, weight: .regular, design: .default)
        static let bodyBold = Font.system(size: 16, weight: .semibold, design: .default)
        static let bodyStrong = Font.system(size: 16, weight: .bold, design: .default)
        static let callout = Font.system(size: 15, weight: .medium, design: .default)
        static let calloutStrong = Font.system(size: 15, weight: .semibold, design: .default)
        static let calloutBold = Font.system(size: 15, weight: .bold, design: .default)
        static let subheadline = Font.system(size: 14, weight: .medium, design: .default)
        static let subheadlineStrong = Font.system(size: 14, weight: .semibold, design: .default)
        static let subheadlineBold = Font.system(size: 14, weight: .bold, design: .default)
        static let footnote = Font.system(size: 13, weight: .medium, design: .default)
        static let footnoteStrong = Font.system(size: 13, weight: .semibold, design: .default)
        static let footnoteBold = Font.system(size: 13, weight: .bold, design: .default)
        static let caption = Font.system(size: 12, weight: .medium, design: .default)
        static let captionStrong = Font.system(size: 12, weight: .semibold, design: .default)
        static let captionBold = Font.system(size: 12, weight: .bold, design: .default)
        static let caption2 = Font.system(size: 11, weight: .medium, design: .default)
        static let caption2Bold = Font.system(size: 11, weight: .bold, design: .default)

        // Monospaced for numbers — precision data
        static let number = Font.system(size: 28, weight: .bold, design: .monospaced)
        static let numberLarge = Font.system(size: 42, weight: .bold, design: .monospaced)
        static let numberSmall = Font.system(size: 17, weight: .bold, design: .monospaced)
        static let metricLarge = Font.system(size: 48, weight: .heavy, design: .monospaced)
        static let metric = Font.system(size: 30, weight: .bold, design: .monospaced)
        static let condensed = Font.system(size: 16, weight: .semibold, design: .default)
        static let microcopy = Font.system(size: 13, weight: .regular, design: .default)
        static let microcopySmall = Font.system(size: 10, weight: .regular, design: .default)
        static let microLabel = Font.system(size: 10, weight: .bold, design: .default)

        // Mono helpers for data-dense UI
        static let monoMedium = Font.system(size: 18, weight: .bold, design: .monospaced)
        static let monoSmall = Font.system(size: 14, weight: .semibold, design: .monospaced)
    }

    enum Iconography {
        static let micro = Font.system(size: 10, weight: .medium, design: .default)
        static let small = Font.system(size: 12, weight: .regular, design: .default)
        static let medium = Font.system(size: 14, weight: .regular, design: .default)
        static let mediumStrong = Font.system(size: 14, weight: .semibold, design: .default)
        static let title3 = Font.system(size: 20, weight: .regular, design: .default)
        static let title3Strong = Font.system(size: 20, weight: .semibold, design: .default)
        static let action = Font.system(size: 22, weight: .regular, design: .default)
        static let title2 = Font.system(size: 24, weight: .regular, design: .default)
        static let title2Strong = Font.system(size: 24, weight: .semibold, design: .default)
        static let title2Bold = Font.system(size: 24, weight: .bold, design: .default)
        static let prominent = Font.system(size: 28, weight: .regular, design: .default)
        static let hero = Font.system(size: 32, weight: .medium, design: .default)
        static let feature = Font.system(size: 40, weight: .regular, design: .default)
        static let featureLarge = Font.system(size: 48, weight: .medium, design: .default)
        static let dashboard = Font.system(size: 52, weight: .regular, design: .default)
        static let display = Font.system(size: 56, weight: .regular, design: .default)
        static let wizard = Font.system(size: 60, weight: .regular, design: .default)
        static let wizardHero = Font.system(size: 80, weight: .regular, design: .default)
        static let largeTitle = Font.system(size: 34, weight: .regular, design: .default)
    }

    // MARK: - Animation

    enum Animation {
        static let spring = SwiftUI.Animation.spring(response: 0.45, dampingFraction: 0.82)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.18)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.45)
        static let chartAppear = SwiftUI.Animation.spring(response: 0.65, dampingFraction: 0.72)
        static let bouncy = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.65)
        static let gentleSpring = SwiftUI.Animation.spring(response: 0.55, dampingFraction: 0.88)
    }

    // MARK: - Spacing — generous whitespace

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 44
    }

    // MARK: - Corner Radius — generous, modern

    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xlarge: CGFloat = 20
        static let pill: CGFloat = 100
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
            // Rich gradient brand moment — deep royal blue shifting to lighter blue
            LinearGradient(
                colors: [
                    Color(uiColor: UIColor(hex: 0x1E40AF)),
                    Theme.Colors.accent,
                    Color(uiColor: UIColor(hex: 0x3B82F6))
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Refined Card Modifier (Layered Shadow)

struct SoftCardBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.CornerRadius.large
    var elevation: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.Colors.border.opacity(0.5), lineWidth: 1)
            )
            // Layered shadow system — inner soft + outer ambient
            .shadow(
                color: Color.black.opacity(0.03 * elevation),
                radius: 1,
                x: 0,
                y: 1
            )
            .shadow(
                color: Color.black.opacity(0.05 * elevation),
                radius: 8 * elevation,
                x: 0,
                y: 4 * elevation
            )
            .shadow(
                color: Color.black.opacity(0.02 * elevation),
                radius: 20 * elevation,
                x: 0,
                y: 8 * elevation
            )
    }
}

// MARK: - Glass Background Modifier (Subtle Surface)

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
                    .strokeBorder(Theme.Colors.border.opacity(0.4), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(0.04 * elevation),
                radius: 6 * elevation,
                x: 0,
                y: 3 * elevation
            )
    }
}

// MARK: - Refined Button Chrome

struct BrutalistButtonChrome: ViewModifier {
    var fill: Color = Theme.Colors.surface
    var border: Color = Theme.Colors.border
    var cornerRadius: CGFloat = Theme.CornerRadius.large
    var borderWidth: CGFloat = 1
    var shadowOffset: CGFloat = 2

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(border.opacity(0.4), lineWidth: borderWidth)
            )
            .shadow(
                color: Color.black.opacity(0.06),
                radius: 4,
                x: 0,
                y: 2
            )
    }
}

struct ToolbarButtonChrome: ViewModifier {
    var fill: Color = Theme.Colors.surface
    var border: Color = Theme.Colors.border

    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(border.opacity(0.9), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(0.035),
                radius: 10,
                x: 0,
                y: 4
            )
    }
}

/// Default interaction style for app controls.
/// Provides consistent pressed/disabled feedback with smooth spring animation.
struct AppInteractionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1.0 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.Animation.bouncy, value: configuration.isPressed)
            .animation(Theme.Animation.quick, value: isEnabled)
    }
}

// MARK: - Accent Gradient Helpers

extension Theme {
    /// Primary action gradient — hero buttons, CTAs
    static let accentGradient = LinearGradient(
        colors: [
            Color(uiColor: UIColor(hex: 0x2563EB)),
            Color(uiColor: UIColor(hex: 0x3B82F6))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm gradient — achievements, highlights
    static let warmGradient = LinearGradient(
        colors: [
            Color(uiColor: UIColor(hex: 0xF97316)),
            Color(uiColor: UIColor(hex: 0xFBBF24))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Success gradient — positive metrics
    static let successGradient = LinearGradient(
        colors: [
            Color(uiColor: UIColor(hex: 0x16A34A)),
            Color(uiColor: UIColor(hex: 0x22C55E))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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

    func brutalistButtonChrome(
        fill: Color = Theme.Colors.surface,
        border: Color = Theme.Colors.border,
        cornerRadius: CGFloat = Theme.CornerRadius.large,
        borderWidth: CGFloat = 1,
        shadowOffset: CGFloat = 2
    ) -> some View {
        modifier(
            BrutalistButtonChrome(
                fill: fill,
                border: border,
                cornerRadius: cornerRadius,
                borderWidth: borderWidth,
                shadowOffset: shadowOffset
            )
        )
    }

    func toolbarButtonChrome(
        fill: Color = Theme.Colors.surface,
        border: Color = Theme.Colors.border
    ) -> some View {
        modifier(
            ToolbarButtonChrome(
                fill: fill,
                border: border
            )
        )
    }

    func cardStyle() -> some View {
        self
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
    }

    /// Tinted section background — adds subtle color behind a content section
    func tintedSection(_ color: Color, cornerRadius: CGFloat = Theme.CornerRadius.large) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(color.opacity(0.12), lineWidth: 1)
            )
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
            .offset(y: isVisible ? 0 : 12)
            .scaleEffect(isVisible ? 1 : 0.98)
            .animation(Theme.Animation.gentleSpring.delay(delay), value: isVisible)
            .onAppear {
                isVisible = true
            }
    }
}

// MARK: - Staggered Appear Modifier

struct StaggeredAppearModifier: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 16)
            .scaleEffect(isVisible ? 1 : 0.96)
            .animation(Theme.Animation.gentleSpring.delay(baseDelay + Double(index) * 0.06), value: isVisible)
            .onAppear { isVisible = true }
    }
}

extension View {
    func staggeredAppear(index: Int, baseDelay: Double = 0.05) -> some View {
        modifier(StaggeredAppearModifier(index: index, baseDelay: baseDelay))
    }
}

// MARK: - PR Marker View

struct PRMarkerView: View {
    let date: Date

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "trophy.fill")
                .font(Theme.Typography.microLabel)
            Text("PR")
                .font(Theme.Typography.metricLabel)
        }
        .foregroundStyle(Theme.Colors.gold)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Theme.Colors.gold.opacity(0.12))
        )
        .overlay(
            Capsule()
                .strokeBorder(Theme.Colors.gold.opacity(0.3), lineWidth: 1)
        )
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
