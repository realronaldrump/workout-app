import SwiftUI

struct ConsistencyView: View {
    let stats: WorkoutStats
    let workouts: [Workout]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Consistency")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Workouts per Week")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f", stats.workoutsPerWeek))
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Longest Streak")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(stats.longestStreak) days")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                }
                
                CalendarHeatmap(workouts: workouts)
                    .frame(height: 120)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
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
                        .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
                
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(intensity))
                        .frame(width: 12, height: 12)
                }
                
                Text("More")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
            return Color(.systemGray5)
        } else if workoutsOnDate.count == 1 {
            return Color.green.opacity(0.5)
        } else {
            return Color.green
        }
    }
}