import SwiftUI
import Charts

struct HealthDashboardView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    
                    if healthManager.healthDataStore.isEmpty {
                        emptyState
                    } else {
                        // Summary Cards
                        summarySection
                        
                        // Recent Trends
                        trendsSection
                        
                        // Recent Workouts List
                        recentWorkoutsSection
                    }
                }
                .padding()
            }
            .background(Theme.Colors.background)
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
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Overview")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                let allData = Array(healthManager.healthDataStore.values)
                
                // Total Workouts
                summaryCard(
                    title: "Workouts",
                    value: "\(allData.count)",
                    icon: "figure.run",
                    color: .green
                )
                
                // Active Calories
                let totalCals = allData.compactMap { $0.activeCalories }.reduce(0, +)
                summaryCard(
                    title: "Active Cals",
                    value: formatNumber(totalCals),
                    icon: "flame.fill",
                    color: .orange
                )
                
                // Avg Heart Rate (Weighted average could be better, but simple avg for now)
                let avgHRs = allData.compactMap { $0.avgHeartRate }
                let avgHR = avgHRs.isEmpty ? 0 : avgHRs.reduce(0, +) / Double(avgHRs.count)
                summaryCard(
                    title: "Avg HR",
                    value: "\(Int(avgHR)) bpm",
                    icon: "heart.fill",
                    color: .red
                )
                
                // Total Duration (if available)
                // Assuming we can sum durations if we had them or just distance
                let totalDist = allData.compactMap { $0.distance }.reduce(0, +)
                summaryCard(
                    title: "Distance",
                    value: String(format: "%.1f mi", totalDist / 1609.34),
                    icon: "map.fill",
                    color: .blue
                )
            }
        }
    }
    
    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            
            Text(value)
                .font(Theme.Typography.title2)
                .bold()
            
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding()
        .glassBackground()
    }
    
    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Trends")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            // HR Trend Chart
            VStack(alignment: .leading) {
                Text("Avg Heart Rate History")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Chart {
                    ForEach(healthManager.healthDataStore.values.sorted(by: { $0.workoutDate < $1.workoutDate }), id: \.workoutId) { data in
                        if let avg = data.avgHeartRate {
                            LineMark(
                                x: .value("Date", data.workoutDate),
                                y: .value("BPM", avg)
                            )
                            .foregroundStyle(.red)
                            .symbol(Circle())
                        }
                    }
                }
                .frame(height: 150)
            }
            .padding()
            .glassBackground()
        }
    }
    
    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Detailed Logs")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            ForEach(healthManager.healthDataStore.values.sorted(by: { $0.workoutDate > $1.workoutDate }), id: \.workoutId) { data in
                HealthDataSummaryView(healthData: data)
                    .padding()
                    .glassBackground()
            }
        }
    }
    
    private func formatNumber(_ num: Double) -> String {
        if num > 10000 {
            return String(format: "%.1fk", num / 1000)
        }
        return "\(Int(num))"
    }
}
