import SwiftUI

struct FinishSessionSummary: Hashable {
    let startedAt: Date
    let exerciseCount: Int
    let completedSetCount: Int
    let strengthVolume: Double
    let cardioDistance: Double
    let cardioSeconds: Double
    let cardioCount: Int
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

    var body: some View {
        ZStack {
            AdaptiveBackground()

            if didSave {
                successContent
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            } else {
                confirmationContent
            }
        }
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: didSave)
        .onChange(of: didSave) { _, saved in
            if saved { successTitleFocused = true }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var successContent: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.Colors.success)
                    .symbolEffect(.bounce, value: reduceMotion ? false : didSave)
                    .accessibilityHidden(true)

                Text("Workout Saved")
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityFocused($successTitleFocused)

                Text("Your history and insights are up to date. If Apple Health is connected, its sync continues in the background.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                summaryCard

                AppPrimaryButton(title: "Done", systemImage: "checkmark") {
                    onDone()
                }
            }
            .padding(Theme.Spacing.xl)
            .contentColumn(maxWidth: 640, alignment: .center)
        }
    }

    private var confirmationContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Finish Workout?")
                            .font(Theme.Typography.title2)
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

                summaryCard

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

    private var summaryCard: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Text("Elapsed")
                Spacer()
                Text(summary.startedAt, style: .timer)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .accessibilityElement(children: .combine)

            statRow(title: "Exercises", value: "\(summary.exerciseCount)")
            statRow(title: "Completed sets", value: "\(summary.completedSetCount)")

            if summary.strengthVolume > 0 {
                statRow(title: "Volume", value: SharedFormatters.volumeCompact(summary.strengthVolume))
            }
            if summary.cardioDistance > 0 {
                statRow(
                    title: "Distance",
                    value: WorkoutValueFormatter.distanceText(summary.cardioDistance)
                )
            }
            if summary.cardioSeconds > 0 {
                statRow(
                    title: "Cardio time",
                    value: WorkoutValueFormatter.durationText(seconds: summary.cardioSeconds)
                )
            }
            if summary.cardioCount > 0 {
                statRow(title: "Count", value: "\(summary.cardioCount)")
            }
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
