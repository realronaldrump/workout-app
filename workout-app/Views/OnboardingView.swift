import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @Binding var hasSeenOnboarding: Bool
    @EnvironmentObject var healthManager: HealthKitManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = 0
    @State private var showingImportWizard = false
    @State private var welcomeVisible = false
    @State private var welcomeFloating = false

    private let totalSteps = 3
    private let onboardingPrimaryText = Color.white
    private let onboardingSecondaryText = Color.white.opacity(0.82)
    private let onboardingTertiaryText = Color.white.opacity(0.68)

    var body: some View {
        ZStack {
            SplashBackground()

            VStack(spacing: Theme.Spacing.lg) {
                topBar

                TabView(selection: $step) {
                    welcomeStep.tag(0)
                    getStartedStep.tag(1)
                    healthStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
            .padding(.vertical, Theme.Spacing.xl)
        }
        .analyticsScreen("Onboarding")
        .onAppear {
            AppAnalytics.shared.track(AnalyticsSignal.onboardingStarted)
            AppAnalytics.shared.track(
                AnalyticsSignal.onboardingStepViewed,
                payload: [
                    "Onboarding.step": "\(step)",
                    "Onboarding.totalSteps": "\(totalSteps)"
                ]
            )
        }
        .onChange(of: step) { _, newValue in
            AppAnalytics.shared.track(
                AnalyticsSignal.onboardingStepViewed,
                payload: [
                    "Onboarding.step": "\(newValue)",
                    "Onboarding.totalSteps": "\(totalSteps)"
                ]
            )
            if newValue == 0 {
                startWelcomeAnimation()
            }
        }
        .fullScreenCover(isPresented: $showingImportWizard) {
            StrongImportWizard(
                isPresented: $showingImportWizard,
                dataManager: dataManager,
                iCloudManager: iCloudManager,
                source: "onboarding"
            )
        }
        .onChange(of: showingImportWizard) { _, isShowing in
            guard !isShowing else { return }
            guard step == 1 else { return }
            guard !dataManager.workouts.isEmpty else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Animation.spring) {
                step = 2
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Spacer()

                Button("Skip") {
                    AppAnalytics.shared.track(
                        AnalyticsSignal.onboardingSkipped,
                        payload: ["Onboarding.step": "\(step)"]
                    )
                    completeOnboarding()
                }
                .font(Theme.Typography.subheadline)
                .foregroundStyle(onboardingSecondaryText)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.white : Color.white.opacity(0.20))
                        .frame(width: index == step ? 24 : 8, height: 4)
                        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.75), value: step)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let primary = primaryButtonTitle {
                Button(action: handlePrimaryAction) {
                    Text(primary)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .frame(minHeight: 52)
                        .background(
                            AnyShapeStyle(Theme.Colors.surface)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge))
                        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
                        .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
                }
            }

            if let secondary = secondaryButtonTitle {
                Button(action: handleSecondaryAction) {
                    Text(secondary)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(onboardingSecondaryText)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private var welcomeStep: some View {
        ZStack {
            splashHeroBackdrop

            ViewThatFits(in: .vertical) {
                welcomeHeroLayout(compact: false)
                welcomeHeroLayout(compact: true)
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .onAppear {
            startWelcomeAnimation()
        }
    }

    private func welcomeHeroLayout(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? Theme.Spacing.lg : Theme.Spacing.xl) {
            Spacer(minLength: compact ? 0 : Theme.Spacing.sm)

            VStack(alignment: .leading, spacing: compact ? Theme.Spacing.md : Theme.Spacing.lg) {
                if !compact {
                    splashEyebrow
                }

                WordmarkLockup(
                    showTagline: false,
                    isOnSplash: true,
                    alignment: .leading
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(welcomeVisible ? 1 : 0)
                .scaleEffect(
                    compact ? 0.84 : (welcomeVisible || reduceMotion ? 1 : 0.98),
                    anchor: .leading
                )
                .offset(y: welcomeFloating ? -4 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.82), value: welcomeVisible)
                .animation(reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: welcomeFloating)

                if compact {
                    Text("Performance, recovery, and momentum in one focused briefing.")
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Color.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Know what changed, what is working, and what to do next.")
                            .font(Theme.Typography.heroTitle)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Performance, recovery, and momentum in one focused briefing instead of a wall of charts.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Color.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    splashPillRow
                }
            }

            splashPreviewPanel(compact: compact)

            Spacer(minLength: 0)
        }
    }

    private var splashHeroBackdrop: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 10)
                .offset(x: 120, y: -130)

            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(width: 220, height: 220)
                .rotationEffect(.degrees(18))
                .offset(x: 135, y: 180)

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(-14))
                .offset(x: -110, y: 220)
        }
        .allowsHitTesting(false)
    }

    private var splashEyebrow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(Theme.Typography.captionBold)
            Text("PERFORMANCE INTELLIGENCE")
                .font(Theme.Typography.captionBold)
                .tracking(0.8)
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var splashPillRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.sm) {
                splashMiniPill(title: "Trends", systemImage: "chart.line.uptrend.xyaxis")
                splashMiniPill(title: "Recovery", systemImage: "heart.text.square")
                splashMiniPill(title: "Momentum", systemImage: "figure.run")
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    splashMiniPill(title: "Trends", systemImage: "chart.line.uptrend.xyaxis")
                    splashMiniPill(title: "Recovery", systemImage: "heart.text.square")
                }
                splashMiniPill(title: "Momentum", systemImage: "figure.run")
            }
        }
    }

    private func splashMiniPill(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(Theme.Typography.captionBold)
            Text(title)
                .font(Theme.Typography.captionBold)
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func splashPreviewPanel(compact: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 22, y: 12)

            VStack(alignment: .leading, spacing: compact ? Theme.Spacing.md : Theme.Spacing.lg) {
                HStack(alignment: .firstTextBaseline) {
                    Text("TODAY")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .tracking(1.0)

                    Spacer()

                    Text("CLEAR NEXT STEP")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Color.white.opacity(0.88))
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                        )
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("One focused briefing before you train.")
                        .font(Theme.Typography.cardHeader)
                        .foregroundStyle(.white)

                    Text("Spot workload shifts, recovery context, and the muscles that actually need attention.")
                        .font(compact ? Theme.Typography.caption : Theme.Typography.subheadline)
                        .foregroundStyle(Color.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: compact ? Theme.Spacing.sm : Theme.Spacing.md) {
                    splashSignalRow(
                        systemImage: "chart.bar.doc.horizontal",
                        title: "See what moved",
                        detail: "Volume, frequency, and exercise trends"
                    )
                    splashSignalRow(
                        systemImage: "bolt.heart",
                        title: "Train with context",
                        detail: "Sleep and recovery alongside your sessions"
                    )
                    if !compact {
                        splashSignalRow(
                            systemImage: "target",
                            title: "Get one next move",
                            detail: "Know where to push instead of guessing"
                        )
                    }
                }
            }
            .padding(compact ? Theme.Spacing.lg : Theme.Spacing.xl)

            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(Theme.Typography.captionBold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("4x / week")
                        .font(Theme.Typography.captionBold)
                    Text("Momentum goal")
                        .font(Theme.Typography.caption2)
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(Theme.Colors.surface)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
            )
            .offset(x: -18, y: compact ? 14 : 18)
        }
    }

    private func splashSignalRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(Theme.Typography.calloutBold)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(.white)

                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var getStartedStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.sm) {
                Text("HOW DO YOU WANT TO START?")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(onboardingPrimaryText)
                    .tracking(1.0)
                    .multilineTextAlignment(.center)

                Text("Import your history or jump right in.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(onboardingSecondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.md) {
                // Import saved data option
                Button {
                    Haptics.selection()
                    AppAnalytics.shared.track(AnalyticsSignal.onboardingImportSelected)
                    showingImportWizard = true
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .font(Theme.Iconography.prominent)
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(Theme.Colors.accentTint)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Import Data")
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Bring a Strong CSV or app backup")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(Theme.Typography.caption2Bold)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                            .fill(Theme.Colors.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                            .strokeBorder(Theme.Colors.accent.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Start fresh option
                Button {
                    Haptics.selection()
                    AppAnalytics.shared.track(AnalyticsSignal.onboardingStartFreshSelected)
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Animation.spring) {
                        step = 2
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(Theme.Iconography.prominent)
                            .foregroundStyle(Theme.Colors.success)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(Theme.Colors.success.opacity(0.08))
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start Fresh")
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Jump right in and log your first workout")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(Theme.Typography.caption2Bold)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                            .fill(Theme.Colors.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                            .strokeBorder(Theme.Colors.border.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.xl)

            Spacer()
        }
    }

    private var healthStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "heart.fill")
                    .font(Theme.Iconography.featureLarge)
                    .foregroundStyle(Theme.Colors.error)
                    .frame(width: 100, height: 100)
                    .background(
                        Circle()
                            .fill(Theme.Colors.error.opacity(0.08))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.Colors.error.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Theme.Colors.error.opacity(0.12), radius: 12, y: 4)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Add recovery context.")
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(onboardingPrimaryText)
                        .tracking(1.0)
                        .multilineTextAlignment(.center)

                    Text("Sleep and recovery alongside training. Use Settings later to connect and sync Apple Health.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(onboardingSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xl)
                }

                DisclosureGroup("What health data do we read?") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        learnMoreBullet("Sleep duration & stages")
                        learnMoreBullet("Resting & workout heart rate")
                        learnMoreBullet("Heart rate variability (HRV)")
                        learnMoreBullet("Active energy & step count")
                        learnMoreBullet("Body weight & composition")
                        learnMoreBullet("VO₂ Max & respiratory rate")
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
                .font(Theme.Typography.subheadline)
                .foregroundStyle(onboardingSecondaryText)
                .tint(onboardingTertiaryText)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )
                .padding(.horizontal, Theme.Spacing.xl)

                healthStatusPill
            }

            Spacer()
        }
    }

    private var healthStatusPill: some View {
        let statusText: String = {
            switch healthManager.authorizationStatus {
            case .authorized:
                return "Connected"
            case .unavailable:
                return "Unavailable"
            default:
                return "Not connected"
            }
        }()

        let tint: Color = {
            switch healthManager.authorizationStatus {
            case .authorized:
                return Theme.Colors.success
            case .unavailable:
                return Theme.Colors.textTertiary
            default:
                return Theme.Colors.warning
            }
        }()

        return HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(onboardingSecondaryText)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .padding(.top, Theme.Spacing.sm)
    }

    private func learnMoreBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text("•")
                .foregroundStyle(onboardingTertiaryText)
            Text(text)
                .foregroundStyle(onboardingSecondaryText)
        }
        .font(Theme.Typography.subheadline)
    }

    private var primaryButtonTitle: String? {
        switch step {
        case 0:
            return "Get started"
        case 1:
            return nil
        default:
            return "Continue"
        }
    }

    private var secondaryButtonTitle: String? {
        switch step {
        case 0, 1:
            return nil
        default:
            return "Not now"
        }
    }

    private func handlePrimaryAction() {
        Haptics.selection()

        switch step {
        case 0:
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Animation.spring) {
                step = 1
            }
        default:
            completeOnboarding()
        }
    }

    private func handleSecondaryAction() {
        Haptics.selection()
        completeOnboarding()
    }

    private func completeOnboarding() {
        AppAnalytics.shared.track(
            AnalyticsSignal.onboardingCompleted,
            payload: ["Onboarding.finalStep": "\(step)"]
        )
        hasSeenOnboarding = true
        isPresented = false
    }

    private func startWelcomeAnimation() {
        welcomeVisible = true
        welcomeFloating = false
        guard !reduceMotion else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            // Mirror the returning-user splash's gentle float to keep the brand moment consistent.
            welcomeFloating = true
        }
    }
}

#Preview {
    OnboardingView(
        isPresented: .constant(true),
        dataManager: WorkoutDataManager(),
        iCloudManager: iCloudDocumentManager(),
        hasSeenOnboarding: .constant(false)
    )
    .environmentObject(HealthKitManager())
}
