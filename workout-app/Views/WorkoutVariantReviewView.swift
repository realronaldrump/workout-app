import SwiftUI

struct WorkoutVariantReviewView: View {
    var focusWorkoutId: UUID?

    @EnvironmentObject private var variantEngine: WorkoutVariantEngine
    @State private var selectedWorkout: Workout?

    private let maxContentWidth: CGFloat = 820

    private var focusedReview: WorkoutVariantWorkoutReview? {
        guard let focusWorkoutId else { return nil }
        return variantEngine.review(for: focusWorkoutId)
    }

    private var standoutPatterns: [WorkoutVariantPattern] {
        Array(variantEngine.library.standoutPatterns.prefix(8))
    }

    private var recentReviews: [WorkoutVariantWorkoutReview] {
        variantEngine.library.recentReviews.filter { $0.id != focusWorkoutId }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    if variantEngine.isAnalyzing && variantEngine.library.recentReviews.isEmpty && variantEngine.library.standoutPatterns.isEmpty {
                        LoadingCard()
                    } else if standoutPatterns.isEmpty && recentReviews.isEmpty && focusedReview == nil {
                        emptyState
                    } else {
                        if let focusedReview {
                            focusedWorkoutSection(focusedReview)
                        }

                        if !standoutPatterns.isEmpty {
                            standoutPatternsSection
                        }

                        if !recentReviews.isEmpty {
                            recentReviewsSection
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .collapsingTitle("Workout variants")
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
    }

    private var header: some View {
        StatsPageHeader(
            eyebrow: "Variants",
            title: "Workout variants",
            systemImage: "square.3.layers.3d",
            help: "Compares similar workouts by exercise order, duration, time, and gym. Differences do not establish cause."
        )
    }

    private func focusedWorkoutSection(_ review: WorkoutVariantWorkoutReview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("This workout")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            WorkoutVariantSummaryCard(review: review, maxDifferences: 2)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(review.differences) { difference in
                    WorkoutVariantDetailCard(difference: difference)
                }
            }
        }
    }

    private var standoutPatternsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Standout patterns")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(standoutPatterns) { pattern in
                MetricTileButton(
                    action: { selectedWorkout = pattern.representativeWorkout },
                    content: {
                        WorkoutVariantPatternCard(pattern: pattern)
                    }
                )
            }
        }
    }

    private var recentReviewsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Recent variant reviews")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(recentReviews) { review in
                MetricTileButton(
                    action: { selectedWorkout = review.workout },
                    content: {
                        WorkoutVariantSummaryCard(review: review, maxDifferences: 1)
                    }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Not enough similar workouts")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }
}
