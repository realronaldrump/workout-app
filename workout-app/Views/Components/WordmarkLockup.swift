import SwiftUI

struct WordmarkLockup: View {
    var showTagline: Bool = true
    var tagline: String = "Best Workout App in The World"
    var isOnSplash: Bool = false

    private var primaryText: Color { isOnSplash ? .white : Theme.Colors.textPrimary }
    private var secondaryText: Color { isOnSplash ? Color.white.opacity(0.86) : Theme.Colors.textSecondary }

    var body: some View {
        VStack(spacing: 8) {
            Text("Davis's")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryText)
                .textCase(.uppercase)
                .tracking(1.2)

            VStack(spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    Text("BIG BEAUTIFUL")
                        .font(Theme.Typography.wordmarkHuge)

                    Text("BIG BEAUTIFUL")
                        .font(.custom("BebasNeue-Regular", size: 44, relativeTo: .largeTitle))
                }
                .tracking(0.8)
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                ViewThatFits(in: .horizontal) {
                    Text("WORKOUT APP")
                        .font(Theme.Typography.wordmarkBig)

                    Text("WORKOUT APP")
                        .font(.custom("BebasNeue-Regular", size: 30, relativeTo: .title))
                }
                .tracking(0.6)
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }

            if showTagline {
                Text(tagline)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Davis's Big Beautiful Workout App. \(tagline)")
    }
}

#Preview {
    ZStack {
        SplashBackground()
        WordmarkLockup(isOnSplash: true)
            .padding(Theme.Spacing.xl)
    }
}
