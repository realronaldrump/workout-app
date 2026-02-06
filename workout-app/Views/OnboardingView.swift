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
    @State private var showingHealthWizard = false

    private let totalSteps = 3

    var body: some View {
        ZStack {
            AdaptiveBackground()

            VStack(spacing: Theme.Spacing.lg) {
                topBar

                TabView(selection: $step) {
                    welcomeStep.tag(0)
                    importStep.tag(1)
                    healthStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
            .padding(.vertical, Theme.Spacing.xl)
        }
        .fullScreenCover(isPresented: $showingImportWizard) {
            StrongImportWizard(
                isPresented: $showingImportWizard,
                dataManager: dataManager,
                iCloudManager: iCloudManager
            )
        }
        .fullScreenCover(isPresented: $showingHealthWizard) {
            HealthSyncWizard(
                isPresented: $showingHealthWizard,
                workouts: dataManager.workouts
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
        .onChange(of: healthManager.authorizationStatus) { _, newValue in
            // If the user authorizes in the wizard, show the "Connected" state immediately.
            if step == 2, newValue == .authorized {
                Haptics.notify(.success)
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Spacer()

                Button("Skip") {
                    completeOnboarding()
                }
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: 44)
            }

            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.Colors.accent : Theme.Colors.border.opacity(0.7))
                        .frame(height: 4)
                        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(), value: step)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button(action: handlePrimaryAction) {
                Text(primaryButtonTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .frame(minHeight: 52)
                    .background(primaryButtonColor)
                    .cornerRadius(Theme.CornerRadius.xlarge)
            }

            if let secondary = secondaryButtonTitle {
                Button(action: handleSecondaryAction) {
                    Text(secondary)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private var welcomeStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            WordmarkLockup(showTagline: false)
                .padding(.horizontal, Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Train with clarity.")
                    .font(Theme.Typography.heroTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("See what's changed, what's working, and what to do next.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Spacer()
        }
    }

    private var importStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(Theme.Spacing.xl)
                    .background(
                        Circle()
                            .fill(Theme.Colors.accent.opacity(0.12))
                    )

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Bring your history.")
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Import your Strong CSV in under a minute.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xl)
                }
            }

            Spacer()
        }
    }

    private var healthStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.Colors.error)
                    .padding(Theme.Spacing.xl)
                    .background(
                        Circle()
                            .fill(Theme.Colors.error.opacity(0.10))
                    )

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Add recovery context.")
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Sleep and recovery alongside training. Read-only and on-device.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xl)
                }

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
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .softCard(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
        .padding(.top, Theme.Spacing.sm)
    }

    private var primaryButtonTitle: String {
        switch step {
        case 0:
            return "Get started"
        case 1:
            return "Import from Strong"
        default:
            switch healthManager.authorizationStatus {
            case .authorized, .unavailable:
                return "Continue"
            default:
                return "Connect Apple Health"
            }
        }
    }

    private var secondaryButtonTitle: String? {
        switch step {
        case 0:
            return nil
        case 1:
            return "Skip for now"
        default:
            return "Not now"
        }
    }

    private var primaryButtonColor: Color {
        switch step {
        case 1:
            return Theme.Colors.accent
        default:
            return Theme.Colors.accent
        }
    }

    private func handlePrimaryAction() {
        Haptics.selection()

        switch step {
        case 0:
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Animation.spring) {
                step = 1
            }
        case 1:
            showingImportWizard = true
        default:
            switch healthManager.authorizationStatus {
            case .authorized, .unavailable:
                completeOnboarding()
            default:
                showingHealthWizard = true
            }
        }
    }

    private func handleSecondaryAction() {
        Haptics.selection()

        switch step {
        case 1:
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Animation.spring) {
                step = 2
            }
        default:
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        hasSeenOnboarding = true
        isPresented = false
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
