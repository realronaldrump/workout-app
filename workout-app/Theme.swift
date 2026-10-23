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
            return "Barlow-Regular"
        case .medium:
            return "Barlow-Medium"
        case .semibold:
            return "Barlow-SemiBold"
        case .bold:
            return "Barlow-Bold"
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
    case semibold
    case bold
    case extraBold
    case black

    var fontName: String {
        switch self {
        case .semibold:
            return "BigShouldersDisplay-SemiBold"
        case .bold:
            return "BigShouldersDisplay-Bold"
        case .extraBold:
            return "BigShouldersDisplay-ExtraBold"
        case .black:
            return "BigShouldersDisplay-Black"
        }
    }

    var fallback: UIFont.Weight {
        switch self {
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        case .extraBold:
            return .heavy
        case .black:
            return .black
        }
    }
}

/// Centralized theme system: Loaded.
///
/// The working surface is monochrome (ink on concrete, chalk on rubber) and flat:
/// no drop shadows, gradients, or glows. Color is reserved for meaning: bumper-plate
/// colors mark training categories, metric hues mark Health data, and green/red/yellow
/// carry better, worse, and personal records. Big Shoulders Display sets every number
/// and title at poster scale; Barlow carries the interface.
enum Theme {

    // MARK: - Colors

    enum Colors {
        /// Helper: creates a SwiftUI Color that adapts between light and dark mode.
        private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(hex: dark)
                    : UIColor(hex: light)
            })
        }

        // Ground and surfaces: concrete (light) / rubber floor (dark).
        static let ground          = adaptive(light: 0xE8E8E3, dark: 0x161719)
        static let panel           = adaptive(light: 0xF5F5F1, dark: 0x212226)
        /// Inset step inside a panel: input wells, nested tiles, tracks.
        static let panelInset      = adaptive(light: 0xECECE7, dark: 0x2A2B2F)
        /// Strongest neutral step: unselected segments, empty plate slots, pressed rows.
        static let panelStrong     = adaptive(light: 0xDCDCD6, dark: 0x2E2F34)
        static let rule            = adaptive(light: 0xCFCFC9, dark: 0x34353A)

        static let background      = ground
        static let surface         = panel
        static let elevated        = adaptive(light: 0xFBFBF8, dark: 0x26272B)
        static let cardBackground  = panel
        static let border          = rule

        // Ink hierarchy. Every text tier clears 4.5:1 on ground and panel.
        static let ink             = adaptive(light: 0x141416, dark: 0xF0EFEA)
        static let textPrimary     = ink
        static let textSecondary   = adaptive(light: 0x56565A, dark: 0xA9A9A4)
        /// Muted text still meets a 4.5:1 contrast target on app surfaces.
        static let textMuted       = adaptive(light: 0x636367, dark: 0x93938E)
        /// Decorative separators and disabled ornament only. Never use for text.
        static let decorativeSubtle = adaptive(light: 0xA6A6A0, dark: 0x4C4D52)
        /// Compatibility alias for existing call sites. Semantically this is muted text.
        static let textTertiary    = textMuted

        // Interaction is monochrome: ink fills carry the inverse color on top.
        static let accent          = ink
        /// Foreground for anything drawn on an `accent` (ink) fill.
        static let onAccent        = adaptive(light: 0xF5F5F1, dark: 0x161719)

        // Bumper plates (IWF colors, matte). Training categories and data marks.
        static let plateRed        = adaptive(light: 0xBF2D27, dark: 0xF0544B)
        static let plateBlue       = adaptive(light: 0x1F52B8, dark: 0x6595F3)
        static let plateYellow     = adaptive(light: 0xE5AE16, dark: 0xF3C537)
        static let plateGreen      = adaptive(light: 0x1B7542, dark: 0x45C177)
        static let plateWhite      = adaptive(light: 0xFFFFFF, dark: 0xE9E7E1)

        static let accentSecondary = plateRed
        static let accentTertiary  = plateBlue

        // Semantic colors
        static let success         = plateGreen
        static let warning         = adaptive(light: 0x7D5A00, dark: 0xF3C537)
        static let error           = plateRed
        /// Filled destructive controls retain contrast with white text in both appearances.
        static let destructiveFill  = Color(uiColor: UIColor(hex: 0xBF2D27))
        static let info            = plateBlue
        static let shadowOpacity: Double = 0

        // PR/Achievement: the yellow 15 kg plate. Use `plateYellow` for fills.
        static let gold            = adaptive(light: 0x8F6800, dark: 0xF3C537)

        // Muscle groups: distinct matte hues so charts with several groups stay legible.
        static let chest           = adaptive(light: 0xBF2D27, dark: 0xF0544B)
        static let back            = adaptive(light: 0x1F52B8, dark: 0x6595F3)
        static let shoulders       = adaptive(light: 0xC9711A, dark: 0xF09A45)
        static let biceps          = adaptive(light: 0x6A4BB8, dark: 0xA48BF0)
        static let triceps         = adaptive(light: 0xB23A6E, dark: 0xEC6FA2)
        static let quads           = adaptive(light: 0x1B7542, dark: 0x45C177)
        static let hamstrings      = adaptive(light: 0x177D7D, dark: 0x3CC4C0)
        static let glutes          = adaptive(light: 0x8B4FA8, dark: 0xC48BE0)
        static let hipFlexors      = adaptive(light: 0x5E7D1E, dark: 0x9CC24A)
        static let calves          = adaptive(light: 0x2C7FAD, dark: 0x5FB4E3)
        static let core            = adaptive(light: 0xA57F00, dark: 0xF3C537)
        static let cardio          = adaptive(light: 0x5D6B78, dark: 0xA5B3BF)

        // Surface tints: flat tonal fills, no gradients.
        static let accentTint      = panelStrong
        static let warmTint        = adaptive(light: 0xF2E8CC, dark: 0x2D2716)
        static let successTint     = adaptive(light: 0xDDEBE1, dark: 0x16271D)
        static let surfaceRaised   = panelInset

        /// Kept for older call sites; cards are flat now.
        static let cardSheen       = panel
        /// Fill behind small labels that previously sat on the electric-blue band.
        static let brandBand       = ink
        static let brandDeep       = ink
        /// Ink for content on a fixed white chip.
        static let onHeroAccent    = Color(uiColor: UIColor(hex: 0x141416))

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

        static let background      = adaptive(light: 0xE8E8E3, dark: 0x161719)
        static let surface         = adaptive(light: 0xF5F5F1, dark: 0x212226)
        static let elevated        = adaptive(light: 0xFBFBF8, dark: 0x26272B)
        static let cardBackground  = adaptive(light: 0xF5F5F1, dark: 0x212226)
        static let border          = adaptive(light: 0xCFCFC9, dark: 0x34353A)

        static let textPrimary     = adaptive(light: 0x141416, dark: 0xF0EFEA)
        static let textSecondary   = adaptive(light: 0x56565A, dark: 0xA9A9A4)
        static let textTertiary    = adaptive(light: 0x636367, dark: 0x93938E)

        static let accent          = adaptive(light: 0x141416, dark: 0xF0EFEA)
        static let accentSecondary = adaptive(light: 0xBF2D27, dark: 0xF0544B)
    }

    static func configureGlobalAppearance() {
        // Keep UIKit appearance intentionally narrow. NavigationStack and TabView own their
        // native iOS 26 materials, scrolling transitions, and accessibility behavior; only
        // the title faces and tint are branded.
        let navBar = UINavigationBar.appearance()
        navBar.tintColor = UIColors.accent
        navBar.largeTitleTextAttributes = [
            .font: Typography.uiKitDisplay(size: 44, textStyle: .largeTitle, weight: .extraBold),
            .foregroundColor: UIColors.textPrimary
        ]
        navBar.titleTextAttributes = [
            .font: Typography.uiKitText(size: 17, textStyle: .headline, weight: .semibold),
            .foregroundColor: UIColors.textPrimary
        ]

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

        // Big Shoulders Display: condensed athletic signage. It sets titles and numbers
        // large; sizes run about a quarter bigger than a regular-width face would need.
        static let wordmarkHuge = display(.black, size: 56, relativeTo: .largeTitle)
        static let wordmarkHugeCompact = display(.black, size: 46, relativeTo: .largeTitle)
        static let wordmarkBig = display(.extraBold, size: 36, relativeTo: .title)
        static let wordmarkBigCompact = display(.extraBold, size: 30, relativeTo: .title)
        static let screenTitle = display(.extraBold, size: 44, relativeTo: .largeTitle)
        static let sectionHeader = display(.bold, size: 32, relativeTo: .title)
        static let sectionHeader2 = display(.bold, size: 28, relativeTo: .title2)
        static let cardHeader = display(.bold, size: 24, relativeTo: .title3)
        static let heroTitle = display(.extraBold, size: 40, relativeTo: .title)
        /// Poster-weight display face for greetings and celebration moments.
        static let displayHero = display(.extraBold, size: 52, relativeTo: .largeTitle)
        static let displayHeroCompact = display(.extraBold, size: 42, relativeTo: .largeTitle)
        /// Big numerals for hero stats. Static values only: the display face has
        /// proportional figures, so live timers use `timer`.
        static let heroNumber = display(.extraBold, size: 64, relativeTo: .largeTitle)
        /// The single poster-scale number on Today.
        static let posterNumber = display(.black, size: 132, relativeTo: .largeTitle)
        /// The Body screen's trend weight: big enough to read across a room, smaller than the week poster.
        static let bodyHero = display(.black, size: 92, relativeTo: .largeTitle)
        static let ringNumber = display(.extraBold, size: 34, relativeTo: .title2)
        /// Small label that used to sit on the brand band; now sentence case.
        static let bandLabel = text(.semibold, size: 12, relativeTo: .caption2)
        static let eyebrowRounded = text(.medium, size: 13, relativeTo: .caption)
        static let metricLabel = text(.medium, size: 13, relativeTo: .caption)
        static let tabLabel = text(.medium, size: 11, relativeTo: .caption2)

        static let largeTitle = display(.extraBold, size: 44, relativeTo: .largeTitle)
        static let title = display(.extraBold, size: 36, relativeTo: .title)
        static let title2 = display(.bold, size: 30, relativeTo: .title2)
        static let title3 = display(.bold, size: 24, relativeTo: .title3)
        static let avatarMonogram = display(.extraBold, size: 30, relativeTo: .title3)

        // Barlow carries the interface.
        static let bodyLarge = text(.medium, size: 20, relativeTo: .title3)
        static let title4 = text(.semibold, size: 18, relativeTo: .headline)
        static let title4Bold = text(.bold, size: 18, relativeTo: .headline)
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
        static let footnote = text(.medium, size: 14, relativeTo: .footnote)
        static let footnoteStrong = text(.semibold, size: 14, relativeTo: .footnote)
        static let footnoteBold = text(.bold, size: 14, relativeTo: .footnote)
        static let caption = text(.medium, size: 13, relativeTo: .caption)
        static let captionStrong = text(.semibold, size: 13, relativeTo: .caption)
        static let captionBold = text(.semibold, size: 13, relativeTo: .caption)
        static let caption2 = text(.medium, size: 12, relativeTo: .caption2)
        static let caption2Bold = text(.semibold, size: 12, relativeTo: .caption2)

        // Numbers: the display face for static values.
        static let number = display(.extraBold, size: 34, relativeTo: .title2)
        static let numberLarge = display(.extraBold, size: 52, relativeTo: .largeTitle)
        static let numberSmall = display(.bold, size: 22, relativeTo: .headline)
        static let metricLarge = display(.extraBold, size: 60, relativeTo: .largeTitle)
        static let metric = display(.extraBold, size: 40, relativeTo: .title)
        /// Live, ticking numbers. Barlow has tabular figures; pair with `.monospacedDigit()`.
        static let timer = text(.semibold, size: 44, relativeTo: .largeTitle)
        /// A ticking number sized to sit beside `number` stats.
        static let timerSmall = text(.bold, size: 28, relativeTo: .title2)
        static let condensed = text(.semibold, size: 16, relativeTo: .callout)
        static let microcopy = text(.regular, size: 14, relativeTo: .footnote)
        static let microcopySmall = text(.regular, size: 12, relativeTo: .caption2)
        static let microLabel = text(.semibold, size: 11, relativeTo: .caption2)

        // Legacy "mono" tokens keep their names for compatibility. Both are number styles.
        static let monoMedium = display(.bold, size: 24, relativeTo: .headline)
        static let monoSmall = text(.semibold, size: 15, relativeTo: .footnote)
    }

    enum Iconography {
        static let micro = Font.system(size: 10, weight: .semibold, design: .default)
        static let small = Font.system(size: 12, weight: .medium, design: .default)
        static let medium = Font.system(size: 14, weight: .medium, design: .default)
        static let mediumStrong = Font.system(size: 14, weight: .semibold, design: .default)
        static let title3 = Font.system(size: 20, weight: .medium, design: .default)
        static let title3Strong = Font.system(size: 20, weight: .semibold, design: .default)
        static let action = Font.system(size: 22, weight: .medium, design: .default)
        static let title2 = Font.system(size: 24, weight: .medium, design: .default)
        static let title2Strong = Font.system(size: 24, weight: .semibold, design: .default)
        static let title2Bold = Font.system(size: 24, weight: .bold, design: .default)
        static let prominent = Font.system(size: 28, weight: .medium, design: .default)
        static let hero = Font.system(size: 32, weight: .semibold, design: .default)
        static let feature = Font.system(size: 40, weight: .medium, design: .default)
        static let featureLarge = Font.system(size: 48, weight: .semibold, design: .default)
        static let dashboard = Font.system(size: 52, weight: .medium, design: .default)
        static let display = Font.system(size: 56, weight: .medium, design: .default)
        static let wizard = Font.system(size: 60, weight: .medium, design: .default)
        static let wizardHero = Font.system(size: 80, weight: .medium, design: .default)
        static let largeTitle = Font.system(size: 34, weight: .medium, design: .default)
    }

    // MARK: - Animation

    enum Animation {
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.86)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.16)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.28)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.42)
        static let chartAppear = SwiftUI.Animation.spring(response: 0.55, dampingFraction: 0.85)
        /// Plates sliding onto the bar: a little weight, a small settle.
        static let plateLoad = SwiftUI.Animation.spring(response: 0.42, dampingFraction: 0.74)
        static let bouncy = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
        static let gentleSpring = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.9)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 44
        /// Vertical gap between major sections of a screen.
        static let section: CGFloat = 40
    }

    // MARK: - Corner Radius
    //
    // Radius follows role, not habit: big panels are soft, controls are capsules,
    // tags are nearly square like a stamped plate label.

    enum CornerRadius {
        static let tag: CGFloat = 5
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 18
        static let xlarge: CGFloat = 24
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
        static let screenGutter: CGFloat = 20
        static let primaryControlHeight: CGFloat = 58
    }

    // MARK: - Opacity — semantic fill levels for tinted backgrounds

    enum Opacity {
        static let subtleFill: Double = 0.08
        static let mediumFill: Double = 0.14
        static let strongFill: Double = 0.22
    }
}

