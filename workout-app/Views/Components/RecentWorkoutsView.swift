import SwiftUI

struct RecentWorkoutsView: View {
    let workouts: [Workout]
    let allWorkouts: [Workout]
    @EnvironmentObject var healthManager: HealthKitManager

    init(workouts: [Workout], allWorkouts: [Workout]? = nil) {
        self.workouts = workouts
        self.allWorkouts = allWorkouts ?? workouts
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Recent Workouts")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Spacer()
                
                NavigationLink(destination: WorkoutHistoryView(workouts: allWorkouts, showsBackButton: true)) {
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
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(workout.name)
                        .font(Theme.Typography.condensed)
                        .tracking(-0.2)
                        .foregroundColor(Theme.Colors.textPrimary)
                    
                    Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                    
                    HStack(spacing: Theme.Spacing.md) {
                        Label(workout.duration, systemImage: "clock")
                        Label("\(workout.exercises.count) exercises", systemImage: "figure.strengthtraining.traditional")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    
                    if let data = healthManager.getHealthData(for: workout.id) {
                        HealthDataSummaryView(healthData: data)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
