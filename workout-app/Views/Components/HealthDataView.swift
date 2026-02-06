import SwiftUI
import Charts

/// Displays health data synced from Apple Health for a workout
struct HealthDataView: View {
    let healthData: WorkoutHealthData
    @State private var showingAllHeartRateSamples = false
    
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Header
                HStack {
                    Image(systemName: "heart.fill")
	                    .foregroundColor(Theme.Colors.error)
                    Text("Health Metrics")
                        .font(Theme.Typography.headline)
                
                Spacer()
                
                if let syncedAt = healthData.syncedAt as Date? {
                    Text("sync \(syncedAt.formatted(.relative(presentation: .named)))")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            
            if !healthData.hasHealthData {
                noDataView
            } else {
                // Key Metrics Grid
                metricsGrid
                
                // Heart Rate Chart
                if !healthData.heartRateSamples.isEmpty {
                    heartRateSection
                }

                if let sleep = healthData.sleepSummary {
                    sleepSection(summary: sleep)
                }

                if hasDailyActivityMetrics {
                    dailyActivitySection
                }

                if hasCardioMetrics {
                    cardioFitnessSection
                }

                // Additional Metrics
                if hasAdditionalMetrics {
                    additionalMetricsSection
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
    
    // MARK: - No Data View
    
    private var noDataView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "heart.slash")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.textTertiary)
            
            Text("health data 0")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)
            
            Text("samples 0")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Theme.Spacing.xl)
    }
    
    // MARK: - Metrics Grid
    
    private var metricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: Theme.Spacing.md) {
            // Heart Rate
            if let avgHR = healthData.avgHeartRate {
                metricCard(
                    title: "Avg Heart Rate",
                    value: "\(Int(avgHR))",
                    unit: "bpm",
                    icon: "heart.fill",
                    color: .red
                )
            }
            
            // Calories
            if let calories = healthData.totalCalories ?? healthData.activeCalories {
                metricCard(
                    title: "Calories",
                    value: "\(Int(calories))",
                    unit: "kcal",
                    icon: "flame.fill",
                    color: .orange
                )
            }
            
            // Max Heart Rate
            if let maxHR = healthData.maxHeartRate {
                metricCard(
                    title: "Max Heart Rate",
                    value: "\(Int(maxHR))",
                    unit: "bpm",
                    icon: "heart.circle.fill",
                    color: .pink
                )
            }
            
            // HRV
            if let avgHRV = healthData.avgHRV {
                metricCard(
                    title: "Avg HRV",
                    value: "\(Int(avgHRV))",
                    unit: "ms",
                    icon: "waveform.path.ecg",
                    color: .purple
                )
            }
            
            // Blood Oxygen
            if let avgSpO2 = healthData.avgBloodOxygen {
                metricCard(
                    title: "Blood Oxygen",
                    value: "\(Int(avgSpO2))",
                    unit: "%",
                    icon: "lungs.fill",
                    color: .blue
                )
            }
            
            // Respiratory Rate
            if let avgResp = healthData.avgRespiratoryRate {
                metricCard(
                    title: "Resp Rate",
                    value: String(format: "%.1f", avgResp),
                    unit: "br/min",
                    icon: "wind",
                    color: .cyan
                )
            }
            
            // Distance (converted to miles)
            if let distance = healthData.distance, distance > 0 {
                metricCard(
                    title: "Distance",
                    value: String(format: "%.2f", distance / 1609.34),
                    unit: "mi",
                    icon: "figure.walk",
                    color: .green
                )
            }
            
            // Steps
            if let steps = healthData.stepCount, steps > 0 {
                metricCard(
                    title: "Steps",
                    value: "\(steps)",
                    unit: "",
                    icon: "shoeprints.fill",
                    color: .teal
                )
            }
        }
    }
    
    private func metricCard(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.Typography.number)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.Colors.surface.opacity(0.6))
        .cornerRadius(Theme.CornerRadius.medium)
    }
    
    // MARK: - Heart Rate Section
    
    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Zones")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)
            HeartRateZoneStrip(samples: healthData.heartRateSamples)
            WorkoutHRChart(samples: healthData.heartRateSamples)
        }
    }
    
    // MARK: - Additional Metrics
    
    private var hasAdditionalMetrics: Bool {
        healthData.appleWorkoutType != nil ||
        healthData.bodyMass != nil ||
        healthData.restingHeartRate != nil ||
        healthData.avgPower != nil ||
        healthData.bodyFatPercentage != nil
    }

    private var hasDailyActivityMetrics: Bool {
        healthData.dailyActiveEnergy != nil ||
        healthData.dailyBasalEnergy != nil ||
        healthData.dailySteps != nil ||
        healthData.dailyExerciseMinutes != nil ||
        healthData.dailyMoveMinutes != nil ||
        healthData.dailyStandMinutes != nil
    }

    private var hasCardioMetrics: Bool {
        healthData.vo2Max != nil ||
        healthData.heartRateRecovery != nil ||
        healthData.walkingHeartRateAverage != nil
    }
    
    private var additionalMetricsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Other Metrics")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)
            
            VStack(spacing: Theme.Spacing.sm) {
                if let workoutType = healthData.appleWorkoutType {
                    additionalMetricRow(
                        label: "Apple Workout",
                        value: workoutType,
                        icon: "figure.mixed.cardio"
                    )
                }
                
                if let duration = healthData.appleWorkoutDuration {
                    additionalMetricRow(
                        label: "Duration",
                        value: formatDuration(duration),
                        icon: "clock"
                    )
                }
                
                if let restingHR = healthData.restingHeartRate {
                    additionalMetricRow(
                        label: "Resting HR",
                        value: "\(Int(restingHR)) bpm",
                        icon: "heart"
                    )
                }
                
                if let power = healthData.avgPower {
                    additionalMetricRow(
                        label: "Avg Power",
                        value: "\(Int(power)) W",
                        icon: "bolt.fill"
                    )
                }
                
                if let bodyMass = healthData.bodyMass {
                    additionalMetricRow(
                        label: "Body Mass",
                        value: String(format: "%.1f lbs", bodyMass * 2.20462),
                        icon: "scalemass"
                    )
                }
                
                if let bodyFat = healthData.bodyFatPercentage {
                    additionalMetricRow(
                        label: "Body Fat",
                        value: String(format: "%.1f%%", bodyFat * 100),
                        icon: "percent"
                    )
                }
            }
        }
    }

    private func sleepSection(summary: SleepSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Sleep (Prev)")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f", summary.totalHours))
                        .font(Theme.Typography.number)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("h asleep")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDuration(summary.inBed))
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("in bed")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            SleepStageStrip(summary: summary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var dailyActivitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Daily Activity")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                if let energy = healthData.dailyActiveEnergy {
                    metricCard(title: "Active Energy", value: "\(Int(energy))", unit: "kcal", icon: "flame.fill", color: .orange)
                }
                if let basal = healthData.dailyBasalEnergy {
                    metricCard(title: "Resting Energy", value: "\(Int(basal))", unit: "kcal", icon: "leaf.fill", color: .blue)
                }
                if let steps = healthData.dailySteps {
                    metricCard(title: "Steps", value: "\(steps)", unit: "", icon: "shoeprints.fill", color: .teal)
                }
                if let exercise = healthData.dailyExerciseMinutes {
                    metricCard(title: "Exercise", value: "\(Int(exercise))", unit: "min", icon: "figure.run", color: .green)
                }
                if let move = healthData.dailyMoveMinutes {
                    metricCard(title: "Move", value: "\(Int(move))", unit: "min", icon: "figure.walk", color: .blue)
                }
                if let stand = healthData.dailyStandMinutes {
                    metricCard(title: "Stand", value: "\(Int(stand))", unit: "min", icon: "figure.stand", color: .purple)
                }
            }
        }
    }

    private var cardioFitnessSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Cardio Fitness")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)

            VStack(spacing: Theme.Spacing.sm) {
                if let vo2 = healthData.vo2Max {
                    additionalMetricRow(label: "VO2 Max", value: String(format: "%.1f", vo2), icon: "wind")
                }
                if let recovery = healthData.heartRateRecovery {
                    additionalMetricRow(label: "HR Recovery", value: "\(Int(recovery)) bpm", icon: "arrow.down.heart")
                }
                if let walking = healthData.walkingHeartRateAverage {
                    additionalMetricRow(label: "Walking HR Avg", value: "\(Int(walking)) bpm", icon: "figure.walk")
                }
            }
        }
    }
    
    private func additionalMetricRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(Theme.Colors.textTertiary)
            
            Text(label)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Compact Health Summary View

