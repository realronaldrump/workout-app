import SwiftUI
import UIKit

private enum ThemeTextWeight {
    case regular
    case medium
    case semibold
    case bold

    var fontName: String {
        switch self {
        case .regular:
            return "InstrumentSans-Regular"
        case .medium:
            return "InstrumentSans-Regular_Medium"
        case .semibold:
            return "InstrumentSans-Regular_SemiBold"
        case .bold:
            return "InstrumentSans-Regular_Bold"
        }
    }

    var fallback: UIFont.Weight {
        switch self {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }
}

private enum ThemeDisplayWeight {
    case regular
    case semibold
    case bold

    var fontName: String {
        switch self {
        case .regular:
            return "Sora-Regular"
        case .semibold:
            return "Sora-Regular_SemiBold"
        case .bold:
            return "Sora-Regular_Bold"
        }
    }

    var fallback: UIFont.Weight {
        switch self {
        case .regular:
            return .regular
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }
}

/// Centralized theme system — Warm Precision.
/// Calm, high-contrast surfaces, two-family typography, and restrained elevation.
enum Theme {

    // MARK: - Colors

    enum Colors {
        // Warm Precision palette with full dark mode support.
        // Uses adaptive UIColors that automatically resolve per trait collection.

        /// Helper: creates a SwiftUI Color that adapts between light and dark mode.
        private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(hex: dark)
                    : UIColor(hex: light)
            })
        }

        // Core surfaces — warm ivory (light) / deep charcoal (dark)
        static let background      = adaptive(light: 0xF6F4F0, dark: 0x0F0F11)
        static let surface         = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
        static let elevated        = adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
        static let cardBackground  = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
        static let border          = adaptive(light: 0xE0DBD3, dark: 0x38383A)

        // Text hierarchy — warm contrast (light) / soft white (dark)
        static let textPrimary     = adaptive(light: 0x1A1714, dark: 0xECECED)
        static let textSecondary   = adaptive(light: 0x5F5954, dark: 0xB0B0B5)
        /// Muted text still meets a 4.5:1 contrast target on app surfaces.
        static let textMuted       = adaptive(light: 0x746E68, dark: 0x98989D)
        /// Decorative separators and disabled ornament only. Never use for text.
        static let decorativeSubtle = adaptive(light: 0xA39E99, dark: 0x5A5A5E)
        /// Compatibility alias for existing call sites. Semantically this is muted text.
        static let textTertiary    = textMuted

        // Accent colors — slightly lighter in dark for contrast
        static let accent          = adaptive(light: 0x2563EB, dark: 0x3B82F6)
        // Light variants are dark enough for both semantic text and white-on-fill controls.
        static let accentSecondary = adaptive(light: 0xC2410C, dark: 0xFB923C)
        static let accentTertiary  = adaptive(light: 0x8B5CF6, dark: 0xA78BFA)

        // Semantic colors — boosted luminance in dark
        static let success         = adaptive(light: 0x15803D, dark: 0x4ADE80)
        static let warning         = adaptive(light: 0x92400E, dark: 0xFBBF24)
        static let error           = adaptive(light: 0xB91C1C, dark: 0xF87171)
        static let info            = accent
        static let shadowOpacity: Double = 0.08

        // PR/Achievement
        static let gold            = adaptive(light: 0xF59E0B, dark: 0xFBBF24)

        // Muscle groups — boosted luminance in dark
        static let chest           = adaptive(light: 0xEF4444, dark: 0xF87171)
        static let back            = adaptive(light: 0x2563EB, dark: 0x3B82F6)
        static let shoulders       = adaptive(light: 0xF59E0B, dark: 0xFBBF24)
        static let biceps          = adaptive(light: 0xA855F7, dark: 0xC084FC)
        static let triceps         = adaptive(light: 0xEC4899, dark: 0xF472B6)
        static let quads           = adaptive(light: 0x16A34A, dark: 0x4ADE80)
        static let hamstrings      = adaptive(light: 0x14B8A6, dark: 0x2DD4BF)
        static let glutes          = adaptive(light: 0x8B5CF6, dark: 0xA78BFA)
        static let hipFlexors      = adaptive(light: 0x0D9488, dark: 0x2DD4BF)
        static let calves          = adaptive(light: 0x06B6D4, dark: 0x22D3EE)
        static let core            = adaptive(light: 0xF59E0B, dark: 0xFBBF24)
        static let cardio          = adaptive(light: 0x06B6D4, dark: 0x22D3EE)

