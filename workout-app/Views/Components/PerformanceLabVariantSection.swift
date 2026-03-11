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

            Text("How different versions of a similar exercise mix tend to change performance.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            if patterns.isEmpty {
                Text("Repeat a similar set of exercises in different ways and the app will compare those variants here.")
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
