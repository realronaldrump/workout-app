import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @Binding var hasSeenOnboarding: Bool
    @EnvironmentObject var healthManager: HealthKitManager

    @State private var step = 0
    @State private var showingImportWizard = false

    private let totalSteps = 4

    var body: some View {
        ZStack {
            AdaptiveBackground()

            VStack(spacing: Theme.Spacing.lg) {
                header

                TabView(selection: $step) {
                    missionControlStep.tag(0)
                    insightsStep.tag(1)
                    healthStep.tag(2)
                    importStep.tag(3)
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
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Button("Skip") {
                    completeOnboarding()
                }
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)

                Spacer()

                Text("Step \(step + 1) of \(totalSteps)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.Colors.accent : Theme.Colors.surface.opacity(0.6))
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            if step > 0 {
                Button(action: {
                    withAnimation(Theme.Animation.spring) {
                        step = max(step - 1, 0)
                    }
                    Haptics.selection()
                }) {
                    Text("Back")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.surface.opacity(0.6))
                        .cornerRadius(Theme.CornerRadius.large)
                }
            }

            Spacer()

            Button(action: {
                handlePrimaryAction()
            }) {
                Text(step == totalSteps - 1 ? "Launch Analytics" : "Continue")
                    .font(Theme.Typography.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accent)
                    .cornerRadius(Theme.CornerRadius.large)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private var missionControlStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Dashboard Preview")
                    .font(Theme.Typography.title)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("sessions \(SampleData.stats.totalWorkouts) | volume \(Int(SampleData.stats.totalVolume))")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)

                OverviewCardsView(stats: SampleData.stats)
                    .padding(.top, Theme.Spacing.md)
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    private var insightsStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Signals Preview")
                    .font(Theme.Typography.title)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("n \(SampleData.insights.count)")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)

                VStack(spacing: Theme.Spacing.md) {
                    ForEach(SampleData.insights) { insight in
                        InsightCardView(insight: insight)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    private var healthStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Health Metrics Preview")
                    .font(Theme.Typography.title)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("avgHRV 48 | resting 58 | sync live")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)

                if #available(iOS 16.0, *) {
                    WorkoutHRChart(samples: SampleData.healthData.heartRateSamples)
                } else {
                    Text("Health charts require iOS 16 or newer.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                HStack(spacing: Theme.Spacing.md) {
                    OnboardingStatPill(title: "Avg HRV", value: "48", unit: "ms")
                    OnboardingStatPill(title: "Resting HR", value: "58", unit: "bpm")
                    OnboardingStatPill(title: "Sync", value: "Live", unit: "")
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    private var importStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Import")
                    .font(Theme.Typography.title)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("CSV import")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)

                Button(action: {
                    showingImportWizard = true
                }) {
                    HStack {
                        Spacer()
                        Text("Import Strong CSV")
                            .font(Theme.Typography.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    .background(Theme.Colors.accent)
                    .cornerRadius(Theme.CornerRadius.large)
                }

                Text("storage on-device/iCloud")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    private func handlePrimaryAction() {
        if step < totalSteps - 1 {
            withAnimation(Theme.Animation.spring) {
                step += 1
            }
            Haptics.selection()
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        Haptics.selection()
        hasSeenOnboarding = true
        isPresented = false
    }
}

struct OnboardingStatPill: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.Typography.numberSmall)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(unit)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surface.opacity(0.6))
        .cornerRadius(Theme.CornerRadius.medium)
    }
}
