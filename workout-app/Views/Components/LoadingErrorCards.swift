import SwiftUI

// MARK: - Loading Card

/// Displayed when initial data load is in progress.
/// Uses shimmer skeleton placeholders that match the app's card layout.
struct LoadingCard: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Mimic a briefing card skeleton
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SkeletonRect(width: 140, height: 16, cornerRadius: Theme.CornerRadius.small)
                SkeletonRect(height: 12, cornerRadius: Theme.CornerRadius.small)
                SkeletonRect(width: 200, height: 12, cornerRadius: Theme.CornerRadius.small)
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)

            // Mimic a metric row skeleton
            HStack(spacing: Theme.Spacing.md) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SkeletonRect(width: 60, height: 10, cornerRadius: Theme.CornerRadius.small)
                        SkeletonRect(width: 80, height: 20, cornerRadius: Theme.CornerRadius.small)
                    }
                    .padding(Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .softCard(elevation: 1)
                }
            }

            // Mimic a chart skeleton
            SkeletonChart(height: Theme.ChartHeight.standard)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading workouts")
    }
}

// MARK: - Error Card

/// Displayed when data loading fails. Includes a retry action.
struct ErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Workouts didn't load")
                .font(Theme.Typography.sectionHeader2)
                .foregroundColor(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AppPrimaryButton(title: "Try again", systemImage: "arrow.clockwise") {
                Haptics.selection()
                onRetry()
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .softCard()
        .accessibilityElement(children: .contain)
    }
}