        // Surface tints — pre-resolved adaptive fills
        static let accentTint      = adaptive(light: 0xEEF2FC, dark: 0x141C30)
        static let warmTint        = adaptive(light: 0xFFF8F0, dark: 0x251D14)
        static let successTint     = adaptive(light: 0xEFFBF3, dark: 0x122118)
        static let surfaceRaised   = adaptive(light: 0xFAF9F7, dark: 0x222224)

        /// Lookup muscle group color by enum value.
        static func muscleGroupColor(for group: MuscleGroup) -> Color {
            switch group {
            case .chest: return chest
            case .back: return back
            case .traps: return shoulders
            case .shoulders: return shoulders
            case .biceps: return biceps
            case .triceps: return triceps
            case .forearms: return biceps
            case .quads: return quads
            case .hamstrings: return hamstrings
            case .glutes: return glutes
            case .hipFlexors: return hipFlexors
            case .adductors: return glutes
            case .calves: return calves
            case .core: return core
            case .cardio: return cardio
            }
        }
    }

    // MARK: - UIKit Colors (for UIAppearance)

    enum UIColors {
        /// Helper: creates a UIColor that adapts between light and dark mode.
        private static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
            UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(hex: dark)
                    : UIColor(hex: light)
            }
        }

        static let background      = adaptive(light: 0xF6F4F0, dark: 0x0F0F11)
        static let surface         = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
        static let elevated        = adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
        static let cardBackground  = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
        static let border          = adaptive(light: 0xE0DBD3, dark: 0x38383A)

        static let textPrimary     = adaptive(light: 0x1A1714, dark: 0xECECED)
        static let textSecondary   = adaptive(light: 0x5F5954, dark: 0xB0B0B5)
        static let textTertiary    = adaptive(light: 0x746E68, dark: 0x98989D)

        static let accent          = adaptive(light: 0x2563EB, dark: 0x3B82F6)
        static let accentSecondary = adaptive(light: 0xC2410C, dark: 0xFB923C)
    }

    static func configureGlobalAppearance() {
        // Keep UIKit appearance intentionally narrow. NavigationStack and TabView own their
        // native iOS 26 materials, scrolling transitions, and accessibility behavior.
        let navBar = UINavigationBar.appearance()
        navBar.tintColor = UIColors.accent

        let tabBar = UITabBar.appearance()
        tabBar.tintColor = UIColors.accent
        tabBar.unselectedItemTintColor = UIColors.textTertiary
    }

    // MARK: - Typography

    enum Typography {
        private static func text(_ weight: ThemeTextWeight, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
            Font.custom(weight.fontName, size: size, relativeTo: style)
        }

        private static func display(_ weight: ThemeDisplayWeight, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
            Font.custom(weight.fontName, size: size, relativeTo: style)
        }

        private static func scaledUIFont(
            named name: String,
            size: CGFloat,
            textStyle: UIFont.TextStyle,
            fallbackWeight: UIFont.Weight
        ) -> UIFont {
            let base = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: fallbackWeight)
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
        }

        fileprivate static func uiKitText(size: CGFloat, textStyle: UIFont.TextStyle, weight: ThemeTextWeight) -> UIFont {
            scaledUIFont(named: weight.fontName, size: size, textStyle: textStyle, fallbackWeight: weight.fallback)
        }

        fileprivate static func uiKitDisplay(size: CGFloat, textStyle: UIFont.TextStyle, weight: ThemeDisplayWeight) -> UIFont {
            scaledUIFont(named: weight.fontName, size: size, textStyle: textStyle, fallbackWeight: weight.fallback)
        }

        // Sora handles brand and display moments. Sizes are moderated from the
        // previous condensed wordmark so the wider letterforms still fit well.
        static let wordmarkHuge = display(.bold, size: 36, relativeTo: .largeTitle)
        static let wordmarkHugeCompact = display(.bold, size: 30, relativeTo: .largeTitle)
        static let wordmarkBig = display(.semibold, size: 28, relativeTo: .title)
        static let wordmarkBigCompact = display(.semibold, size: 24, relativeTo: .title)
        static let eyebrowRounded = text(.medium, size: 13, relativeTo: .caption)
        static let screenTitle = display(.bold, size: 32, relativeTo: .largeTitle)
        static let sectionHeader = display(.semibold, size: 24, relativeTo: .title)
        static let sectionHeader2 = display(.semibold, size: 20, relativeTo: .title2)
        static let cardHeader = display(.semibold, size: 18, relativeTo: .title3)
        static let metricLabel = text(.semibold, size: 12, relativeTo: .caption)
        static let tabLabel = text(.medium, size: 11, relativeTo: .caption2)
        static let heroTitle = display(.bold, size: 30, relativeTo: .title)

        // Instrument Sans carries the app UI. Display grades stay reserved for
        // headings and brand moments to keep the hierarchy tight.
        static let largeTitle = display(.bold, size: 32, relativeTo: .largeTitle)
        static let title = display(.bold, size: 28, relativeTo: .title)
        static let title2 = display(.semibold, size: 22, relativeTo: .title2)
        static let title3 = display(.semibold, size: 18, relativeTo: .title3)
        static let avatarMonogram = display(.bold, size: 22, relativeTo: .title3)
        static let bodyLarge = text(.medium, size: 20, relativeTo: .title3)
        static let title4 = display(.semibold, size: 17, relativeTo: .headline)
        static let title4Bold = display(.bold, size: 17, relativeTo: .headline)
        static let headline = text(.semibold, size: 17, relativeTo: .headline)
        static let body = text(.regular, size: 17, relativeTo: .body)
        static let bodyBold = text(.semibold, size: 17, relativeTo: .body)
        static let bodyStrong = text(.bold, size: 17, relativeTo: .body)
        static let callout = text(.medium, size: 16, relativeTo: .callout)
        static let calloutStrong = text(.semibold, size: 16, relativeTo: .callout)
        static let calloutBold = text(.bold, size: 16, relativeTo: .callout)
        static let subheadline = text(.medium, size: 15, relativeTo: .subheadline)
        static let subheadlineStrong = text(.semibold, size: 15, relativeTo: .subheadline)
        static let subheadlineBold = text(.bold, size: 15, relativeTo: .subheadline)
        static let footnote = text(.medium, size: 13, relativeTo: .footnote)
        static let footnoteStrong = text(.semibold, size: 13, relativeTo: .footnote)
        static let footnoteBold = text(.bold, size: 13, relativeTo: .footnote)
        static let caption = text(.medium, size: 12, relativeTo: .caption)
        static let captionStrong = text(.semibold, size: 12, relativeTo: .caption)
        static let captionBold = text(.bold, size: 12, relativeTo: .caption)
        static let caption2 = text(.medium, size: 11, relativeTo: .caption2)
        static let caption2Bold = text(.bold, size: 11, relativeTo: .caption2)

        // Numeric emphasis now uses the UI family instead of a monospaced face.
        static let number = text(.bold, size: 28, relativeTo: .title2)
        static let numberLarge = text(.bold, size: 40, relativeTo: .largeTitle)
        static let numberSmall = text(.bold, size: 17, relativeTo: .headline)
        static let metricLarge = text(.bold, size: 44, relativeTo: .largeTitle)
        static let metric = text(.bold, size: 30, relativeTo: .title)
        static let condensed = text(.semibold, size: 16, relativeTo: .callout)
        static let microcopy = text(.regular, size: 13, relativeTo: .footnote)
        static let microcopySmall = text(.regular, size: 11, relativeTo: .caption2)
        static let microLabel = text(.bold, size: 10, relativeTo: .caption2)

        // Legacy "mono" tokens keep their names for compatibility, but now
        // resolve to the primary UI family.
        static let monoMedium = text(.bold, size: 18, relativeTo: .headline)
        static let monoSmall = text(.semibold, size: 14, relativeTo: .footnote)
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

    // MARK: - Chart Heights

    enum ChartHeight {
        static let compact: CGFloat = 140
        static let standard: CGFloat = 240
        static let expanded: CGFloat = 300
    }

    // MARK: - Layout

    enum Layout {
        static let maxContentWidth: CGFloat = 880
        static let minimumTapTarget: CGFloat = 44
    }

    // MARK: - Opacity — semantic fill levels for tinted backgrounds

    enum Opacity {
        static let subtleFill: Double = 0.06
        static let mediumFill: Double = 0.12
        static let strongFill: Double = 0.20
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

// MARK: - Refined Card Modifier

struct SoftCardBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.CornerRadius.large
    var elevation: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        Theme.Colors.border.opacity(isDark ? 0.8 : 0.5),
                        lineWidth: isDark ? 0.5 : 1
                    )
            )
            .shadow(
                color: Color.black.opacity((isDark ? 0.12 : 0.055) * min(elevation, 2)),
                radius: 5 * elevation,
                x: 0,
                y: 2 * elevation
            )
    }
}

