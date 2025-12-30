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
                    .foregroundColor(.red)
                Text("Apple Health Data")
                    .font(Theme.Typography.headline)
                
                Spacer()
                
                if let syncedAt = healthData.syncedAt as Date? {
                    Text("Synced \(syncedAt.formatted(.relative(presentation: .named)))")
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
                
                // Additional Metrics
                if hasAdditionalMetrics {
                    additionalMetricsSection
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 2)
    }
    
    // MARK: - No Data View
    
    private var noDataView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "heart.slash")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.textTertiary)
            
            Text("No Health Data Found")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)
            
            Text("No Apple Health data was recorded during this workout window.")
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
            Text("Intensity Zones")
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
        healthData.avgPower != nil
    }
    
    private var additionalMetricsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Additional Data")
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
                
                Text(isSyncing ? "Syncing..." : "Sync Health Data")
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
