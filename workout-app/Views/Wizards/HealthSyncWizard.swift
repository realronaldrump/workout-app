import SwiftUI

struct HealthSyncWizard: View {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var healthManager: HealthKitManager
    let workouts: [Workout]
    let source: String

    @State private var step = 0
    @State private var errorMessage: String?
    @State private var hasStartedSync = false
    @State private var showingCloseConfirmation = false
    @State private var isAuthorizing = false
    @State private var initialWorkoutTargets: [Workout] = []
    @State private var skippedOlderWorkoutCount = 0
    @State private var hasCapturedSyncPlan = false

    private var initialDailyRange: DateInterval {
        healthManager.recommendedInitialDailySyncRange()
    }

    private var syncSummaryText: String {
        if initialWorkoutTargets.isEmpty {
            return "Recent workouts are already synced."
        }

        return "Recent workouts: \(healthManager.syncedWorkoutsCount) of \(initialWorkoutTargets.count)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()
                VStack {
                    // Progress Indicator
                    HStack(spacing: 8) {
                        ForEach(0..<4) { index in
                            Capsule()
                                .fill(index <= step ? Theme.Colors.error : Theme.Colors.border) // Red/pink for Health
                                .frame(height: 4)
                                .animation(reduceMotion ? nil : Theme.Animation.spring, value: step)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.lg)

                    stepContent
                        .id(step)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentColumn(maxWidth: 640, alignment: .center)
                        .animation(reduceMotion ? nil : Theme.Animation.spring, value: step)
                }
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                        handleCloseTapped()
                    }
                }
            }
            .confirmationDialog(
                "Sync in progress",
                isPresented: $showingCloseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Continue in background") {
                    isPresented = false
                }
                Button("Keep open", role: .cancel) {}
            } message: {
                Text("You can close this screen and sync will continue.")
            }
            .alert("Health sync failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { newValue in
                    if !newValue { errorMessage = nil }
                }
            )) {
                Button("Close", role: .cancel) { isPresented = false }
                Button("Try again") {
                    errorMessage = nil
                    hasStartedSync = false
                    withAnimation(reduceMotion ? nil : Theme.Animation.spring) {
                        step = healthManager.authorizationStatus == .authorized ? 2 : 1
                    }
                }
            } message: {
                Text(errorMessage ?? "Something went wrong. Try again.")
            }
        }
        .analyticsScreen("HealthSyncWizard", source: source)
        .onAppear {
            captureSyncPlanIfNeeded()
            AppAnalytics.shared.track(
                AnalyticsSignal.healthSyncWizardViewed,
                payload: [
                    "Context.source": source,
                    "Health.workoutCount": "\(workouts.count)"
                ]
            )
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            introStep
        case 1:
            authStep
        case 2:
            syncStep
        default:
            successStep
        }
    }

    private var introStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    Image(systemName: "heart.text.square.fill")
                        .font(Theme.Iconography.wizardHero)
                        .foregroundStyle(Theme.Colors.error)
                        .padding()
                        .background(
                            Circle()
                                .fill(Theme.Colors.error.opacity(0.12))
                                .frame(width: 160, height: 160)
                        )

                    Text("Health sync")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Sync recent workouts and the past year of daily Health data.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)

                    if skippedOlderWorkoutCount > 0 {
                        Text(
                            "Sync older workouts later from Settings > Health data."
                        )
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
            }

            primaryActionButton(title: "Next") {
                withAnimation(reduceMotion ? nil : Theme.Animation.spring) { step = 1 }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private var authStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    Image(systemName: "lock.shield.fill")
                        .font(Theme.Iconography.wizard)
                        .foregroundStyle(Theme.Colors.accent)

                    Text("Read access")
                        .font(Theme.Typography.title2)

                    Text("Choose which Health data this app can read. Your Health records won’t be changed.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
            }

            primaryActionButton(
                title: isAuthorizing ? "Waiting for Apple Health…" : "Connect Apple Health",
                isEnabled: !isAuthorizing,
                action: requestAuthorization
            )
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private var syncStep: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                ProgressView(value: healthManager.syncProgress) {
                    Text("Syncing Health data")
                        .font(Theme.Typography.headline)
                } currentValueLabel: {
                    Text("\(Int(healthManager.syncProgress * 100))%")
                        .font(Theme.Typography.caption)
                }
                .progressViewStyle(.linear)
                .tint(Theme.Colors.error)
                .accessibilityValue("\(Int(healthManager.syncProgress * 100)) percent")

                Text(syncSummaryText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if healthManager.isDailySyncing {
                    Text("Daily Health \(Int(healthManager.dailySyncProgress * 100))%")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.xl)
        }
        .onAppear {
            startSync()
        }
    }

    private var successStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(Theme.Iconography.wizardHero)
                        .foregroundStyle(Theme.Colors.success)

                    Text(workouts.isEmpty ? "Connected" : "Sync complete")
                        .font(Theme.Typography.title)

                    Text(workouts.isEmpty ? "Sync starts once you import or log workouts." : "Recent Health data is ready.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)

                    if skippedOlderWorkoutCount > 0 {
                        Text(
                            "Skipped \(skippedOlderWorkoutCount) older unsynced "
                                + "workout\(skippedOlderWorkoutCount == 1 ? "" : "s") "
                                + "to keep setup fast. Sync them later from Settings > Health data."
                        )
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
            }

            primaryActionButton(title: "Done") {
                isPresented = false
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    // MARK: - Logic

    private func primaryActionButton(
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if !isEnabled {
                    ProgressView()
                        .tint(Theme.Colors.textSecondary)
                }
                Text(title)
                    .font(Theme.Typography.headline)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.primaryControlHeight)
        }
        .buttonStyle(BrandPrimaryButtonStyle())
        .disabled(!isEnabled)
    }

    private func requestAuthorization() {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        AppAnalytics.shared.track(
            AnalyticsSignal.healthAuthorizationStarted,
            payload: ["Context.source": source]
        )
        Task {
            defer { isAuthorizing = false }
            do {
                try await healthManager.requestAuthorization()
                // If the user hasn't imported or logged workouts yet, there's nothing workout-scoped to sync.
                // Mark as connected and let sync happen later once workouts exist.
                if workouts.isEmpty {
                    withAnimation(reduceMotion ? nil : Theme.Animation.spring) { step = 3 }
                    Haptics.notify(.success)
                } else {
                    withAnimation(reduceMotion ? nil : Theme.Animation.spring) { step = 2 }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func captureSyncPlanIfNeeded() {
        guard !hasCapturedSyncPlan else { return }
        let missingCount = workouts.filter { healthManager.getHealthData(for: $0.id) == nil }.count
        let targets = healthManager.recommendedInitialWorkoutSyncTargets(from: workouts)
        initialWorkoutTargets = targets
        skippedOlderWorkoutCount = max(0, missingCount - targets.count)
        hasCapturedSyncPlan = true
    }

    private func startSync() {
        guard !hasStartedSync else { return }
        hasStartedSync = true
        AppAnalytics.shared.track(
            AnalyticsSignal.healthSyncStarted,
            payload: [
                "Context.source": source,
                "Health.targetWorkoutCount": "\(initialWorkoutTargets.count)"
            ]
        )

        Task {
            do {
                guard healthManager.authorizationStatus == .authorized else {
                    await MainActor.run {
                        self.hasStartedSync = false
                        withAnimation(reduceMotion ? nil : Theme.Animation.spring) {
                            self.step = 1
                        }
                    }
                    return
                }

                _ = try await healthManager.syncAllWorkouts(initialWorkoutTargets)
                await healthManager.ensureDailyHealthData(range: initialDailyRange)

                withAnimation(reduceMotion ? nil : Theme.Animation.spring) {
                    step = 3 // Success step
                }
                Haptics.notify(.success)
                AppAnalytics.shared.track(
                    AnalyticsSignal.healthSyncCompleted,
                    payload: [
                        "Context.source": source,
                        "Health.targetWorkoutCount": "\(initialWorkoutTargets.count)"
                    ]
                )
            } catch {
                errorMessage = error.localizedDescription
                AppAnalytics.shared.track(
                    AnalyticsSignal.healthSyncFailed,
                    payload: [
                        "Context.source": source,
                        "Health.errorDomain": String(describing: type(of: error))
                    ]
                )
            }
        }
    }

    private func handleCloseTapped() {
        if step == 2, healthManager.isSyncing, errorMessage == nil {
            showingCloseConfirmation = true
            return
        }
        isPresented = false
    }
}
