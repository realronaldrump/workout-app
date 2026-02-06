import SwiftUI

struct InAppSplashView: View {
    var statusText: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var isFloating = false

    var body: some View {
        ZStack {
            SplashBackground()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                WordmarkLockup(showTagline: true, isOnSplash: true)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .opacity(isVisible ? 1 : 0)
                    .scaleEffect(isVisible || reduceMotion ? 1 : 0.98)
                    .offset(y: isFloating ? -4 : 0)
                    .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.82), value: isVisible)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: isFloating)

                Spacer()

                if let statusText {
                    Text(statusText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .padding(.bottom, Theme.Spacing.xl)
                } else {
                    // Keep spacing consistent so the lockup doesn't jump when status is used elsewhere.
                    Color.clear.frame(height: 24)
                }
            }
        }
        .onAppear {
            isVisible = true
            guard !reduceMotion else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 650_000_000)
                isFloating = true
            }
        }
        .accessibilityAddTraits(.isModal)
    }
}

#Preview {
    InAppSplashView(statusText: "Loading...")
}
