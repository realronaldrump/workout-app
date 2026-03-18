import SwiftUI

struct PerformanceLabVariantSection: View {
    let patterns: [WorkoutVariantPattern]
    let onSelectWorkout: (Workout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Workout Variants")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                NavigationLink {
                    WorkoutVariantReviewView()
                } label: {
                    Text("More")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.accent)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }
                .buttonStyle(.plain)
            }

            Text("Compare how swapping exercises in a similar routine affects your results.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            if patterns.isEmpty {
                Text("Try mixing up your exercises across workouts and the app will compare the variants here.")
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
