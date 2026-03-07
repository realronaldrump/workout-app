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
        .navigationTitle("Workout Variants")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Workout Variants")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.5)

            Text("This shows what usually changes when you do the same workout in a different way.")
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func focusedWorkoutSection(_ review: WorkoutVariantWorkoutReview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("This Workout")
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
            Text("Standout Patterns")
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
            Text("Recent Variant Reviews")
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
            Text("Not enough repeated variation yet")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("This feature appears once the app can compare multiple versions of the same workout name across your history.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }
}
