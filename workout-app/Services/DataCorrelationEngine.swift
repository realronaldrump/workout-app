import Foundation
import Combine
import SwiftUI

// MARK: - Data Correlation Engine
// Correlates workout performance data with Apple Health biometrics.
// All insights are derived purely from the user's data — no subjective advice.

@MainActor
final class DataCorrelationEngine: ObservableObject {

    @Published var correlations: [PerformanceCorrelation] = []
    @Published var recoveryReadiness: RecoveryReadiness?
    @Published var plateauAlerts: [PlateauAlert] = []
    @Published var frequencyInsights: [FrequencyInsight] = []
    @Published var efficiencyTrends: [EfficiencyDataPoint] = []
    @Published var timeOfDayAnalysis: [TimeOfDayBucket] = []
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
            let readiness = Self.computeRecoveryReadiness(dailyHealth: dailyHealth)
            let plateaus = Self.detectPlateaus(workouts: workouts)
            let frequency = Self.analyzeFrequency(workouts: workouts, mappings: muscleMappings)
            let efficiency = Self.computeEfficiency(workouts: workouts)
            let timeOfDay = Self.analyzeTimeOfDay(workouts: workouts)

            return (correlations, readiness, plateaus, frequency, efficiency, timeOfDay)
        }.value

        correlations = result.0
        recoveryReadiness = result.1
        plateauAlerts = result.2
        frequencyInsights = result.3
        efficiencyTrends = result.4
        timeOfDayAnalysis = result.5
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
            dp.durationMinutes += Double(workout.estimatedDurationMinutes())
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
        var durationMinutes: Double = 0
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

    private struct ExercisePerformanceSnapshot {
        let date: Date
        let maxWeight: Double
        let e1rm: Double
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

    // MARK: - Recovery Readiness

    private static func computeRecoveryReadiness(
        dailyHealth: [Date: DailyHealthData]
    ) -> RecoveryReadiness? {
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
        guard recentDays.count >= 2 else { return nil }

        // Gather baseline (past 30 days for comparison)
        var baselineDays: [DailyHealthData] = []
        for offset in 7..<37 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayKey = calendar.startOfDay(for: day)
            if let data = dailyHealth[dayKey] {
                baselineDays.append(data)
            }
        }

        var signals: [ReadinessSignal] = []

        // HRV signal: higher than baseline = good
        let recentHRV = recentDays.compactMap(\.heartRateVariability)
        let baseHRV = baselineDays.compactMap(\.heartRateVariability)
        if let avgRecent = average(recentHRV), let avgBase = average(baseHRV), avgBase > 0 {
            let deviation = (avgRecent - avgBase) / avgBase
            signals.append(ReadinessSignal(
                metric: "HRV",
                icon: "waveform.path.ecg",
                currentValue: avgRecent,
                baselineValue: avgBase,
                unit: "ms",
                deviation: deviation,
                direction: deviation >= 0 ? .favorable : .unfavorable,
                weight: 0.35,
                valueIncreased: avgRecent >= avgBase
            ))
        }

        // Resting HR signal: lower than baseline = good
        let recentRHR = recentDays.compactMap(\.restingHeartRate)
        let baseRHR = baselineDays.compactMap(\.restingHeartRate)
        if let avgRecent = average(recentRHR), let avgBase = average(baseRHR), avgBase > 0 {
            let deviation = (avgBase - avgRecent) / avgBase // inverted: lower is better
            signals.append(ReadinessSignal(
                metric: "Resting HR",
                icon: "heart",
                currentValue: avgRecent,
                baselineValue: avgBase,
                unit: "bpm",
                deviation: deviation,
                direction: deviation >= 0 ? .favorable : .unfavorable,
                weight: 0.30,
                valueIncreased: avgRecent >= avgBase
            ))
        }

        // Sleep signal: more than baseline = good
        let recentSleep = recentDays.compactMap { $0.sleepSummary?.totalHours }
        let baseSleep = baselineDays.compactMap { $0.sleepSummary?.totalHours }
        if let avgRecent = average(recentSleep), let avgBase = average(baseSleep), avgBase > 0 {
            let deviation = (avgRecent - avgBase) / avgBase
            signals.append(ReadinessSignal(
                metric: "Sleep",
                icon: "moon.zzz.fill",
                currentValue: avgRecent,
                baselineValue: avgBase,
                unit: "hrs",
                deviation: deviation,
                direction: deviation >= 0 ? .favorable : .unfavorable,
                weight: 0.35,
                valueIncreased: avgRecent >= avgBase
            ))
        }

        guard !signals.isEmpty else { return nil }

        // Weighted composite score: 0.0 to 1.0
        let totalWeight = signals.map(\.weight).reduce(0, +)
        let weightedScore = signals.reduce(0.0) { sum, signal in
            // Clamp deviation to [-1, 1], map to [0, 1]
            let clamped = max(-1.0, min(1.0, signal.deviation))
            let normalized = (clamped + 1.0) / 2.0 // 0 = very bad, 1 = very good
            return sum + normalized * signal.weight
        }
        let score = totalWeight > 0 ? weightedScore / totalWeight : 0.5

        return RecoveryReadiness(
            score: score,
            signals: signals,
            dataPointCount: recentDays.count,
            baselineDataPointCount: baselineDays.count
        )
    }

    // MARK: - Plateau Detection

    private static func detectPlateaus(workouts: [Workout]) -> [PlateauAlert] {
        var alerts: [PlateauAlert] = []
        let calendar = Calendar.current
        guard let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date()) else { return [] }

        let allExercises = workouts.flatMap { $0.exercises }
        let exerciseGroups = Dictionary(grouping: allExercises) { $0.name }

        for name in exerciseGroups.keys {
            // Need at least 6 sessions of an exercise to detect plateau
            let history = workouts.compactMap { workout -> ExercisePerformanceSnapshot? in
                guard let ex = workout.exercises.first(where: { $0.name == name }) else { return nil }
                return ExercisePerformanceSnapshot(
                    date: workout.date,
                    maxWeight: ex.maxWeight,
                    e1rm: ex.oneRepMax
                )
            }.sorted { $0.date < $1.date }

            guard history.count >= 6 else { continue }

            // Check last 4 weeks for stagnation in estimated 1RM
            let recentHistory = history.filter { $0.date >= fourWeeksAgo }
            guard recentHistory.count >= 3 else { continue }

            let recent1RMs = recentHistory.map(\.e1rm)
            let older1RMs = history.filter { $0.date < fourWeeksAgo }.suffix(6).map(\.e1rm)

            guard !older1RMs.isEmpty else { continue }

            let recentAvg = recent1RMs.reduce(0, +) / Double(recent1RMs.count)
            let olderAvg = older1RMs.reduce(0, +) / Double(older1RMs.count)

            // Plateau = recent avg within 2% of older avg (no meaningful progress)
            let changePercent = olderAvg > 0 ? ((recentAvg - olderAvg) / olderAvg) * 100 : 0

            if abs(changePercent) < 2.0 && recentHistory.count >= 3 {
                // Confirm low variance (not just oscillating)
                let variance = standardDeviation(recent1RMs)
                let relativeVariance = recentAvg > 0 ? variance / recentAvg : 0

                if relativeVariance < 0.05 { // less than 5% std dev = plateau
                    alerts.append(PlateauAlert(
                        exerciseName: name,
                        currentE1RM: recentAvg,
                        weeksSinceProgress: weeksStagnant(history: history),
                        sessionCount: recentHistory.count,
                        changePercent: changePercent
                    ))
                }
            }
        }

        return alerts.sorted { $0.weeksSinceProgress > $1.weeksSinceProgress }
    }

    private static func weeksStagnant(history: [ExercisePerformanceSnapshot]) -> Int {
        guard history.count >= 2 else { return 0 }
        let calendar = Calendar.current

        // Walk backward from most recent, find when they last set a new peak
        var lastPeakDate = history.last?.date ?? Date()
        var runningMax = 0.0
        for entry in history where entry.e1rm > runningMax {
            runningMax = entry.e1rm
            lastPeakDate = entry.date
        }

        let weeks = calendar.dateComponents([.weekOfYear], from: lastPeakDate, to: Date()).weekOfYear ?? 0
        return max(0, weeks)
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

    // MARK: - Session Efficiency

    private static func computeEfficiency(workouts: [Workout]) -> [EfficiencyDataPoint] {
        let sorted = workouts.sorted { $0.date < $1.date }

        return sorted.compactMap { workout in
            let minutes = Double(workout.estimatedDurationMinutes())
            guard minutes > 0 else { return nil }

            let volumePerMinute = workout.totalVolume / minutes
            let setsPerMinute = Double(workout.totalSets) / minutes

            return EfficiencyDataPoint(
                date: workout.date,
                workoutName: workout.name,
                durationMinutes: minutes,
                totalVolume: workout.totalVolume,
                totalSets: workout.totalSets,
                volumePerMinute: volumePerMinute,
                setsPerMinute: setsPerMinute
            )
        }
    }

    // MARK: - Time of Day Analysis

    private static func analyzeTimeOfDay(workouts: [Workout]) -> [TimeOfDayBucket] {
        guard workouts.count >= 5 else { return [] }
        let calendar = Calendar.current

        struct BucketAccumulator {
            var sessions: Int = 0
            var totalVolume: Double = 0
            var totalDuration: Double = 0
        }

        // 2-hour windows for tighter precision
        let buckets: [(label: String, range: ClosedRange<Int>)] = [
            ("5–7 AM",    5...6),
            ("7–9 AM",    7...8),
            ("9–11 AM",   9...10),
            ("11 AM–1 PM", 11...12),
            ("1–3 PM",    13...14),
            ("3–5 PM",    15...16),
            ("5–7 PM",    17...18),
            ("7–9 PM",    19...20),
            ("9–11 PM",   21...22)
        ]

        var accumulators = buckets.map { _ in BucketAccumulator() }

        for workout in workouts {
            let hour = calendar.component(.hour, from: workout.date)
            if let idx = buckets.firstIndex(where: { $0.range.contains(hour) }) {
                accumulators[idx].sessions += 1
                accumulators[idx].totalVolume += workout.totalVolume
                accumulators[idx].totalDuration += Double(workout.estimatedDurationMinutes())
            }
        }

        // Global average volume for Bayesian shrinkage
        let totalSessions = accumulators.reduce(0) { $0 + $1.sessions }
        let totalVolume = accumulators.reduce(0.0) { $0 + $1.totalVolume }
        let globalAvgVolume = totalSessions > 0 ? totalVolume / Double(totalSessions) : 0

        // A bucket must have at least 3 sessions or 3 % of all workouts
        // (whichever is larger) to be considered reliable.
        let minSessions = max(3, Int(ceil(Double(workouts.count) * 0.03)))

        // Bayesian confidence weight — pulls low-sample buckets toward the
        // global mean so a handful of outlier sessions can't dominate.
        let k = 5.0

        return zip(buckets, accumulators).compactMap { bucket, acc in
            guard acc.sessions > 0 else { return nil }
            let avgVolume = acc.totalVolume / Double(acc.sessions)
            let avgDuration = acc.totalDuration / Double(acc.sessions)
            let n = Double(acc.sessions)
            let confidenceScore = (n * avgVolume + k * globalAvgVolume) / (n + k)
            return TimeOfDayBucket(
                label: bucket.label,
                hourRange: bucket.range,
                sessionCount: acc.sessions,
                avgVolume: avgVolume,
                avgDuration: avgDuration,
                confidenceScore: confidenceScore,
                meetsMinimum: acc.sessions >= minSessions
            )
        }
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

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return sqrt(variance)
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

    var strengthLabel: String {
        let abs = abs(coefficient)
        if abs >= 0.7 { return "Strong" }
        if abs >= 0.4 { return "Moderate" }
        if abs >= 0.2 { return "Weak" }
        return "Negligible"
    }

    var directionLabel: String {
        coefficient > 0 ? "positive" : "negative"
    }

    var tint: Color {
        let abs = abs(coefficient)
        if abs >= 0.7 { return Theme.Colors.success }
        if abs >= 0.4 { return Theme.Colors.accent }
        if abs >= 0.2 { return Theme.Colors.warning }
        return Theme.Colors.textTertiary
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

struct RecoveryReadiness: Identifiable {
    let id = UUID()
    let score: Double // 0.0 to 1.0
    let signals: [ReadinessSignal]
    let dataPointCount: Int
    let baselineDataPointCount: Int

    var label: String {
        if score >= 0.7 { return "Primed" }
        if score >= 0.5 { return "Baseline" }
        if score >= 0.3 { return "Fatigued" }
        return "Depleted"
    }

    var tint: Color {
        if score >= 0.7 { return Theme.Colors.success }
        if score >= 0.5 { return Theme.Colors.accent }
        if score >= 0.3 { return Theme.Colors.warning }
        return Theme.Colors.error
    }

    var scorePercent: Int {
        Int(round(score * 100))
    }
}

struct ReadinessSignal: Identifiable {
    let id = UUID()
    let metric: String
    let icon: String
    let currentValue: Double
    let baselineValue: Double
    let unit: String
    let deviation: Double
    let direction: SignalDirection
    let weight: Double
    /// Whether the raw value increased compared to baseline (independent of whether that's good or bad)
    let valueIncreased: Bool

    enum SignalDirection {
        case favorable
        case unfavorable
    }

    var deviationPercent: Double {
        abs(deviation) * 100
    }

    var tint: Color {
        direction == .favorable ? Theme.Colors.success : Theme.Colors.warning
    }
}

struct PlateauAlert: Identifiable {
    let id = UUID()
    let exerciseName: String
    let currentE1RM: Double
    let weeksSinceProgress: Int
    let sessionCount: Int
    let changePercent: Double
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

struct EfficiencyDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let workoutName: String
    let durationMinutes: Double
    let totalVolume: Double
    let totalSets: Int
    let volumePerMinute: Double
    let setsPerMinute: Double
}

struct TimeOfDayBucket: Identifiable {
    let id = UUID()
    let label: String
    let hourRange: ClosedRange<Int>
    let sessionCount: Int
    let avgVolume: Double
    let avgDuration: Double
    /// Bayesian-weighted score that penalises low-sample buckets by pulling
    /// them toward the global average volume.
    let confidenceScore: Double
    /// Whether this bucket meets the minimum session threshold to be
    /// considered a reliable "best" recommendation.
    let meetsMinimum: Bool
}
