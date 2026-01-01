import SwiftUI

struct ConsistencyView: View {
    let stats: WorkoutStats
    let workouts: [Workout]
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Consistency")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
            
            VStack(spacing: Theme.Spacing.lg) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Workouts per Week")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Text(String(format: "%.1f", stats.workoutsPerWeek))
                            .font(Theme.Typography.metric)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Longest Streak")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Text("\(stats.longestStreak) days")
                            .font(Theme.Typography.metric)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
                
                CalendarHeatmap(workouts: workouts)
            }
            .padding(Theme.Spacing.lg)
            .glassBackground(elevation: 2)
        }
    }
}

struct CalendarHeatmap: View {
    let workouts: [Workout]
    
    private let columns = 7
    private let cellSize: CGFloat = 20
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: cellSize)
                }
            }
            
            let dates = generateDateGrid()
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 4), count: columns), spacing: 4) {
                ForEach(dates, id: \.self) { date in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorForDate(date))
                        .frame(width: cellSize, height: cellSize)
                }
            }
            
            HStack(spacing: 8) {
                Text("Less")
                    .font(.caption2)
                    .foregroundColor(Theme.Colors.textTertiary)
                
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Colors.success.opacity(intensity))
                        .frame(width: 12, height: 12)
                }
                
                Text("More")
                    .font(.caption2)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.top, 8)
        }
    }
    
    private func generateDateGrid() -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        let today = Date()
        
        // Go back 12 weeks
        for week in 0..<12 {
            for day in 0..<7 {
                if let date = calendar.date(byAdding: .day, value: -(week * 7 + day), to: today) {
                    dates.insert(date, at: 0)
                }
            }
        }
        
        return dates
    }
    
    private func colorForDate(_ date: Date) -> Color {
        let calendar = Calendar.current
        let workoutsOnDate = workouts.filter { calendar.isDate($0.date, inSameDayAs: date) }
        
        if workoutsOnDate.isEmpty {
            return Theme.Colors.surface.opacity(0.6)
        } else if workoutsOnDate.count == 1 {
            return Theme.Colors.success.opacity(0.5)
        } else {
            return Theme.Colors.success
        }
    }
}
