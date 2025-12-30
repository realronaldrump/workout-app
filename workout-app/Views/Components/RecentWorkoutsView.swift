import SwiftUI

struct RecentWorkoutsView: View {
    let workouts: [Workout]
    @EnvironmentObject var healthManager: HealthKitManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Recent Workouts")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Spacer()
                
                NavigationLink(destination: WorkoutHistoryView(workouts: workouts)) {
                    Text("See All")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.accent)
                }
            }
            
            VStack(spacing: Theme.Spacing.md) {
                ForEach(workouts) { workout in
                    WorkoutRowView(workout: workout)
                }
            }
        }
    }
}

struct WorkoutRowView: View {
    let workout: Workout
    @EnvironmentObject var healthManager: HealthKitManager
    
    var body: some View {
        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text(workout.name)
                        .font(Theme.Typography.condensed)
                        .tracking(-0.2)
                        .foregroundColor(Theme.Colors.textPrimary)
                    
                    Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                
                HStack(spacing: Theme.Spacing.md) {
                    Label(workout.duration, systemImage: "clock")
                    Label("\(workout.exercises.count) exercises", systemImage: "figure.strengthtraining.traditional")
                }
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                
                if let data = healthManager.getHealthData(for: workout.id) {
                    HealthDataSummaryView(healthData: data)
                }
            }
            .padding(Theme.Spacing.lg)
            .glassBackground(elevation: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