/// A compact view showing key health metrics, suitable for list items
struct HealthDataSummaryView: View {
    let healthData: WorkoutHealthData
    
    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            if let avgHR = healthData.avgHeartRate {
                compactMetric(
                    icon: "heart.fill",
                    value: "\(Int(avgHR))",
                    unit: "bpm",
                    color: .red
                )
            }
            
            if let calories = healthData.totalCalories ?? healthData.activeCalories {
                compactMetric(
                    icon: "flame.fill",
                    value: "\(Int(calories))",
                    unit: "kcal",
                    color: .orange
                )
            }
            
            if let avgHRV = healthData.avgHRV {
                compactMetric(
                    icon: "waveform.path.ecg",
                    value: "\(Int(avgHRV))",
                    unit: "ms",
                    color: .purple
                )
            }
        }
    }
    
    private func compactMetric(icon: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.Colors.textPrimary)
            
            Text(unit)
                .font(.system(size: 10))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }
}

// MARK: - Sync Button View

/// A button to trigger health data sync for a workout
struct HealthSyncButton: View {
    @ObservedObject var healthManager: HealthKitManager
    let workout: Workout
    let onSync: ((WorkoutHealthData) -> Void)?
    
    @State private var isSyncing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Button(action: syncHealthData) {
            HStack(spacing: Theme.Spacing.sm) {
                if isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "heart.text.square")
                }
                
