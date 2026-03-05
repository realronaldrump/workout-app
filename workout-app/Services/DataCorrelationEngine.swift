import Combine
import Foundation
import SwiftUI

// MARK: - Data Correlation Engine
// Correlates workout performance data with Apple Health biometrics.
// All insights are derived purely from the user's data — no subjective advice.

@MainActor
final class DataCorrelationEngine: ObservableObject {

    @Published var correlations: [PerformanceCorrelation] = []
    @Published var recoverySignals: [RecoverySignal] = []
    @Published var frequencyInsights: [FrequencyInsight] = []
    @Published var isAnalyzing = false

    /// Run full analysis. Call when workout or health data changes.
    func analyze(
        workouts: [Workout],
        healthStore: [UUID: WorkoutHealthData],
        dailyHealth: [Date: DailyHealthData],
        muscleMappings: [String: [MuscleTag]]
    ) async {
        guard !workouts.isEmpty else { return }
        isAnalyzing = true

        let result = await Task(priority: .userInitiated) {
            let correlations = Self.computeCorrelations(
                workouts: workouts,
                healthStore: healthStore,
                dailyHealth: dailyHealth
            )
            let recoverySignals = Self.computeRecoverySignals(dailyHealth: dailyHealth)
            let frequency = Self.analyzeFrequency(workouts: workouts, mappings: muscleMappings)

            return (correlations, recoverySignals, frequency)
        }.value

        correlations = result.0
        recoverySignals = result.1
        frequencyInsights = result.2
        isAnalyzing = false
    }

    // MARK: - Health ↔ Performance Correlations

    private static func computeCorrelations(
        workouts: [Workout],
        healthStore _: [UUID: WorkoutHealthData],
        dailyHealth: [Date: DailyHealthData]
    ) -> [PerformanceCorrelation] {
        var results: [PerformanceCorrelation] = []
        let calendar = Calendar.current

        var dayMap: [Date: DayPerformance] = [:]
        for workout in workouts {
            let dayKey = calendar.startOfDay(for: workout.date)
            var dp = dayMap[dayKey] ?? DayPerformance(date: dayKey)
            dp.totalVolume += workout.totalVolume
            dp.maxWeight = max(dp.maxWeight, workout.exercises.map(\.maxWeight).max() ?? 0)
            dp.sessionCount += 1
            dayMap[dayKey] = dp
        }

        // Correlate sleep → next-day performance
        let sleepVolumeCorrelation = correlateSleepWithPerformance(dayMap: dayMap, dailyHealth: dailyHealth, calendar: calendar)
        if let sleepCorrelation = sleepVolumeCorrelation { results.append(sleepCorrelation) }

        // Correlate HRV → performance
        let hrvCorrelation = correlateMetricWithPerformance(
            dayMap: dayMap,
            dailyHealth: dailyHealth,
            calendar: calendar,
            config: MetricCorrelationConfig(
                metric: .heartRateVariability,
                metricLabel: "HRV",
                extractMetric: { $0.heartRateVariability }
            )
        )
        if let hrvResult = hrvCorrelation { results.append(hrvResult) }

        // Correlate resting heart rate → performance
        let rhrCorrelation = correlateMetricWithPerformance(
            dayMap: dayMap,
            dailyHealth: dailyHealth,
            calendar: calendar,
            config: MetricCorrelationConfig(
                metric: .restingHeartRate,
                metricLabel: "Resting HR",
                extractMetric: { $0.restingHeartRate },
                invertedRelationship: true
            )
        )
        if let restingHrResult = rhrCorrelation { results.append(restingHrResult) }

        // Correlate active calories → workout volume
        let calCorrelation = correlateMetricWithPerformance(
            dayMap: dayMap,
            dailyHealth: dailyHealth,
            calendar: calendar,
            config: MetricCorrelationConfig(
                metric: .activeEnergy,
                metricLabel: "Active Calories",
                extractMetric: { $0.activeEnergy }
            )
        )
        if let activeCalorieResult = calCorrelation { results.append(activeCalorieResult) }

        // Correlate steps → workout performance
        let stepCorrelation = correlateMetricWithPerformance(
            dayMap: dayMap,
            dailyHealth: dailyHealth,
            calendar: calendar,
            config: MetricCorrelationConfig(
                metric: .steps,
                metricLabel: "Step Count",
                extractMetric: { $0.steps }
            )
        )
        if let stepResult = stepCorrelation { results.append(stepResult) }

        return results.sorted { abs($0.coefficient) > abs($1.coefficient) }
    }

