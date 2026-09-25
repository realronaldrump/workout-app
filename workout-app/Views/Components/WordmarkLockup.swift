import SwiftUI

struct WordmarkLockup: View {
    var showTagline: Bool = true
    var tagline: String = "Best Workout App in The World"
    var isOnSplash: Bool = false
    var alignment: HorizontalAlignment = .center

    private var primaryText: Color { isOnSplash ? .white : Theme.Colors.textPrimary }
    private var secondaryText: Color { isOnSplash ? Color.white.opacity(0.86) : Theme.Colors.textSecondary }
    private var textAlignment: TextAlignment {
        switch alignment {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        default:
            return .center
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            Text("Davis's")
                .font(Theme.Typography.eyebrowRounded)
                .foregroundStyle(secondaryText)
                .textCase(.uppercase)
                .tracking(2.0)

            // Mirrors the app icon: BIG / BEAUTIFUL on a band / WORKOUT APP.
            VStack(alignment: alignment, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    Text("BIG")
                        .font(Theme.Typography.wordmarkHuge)

                    Text("BIG")
                        .font(Theme.Typography.wordmarkHugeCompact)
                }
                .tracking(1.5)
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                ViewThatFits(in: .horizontal) {
                    bandWord(font: Theme.Typography.wordmarkHuge)
                    bandWord(font: Theme.Typography.wordmarkHugeCompact)
                }

                ViewThatFits(in: .horizontal) {
                    Text("WORKOUT APP")
                        .font(Theme.Typography.wordmarkBig)

                    Text("WORKOUT APP")
                        .font(Theme.Typography.wordmarkBigCompact)
                }
                .tracking(1.0)
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }

            if showTagline {
                Text(tagline)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(textAlignment)
                    .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Davis's Big Beautiful Workout App. \(tagline)")
    }

    private func bandWord(font: Font) -> some View {
        Text("BEAUTIFUL")
            .font(font)
            .tracking(1.5)
            .foregroundStyle(isOnSplash ? Theme.Colors.onHeroAccent : Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(
                Rectangle()
                    .fill(isOnSplash ? Color.white : Theme.Colors.brandBand)
            )
    }
}

#Preview {
    ZStack {
        SplashBackground()
        WordmarkLockup(isOnSplash: true)
            .padding(Theme.Spacing.xl)
    }
}