                Text(isSyncing ? "syncing" : "sync")
                    .font(Theme.Typography.subheadline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                LinearGradient(
                    colors: [.red, .pink],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(Theme.CornerRadius.medium)
        }
        .disabled(isSyncing || !healthManager.isHealthKitAvailable())
        .opacity(isSyncing ? 0.7 : 1)
        .alert("Sync Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func syncHealthData() {
        Task {
            isSyncing = true
            
            do {
                // Request authorization if needed
                if healthManager.authorizationStatus != .authorized {
                    try await healthManager.requestAuthorization()
                }
                
                let healthData = try await healthManager.syncHealthDataForWorkout(workout)
                onSync?(healthData)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            
            isSyncing = false
        }
    }
}

// MARK: - Heart Rate Zones

struct HeartRateZoneStrip: View {
    let samples: [HeartRateSample]

    private var zones: [HeartRateZone] {
        HeartRateZone.calculate(from: samples)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 4) {
                ForEach(zones) { zone in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(zone.color.opacity(0.85))
                        .frame(width: max(8, geometry.size.width * zone.fraction))
                        .overlay(
                            Text(zone.label)
                                .font(Theme.Typography.caption)
                                .foregroundColor(.white)
                                .opacity(zone.fraction > 0.18 ? 1 : 0)
                        )
                }
            }
        }
        .frame(height: 18)
    }
}

struct HeartRateZone: Identifiable {
    let id = UUID()
    let label: String
    let color: Color
    let fraction: Double

    static func calculate(from samples: [HeartRateSample]) -> [HeartRateZone] {
        guard let maxSample = samples.map({ $0.value }).max(), maxSample > 0 else {
            return []
        }

        let maxHR = maxSample
        let thresholds: [(String, Double, Double, Color)] = [
            ("Z1", 0.5, 0.6, Theme.Colors.info),
            ("Z2", 0.6, 0.7, Theme.Colors.accentSecondary),
            ("Z3", 0.7, 0.8, Theme.Colors.warning),
            ("Z4", 0.8, 0.9, Theme.Colors.error),
            ("Z5", 0.9, 1.1, Theme.Colors.gold)
        ]

        let total = Double(samples.count)

        return thresholds.map { label, lower, upper, color in
            let count = samples.filter { sample in
                let ratio = sample.value / maxHR
                return ratio >= lower && ratio < upper
            }.count
            return HeartRateZone(label: label, color: color, fraction: total > 0 ? Double(count) / total : 0)
        }
    }
}

struct SleepStageStrip: View {
    let summary: SleepSummary

    private var stages: [(SleepStage, Double)] {
        let stages = summary.stageDurations
        let ordered: [SleepStage] = [.deep, .core, .rem, .awake]
        let total = max(ordered.reduce(0) { $0 + (stages[$1] ?? 0) }, 1)
        return ordered.map { stage in
            let duration = stages[stage] ?? 0
            return (stage, duration / total)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 4) {
                ForEach(stages, id: \.0) { stage, fraction in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(stageColor(stage).opacity(0.85))
                        .frame(width: max(6, geometry.size.width * fraction))
                        .overlay(
                            Text(stage.label)
                                .font(Theme.Typography.caption)
                                .foregroundColor(.white)
                                .opacity(fraction > 0.18 ? 1 : 0),
                            alignment: .center
                        )
                }
            }
        }
        .frame(height: 18)
    }

    private func stageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .deep: return Theme.Colors.accent
        case .core: return Theme.Colors.accentSecondary
        case .rem: return Theme.Colors.warning
        case .awake: return Theme.Colors.textSecondary
        case .inBed: return Theme.Colors.textTertiary
        case .unknown: return Theme.Colors.textTertiary
        }
    }
}