// MARK: - Glass Background Modifier (Subtle Surface)

struct GlassBackground: ViewModifier {
    var opacity: Double = 0.08
    var cornerRadius: CGFloat = Theme.CornerRadius.medium
    var elevation: CGFloat = 1
    var interactive = false
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(
                    Theme.Colors.surface.opacity(opacity),
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
                .shadow(
                    color: Color.black.opacity(0.04 * elevation),
                    radius: 5 * elevation,
                    y: 2 * elevation
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
                .background(
                    Theme.Colors.surface.opacity(opacity),
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            Theme.Colors.border.opacity(colorScheme == .dark ? 0.7 : 0.4),
                            lineWidth: colorScheme == .dark ? 0.5 : 1
                        )
                )
        }
    }
}

// MARK: - Refined Button Chrome

struct SurfaceButtonChrome: ViewModifier {
    var fill: Color = Theme.Colors.surface
    var border: Color = Theme.Colors.border
    var cornerRadius: CGFloat = Theme.CornerRadius.large
    var borderWidth: CGFloat = 1
    var shadowOffset: CGFloat = 2
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        border.opacity(isDark ? 0.7 : 0.4),
                        lineWidth: isDark ? 0.5 : borderWidth
                    )
            )
            .shadow(
                color: Color.black.opacity(0.06),
                radius: max(2, shadowOffset * 2),
                x: 0,
                y: shadowOffset
            )
    }
}