// MARK: - Background

/// The ground every screen sits on: flat concrete in light mode, rubber floor in dark.
struct AdaptiveBackground: View {
    var body: some View {
        Theme.Colors.ground
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

// MARK: - Splash Background

struct SplashBackground: View {
    var body: some View {
        Theme.Colors.ground
            .ignoresSafeArea()
    }
}

// MARK: - Panel Modifier

/// The app's container: a flat tonal plate with soft corners. No shadow and no border
/// unless the person asked for increased contrast. `elevation` picks the tone step:
/// 0 sits inset, 1 is the standard panel, 2 and up lift to the elevated tone.
struct SoftCardBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.CornerRadius.xlarge
    var elevation: CGFloat = 1
    @Environment(\.colorSchemeContrast) private var contrast

    private var fill: Color {
        if elevation <= 0 { return Theme.Colors.panelInset }
        return Theme.Colors.panel
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(fill))
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(Theme.Colors.textSecondary, lineWidth: 1.5)
                }
            }
    }
}

// MARK: - Subtle Surface Modifier

/// Formerly frosted glass. Now the same flat panel tone, tuned for small controls.
struct GlassBackground: ViewModifier {
    var opacity: Double = 0.08
    var cornerRadius: CGFloat = Theme.CornerRadius.medium
    var elevation: CGFloat = 1
    var interactive = false
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(Theme.Colors.panel))
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(Theme.Colors.textSecondary, lineWidth: 1.5)
                }
            }
    }
}

