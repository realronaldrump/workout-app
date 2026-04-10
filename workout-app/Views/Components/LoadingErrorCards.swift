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
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Theme.Iconography.hero)
                .foregroundColor(Theme.Colors.warning)
                .accessibilityHidden(true)

            Text("Something went wrong")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(message)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Button {
                Haptics.selection()
                onRetry()
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                        .font(Theme.Typography.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .frame(minHeight: 48)
                .background(Theme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge))
                .shadow(color: Theme.Colors.accent.opacity(0.2), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error loading workouts. \(message)")
        .accessibilityHint("Double tap to retry")
    }
}
