import SwiftUI

struct SleepSourceAttributionView: View {
    let summary: SleepSummary

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                if let sourceName = summary.primarySourceName, !sourceName.isEmpty {
                    Text("Source: \(sourceName)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                if summary.usedFallbackSource {
                    Text("Alternate source")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            if let statusText = summary.sourceStatusText {
                AppHelpButton(title: "Sleep source", message: statusText)
            }
        }
    }
}

/// Displays health data synced from Apple Health for a workout
struct HealthDataView: View {
    let healthData: WorkoutHealthData
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Reading: Identifiable {
        let label: String
        let value: String
        var tint: Color = Theme.Colors.textTertiary
        var id: String { label }
    }

    /// The four numbers that describe the session itself.
    private var headlineStats: [(value: String, label: String)] {
        var stats: [(String, String)] = []
        if let avgHR = healthData.avgHeartRate { stats.append(("\(Int(avgHR))", "avg bpm")) }
        if let maxHR = healthData.maxHeartRate { stats.append(("\(Int(maxHR))", "max bpm")) }
        if let calories = healthData.totalCalories ?? healthData.activeCalories {
            stats.append((Int(calories).formatted(), "cal"))
        }
        if let avgHRV = healthData.avgHRV { stats.append(("\(Int(avgHRV))", "ms HRV")) }
        return stats
    }

    private var sessionReadings: [Reading] {
        var readings: [Reading] = []
        if let avgSpO2 = healthData.avgBloodOxygen {
            readings.append(Reading(label: "Blood oxygen", value: "\(Int(avgSpO2))%", tint: HealthMetric.bloodOxygen.chartColor))
        }
        if let avgResp = healthData.avgRespiratoryRate {
            readings.append(Reading(
                label: "Respiratory rate",
                value: String(format: "%.1f br/min", avgResp),
                tint: HealthMetric.respiratoryRate.chartColor
            ))
        }
        if let distance = healthData.distance, distance > 0 {
            readings.append(Reading(
                label: "Distance",
                value: String(format: "%.2f mi", distance / 1609.34),
                tint: HealthMetric.distanceWalkingRunning.chartColor
            ))
        }
        if let steps = healthData.stepCount, steps > 0 {
            readings.append(Reading(label: "Steps", value: steps.formatted(), tint: HealthMetric.steps.chartColor))
        }
        if let power = healthData.avgPower {
            readings.append(Reading(label: "Avg power", value: "\(Int(power)) W"))
        }
        if let workoutType = healthData.appleWorkoutType {
            readings.append(Reading(label: "Apple workout", value: workoutType))
        }
        if let duration = healthData.appleWorkoutDuration {
            readings.append(Reading(label: "Apple workout length", value: formatDuration(duration)))
        }
        return readings
    }