// MARK: - Button Chrome

/// Flat fill with a thin rule. Used by secondary in-content buttons.
struct SurfaceButtonChrome: ViewModifier {
    var fill: Color = Theme.Colors.surface
    var border: Color = Theme.Colors.border
    var cornerRadius: CGFloat = Theme.CornerRadius.large
    var borderWidth: CGFloat = 1
    var shadowOffset: CGFloat = 0
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(fill))
            .overlay(
                shape.strokeBorder(
                    contrast == .increased ? Theme.Colors.textSecondary : border,
                    lineWidth: contrast == .increased ? 1.5 : borderWidth
                )
            )
    }
}

/// Default interaction style for app controls.
/// Provides consistent pressed/disabled feedback.
struct AppInteractionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1.0) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: configuration.isPressed)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: isEnabled)
    }
}

// MARK: - Fill Helpers
//
// These names predate the flat system and are typed as gradients at their call sites.
// Each is now a single flat color.

extension Theme {
    /// Primary action fill: solid ink.
    static let accentGradient = LinearGradient(
        colors: [Theme.Colors.accent, Theme.Colors.accent],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Hero fill: solid ink.
    static let heroGradient = LinearGradient(
        colors: [Theme.Colors.ink, Theme.Colors.ink],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Achievement fill: the yellow plate.
    static let warmGradient = LinearGradient(
        colors: [Theme.Colors.plateYellow, Theme.Colors.plateYellow],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Positive fill: the green plate.
    static let successGradient = LinearGradient(
        colors: [Theme.Colors.plateGreen, Theme.Colors.plateGreen],
        startPoint: .top,
        endPoint: .bottom
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
        cornerRadius: CGFloat = Theme.CornerRadius.xlarge,
        elevation: CGFloat = 1
    ) -> some View {
        modifier(SoftCardBackground(cornerRadius: cornerRadius, elevation: elevation))
    }

    func surfaceButtonChrome(
        fill: Color = Theme.Colors.surface,
        border: Color = Theme.Colors.border,
        cornerRadius: CGFloat = Theme.CornerRadius.large,
        borderWidth: CGFloat = 1,
        shadowOffset: CGFloat = 0
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
            .softCard()
    }

    /// Small supporting label above a value or group: sentence case, secondary ink.
    func sectionHeaderStyle() -> some View {
        self
            .font(Theme.Typography.metricLabel)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    /// Tinted section background: a flat wash of a meaning color.
    func tintedSection(_ color: Color, cornerRadius: CGFloat = Theme.CornerRadius.xlarge) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color.opacity(Theme.Opacity.subtleFill))
            )
    }

    /// Entrance animation hook. Sections appear in place; the Today bar owns the
    /// screen's one orchestrated motion.
    func animateOnAppear(delay: Double = 0) -> some View {
        self
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

extension View {
    /// Former staggered entrance. Lists render in place.
    func staggeredAppear(index: Int, baseDelay: Double = 0.05) -> some View {
        self
    }

    /// Adds a subtle swipe-hint chevron affordance to the trailing edge of a view.
    func swipeHint(edge: HorizontalEdge = .trailing) -> some View {
        modifier(SwipeHintModifier(edge: edge))
    }
}

// MARK: - PR Marker View

/// A personal record, stamped like the label on a yellow 15 kg plate.
struct PRMarkerView: View {
    let date: Date

    var body: some View {
        PRTag()
    }
}

struct PRTag: View {
    var text = "PR"

    var body: some View {
        Text(text)
            .font(Theme.Typography.caption2Bold)
            .foregroundStyle(Theme.Colors.onHeroAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Colors.plateYellow, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.tag, style: .continuous))
            .accessibilityLabel(text == "PR" ? "Personal record" : text)
    }
}

// MARK: - MuscleGroup Extensions

extension MuscleGroup {
    var color: Color {
        Theme.Colors.muscleGroupColor(for: self)
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

/// A ruled line between sections, like the lines in a training log.
struct SectionDivider: View {
    var tint: Color = Theme.Colors.rule
    var verticalPadding: CGFloat = Theme.Spacing.sm

    var body: some View {
        Rectangle()
            .fill(tint)
            .frame(height: 1)
            .padding(.vertical, verticalPadding)
            .accessibilityHidden(true)
    }
}

// MARK: - Swipe Hint Modifier

struct SwipeHintModifier: ViewModifier {
    let edge: HorizontalEdge

    func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .trailing ? .trailing : .leading) {
                Image(systemName: edge == .trailing ? "chevron.right" : "chevron.left")
                    .font(Theme.Typography.caption2Bold)
                    .foregroundStyle(Theme.Colors.decorativeSubtle)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .accessibilityHidden(true)
            }
    }
}
