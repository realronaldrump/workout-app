import SwiftUI
import Charts

struct HealthDashboardView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var dataManager: WorkoutDataManager
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
                            recoveryScoreSection
                            recoveryDebtSection
                            weekComparisonSection
                            heartRateTrendsSection
                            sleepRecoverySection
                            activityLoadSection
                            cardioProgressSection
                            bodyCompositionSection
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

    private var recoveryDebtSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Recovery Debt")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)

            if let snapshot = WorkoutAnalytics.recoveryDebtSnapshot(workouts: dataManager.workouts, healthData: healthManager.healthDataStore) {
                HStack(spacing: Theme.Spacing.lg) {
                    ZStack {
                        Circle()
                            .stroke(Theme.Colors.surface, lineWidth: 8)
                            .frame(width: 70, height: 70)

                        Circle()
                            .trim(from: 0, to: CGFloat(snapshot.score) / 100)
                            .stroke(snapshot.tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 70, height: 70)
                            .rotationEffect(.degrees(-90))

                        Text("\(snapshot.score)")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(snapshot.label)
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(snapshot.detail)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer()
                }
                .padding(Theme.Spacing.lg)
                .glassBackground(elevation: 2)
            } else {
                Text("Sync Health data to calculate recovery debt.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
            }
        }
    }

    // MARK: - Week Comparison Section

    private var weekComparisonSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("This Week vs Last Week")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                let thisWeekCount = thisWeekData.count
                let lastWeekCount = lastWeekData.count
                comparisonCard(
                    title: "Workouts",
                    thisWeek: "\(thisWeekCount)",
                    change: thisWeekCount - lastWeekCount,
                    icon: "figure.run",
                    color: .green
                )

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

                let thisWeekCals = thisWeekData.compactMap { $0.activeCalories }.reduce(0, +)
                let lastWeekCals = lastWeekData.compactMap { $0.activeCalories }.reduce(0, +)
                comparisonCard(
                    title: "Calories Burned",
                    thisWeek: formatNumber(thisWeekCals),
                    change: Int(thisWeekCals - lastWeekCals),
                    icon: "flame.fill",
                    color: .orange
                )

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

    // MARK: - Heart Rate Trends

    private var heartRateTrendsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Heart Rate Trends")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
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

    // MARK: - Sleep & Recovery

    private var sleepRecoverySection: some View {
        let sleepPoints = sortedHealthData.compactMap { data -> HealthTrendPoint? in
            guard let hours = data.sleepSummary?.totalHours else { return nil }
            return HealthTrendPoint(date: data.workoutDate, value: hours, label: "Sleep")
        }
        .sorted { $0.date < $1.date }

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Sleep & Recovery")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)

            if sleepPoints.isEmpty {
                Text("Sleep data isn't available yet. Enable sleep tracking in Apple Health.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
            } else {
                Chart(sleepPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Hours", point.value)
                    )
                    .foregroundStyle(Theme.Colors.accentSecondary)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Hours", point.value)
                    )
                    .foregroundStyle(Theme.Colors.accentSecondary)
                }
                .chartYScale(domain: 0...10)
                .frame(height: 160)
                .padding(Theme.Spacing.lg)
                .glassBackground(elevation: 2)

                let avgSleep = average(sleepPoints.map { $0.value }) ?? 0
                Text(avgSleep >= 7 ? "Sleep is supporting your training." : "Sleep is trending below 7 hours. Recovery could improve.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    // MARK: - Activity Load

    private var activityLoadSection: some View {
        let points = sortedHealthData.compactMap { data -> HealthTrendPoint? in
            guard let energy = data.dailyActiveEnergy else { return nil }
            return HealthTrendPoint(date: data.workoutDate, value: energy, label: "Active Energy")
        }
        .sorted { $0.date < $1.date }

        let ratios = sortedHealthData.compactMap { data -> HealthTrendPoint? in
            guard let energy = data.dailyActiveEnergy else { return nil }
            guard let workout = dataManager.workouts.first(where: { $0.id == data.workoutId }) else { return nil }
            let ratio = workout.totalVolume / max(energy, 1)
            return HealthTrendPoint(date: data.workoutDate, value: ratio, label: "Load Ratio")
        }
        .sorted { $0.date < $1.date }

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Activity vs Training")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)

            if points.isEmpty {
                Text("Daily activity metrics are missing. Check Apple Health permissions.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Active Energy", point.value)
                    )
                    .foregroundStyle(.orange)
                }
                .frame(height: 160)
                .padding(Theme.Spacing.lg)
                .glassBackground(elevation: 2)

                if !ratios.isEmpty {
                    Chart(ratios) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Load Ratio", point.value)
                        )
                        .foregroundStyle(Theme.Colors.accent)
                    }
                    .frame(height: 140)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
                }
            }
        }
    }

    // MARK: - Cardio Progress

    private var cardioProgressSection: some View {
        let vo2Points = sortedHealthData.compactMap { data -> HealthTrendPoint? in
            guard let vo2 = data.vo2Max else { return nil }
            return HealthTrendPoint(date: data.workoutDate, value: vo2, label: "VO2 Max")
        }
        .sorted { $0.date < $1.date }

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Cardio Progress")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)

            if vo2Points.isEmpty {
                Text("VO2 Max isn't available yet. Cardio fitness data appears after runs or walks.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
            } else {
                Chart(vo2Points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("VO2", point.value)
                    )
                    .foregroundStyle(Theme.Colors.success)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("VO2", point.value)
                    )
                    .foregroundStyle(Theme.Colors.success)
                }
                .frame(height: 160)
                .padding(Theme.Spacing.lg)
                .glassBackground(elevation: 2)

                let recoveryAvg = average(sortedHealthData.compactMap { $0.heartRateRecovery }) ?? 0
                let walkingAvg = average(sortedHealthData.compactMap { $0.walkingHeartRateAverage }) ?? 0

                if recoveryAvg > 0 || walkingAvg > 0 {
                    HStack(spacing: Theme.Spacing.xl) {
                        if recoveryAvg > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Avg HR Recovery")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text("\(Int(recoveryAvg)) bpm")
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                        }

                        if walkingAvg > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Walking HR Avg")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text("\(Int(walkingAvg)) bpm")
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                        }

                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Body Composition

    private var bodyCompositionSection: some View {
        let weightPoints = sortedHealthData.compactMap { data -> HealthTrendPoint? in
            guard let mass = data.bodyMass else { return nil }
            return HealthTrendPoint(date: data.workoutDate, value: mass * 2.20462, label: "Weight")
        }
        .sorted { $0.date < $1.date }

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Body Composition")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)

            if weightPoints.isEmpty {
                Text("Body mass data isn't available. Enable weight tracking in Apple Health.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
            } else {
                Chart(weightPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                }
                .frame(height: 160)
                .padding(Theme.Spacing.lg)
                .glassBackground(elevation: 2)

                let volumePoints = sortedHealthData.compactMap { data -> Double? in
                    guard let workout = dataManager.workouts.first(where: { $0.id == data.workoutId }) else { return nil }
                    return workout.totalVolume
                }
                let avgVolume = average(volumePoints) ?? 0
                let avgBodyFat = average(sortedHealthData.compactMap { $0.bodyFatPercentage }) ?? 0

                Text("Average volume at current weight: \(formatNumber(avgVolume))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if avgBodyFat > 0 {
                    Text("Avg body fat: \(String(format: "%.1f", avgBodyFat * 100))%")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Recent Workouts Section

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Recent Workout Health Data")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)

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

        let avgHRs = recentData.compactMap { $0.avgHeartRate }
        let overallAvgHR = avgHRs.isEmpty ? 0 : avgHRs.reduce(0, +) / Double(avgHRs.count)

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

private struct WorkoutHealthCard: View {
    let healthData: WorkoutHealthData

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
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
