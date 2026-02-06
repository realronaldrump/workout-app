import SwiftUI

struct InAppSplashView: View {
    var statusText: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        ZStack {
            SplashBackground()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                WordmarkLockup(showTagline: true)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .opacity(isVisible ? 1 : 0)
                    .scaleEffect(isVisible || reduceMotion ? 1 : 0.98)
                    .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.82), value: isVisible)

                Spacer()

                if let statusText {
                    Text(statusText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.bottom, Theme.Spacing.xl)
                } else {
                    // Keep spacing consistent so the lockup doesn't jump when status is used elsewhere.
                    Color.clear.frame(height: 24)
                }
            }
        }
        .onAppear {
            isVisible = true
        }
        .accessibilityAddTraits(.isModal)
    }
}

#Preview {
    InAppSplashView(statusText: "Preparing your dashboard...")
}
