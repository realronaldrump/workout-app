import Foundation

enum BodyCompositionMetricKind: String, CaseIterable, Identifiable {
    case weight
    case bodyFat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: return "Weight"
        case .bodyFat: return "Body Fat"
        }
    }

    var healthMetric: HealthMetric {
        switch self {
        case .weight: return .bodyMass
        case .bodyFat: return .bodyFatPercentage
        }
    }

    var unitLabel: String {
        switch self {
        case .weight: return "lb"
        case .bodyFat: return "%"
        }
    }
}

struct BodyRawSample: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    /// Display units (lb for weight, % for body fat).
    let value: Double

    init(id: UUID = UUID(), timestamp: Date, value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}

struct TimeSeriesPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }

    init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

struct LinearRegressionResult: Equatable {
    let slopePerDay: Double
    let intercept: Double
    let rSquared: Double?
    let residualStdDev: Double?
    let pointCount: Int
}

struct BodyLogbookDay: Identifiable {
    let dayStart: Date
    let representativeTimestamp: Date
    let representative: Double
    let samples: [BodyRawSample]
    let movingAverage7d: Double?
    let rollingAverage30d: Double?
    let weeklyRate: Double?
    let isNewLow: Bool
    let isNewHigh: Bool

    var id: Date { dayStart }
}

struct IntervalDelta: Identifiable {
    let id: String
    let label: String
    let delta: Double
    let baselineDate: Date?
}

struct ForecastPoint: Identifiable {
    let id: String
    let horizonDays: Int
    let date: Date
    let predicted: Double
    let sigma: Double?
}

struct TrendSummary {
    let slopePerDay: Double
    let intercept: Double
    let pacePerWeek: Double
    let rSquared: Double?
    let residualStdDev: Double?
    let windowStart: Date
    let windowEnd: Date
    let pointCount: Int
}

enum ReportGranularity: String, CaseIterable, Identifiable {
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }
}

struct ReportBucket: Identifiable {
    let keyDate: Date
    let label: String
    let average: Double
    let start: Double
    let end: Double
    let change: Double
    let min: Double
    let max: Double
    let count: Int

    var id: Date { keyDate }
}

enum BodyCompositionAnalytics {
    struct DailyRepresentative: Identifiable, Equatable {
        let dayStart: Date
        let timestamp: Date
        let value: Double
        let samples: [BodyRawSample]

        var id: Date { dayStart }
    }