/// Default interaction style for app controls.
/// Provides consistent pressed/disabled feedback with smooth spring animation.
struct AppInteractionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1.0 : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: configuration.isPressed)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: isEnabled)
    }
}

// MARK: - Accent Gradient Helpers

extension Theme {
    /// Primary action gradient — hero buttons, CTAs
    static let accentGradient = LinearGradient(
        colors: [
            Color(uiColor: UIColor(hex: 0x60A5FA)),
            Color(uiColor: UIColor(hex: 0x2563EB)),
            Color(uiColor: UIColor(hex: 0x1E40AF))
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
        elevation: CGFloat = 1,
        interactive: Bool = false
    ) -> some View {
        modifier(
            GlassBackground(
                opacity: opacity,
                cornerRadius: cornerRadius,
                elevation: elevation,
                interactive: interactive
            )
        )
    }

    func softCard(
        cornerRadius: CGFloat = Theme.CornerRadius.large,
        elevation: CGFloat = 1
    ) -> some View {
        modifier(SoftCardBackground(cornerRadius: cornerRadius, elevation: elevation))
    }

    func surfaceButtonChrome(
        fill: Color = Theme.Colors.surface,
        border: Color = Theme.Colors.border,
        cornerRadius: CGFloat = Theme.CornerRadius.large,
        borderWidth: CGFloat = 1,
        shadowOffset: CGFloat = 2
    ) -> some View {
        modifier(
            SurfaceButtonChrome(
                fill: fill,
                border: border,
                cornerRadius: cornerRadius,
                borderWidth: borderWidth,
                shadowOffset: shadowOffset
            )
        )
    }

    func cardStyle() -> some View {
        self
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
    }

    /// Consistent section header styling: uppercase, tracked, tertiary color.
    func sectionHeaderStyle() -> some View {
        self
            .font(Theme.Typography.metricLabel)
            .foregroundStyle(Theme.Colors.textTertiary)
            .tracking(1.0)
            .textCase(.uppercase)
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

    /// Keeps reading and form content comfortably centered on wide displays while
    /// remaining fluid on iPhone and in compact split-view widths.
    func contentColumn(
        maxWidth: CGFloat = Theme.Layout.maxContentWidth,
        alignment: Alignment = .leading
    ) -> some View {
        self
            .frame(maxWidth: maxWidth, alignment: alignment)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Provides a final safety net for custom animations that do not directly
    /// inspect Reduce Motion, including content in deeper navigation flows.
    func respectReduceMotion() -> some View {
        modifier(ReduceMotionTransactionModifier())
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 12)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.98)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Animation.gentleSpring.delay(delay), value: isVisible)
            .onAppear {
                isVisible = true
            }
    }
}

