import SwiftUI

struct WordmarkLockup: View {
    var showTagline: Bool = true
    var tagline: String = "Progress, without the noise."

    var body: some View {
        VStack(spacing: 8) {
            Text("Davis's")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)
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
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                ViewThatFits(in: .horizontal) {
                    Text("WORKOUT APP")
                        .font(Theme.Typography.wordmarkBig)

                    Text("WORKOUT APP")
                        .font(.custom("BebasNeue-Regular", size: 30, relativeTo: .title))
                }
                .tracking(0.6)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }

            if showTagline {
                Text(tagline)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
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
        WordmarkLockup()
            .padding(Theme.Spacing.xl)
    }
}

