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

    let isFinishing: Bool
    let summary: FinishSessionSummary
    let errorMessage: String?
    let onFinish: () -> Void
    let onDismissError: () -> Void

    var body: some View {
        ZStack {
            AdaptiveBackground()

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Finish Session")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("Save your workout and (optionally) sync Apple Health.")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    AppToolbarButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }

                VStack(spacing: Theme.Spacing.sm) {
                    statRow(title: "Elapsed", value: SharedFormatters.elapsed(Date().timeIntervalSince(summary.startedAt)))
                    statRow(title: "Exercises", value: "\(summary.exerciseCount)")
                    statRow(title: "Completed sets", value: "\(summary.completedSetCount)")
                    if summary.strengthVolume > 0 {
                        statRow(title: "Volume", value: SharedFormatters.volumeCompact(summary.strengthVolume))
                    }
                    if summary.cardioDistance > 0 {
                        statRow(
                            title: "Distance",
                            value: "\(WorkoutValueFormatter.distanceText(summary.cardioDistance)) dist"
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
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 1)

                if let errorMessage {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMessage)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        AppPillButton(title: "Dismiss", systemImage: "xmark", variant: .danger) {
                            onDismissError()
                        }
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.error)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
                }

                Button {
                    onFinish()
                } label: {
                    HStack {
                        Spacer()
                        Text(isFinishing ? "Finishing..." : "Finish & Save")
                            .font(Theme.Typography.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    .background(Theme.Colors.success)
                    .cornerRadius(Theme.CornerRadius.large)
                }
                .buttonStyle(.plain)
                .disabled(isFinishing)
                .opacity(isFinishing ? 0.7 : 1.0)

                Spacer()
            }
            .padding(Theme.Spacing.xl)
        }
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }

}
