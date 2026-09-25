import SwiftUI

struct FinishSessionSummary: Hashable {
    let startedAt: Date
    let exerciseCount: Int
    let completedSetCount: Int
    let strengthVolume: Double
    let cardioDistance: Double
    let cardioSeconds: Double
    let cardioCount: Int
    /// Set once the workout is saved so the summary shows a fixed duration instead of a live timer.
    var endedAt: Date? = nil
}

struct FinishSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isFinishing: Bool
    let didSave: Bool
    let summary: FinishSessionSummary
    let errorMessage: String?
    let onFinish: () -> Void
    let onDismissError: () -> Void
    let onDone: () -> Void

    @AccessibilityFocusState private var successTitleFocused: Bool
    @State private var confettiTrigger = 0

    var body: some View {
        ZStack {
            AdaptiveBackground()

            if didSave {
                successContent
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            } else {
                confirmationContent
            }

            ConfettiBurst(trigger: confettiTrigger, originY: 0.22)
                .ignoresSafeArea()
        }
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: didSave)
        .onChange(of: didSave) { _, saved in
            if saved {
                successTitleFocused = true
                confettiTrigger += 1
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var successContent: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Theme.Colors.success.opacity(0.28), Theme.Colors.success.opacity(0)],
                                center: .center,
                                startRadius: 10,
                                endRadius: 80
                            )
                        )
                        .frame(width: 150, height: 150)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 68, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Theme.Colors.success)
                        .symbolEffect(.bounce, value: reduceMotion ? false : didSave)
                }
                .accessibilityHidden(true)

                VStack(spacing: Theme.Spacing.sm) {
                    BrandBandLabel(text: "Workout saved", systemImage: "checkmark")

                    Text("Big. Beautiful.")
                        .font(Theme.Typography.displayHero)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Workout saved")
                        .accessibilityFocused($successTitleFocused)
                }

                Text("History and insights are up to date. If Apple Health is connected, its sync continues in the background.")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                statGrid

                AppPrimaryButton(title: "Done", systemImage: "checkmark") {
                    onDone()
                }
                .padding(.top, Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.xl)
            .contentColumn(maxWidth: 640, alignment: .center)
        }
    }

    private var confirmationContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        BrandBandLabel(text: "Wrap it up", systemImage: "flag.checkered")
                        Text("Finish Workout?")
                            .font(Theme.Typography.displayHeroCompact)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Only completed sets will be saved.")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer(minLength: Theme.Spacing.sm)

                    AppToolbarIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "Keep editing",
                        variant: .subtle
                    ) {
                        dismiss()
                    }
                }

                statGrid

                if let errorMessage {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)

                        Text(errorMessage)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: Theme.Spacing.xs)

                        Button("Dismiss") { onDismissError() }
                            .font(Theme.Typography.captionBold)
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.error)
                    .padding(Theme.Spacing.lg)
                    .background(Theme.Colors.error.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
                    .accessibilityElement(children: .combine)
                }

                if isFinishing {
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressView()
                        Text("Saving your workout…")
                            .font(Theme.Typography.subheadline)
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }

                AppPrimaryButton(
                    title: isFinishing ? "Saving…" : "Finish & Save",
                    systemImage: "checkmark.circle.fill",
                    isEnabled: !isFinishing
                ) {
                    onFinish()
                }
            }
            .padding(Theme.Spacing.xl)
            .contentColumn(maxWidth: 640)
        }
    }

    private var statGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Theme.Spacing.sm),
                GridItem(.flexible(), spacing: Theme.Spacing.sm)
            ],
            spacing: Theme.Spacing.sm
        ) {
            durationTile

            statTile(
                title: "Sets",
                value: "\(summary.completedSetCount)",
                icon: "checkmark.circle.fill",
                tint: Theme.Colors.success
            )
            statTile(
                title: "Exercises",
                value: "\(summary.exerciseCount)",
                icon: "dumbbell.fill",
                tint: Theme.Colors.accentSecondary
            )

            if summary.strengthVolume > 0 {
                statTile(
                    title: "Volume",
                    value: SharedFormatters.volumeWithUnit(summary.strengthVolume),
                    icon: "scalemass.fill",
                    tint: Theme.Colors.accentTertiary
                )
            }
            if summary.cardioDistance > 0 {
                statTile(
                    title: "Distance",
                    value: WorkoutValueFormatter.distanceText(summary.cardioDistance),
                    icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                    tint: Theme.Colors.cardio
                )
            }
            if summary.cardioSeconds > 0 {
                statTile(
                    title: "Cardio time",
                    value: WorkoutValueFormatter.durationText(seconds: summary.cardioSeconds),
                    icon: "stopwatch.fill",
                    tint: Theme.Colors.cardio
                )
            }
            if summary.cardioCount > 0 {
                statTile(
                    title: "Count",
                    value: "\(summary.cardioCount)",
                    icon: "number",
                    tint: Theme.Colors.cardio
                )
            }
        }
    }

    @ViewBuilder
    private var durationTile: some View {
        if let endedAt = summary.endedAt {
            statTile(
                title: "Duration",
                value: SharedFormatters.elapsed(endedAt.timeIntervalSince(summary.startedAt)),
                icon: "clock.fill",
                tint: Theme.Colors.accent
            )
        } else {
            tileChrome(title: "Elapsed", icon: "clock.fill", tint: Theme.Colors.accent) {
                Text(summary.startedAt, style: .timer)
                    .monospacedDigit()
            }
        }
    }

    private func statTile(title: String, value: String, icon: String, tint: Color) -> some View {
        tileChrome(title: title, icon: icon, tint: tint) {
            Text(value)
        }
    }

    private func tileChrome<Value: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder value: () -> Value
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Theme.Typography.caption2Bold)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .sectionHeaderStyle()
                    .lineLimit(1)
            }
            value()
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .fill(tint.opacity(Theme.Opacity.subtleFill))
        )
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
    }
}
