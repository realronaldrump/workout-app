import SwiftUI

// MARK: - Loading Card

/// Displayed when initial data load is in progress.
/// Matches the brutalist card style used throughout the app.
struct LoadingCard: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .controlSize(.regular)
                .tint(Theme.Colors.accent)

            Text("Loading workouts…")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
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
