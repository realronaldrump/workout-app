import SwiftUI

struct OverviewCardsView: View {
    let stats: WorkoutStats

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Overview")
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                StatCard(
                    title: "Total Workouts",
                    value: "\(stats.totalWorkouts)",
                    icon: "figure.strengthtraining.traditional",
                    color: .blue
                )

                StatCard(
                    title: "Current Streak",
                    value: "\(stats.currentStreak)",
                    subtitle: "days",
                    icon: "flame.fill",
                    color: .orange
                )

                StatCard(
                    title: "Total Volume",
                    value: formatVolume(stats.totalVolume),
                    icon: "scalemass.fill",
                    color: .green
                )

                StatCard(
                    title: "Avg Duration",
                    value: stats.avgWorkoutDuration,
                    icon: "clock.fill",
                    color: .purple
                )
            }

            if let lastWorkout = stats.lastWorkoutDate {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text("last \(lastWorkout.formatted(date: .abbreviated, time: .omitted))")
                        .font(Theme.Typography.caption)
                }
                .foregroundColor(Theme.Colors.textTertiary)
            }
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000000 {
            return String(format: "%.1fM", volume / 1000000)
        } else if volume >= 1000 {
            return String(format: "%.0fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String?
    let icon: String
    let color: Color
    var onTap: (() -> Void)?

    @State private var isAppearing = false

    // Keep tiles visually consistent while giving text enough vertical room
    // (prevents top/bottom clipping on metric screens).
    private let tileHeight: CGFloat = 128

    var body: some View {
        Group {
            if let onTap {
                MetricTileButton(action: onTap) {
                    cardContent
                }
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.Typography.metric)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(height: tileHeight)
        .softCard(elevation: 2)
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 8)
        .onAppear {
            withAnimation(Theme.Animation.spring) {
                isAppearing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let subtitle {
            return "\(title), \(value) \(subtitle)"
        }
        return "\(title), \(value)"
    }
}