    private static func correlateSleepWithPerformance(
        dayMap: [Date: DayPerformance],
        dailyHealth: [Date: DailyHealthData],
        calendar: Calendar
    ) -> PerformanceCorrelation? {
        // Look at sleep the night before a workout day
        var pairs: [(sleep: Double, volume: Double)] = []

        for (day, perf) in dayMap {
            // Previous day's sleep
            guard let prevDay = calendar.date(byAdding: .day, value: -1, to: day) else { continue }
            let prevDayKey = calendar.startOfDay(for: prevDay)
            guard let healthDay = dailyHealth[prevDayKey],
                  let sleepHours = healthDay.sleepSummary?.totalHours,
                  sleepHours > 0 else { continue }
            pairs.append((sleep: sleepHours, volume: perf.totalVolume))
        }

        guard pairs.count >= 5 else { return nil }

        let coefficient = pearsonCorrelation(
            x: pairs.map(\.sleep),
            y: pairs.map(\.volume)
        )

        guard abs(coefficient) > 0.1 else { return nil }

        // Compute above/below average split
        let avgSleep = pairs.map(\.sleep).reduce(0, +) / Double(pairs.count)
        let aboveAvg = pairs.filter { $0.sleep >= avgSleep }
        let belowAvg = pairs.filter { $0.sleep < avgSleep }
        let avgVolumeAbove = aboveAvg.isEmpty ? 0 : aboveAvg.map(\.volume).reduce(0, +) / Double(aboveAvg.count)
        let avgVolumeBelow = belowAvg.isEmpty ? 0 : belowAvg.map(\.volume).reduce(0, +) / Double(belowAvg.count)

        return PerformanceCorrelation(
            healthMetric: .sleep,
            healthMetricLabel: "Sleep (night before)",
            performanceMetric: "Volume",
            coefficient: coefficient,
            dataPoints: pairs.count,
            split: CorrelationSplit(
                aboveAverageLabel: "≥\(String(format: "%.1f", avgSleep))h sleep",
                belowAverageLabel: "<\(String(format: "%.1f", avgSleep))h sleep",
                aboveAveragePerformance: avgVolumeAbove,
                belowAveragePerformance: avgVolumeBelow
            )
        )
    }

    private struct DayPerformance {
        let date: Date
        var totalVolume: Double = 0
        var maxWeight: Double = 0
        var sessionCount: Int = 0
    }

    private struct MetricCorrelationConfig {
        let metric: HealthMetric
        let metricLabel: String
        let extractMetric: (DailyHealthData) -> Double?
        let invertedRelationship: Bool

        init(
            metric: HealthMetric,
            metricLabel: String,
            extractMetric: @escaping (DailyHealthData) -> Double?,
            invertedRelationship: Bool = false
        ) {
            self.metric = metric
            self.metricLabel = metricLabel
            self.extractMetric = extractMetric
            self.invertedRelationship = invertedRelationship
        }
    }