    private var dayReadings: [Reading] {
        var readings: [Reading] = []
        if let restingHR = healthData.restingHeartRate {
            readings.append(Reading(label: "Resting heart rate", value: "\(Int(restingHR)) bpm", tint: HealthMetric.restingHeartRate.chartColor))
        }
        if let energy = healthData.dailyActiveEnergy {
            readings.append(Reading(label: "Active energy", value: "\(Int(energy).formatted()) cal", tint: HealthMetric.activeEnergy.chartColor))
        }
        if let basal = healthData.dailyBasalEnergy {
            readings.append(Reading(label: "Resting energy", value: "\(Int(basal).formatted()) cal", tint: HealthMetric.basalEnergy.chartColor))
        }
        if let steps = healthData.dailySteps {
            readings.append(Reading(label: "Steps", value: steps.formatted(), tint: HealthMetric.steps.chartColor))
        }
        if let exercise = healthData.dailyExerciseMinutes {
            readings.append(Reading(label: "Exercise", value: "\(Int(exercise)) min", tint: HealthMetric.exerciseMinutes.chartColor))
        }
        if let move = healthData.dailyMoveMinutes {
            readings.append(Reading(label: "Move", value: "\(Int(move)) min", tint: HealthMetric.moveMinutes.chartColor))
        }
        if let stand = healthData.dailyStandMinutes {
            readings.append(Reading(label: "Stand", value: "\(Int(stand)) min", tint: HealthMetric.standMinutes.chartColor))
        }
        if let vo2 = healthData.vo2Max {
            readings.append(Reading(label: "VO2 max", value: String(format: "%.1f", vo2), tint: HealthMetric.vo2Max.chartColor))
        }
        if let recovery = healthData.heartRateRecovery {
            readings.append(Reading(label: "Heart rate recovery", value: "\(Int(recovery)) bpm", tint: HealthMetric.heartRateRecovery.chartColor))
        }
        if let walking = healthData.walkingHeartRateAverage {
            readings.append(Reading(label: "Walking heart rate", value: "\(Int(walking)) bpm", tint: HealthMetric.walkingHeartRateAverage.chartColor))
        }
        if let bodyMass = healthData.bodyMass {
            readings.append(Reading(label: "Body weight", value: String(format: "%.1f lb", bodyMass * 2.20462), tint: HealthMetric.bodyMass.chartColor))
        }
        if let bodyFat = healthData.bodyFatPercentage {
            readings.append(Reading(label: "Body fat", value: String(format: "%.1f%%", bodyFat * 100), tint: HealthMetric.bodyFatPercentage.chartColor))
        }
        return readings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Synced \(healthData.syncedAt.formatted(.relative(presentation: .named)))")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            if !healthData.hasHealthData {
                noDataView
            } else {
                if !headlineStats.isEmpty {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
                        : AnyLayout(StatColumns())
                    layout {
                        ForEach(headlineStats, id: \.label) { stat in
                            DisplayStat(value: stat.value, label: stat.label, valueFont: Theme.Typography.number)
                        }
                    }
                }

                if !healthData.heartRateSamples.isEmpty {
                    heartRateSection
                }

                if !sessionReadings.isEmpty {
                    readingList(title: "During the workout", readings: sessionReadings)
                }

                if let sleep = healthData.sleepSummary {
                    sleepSection(summary: sleep)
                }

                if !dayReadings.isEmpty {
                    readingList(title: "That day", readings: dayReadings)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }

    // MARK: - No Data View

    private var noDataView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("No health data for this workout")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Sync Apple Health to load samples.")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Heart Rate Section

    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Relative intensity")
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                AppHelpButton(
                    title: "Relative intensity",
                    message: "Groups readings by percentage of the highest heart rate recorded during this workout. "
                        + "The bar shows the share of readings in each band."
                )
            }
            HeartRateZoneStrip(samples: healthData.heartRateSamples)
            WorkoutHRChart(samples: healthData.heartRateSamples)
        }
    }

    // MARK: - Readings

    private func readingList(title: String, readings: [Reading]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.bottom, Theme.Spacing.xs)

            ForEach(readings) { reading in
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
                layout {
                    HStack(spacing: Theme.Spacing.sm) {
                        TintMark(tint: reading.tint)
                        Text(reading.label)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.sm) }
                    Text(reading.value)
                        .font(Theme.Typography.callout)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .ledgerRow(verticalPadding: Theme.Spacing.sm)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func sleepSection(summary: SleepSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Sleep the night before")
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", summary.totalHours))
                    .font(Theme.Typography.number)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("hours asleep, \(formatDuration(summary.inBed)) in bed")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)

            SleepStageStrip(summary: summary)

            SleepSourceAttributionView(summary: summary)
        }
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.lg) {
                summaryMetrics
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                summaryMetrics
            }
        }
    }

    @ViewBuilder
    private var summaryMetrics: some View {
            if let avgHR = healthData.avgHeartRate {
                compactMetric(
                    icon: "heart.fill",
                    value: "\(Int(avgHR))",
                    unit: "bpm avg",
                    color: HealthMetric.restingHeartRate.accentColor
                )
            }

            if let calories = healthData.totalCalories ?? healthData.activeCalories {
                compactMetric(
                    icon: "flame.fill",
                    value: "\(Int(calories))",
                    unit: "cal",
                    color: HealthMetric.activeEnergy.accentColor
                )
            }

            if let avgHRV = healthData.avgHRV {
                compactMetric(
                    icon: "waveform.path.ecg",
                    value: "\(Int(avgHRV))",
                    unit: "ms HRV",
                    color: HealthMetric.heartRateVariability.accentColor
                )
            }
    }

    private func compactMetric(icon: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(color)
                .frame(width: 3, height: 11)
                .accessibilityHidden(true)

            Text(value)
                .font(Theme.Typography.captionStrong)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(unit)
                .font(Theme.Typography.caption2)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Heart Rate Zones

struct HeartRateZoneStrip: View {
    private let zones: [HeartRateZone]

    init(samples: [HeartRateSample]) {
        zones = HeartRateZone.calculate(from: samples)
    }

    var body: some View {
        let filled = zones.filter { $0.fraction > 0 }
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            GeometryReader { geometry in
                let spacing: CGFloat = 2
                let available = max(geometry.size.width - spacing * CGFloat(max(filled.count - 1, 0)), 0)
                HStack(spacing: spacing) {
                    ForEach(filled) { zone in
                        Rectangle()
                            .fill(zone.color)
                            .frame(width: max(available * zone.fraction, 2))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .frame(height: 14)

            HStack(spacing: Theme.Spacing.md) {
                ForEach(zones) { zone in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(zone.color)
                            .frame(width: 3, height: 10)
                        Text("\(zone.label) \(Int((zone.fraction * 100).rounded()))%")
                            .font(Theme.Typography.caption)
                            .monospacedDigit()
                            .foregroundStyle(zone.fraction > 0 ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Relative workout intensity")
        .accessibilityValue(
            zones
                .filter { $0.fraction > 0 }
                .map { "\($0.label) \(Int(($0.fraction * 100).rounded())) percent" }
                .joined(separator: ", ")
        )
    }
}

struct HeartRateZone: Identifiable {
    let label: String
    let color: Color
    let fraction: Double

    var id: String { label }

    static func calculate(from samples: [HeartRateSample]) -> [HeartRateZone] {
        guard let maxSample = samples.map({ $0.value }).max(), maxSample > 0 else {
            return []
        }

        let maxHR = maxSample
        // Steps of the heart hue: harder bands are darker.
        let heart = HealthMetric.restingHeartRate.chartColor
        // swiftlint:disable:next large_tuple
        let thresholds: [(String, Double, Double, Color)] = [
            ("Z1", 0.5, 0.6, heart.opacity(0.22)),
            ("Z2", 0.6, 0.7, heart.opacity(0.4)),
            ("Z3", 0.7, 0.8, heart.opacity(0.6)),
            ("Z4", 0.8, 0.9, heart.opacity(0.8)),
            ("Z5", 0.9, 1.1, heart)
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
        return ordered.compactMap { stage in
            let duration = stages[stage] ?? 0
            return duration > 0 ? (stage, duration / total) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            GeometryReader { geometry in
                let spacing: CGFloat = 2
                let available = max(geometry.size.width - spacing * CGFloat(max(stages.count - 1, 0)), 0)
                HStack(spacing: spacing) {
                    ForEach(stages, id: \.0) { stage, fraction in
                        Rectangle()
                            .fill(stage.tint)
                            .frame(width: max(available * fraction, 2))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .frame(height: 14)

            HStack(spacing: Theme.Spacing.md) {
                ForEach(stages, id: \.0) { stage, fraction in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(stage.tint)
                            .frame(width: 3, height: 10)
                        Text("\(stage.label) \(Int((fraction * 100).rounded()))%")
                            .font(Theme.Typography.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages")
        .accessibilityValue(
            stages.map { "\($0.0.label) \(Int(($0.1 * 100).rounded())) percent" }.joined(separator: ", ")
        )
    }
}
