import SwiftUI

struct OverviewCardsView: View {
    let stats: WorkoutStats

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: Theme.Spacing.md)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("OVERVIEW")
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .tracking(1.2)
                .padding(.leading, 4)

            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
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
                    value: SharedFormatters.volumeCompact(stats.totalVolume),
                    icon: "scalemass.fill",
                    color: .green
                )

                StatCard(
                    title: "Total Sets",
                    value: "\(stats.totalSets)",
                    icon: "number.square.fill",
                    color: .purple
                )
            }

            if let lastWorkout = stats.lastWorkoutDate {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "calendar")
                        .font(Theme.Typography.caption)
                    Text("last \(lastWorkout.formatted(date: .abbreviated, time: .omitted))")
                        .font(Theme.Typography.caption)
                }
                .foregroundColor(Theme.Colors.textTertiary)
            }
        }
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
                MetricTileButton(action: onTap, content: { cardContent })
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Iconography.title3Strong)
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
        .softCard(elevation: 1)
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