    private static func correlateMetricWithPerformance(
        dayMap: [Date: DayPerformance],
        dailyHealth: [Date: DailyHealthData],
        calendar: Calendar,
        config: MetricCorrelationConfig
    ) -> PerformanceCorrelation? {
        var pairs: [(metric: Double, performance: Double)] = []

        for (day, perf) in dayMap {
            let dayKey = calendar.startOfDay(for: day)
            guard let healthDay = dailyHealth[dayKey],
                  let metricVal = config.extractMetric(healthDay) else { continue }
            pairs.append((metric: metricVal, performance: perf.totalVolume))
        }

        guard pairs.count >= 5 else { return nil }

        let rawCoefficient = pearsonCorrelation(
            x: pairs.map(\.metric),
            y: pairs.map(\.performance)
        )

        guard abs(rawCoefficient) > 0.1 else { return nil }
        let coefficient = config.invertedRelationship ? -rawCoefficient : rawCoefficient

        let avgMetric = pairs.map(\.metric).reduce(0, +) / Double(pairs.count)
        let above = pairs.filter { $0.metric >= avgMetric }
        let below = pairs.filter { $0.metric < avgMetric }
        let avgPerfAbove = above.isEmpty ? 0 : above.map(\.performance).reduce(0, +) / Double(above.count)
        let avgPerfBelow = below.isEmpty ? 0 : below.map(\.performance).reduce(0, +) / Double(below.count)

        let displayMetric = config.metric.displayValue(from: avgMetric)
        let formattedAvg = config.metric.formatDisplay(displayMetric)

        return PerformanceCorrelation(
            healthMetric: config.metric,
            healthMetricLabel: config.metricLabel,
            performanceMetric: "Volume",
            coefficient: coefficient,
            dataPoints: pairs.count,
            split: CorrelationSplit(
                aboveAverageLabel: "≥\(formattedAvg) \(config.metric.displayUnit)",
                belowAverageLabel: "<\(formattedAvg) \(config.metric.displayUnit)",
                aboveAveragePerformance: avgPerfAbove,
                belowAveragePerformance: avgPerfBelow
            )
        )
    }

    // MARK: - Recovery Signals

    /// Computes transparent recovery signals by comparing the recent 7-day
    /// average to the prior 30-day baseline for each metric.
    private static func computeRecoverySignals(
        dailyHealth: [Date: DailyHealthData]
    ) -> [RecoverySignal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Gather the last 7 days of health data
        var recentDays: [DailyHealthData] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayKey = calendar.startOfDay(for: day)
            if let data = dailyHealth[dayKey] {
                recentDays.append(data)
            }
        }
        guard recentDays.count >= 2 else { return [] }