private struct ReduceMotionTransactionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            guard reduceMotion else { return }
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

// MARK: - Staggered Appear Modifier

struct StaggeredAppearModifier: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 16)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.96)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Animation.gentleSpring.delay(baseDelay + Double(index) * 0.06), value: isVisible)
            .onAppear { isVisible = true }
    }
}

extension View {
    func staggeredAppear(index: Int, baseDelay: Double = 0.05) -> some View {
        modifier(StaggeredAppearModifier(index: index, baseDelay: baseDelay))
    }

    /// Adds a subtle swipe-hint chevron affordance to the trailing edge of a view.
    func swipeHint(edge: HorizontalEdge = .trailing) -> some View {
        modifier(SwipeHintModifier(edge: edge))
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
        case .traps: return Theme.Colors.shoulders
        case .shoulders: return Theme.Colors.shoulders
        case .biceps: return Theme.Colors.biceps
        case .triceps: return Theme.Colors.triceps
        case .forearms: return Theme.Colors.biceps
        case .quads: return Theme.Colors.quads
        case .hamstrings: return Theme.Colors.hamstrings
        case .glutes: return Theme.Colors.glutes
        case .hipFlexors: return Theme.Colors.hipFlexors
        case .adductors: return Theme.Colors.glutes
        case .calves: return Theme.Colors.calves
        case .core: return Theme.Colors.core
        case .cardio: return Theme.Colors.cardio
        }
    }

    var iconName: String {
        switch self {
        case .chest: return "heart.fill"
        case .back: return "arrow.left.and.right"
        case .traps: return "mountain.2.fill"
        case .shoulders: return "figure.arms.open"
        case .biceps: return "figure.strengthtraining.functional"
        case .triceps: return "arrow.up.right"
        case .forearms: return "hand.raised.fill"
        case .quads: return "figure.walk"
        case .hamstrings: return "figure.run"
        case .glutes: return "figure.cooldown"
        case .hipFlexors: return "figure.flexibility"
        case .adductors: return "figure.flexibility"
        case .calves: return "shoeprints.fill"
        case .core: return "circle.hexagongrid"
        case .cardio: return "heart.text.square"
        }
    }

    var shortName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .traps: return "Traps"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quads: return "Quads"
        case .hamstrings: return "Hams"
        case .glutes: return "Glutes"
        case .hipFlexors: return "Hip Flexors"
        case .adductors: return "Adductors"
        case .calves: return "Calves"
        case .core: return "Core"
        case .cardio: return "Cardio"
        }
    }
}

// MARK: - Section Divider

/// A subtle full-bleed divider for separating visual sections with breathing room.
struct SectionDivider: View {
    var tint: Color = Theme.Colors.border
    var verticalPadding: CGFloat = Theme.Spacing.sm

    var body: some View {
        Rectangle()
            .fill(tint.opacity(0.35))
            .frame(height: 1)
            .padding(.vertical, verticalPadding)
    }
}

// MARK: - Swipe Hint Modifier

struct SwipeHintModifier: ViewModifier {
    let edge: HorizontalEdge
    @State private var hintVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .trailing ? .trailing : .leading) {
                Image(systemName: edge == .trailing ? "chevron.right" : "chevron.left")
                    .font(Theme.Typography.caption2Bold)
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.5))
                    .padding(.horizontal, Theme.Spacing.xs)
                    .opacity(hintVisible ? 1 : 0)
                    .offset(x: hintVisible ? 0 : (edge == .trailing ? -4 : 4))
                    .animation(reduceMotion ? .none : Theme.Animation.gentleSpring.repeatForever(autoreverses: true), value: hintVisible)
            }
            .onAppear {
                if !reduceMotion {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        hintVisible = true
                    }
                }
            }
    }
}

// MARK: - Inline Section Surface

/// Alternating surface tint for visual rhythm between stacked full-bleed sections.
struct InlineSectionSurface: ViewModifier {
    var isAlternate: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.lg)
            .background(
                isAlternate
                    ? Theme.Colors.surfaceRaised
                    : Color.clear
            )
    }
}
