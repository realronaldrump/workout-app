import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @Binding var hasSeenOnboarding: Bool
    @EnvironmentObject var healthManager: HealthKitManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var step = 0
    @State private var showingImportWizard = false
    @State private var welcomeVisible = false
    @State private var isRequestingHealth = false
    @State private var healthErrorMessage: String?

    private let totalSteps = 3
    private let stepTitles = ["Welcome", "Your workouts", "Apple Health"]
    private let healthReadItems = [
        "Sleep duration and stages",
        "Resting and workout heart rate",
        "Heart rate variability",
        "Active energy and steps",
        "Body weight and composition",
        "VO2 max and respiratory rate"
    ]

    var body: some View {
        ZStack {
            AdaptiveBackground()

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
            .padding(.vertical, Theme.Spacing.lg)
            .contentColumn(maxWidth: 640, alignment: .center)
        }
        .interactiveDismissDisabled(isRequestingHealth)
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
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                if step > 0 {
                    Button {
                        withAnimation(reduceMotion ? nil : Theme.Animation.smooth) {
                            step -= 1
                        }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(Theme.Typography.subheadlineStrong)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(minHeight: Theme.Layout.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequestingHealth)
                }
                Spacer()

                Button("Skip") {
                    AppAnalytics.shared.track(
                        AnalyticsSignal.onboardingSkipped,
                        payload: ["Onboarding.step": "\(step)"]
                    )
                    completeOnboarding()
                }
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(minHeight: Theme.Layout.minimumTapTarget)
                .buttonStyle(.plain)
                .disabled(isRequestingHealth)
                .accessibilityHint("Finishes setup now. You can import data and connect Apple Health later in Settings.")
            }

            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                OnboardingStepPlates(current: step, total: totalSteps)
                Text("Step \(step + 1) of \(totalSteps), \(stepTitles[min(step, stepTitles.count - 1)].lowercased())")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.horizontal, Theme.Layout.screenGutter)
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let primary = primaryButtonTitle {
                Button(action: handlePrimaryAction) {
                    HStack(spacing: Theme.Spacing.sm) {
                        if isRequestingHealth {
                            ProgressView()
                                .tint(Theme.Colors.onAccent)
                        }
                        Text(primary)
                            .font(Theme.Typography.headline)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.Layout.primaryControlHeight)
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(isRequestingHealth)
            }

            if let secondary = secondaryButtonTitle {
                Button(action: handleSecondaryAction) {
                    Text(secondary)
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .disabled(isRequestingHealth)
            }
        }
        .padding(.horizontal, Theme.Layout.screenGutter)
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                WordmarkLockup(showTagline: false, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(welcomeVisible ? 1 : 0)
                    .offset(y: welcomeVisible || reduceMotion ? 0 : 8)
                    .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.82), value: welcomeVisible)

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Log every set. See what's working.")
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    BarbellLoadView(plates: Self.samplePlates, goal: 4, plateHeight: 72, showsDayLabels: false)
                        .accessibilityHidden(true)

                    Text("Each workout loads a plate on this week's bar. Hit your weekly goal and the bar is full.")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    welcomeRow(title: "Workouts", detail: "Log sets fast, with last time's numbers ready.", showsRule: false)
                    welcomeRow(title: "Progress", detail: "Records, trends, and how each lift is moving.")
                    welcomeRow(title: "Apple Health", detail: "Sleep, heart rate, and body weight beside your training.")
                }
            }
            .padding(.horizontal, Theme.Layout.screenGutter)
            .padding(.vertical, Theme.Spacing.md)
        }
        .onAppear {
            startWelcomeAnimation()
        }
    }

    /// Three sessions of a four-session week, to show the bar before there is any data.
    private static let samplePlates: [LoadedPlate] = {
        let start = Calendar.current.startOfDay(for: .now)
        return [PlateCategory.push, .pull, .legs].enumerated().map { index, category in
            LoadedPlate(id: UUID(), date: start.addingTimeInterval(Double(index) * 86_400), category: category)
        }
    }()

    private func welcomeRow(title: String, detail: String, showsRule: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(detail)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ledgerRow(showsRule: showsRule, verticalPadding: Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Get started

    private var getStartedStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("How do you want to start?")
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text("Bring your history from Strong, or log your first workout.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    startChoice(
                        title: "Import from Strong",
                        detail: "A Strong CSV export, or a backup from this app.",
                        systemImage: "square.and.arrow.down",
                        showsRule: false
                    ) {
                        Haptics.selection()
                        AppAnalytics.shared.track(AnalyticsSignal.onboardingImportSelected)
                        showingImportWizard = true
                    }

                    startChoice(
                        title: "Start fresh",
                        detail: "Log your first workout from Today.",
                        systemImage: "plus"
                    ) {
                        Haptics.selection()
                        AppAnalytics.shared.track(AnalyticsSignal.onboardingStartFreshSelected)
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Animation.spring) {
                            step = 2
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Layout.screenGutter)
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    private func startChoice(
        title: String,
        detail: String,
        systemImage: String,
        showsRule: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Image(systemName: systemImage)
                    .font(Theme.Typography.title4)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.title4)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(detail)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .ledgerRow(showsRule: showsRule, verticalPadding: Theme.Spacing.lg)
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardButtonStyle())
    }

    // MARK: - Apple Health

    private var healthStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Connect Apple Health")
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Text("See sleep, heart rate, and body weight next to your workouts. You choose what to share and can change it anytime.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("What the app reads")
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.bottom, Theme.Spacing.xs)

                    ForEach(Array(healthReadItems.enumerated()), id: \.offset) { index, item in
                        Text(item)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .ledgerRow(verticalPadding: Theme.Spacing.sm)
                    }
                }

                healthStatusLine

                if let healthErrorMessage {
                    Text(healthErrorMessage)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Apple Health error: \(healthErrorMessage)")
                }
            }
            .padding(.horizontal, Theme.Layout.screenGutter)
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    private var healthStatusLine: some View {
        let statusText: String = {
            switch healthManager.authorizationStatus {
            case .authorized:
                return "Connected"
            case .unavailable:
                return "Apple Health isn't available on this device"
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
                return Theme.Colors.decorativeSubtle
            }
        }()

        return HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(statusText)
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryButtonTitle: String? {
        switch step {
        case 0:
            return "Get started"
        case 1:
            return nil
        default:
            if isRequestingHealth { return "Connecting…" }
            return healthManager.authorizationStatus == .authorized
                || healthManager.authorizationStatus == .unavailable
                ? "Finish setup"
                : "Connect Apple Health"
        }
    }

    private var secondaryButtonTitle: String? {
        switch step {
        case 0, 1:
            return nil
        default:
            return healthManager.authorizationStatus == .authorized
                || healthManager.authorizationStatus == .unavailable ? nil : "Not now"
        }
    }

    private func handlePrimaryAction() {
        Haptics.selection()

        switch step {
        case 0:
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Animation.spring) {
                step = 1
            }
        case 2 where healthManager.authorizationStatus != .authorized
            && healthManager.authorizationStatus != .unavailable:
            requestHealthAccess()
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

    private func requestHealthAccess() {
        guard !isRequestingHealth else { return }
        isRequestingHealth = true
        healthErrorMessage = nil

        Task { @MainActor in
            defer { isRequestingHealth = false }
            do {
                try await healthManager.requestAuthorization()
                completeOnboarding()
            } catch {
                healthErrorMessage = error.localizedDescription
                Haptics.notify(.error)
            }
        }
    }

    private func startWelcomeAnimation() {
        welcomeVisible = true
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

/// Setup progress as plates on a bar: one plate per step, loaded as you go.
private struct OnboardingStepPlates: View {
    let current: Int
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
                Group {
                    if index <= current {
                        shape.fill(Theme.Colors.ink)
                    } else {
                        shape.strokeBorder(Theme.Colors.decorativeSubtle, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }
                .frame(width: 7, height: 22)
            }
        }
        .animation(reduceMotion ? nil : Theme.Animation.quick, value: current)
        .accessibilityHidden(true)
    }
}
