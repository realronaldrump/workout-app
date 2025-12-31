import SwiftUI
import Charts

struct HealthDashboardView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @Environment(\.dismiss) var dismiss
    
    private var sortedHealthData: [WorkoutHealthData] {
        healthManager.healthDataStore.values
            .sorted { $0.workoutDate > $1.workoutDate }
    }
    
    private var thisWeekData: [WorkoutHealthData] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sortedHealthData.filter { $0.workoutDate >= weekAgo }
    }
    
    private var lastWeekData: [WorkoutHealthData] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        return sortedHealthData.filter { $0.workoutDate >= twoWeeksAgo && $0.workoutDate < weekAgo }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        if healthManager.healthDataStore.isEmpty {
                            emptyState
                        } else {
                            // Recovery & Readiness
                            recoveryScoreSection
                            
                            // Week over Week Comparison
                            weekComparisonSection
                            
                            // Heart Rate Trends Chart
                            heartRateTrendsSection
                            
                            // Recent Workouts (Limited)
                            recentWorkoutsSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Health Insights")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.top, 40)
            
            Text("No Health Data Yet")
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text("Sync your workouts with Apple Health to see aggregated insights here.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Recovery Score Section
    
    private var recoveryScoreSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Recovery Status")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            let recovery = calculateRecoveryScore()
            
            HStack(spacing: Theme.Spacing.lg) {
                // Recovery Score Circle
                ZStack {
                    Circle()
                        .stroke(Theme.Colors.surface, lineWidth: 8)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(recovery.score) / 100)
                        .stroke(recovery.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    
                    VStack(spacing: 2) {
                        Text("\(recovery.score)")
                            .font(Theme.Typography.title2)
                            .bold()
                        Text("%")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(recovery.label)
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text(recovery.message)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .glassBackground(elevation: 2)
        }
    }
    
    // MARK: - Week Comparison Section
    
    private var weekComparisonSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("This Week vs Last Week")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                // Workout Count
                let thisWeekCount = thisWeekData.count
                let lastWeekCount = lastWeekData.count
                comparisonCard(
                    title: "Workouts",
                    thisWeek: "\(thisWeekCount)",
                    change: thisWeekCount - lastWeekCount,
                    icon: "figure.run",
                    color: .green
                )
                
                // Average HR
                let thisWeekAvgHR = average(thisWeekData.compactMap { $0.avgHeartRate })
                let lastWeekAvgHR = average(lastWeekData.compactMap { $0.avgHeartRate })
                comparisonCard(
                    title: "Avg HR",
                    thisWeek: thisWeekAvgHR != nil ? "\(Int(thisWeekAvgHR!)) bpm" : "--",
                    change: Int((thisWeekAvgHR ?? 0) - (lastWeekAvgHR ?? 0)),
                    icon: "heart.fill",
                    color: .red,
                    lowerIsBetter: true
                )
                
                // Total Calories
                let thisWeekCals = thisWeekData.compactMap { $0.activeCalories }.reduce(0, +)
                let lastWeekCals = lastWeekData.compactMap { $0.activeCalories }.reduce(0, +)
                comparisonCard(
                    title: "Calories Burned",
                    thisWeek: formatNumber(thisWeekCals),
                    change: Int(thisWeekCals - lastWeekCals),
                    icon: "flame.fill",
                    color: .orange
                )
                
                // Max HR
                let thisWeekMaxHR = thisWeekData.compactMap { $0.maxHeartRate }.max()
                let lastWeekMaxHR = lastWeekData.compactMap { $0.maxHeartRate }.max()
                comparisonCard(
                    title: "Peak HR",
                    thisWeek: thisWeekMaxHR != nil ? "\(Int(thisWeekMaxHR!))" : "--",
                    change: Int((thisWeekMaxHR ?? 0) - (lastWeekMaxHR ?? 0)),
                    icon: "bolt.heart.fill",
                    color: .pink
                )
            }
        }
    }
    
    private func comparisonCard(title: String, thisWeek: String, change: Int, icon: String, color: Color, lowerIsBetter: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
                if change != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                        Text("\(abs(change))")
                            .font(Theme.Typography.caption)
                    }
                    .foregroundStyle(changeColor(change, lowerIsBetter: lowerIsBetter))
                }
            }
            
            Text(thisWeek)
                .font(Theme.Typography.title2)
                .bold()
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding()
        .glassBackground(elevation: 2)
    }
    
    private func changeColor(_ change: Int, lowerIsBetter: Bool) -> Color {
        if change == 0 { return Theme.Colors.textTertiary }
        let isPositive = change > 0
        let isGood = lowerIsBetter ? !isPositive : isPositive
        return isGood ? Theme.Colors.success : Theme.Colors.error
    }
    
    // MARK: - Heart Rate Trends Section
    
    private var heartRateTrendsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Heart Rate Trends")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Trend insight message
                if let insight = heartRateTrendInsight() {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: insight.icon)
                            .foregroundStyle(insight.color)
                        Text(insight.message)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(insight.color.opacity(0.1))
                    .cornerRadius(Theme.CornerRadius.medium)
                }
                
                // Chart
                let chartData = sortedHealthData.suffix(20).reversed()
                Chart {
                    ForEach(Array(chartData), id: \.workoutId) { data in
                        if let avg = data.avgHeartRate {
                            LineMark(
                                x: .value("Date", data.workoutDate),
                                y: .value("Avg HR", avg)
                            )
                            .foregroundStyle(Color.red)
                            .symbol(Circle())
                        }
                        
                        if let max = data.maxHeartRate {
                            LineMark(
                                x: .value("Date", data.workoutDate),
                                y: .value("Max HR", max)
                            )
                            .foregroundStyle(Color.pink.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [5, 5]))
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartLegend(position: .bottom)
                .frame(height: 180)
                
                // Legend
                HStack(spacing: Theme.Spacing.lg) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("Avg HR").font(Theme.Typography.caption)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.pink.opacity(0.5)).frame(width: 8, height: 8)
                        Text("Max HR").font(Theme.Typography.caption)
                    }
                }
                .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
            .glassBackground(elevation: 2)
        }
    }
    
    // MARK: - Recent Workouts Section
    
    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Recent Workout Health Data")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            // Only show last 5 workouts
            ForEach(Array(sortedHealthData.prefix(5)), id: \.workoutId) { data in
                WorkoutHealthCard(healthData: data)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func calculateRecoveryScore() -> (score: Int, label: String, message: String, color: Color) {
        let recentData = Array(sortedHealthData.prefix(3))
        guard !recentData.isEmpty else {
            return (50, "Unknown", "Not enough data to assess recovery.", Theme.Colors.textTertiary)
        }
        
        // Simple recovery score based on HR trends
        let avgHRs = recentData.compactMap { $0.avgHeartRate }
        let overallAvgHR = avgHRs.isEmpty ? 0 : avgHRs.reduce(0, +) / Double(avgHRs.count)
        
        // Lower workout HR generally indicates better fitness/recovery
        // This is a simplified model
        var score: Int
        var label: String
        var message: String
        var color: Color
        
        if overallAvgHR < 120 {
            score = 90
            label = "Excellent"
            message = "Your recent workout heart rates are low, indicating great cardiovascular fitness."
            color = Theme.Colors.success
        } else if overallAvgHR < 140 {
            score = 75
            label = "Good"
            message = "Your heart rate efficiency is solid. Keep up the consistent training."
            color = Color.green
        } else if overallAvgHR < 155 {
            score = 60
            label = "Moderate"
            message = "Your workout intensity has been high. Consider adding recovery sessions."
            color = Theme.Colors.warning
        } else {
            score = 45
            label = "Recovery Needed"
            message = "High workout heart rates detected. Take rest days to allow proper recovery."
            color = Theme.Colors.error
        }
        
        return (score, label, message, color)
    }
    
    private func heartRateTrendInsight() -> (icon: String, message: String, color: Color)? {
        guard thisWeekData.count >= 2 && lastWeekData.count >= 1 else { return nil }
        
        let thisWeekAvgHR = average(thisWeekData.compactMap { $0.avgHeartRate })
        let lastWeekAvgHR = average(lastWeekData.compactMap { $0.avgHeartRate })
        
        guard let thisAvg = thisWeekAvgHR, let lastAvg = lastWeekAvgHR else { return nil }
        
        let diff = thisAvg - lastAvg
        
        if abs(diff) < 3 {
            return ("arrow.forward", "Your heart rate is stable compared to last week.", Theme.Colors.textSecondary)
        } else if diff < 0 {
            return ("arrow.down.circle.fill", "Your workout heart rate dropped \(Int(abs(diff))) bpm from last week. Great progress!", Theme.Colors.success)
        } else {
            return ("arrow.up.circle.fill", "Your workout heart rate increased \(Int(diff)) bpm. This could indicate fatigue or higher intensity.", Theme.Colors.warning)
        }
    }
    
    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private func formatNumber(_ num: Double) -> String {
        if num > 10000 {
            return String(format: "%.1fk", num / 1000)
        }
        return "\(Int(num))"
    }
}

// MARK: - Workout Health Card

private struct WorkoutHealthCard: View {
    let healthData: WorkoutHealthData
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Header with date
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(healthData.workoutDate.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(healthData.workoutDate.formatted(date: .omitted, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
            }
            
            // Metrics in a horizontal layout
            HStack(spacing: Theme.Spacing.lg) {
                if let avgHR = healthData.avgHeartRate {
                    metricPill(icon: "heart.fill", value: "\(Int(avgHR))", unit: "bpm", color: .red)
                }
                
                if let cals = healthData.activeCalories {
                    metricPill(icon: "flame.fill", value: "\(Int(cals))", unit: "cal", color: .orange)
                }
                
                if let maxHR = healthData.maxHeartRate {
                    metricPill(icon: "bolt.heart", value: "\(Int(maxHR))", unit: "max", color: .pink)
                }
                
                Spacer()
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 2)
    }
    
    private func metricPill(icon: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(Theme.Typography.subheadline)
                .bold()
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(unit)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}
