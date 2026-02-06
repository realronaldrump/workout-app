import SwiftUI

struct ConsistencyView: View {
    let stats: WorkoutStats
    let workouts: [Workout]
    var onTap: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Consistency")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
            
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
    }

    private var cardContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Sessions/Wk")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text(String(format: "%.1f", stats.workoutsPerWeek))
                        .font(Theme.Typography.metric)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Longest")
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

struct CalendarHeatmap: View {
    let workouts: [Workout]
    
    private let rows = Array(repeating: GridItem(.fixed(12), spacing: 4), count: 7)
    private let weeks = 16
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Day Labels
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    if index % 2 == 1 { // Mon, Wed, Fri
                        Text(dayLabel(for: index))
                            .font(.caption2)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(height: 12)
                    } else {
                        Spacer().frame(height: 12)
                    }
                }
            }
            .padding(.top, 0)
            
            // Heatmap Grid
            let dates = generateDateGrid()
            LazyHGrid(rows: rows, spacing: 4) {
                ForEach(dates, id: \.self) { date in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForDate(date))
                        .frame(width: 12, height: 12)
                }
            }
        }
        .frame(height: 120) // Fixed height for the horizontal container
        
        // Legend
        HStack(spacing: 8) {
            Text("0")
                .font(.caption2)
                .foregroundColor(Theme.Colors.textTertiary)
            
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.success.opacity(intensity))
                    .frame(width: 12, height: 12)
            }
            
            Text(formatVolume(maxVolume))
                .font(.caption2)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.top, 8)
    }
    
    private func dayLabel(for index: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // weekdaySymbols returns [Sun, Mon, Tue...]
        // We want short labels like M, W, F
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        return symbols[index]
    }
    
    private func generateDateGrid() -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        let today = Date()
        
        // Find the most recent Saturday (end of current week)
        let weekday = calendar.component(.weekday, from: today) // Sun=1 ... Sat=7
        // Calculate days to add to get to Saturday
        let daysToSaturday = 7 - weekday
        
        guard let endOfWeek = calendar.date(byAdding: .day, value: daysToSaturday, to: today) else { return [] }
        
        // We want 'weeks' number of weeks.
        // Total days = weeks * 7
        // Start date is (weeks * 7) - 1 days ago relative to endOfWeek? 
        // No, we want exactly 'weeks' columns. 
        // Example: weeks=1. End = Sat. Start = Sun (6 days ago).
        // dates needed: Sun ... Sat.
        
        let totalDays = weeks * 7
        
        for i in 0..<totalDays {
            // we want to start from the past.
            // i=0 -> oldest date.
            // i=totalDays-1 -> endOfWeek
            
            let daysBack = (totalDays - 1) - i
            if let date = calendar.date(byAdding: .day, value: -daysBack, to: endOfWeek) {
                dates.append(date)
            }
        }
        
        return dates
    }
    
    private func colorForDate(_ date: Date) -> Color {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let volume = dailyVolume[day, default: 0]
        guard volume > 0, maxVolume > 0 else {
            return Theme.Colors.surface.opacity(0.3)
        }
        let intensity = min(max(volume / maxVolume, 0.1), 1)
        return Theme.Colors.success.opacity(0.15 + intensity * 0.85)
    }

    private var dailyVolume: [Date: Double] {
        let calendar = Calendar.current
        return workouts.reduce(into: [Date: Double]()) { totals, workout in
            let day = calendar.startOfDay(for: workout.date)
            totals[day, default: 0] += workout.totalVolume
        }
    }

    private var maxVolume: Double {
        dailyVolume.values.max() ?? 0
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000000 {
            return String(format: "%.1fM", volume / 1000000)
        } else if volume >= 1000 {
            return String(format: "%.0fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }
}
