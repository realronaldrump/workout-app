import SwiftUI

struct OverviewCardsView: View {
    let stats: WorkoutStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Overview")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
            
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
                    Text("Last workout: \(lastWorkout.formatted(date: .abbreviated, time: .omitted))")
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
    var subtitle: String? = nil
    let icon: String
    let color: Color
    
    @State private var isAppearing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
            
            Spacer()
            
            // Value with optional subtitle
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.Typography.number)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            
            // Title
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .frame(height: 120)
        .glassBackground()
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 8)
        .onAppear {
            withAnimation(Theme.Animation.spring) {
                isAppearing = true
            }
        }
    }
}