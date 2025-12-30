import SwiftUI

struct WorkoutHistoryView: View {
    let workouts: [Workout]
    @State private var searchText = ""
    
    private var groupedWorkouts: [(month: String, workouts: [Workout])] {
        let filtered = workouts.filter { workout in
            searchText.isEmpty || 
            workout.name.localizedCaseInsensitiveContains(searchText) ||
            workout.exercises.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        let grouped = Dictionary(grouping: filtered) { workout in
            let components = Calendar.current.dateComponents([.year, .month], from: workout.date)
            return Calendar.current.date(from: components)!
        }
        
        return grouped
            .sorted { $0.key > $1.key }
            .map { (month: $0.key.formatted(.dateTime.year().month(.wide)), workouts: $0.value.sorted { $0.date > $1.date }) }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.xl) {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.badge.exclamationmark",
                        description: Text("Complete workouts to see them here.")
                    )
                    .padding(.top, 50)
                } else {
                    ForEach(groupedWorkouts, id: \.month) { group in
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Text(group.month)
                                .font(Theme.Typography.title3)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.horizontal)
                            
                            ForEach(group.workouts) { workout in
                                WorkoutHistoryRow(workout: workout)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("History")
        .searchable(text: $searchText, prompt: "Search workouts or exercises")
    }
}

struct WorkoutHistoryRow: View {
    let workout: Workout
    
    var body: some View {
        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(workout.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Spacer()
                        
                        Text(workout.date.formatted(date: .omitted, time: .shortened))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    
                    Text(workout.date.formatted(.dateTime.weekday(.wide)) + ", " + workout.date.formatted(.dateTime.day()))
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    HStack(spacing: 12) {
                        Label(workout.duration, systemImage: "clock")
                        Label("\(workout.exercises.count) Exercises", systemImage: "figure.strengthtraining.traditional")
                        Label(formatVolume(workout.totalVolume), systemImage: "scalemass")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.top, 4)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
            .glassBackground()
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk lbs", volume / 1000)
        }
        return "\(Int(volume)) lbs"
    }
}