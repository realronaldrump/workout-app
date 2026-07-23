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
            return "Recent workout cache is already covered."
        }

        return "Recent workouts \(healthManager.syncedWorkoutsCount) / \(initialWorkoutTargets.count)"
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        handleCloseTapped()
                    }
                }
            }
            .confirmationDialog(
                "Sync in progress",
                isPresented: $showingCloseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Run in Background") {
                    isPresented = false
                }
                Button("Keep Open", role: .cancel) {}
            } message: {
                Text("You can close this screen and sync will continue.")
            }
            .alert("Health Sync Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { newValue in
                    if !newValue { errorMessage = nil }
                }
            )) {
                Button("Close", role: .cancel) { isPresented = false }
                Button("Retry") {
                    errorMessage = nil
                    hasStartedSync = false
                    withAnimation(reduceMotion ? nil : Theme.Animation.spring) {
                        step = healthManager.authorizationStatus == .authorized ? 2 : 1
                    }
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
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

                    Text("Health Sync")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Read-only, on-device, and starts with recent history.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)

                    if skippedOlderWorkoutCount > 0 {
                        Text(
                            "We start with recent missing workouts and the last year of daily Health history so setup stays fast. " +
                            "Older history can be backfilled later."
                        )
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
            }

            primaryActionButton(title: "Next", fill: Theme.Colors.accent) {
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

                    Text("Read Access")
                        .font(Theme.Typography.title2)

                    Text("Read-only, on-device, private.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
            }

            primaryActionButton(
                title: isAuthorizing ? "Waiting for Apple Health…" : "Authorize",
                fill: Theme.Colors.accent,
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
                    Text("Syncing Health Data")
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

                Text("Daily history covers the last 12 months by default.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)

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

                    Text(workouts.isEmpty ? "Connected" : "Sync Complete")
                        .font(Theme.Typography.title)

                    Text(workouts.isEmpty ? "We'll start syncing once you import or log workouts." : "Recent Health data is ready.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)

                    if skippedOlderWorkoutCount > 0 {
                        Text(
                            "Skipped \(skippedOlderWorkoutCount) older unsynced "
                                + "workout\(skippedOlderWorkoutCount == 1 ? "" : "s") "
                                + "to keep setup fast. Use Health Cache or Health "
                                + "History in Settings to backfill more."
                        )
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
            }

            primaryActionButton(title: "Done", fill: Theme.Colors.success) {
                isPresented = false
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    // MARK: - Logic

    private func primaryActionButton(
        title: String,
        fill: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if !isEnabled {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(Theme.Typography.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
            .surfaceButtonChrome(
                fill: fill,
                cornerRadius: Theme.CornerRadius.large
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.72)
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