    static func bufferedAnalysisRange(for displayRange: DateInterval, bufferDays: Int = 35) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -bufferDays, to: displayRange.start) ?? displayRange.start
        return DateInterval(start: start, end: displayRange.end)
    }

    static func dailyRepresentatives(from samples: [BodyRawSample], calendar: Calendar = .current) -> [DailyRepresentative] {
        guard !samples.isEmpty else { return [] }

        let grouped = Dictionary(grouping: samples) { sample in
            calendar.startOfDay(for: sample.timestamp)
        }

        let reps: [DailyRepresentative] = grouped.compactMap { dayStart, daySamples in
            let sorted = daySamples.sorted { $0.timestamp < $1.timestamp }
            guard let first = sorted.first else { return nil }
            return DailyRepresentative(
                dayStart: dayStart,
                timestamp: first.timestamp,
                value: first.value,
                samples: sorted
            )
        }

        return reps.sorted { $0.dayStart < $1.dayStart }
    }

    static func trailingAverages(
        representatives: [DailyRepresentative],
        windowDays: Int,
        calendar: Calendar = .current
    ) -> [Date: Double] {
        guard windowDays > 0 else { return [:] }
        guard !representatives.isEmpty else { return [:] }

        var result: [Date: Double] = [:]
        var startIndex = 0
        var runningSum = 0.0

        for index in representatives.indices {
            let currentDay = representatives[index].dayStart
            let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: currentDay) ?? currentDay

            while startIndex < index, representatives[startIndex].dayStart < windowStart {
                runningSum -= representatives[startIndex].value
                startIndex += 1
            }

            // Add the current point to the window sum.
            if index == startIndex {
                runningSum = representatives[index].value
            } else {
                runningSum += representatives[index].value
            }

            let count = (index - startIndex) + 1
            result[currentDay] = runningSum / Double(count)
        }

        return result
    }

    static func trailingRegression(
        representatives: [DailyRepresentative],
        windowDays: Int,
        calendar: Calendar = .current
    ) -> [Date: LinearRegressionResult] {
        guard windowDays > 0 else { return [:] }
        guard representatives.count >= 2 else { return [:] }

        var results: [Date: LinearRegressionResult] = [:]
        var startIndex = 0

        for index in representatives.indices {
            let endDay = representatives[index].dayStart
            let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: endDay) ?? endDay

            while startIndex < index, representatives[startIndex].dayStart < windowStart {
                startIndex += 1
            }

            let window = Array(representatives[startIndex...index])
            guard window.count >= 2 else { continue }

            let pairs: [(Double, Double)] = window.map { rep in
                let x = Double(daysBetween(windowStart, rep.dayStart, calendar: calendar))
                return (x, rep.value)
            }

            if let computed = linearRegression(pairs: pairs) {
                results[endDay] = computed
            }
        }

        return results
    }

    static func recordFlagsSinceAnchor(
        representatives: [DailyRepresentative]
    ) -> [Date: (isNewLow: Bool, isNewHigh: Bool)] {
        var result: [Date: (Bool, Bool)] = [:]
        var runningMin: Double?
        var runningMax: Double?
        var seenFirst = false

        for rep in representatives.sorted(by: { $0.dayStart < $1.dayStart }) {
            let value = rep.value
            let isLow: Bool
            let isHigh: Bool

            if !seenFirst {
                isLow = false
                isHigh = false
                runningMin = value
                runningMax = value
                seenFirst = true
            } else {
                isLow = (runningMin.map { value < $0 } ?? false)
                isHigh = (runningMax.map { value > $0 } ?? false)
                runningMin = min(runningMin ?? value, value)
                runningMax = max(runningMax ?? value, value)
            }

            result[rep.dayStart] = (isLow, isHigh)
        }

        return result
    }

    static func intervalDeltas(
        points: [TimeSeriesPoint],
        displayRangeStart: Date,
        calendar: Calendar = .current
    ) -> [IntervalDelta] {
        guard let latest = points.max(by: { $0.date < $1.date }) else { return [] }
        let sorted = points.sorted { $0.date < $1.date }

        func baseline(onOrBefore target: Date) -> TimeSeriesPoint? {
            sorted.last(where: { $0.date <= target })
        }

        var deltas: [IntervalDelta] = []

        // Since range start
        if let firstInRange = sorted.first(where: { $0.date >= calendar.startOfDay(for: displayRangeStart) }) {
            deltas.append(
                IntervalDelta(
                    id: "sinceStart",
                    label: "Since start",
                    delta: latest.value - firstInRange.value,
                    baselineDate: firstInRange.date
                )
            )
        }

        let rangeDays = max(1, daysBetween(displayRangeStart, latest.date, calendar: calendar))
        let intervalDays: [Int]
        if rangeDays <= 45 {
            intervalDays = [7, 30]
        } else if rangeDays <= 180 {
            intervalDays = [30, 90]
        } else {
            intervalDays = [30, 90, 180]
        }

        for days in intervalDays {
            let target = calendar.date(byAdding: .day, value: -days, to: latest.date) ?? latest.date
            if let base = baseline(onOrBefore: target) {
                deltas.append(
                    IntervalDelta(
                        id: "\(days)d",
                        label: "\(days)d",
                        delta: latest.value - base.value,
                        baselineDate: base.date
                    )
                )
            }
        }

        return deltas
    }

    static func trendSummaryForLatest(
        representatives: [DailyRepresentative],
        windowDays: Int,
        calendar: Calendar = .current
    ) -> TrendSummary? {
        guard let latest = representatives.max(by: { $0.dayStart < $1.dayStart }) else { return nil }
        guard representatives.count >= 2 else { return nil }

        let windowEnd = latest.dayStart
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: windowEnd) ?? windowEnd
        let window = representatives.filter { $0.dayStart >= windowStart && $0.dayStart <= windowEnd }
        guard window.count >= 2 else { return nil }

        let pairs: [(Double, Double)] = window.map { rep in
            let x = Double(daysBetween(windowStart, rep.dayStart, calendar: calendar))
            return (x, rep.value)
        }

        guard let reg = linearRegression(pairs: pairs) else { return nil }
        return TrendSummary(
            slopePerDay: reg.slopePerDay,
            intercept: reg.intercept,
            pacePerWeek: reg.slopePerDay * 7,
            rSquared: reg.rSquared,
            residualStdDev: reg.residualStdDev,
            windowStart: windowStart,
            windowEnd: windowEnd,
            pointCount: reg.pointCount
        )
    }

    static func forecast(
        latestDay: Date,
        currentValue: Double,
        regression: LinearRegressionResult,
        horizons: [Int] = [7, 30, 90],
        calendar: Calendar = .current
    ) -> [ForecastPoint] {
        // Use the regression slope, but anchor to the current value so the forecast starts from
        // "where you are today" instead of potentially jumping to the regression line.
        horizons.map { days in
            let date = calendar.date(byAdding: .day, value: days, to: latestDay) ?? latestDay
            let predicted = currentValue + (regression.slopePerDay * Double(days))
            return ForecastPoint(
                id: "\(days)d",
                horizonDays: days,
                date: date,
                predicted: predicted,
                sigma: regression.residualStdDev
            )
        }
    }

    static func reportBuckets(
        points: [TimeSeriesPoint],
        granularity: ReportGranularity,
        calendar: Calendar = .current
    ) -> [ReportBucket] {
        let sorted = points.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        let groups: [Date: [TimeSeriesPoint]] = Dictionary(grouping: sorted) { point in
            bucketKey(for: point.date, granularity: granularity, calendar: calendar)
        }

        let buckets: [ReportBucket] = groups.compactMap { keyDate, bucketPoints in
            let values = bucketPoints.map(\.value)
            guard let minValue = values.min(),
                  let maxValue = values.max(),
                  let first = bucketPoints.first,
                  let last = bucketPoints.last else { return nil }

            let avg = values.reduce(0, +) / Double(values.count)
            let label = bucketLabel(for: keyDate, granularity: granularity, calendar: calendar)

            return ReportBucket(
                keyDate: keyDate,
                label: label,
                average: avg,
                start: first.value,
                end: last.value,
                change: last.value - first.value,
                min: minValue,
                max: maxValue,
                count: values.count
            )
        }

        return buckets.sorted { $0.keyDate < $1.keyDate }
    }

    // MARK: - Helpers

    private static func linearRegression(pairs: [(Double, Double)]) -> LinearRegressionResult? {
        let n = pairs.count
        guard n >= 2 else { return nil }

        let count = Double(n)
        let sumX = pairs.reduce(0.0) { $0 + $1.0 }
        let sumY = pairs.reduce(0.0) { $0 + $1.1 }
        let sumXX = pairs.reduce(0.0) { $0 + ($1.0 * $1.0) }
        let sumXY = pairs.reduce(0.0) { $0 + ($1.0 * $1.1) }

        let denom = count * sumXX - sumX * sumX
        guard abs(denom) > 1e-9 else { return nil }

        let slope = (count * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / count

        let meanY = sumY / count
        var ssTot = 0.0
        var ssRes = 0.0
        for (x, y) in pairs {
            let pred = slope * x + intercept
            ssRes += (y - pred) * (y - pred)
            ssTot += (y - meanY) * (y - meanY)
        }

        let r2: Double?
        if ssTot > 1e-9 {
            r2 = 1 - (ssRes / ssTot)
        } else {
            r2 = nil
        }

        let sigma: Double?
        if n >= 3 {
            sigma = sqrt(ssRes / Double(max(1, n - 2)))
        } else {
            sigma = nil
        }

        return LinearRegressionResult(
            slopePerDay: slope,
            intercept: intercept,
            rSquared: r2,
            residualStdDev: sigma,
            pointCount: n
        )
    }

    private static func bucketKey(for date: Date, granularity: ReportGranularity, calendar: Calendar) -> Date {
        switch granularity {
        case .weekly:
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
        case .monthly:
            let comps = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
        case .yearly:
            let comps = calendar.dateComponents([.year], from: date)
            return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
        }
    }

    private static func bucketLabel(for key: Date, granularity: ReportGranularity, calendar: Calendar) -> String {
        switch granularity {
        case .weekly:
            let week = calendar.component(.weekOfYear, from: key)
            let dayLabel = key.formatted(.dateTime.month(.abbreviated).day())
            return "W\(week) \(dayLabel)"
        case .monthly:
            return key.formatted(.dateTime.year().month(.abbreviated))
        case .yearly:
            return key.formatted(.dateTime.year())
        }
    }

    private static func daysBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0)
    }
}
