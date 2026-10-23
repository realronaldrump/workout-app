import SwiftUI

struct PerformanceLabVariantSection: View {
    let patterns: [WorkoutVariantPattern]
    let onSelectWorkout: (Workout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Workout variants")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                AppHelpButton(
                    title: "Workout variants",
                    message: "Compares sessions with similar exercises, grouped by exercise order, duration, time, and gym. Differences do not establish cause."
                )
                Spacer()

                NavigationLink {
                    WorkoutVariantReviewView()
                } label: {
                    Text("More")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
            }

            if patterns.isEmpty {
                Text("Variants need at least 4 workouts with the same exercises.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(patterns) { pattern in
                        MetricTileButton(
                            action: { onSelectWorkout(pattern.representativeWorkout) },
                            content: {
                                WorkoutVariantPatternCard(pattern: pattern, maxEvidence: 1)
                            }
                        )
                    }
                }
            }
        }
    }
}