        // Gather baseline (past 30 days for comparison)
        var baselineDays: [DailyHealthData] = []
        for offset in 7..<37 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayKey = calendar.startOfDay(for: day)
            if let data = dailyHealth[dayKey] {
                baselineDays.append(data)
            }
        }

        var signals: [RecoverySignal] = []

        // HRV
        let recentHRV = recentDays.compactMap(\.heartRateVariability)
        let baseHRV = baselineDays.compactMap(\.heartRateVariability)
        if let avgRecent = average(recentHRV), let avgBase = average(baseHRV), avgBase > 0 {
            let percentChange = ((avgRecent - avgBase) / avgBase) * 100
            signals.append(RecoverySignal(
                metric: "HRV",
                icon: "waveform.path.ecg",
                currentValue: avgRecent,
                baselineValue: avgBase,
                unit: "ms",
                percentChange: percentChange
            ))
        }

        // Resting HR
        let recentRHR = recentDays.compactMap(\.restingHeartRate)
        let baseRHR = baselineDays.compactMap(\.restingHeartRate)
        if let avgRecent = average(recentRHR), let avgBase = average(baseRHR), avgBase > 0 {
            let percentChange = ((avgRecent - avgBase) / avgBase) * 100
            signals.append(RecoverySignal(
                metric: "Resting HR",
                icon: "heart",
                currentValue: avgRecent,
                baselineValue: avgBase,
                unit: "bpm",
                percentChange: percentChange
            ))
        }

        // Sleep duration
        let recentSleep = recentDays.compactMap { $0.sleepSummary?.totalHours }
        let baseSleep = baselineDays.compactMap { $0.sleepSummary?.totalHours }
        if let avgRecent = average(recentSleep), let avgBase = average(baseSleep), avgBase > 0 {
            let percentChange = ((avgRecent - avgBase) / avgBase) * 100
            signals.append(RecoverySignal(
                metric: "Sleep",
                icon: "moon.zzz.fill",
                currentValue: avgRecent,
                baselineValue: avgBase,
                unit: "hrs",
                percentChange: percentChange
            ))
        }

        return signals
    }

    // MARK: - Training Frequency Analysis

    private static func analyzeFrequency(
        workouts: [Workout],
        mappings: [String: [MuscleTag]]
    ) -> [FrequencyInsight] {
        let calendar = Calendar.current
        guard let twelveWeeksAgo = calendar.date(byAdding: .day, value: -84, to: Date()) else { return [] }

        let recentWorkouts = workouts.filter { $0.date >= twelveWeeksAgo }
        guard !recentWorkouts.isEmpty else { return [] }

        // Count weeks active per muscle group
        var muscleWeekSets: [String: Set<Int>] = [:]

        for workout in recentWorkouts {
            let weekNumber = calendar.component(.weekOfYear, from: workout.date)
            let yearWeek = calendar.component(.year, from: workout.date) * 100 + weekNumber

            for exercise in workout.exercises {
                let tags = mappings[exercise.name] ?? []
                for tag in tags {
                    let key = tag.displayName
                    muscleWeekSets[key, default: Set()].insert(yearWeek)
                }
            }
        }

        let totalWeeks = 12
        var insights: [FrequencyInsight] = []

        for (muscle, weeks) in muscleWeekSets {
            let weeksHit = weeks.count
            let frequencyPerWeek = Double(weeksHit) / Double(totalWeeks)

            insights.append(FrequencyInsight(
                muscleGroup: muscle,
                weeksHit: weeksHit,
                totalWeeks: totalWeeks,
                frequencyPerWeek: frequencyPerWeek
            ))
        }

        return insights.sorted { $0.frequencyPerWeek > $1.frequencyPerWeek }
    }

    // MARK: - Math Helpers

    private static func pearsonCorrelation(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count, x.count >= 3 else { return 0 }
        let sampleCount = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = x.reduce(0) { $0 + $1 * $1 }
        let sumY2 = y.reduce(0) { $0 + $1 * $1 }

        let numerator = sampleCount * sumXY - sumX * sumY
        let denominator = sqrt((sampleCount * sumX2 - sumX * sumX) * (sampleCount * sumY2 - sumY * sumY))

        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Models

struct PerformanceCorrelation: Identifiable {
    let id = UUID()
    let healthMetric: HealthMetric
    let healthMetricLabel: String
    let performanceMetric: String
    let coefficient: Double
    let dataPoints: Int
    let split: CorrelationSplit

    var tint: Color {
        Theme.Colors.accent
    }
}

struct CorrelationSplit {
    let aboveAverageLabel: String
    let belowAverageLabel: String
    let aboveAveragePerformance: Double
    let belowAveragePerformance: Double

    var percentDifference: Double {
        guard belowAveragePerformance > 0 else { return 0 }
        return ((aboveAveragePerformance - belowAveragePerformance) / belowAveragePerformance) * 100
    }
}

struct RecoverySignal: Identifiable {
    let id = UUID()
    let metric: String
    let icon: String
    let currentValue: Double
    let baselineValue: Double
    let unit: String
    /// Signed percent change from baseline.
    let percentChange: Double
}

struct FrequencyInsight: Identifiable {
    let id = UUID()
    let muscleGroup: String
    let weeksHit: Int
    let totalWeeks: Int
    let frequencyPerWeek: Double

    var coveragePercent: Double {
        guard totalWeeks > 0 else { return 0 }
        return (Double(weeksHit) / Double(totalWeeks)) * 100
    }
}
