import Foundation

nonisolated enum BodyCompositionMetricKind: String, CaseIterable, Identifiable, Sendable {
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

nonisolated struct BodyRawSample: Sendable, Identifiable, Codable, Equatable {
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

nonisolated struct TimeSeriesPoint: Sendable, Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }

    init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

nonisolated struct LinearRegressionResult: Sendable, Equatable {
    let slopePerDay: Double
    let intercept: Double
    let rSquared: Double?
    let residualStdDev: Double?
    let pointCount: Int
    let observedSpanDays: Int
    let meanDay: Double
    let sumSquaredDayOffsets: Double
    let latestDayOffset: Double

    init(
        slopePerDay: Double,
        intercept: Double,
        rSquared: Double?,
        residualStdDev: Double?,
        pointCount: Int,
        observedSpanDays: Int = 0,
        meanDay: Double = 0,
        sumSquaredDayOffsets: Double = 0,
        latestDayOffset: Double = 0
    ) {
        self.slopePerDay = slopePerDay
        self.intercept = intercept
        self.rSquared = rSquared
        self.residualStdDev = residualStdDev
        self.pointCount = pointCount
        self.observedSpanDays = observedSpanDays
        self.meanDay = meanDay
        self.sumSquaredDayOffsets = sumSquaredDayOffsets
        self.latestDayOffset = latestDayOffset
    }
}

nonisolated struct RollingWindowStatistics: Sendable, Equatable {
    let average: Double
    let measuredDayCount: Int
    let observedSpanDays: Int
    let windowDays: Int
}

nonisolated struct BodyLogbookDay: Sendable, Identifiable {
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

nonisolated struct IntervalDelta: Sendable, Identifiable {
    let id: String
    let label: String
    let delta: Double
    let baselineDate: Date?
}

nonisolated struct ForecastPoint: Sendable, Identifiable {
    let id: String
    let horizonDays: Int
    let date: Date
    let predicted: Double
    let sigma: Double?
    /// Two-sided 95% Student-t multiplier; sigma includes new-observation uncertainty.
    var predictionIntervalMultiplier: Double = 1.96

    var lowerBound: Double? { sigma.map { predicted - predictionIntervalMultiplier * $0 } }
    var upperBound: Double? { sigma.map { predicted + predictionIntervalMultiplier * $0 } }
}

nonisolated struct TrendSummary: Sendable {
    let slopePerDay: Double
    let intercept: Double
    let pacePerWeek: Double
    let rSquared: Double?
    let residualStdDev: Double?
    let windowStart: Date
    let windowEnd: Date
    let pointCount: Int
    var observedSpanDays: Int = 0
    var fittedValueAtEnd: Double = 0
    var endpointPredictionSigma: Double?
    var predictionIntervalMultiplier: Double = 1.96
}

nonisolated enum ReportGranularity: String, CaseIterable, Identifiable, Sendable {
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

nonisolated struct ReportBucket: Sendable, Identifiable {
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

nonisolated enum BodyCompositionAnalytics {
    nonisolated struct DailyRepresentative: Sendable, Identifiable, Equatable {
        let dayStart: Date
        let timestamp: Date
        let value: Double
        let samples: [BodyRawSample]

        var id: Date { dayStart }
    }

    static func bufferedAnalysisRange(
        for displayRange: DateInterval,
        bufferDays: Int = 35,
        calendar: Calendar = .current
    ) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -max(0, bufferDays), to: displayRange.start) ?? displayRange.start
        return DateInterval(start: start, end: displayRange.end)
    }

    static func isValidSampleValue(_ value: Double, metricKind: BodyCompositionMetricKind? = nil) -> Bool {
        guard value.isFinite, value > 0 else { return false }
        return metricKind != .bodyFat || value <= 100
    }

    /// Keep one earliest valid reading per day so repeated weigh-ins do not receive extra weight.
    /// All distinct readings are retained for the logbook; "first" does not imply a morning reading.
    static func dailyRepresentatives(
        from samples: [BodyRawSample],
        metricKind: BodyCompositionMetricKind? = nil,
        calendar: Calendar = .current
    ) -> [DailyRepresentative] {
        var seenIDs: Set<UUID> = []
        let validSamples = samples.filter {
            isValidSampleValue($0.value, metricKind: metricKind)
                && $0.timestamp.timeIntervalSinceReferenceDate.isFinite
        }.sorted { sampleOrder($0, $1) }.filter { seenIDs.insert($0.id).inserted }

        let grouped = Dictionary(grouping: validSamples) { sample in
            calendar.startOfDay(for: sample.timestamp)
        }

        let reps: [DailyRepresentative] = grouped.compactMap { dayStart, daySamples in
            // Dictionary grouping preserves the globally sorted sample order.
            guard let first = daySamples.first else { return nil }
            return DailyRepresentative(
                dayStart: dayStart,
                timestamp: first.timestamp,
                value: first.value,
                samples: daySamples
            )
        }

        return reps.sorted { $0.dayStart < $1.dayStart }
    }

    static func trailingAverages(
        representatives: [DailyRepresentative],
        windowDays: Int,
        calendar: Calendar = .current
    ) -> [Date: Double] {
        trailingWindowStatistics(representatives: representatives, windowDays: windowDays, calendar: calendar)
            .mapValues(\.average)
    }

    /// Calendar windows average measured days only. Missing days are never filled with zero or carried forward.
    static func trailingWindowStatistics(
        representatives: [DailyRepresentative],
        windowDays: Int,
        calendar: Calendar = .current
    ) -> [Date: RollingWindowStatistics] {
        guard windowDays > 0 else { return [:] }
        let representatives = normalizedRepresentatives(representatives)
        guard !representatives.isEmpty else { return [:] }

        var result: [Date: RollingWindowStatistics] = [:]
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
            let average = runningSum / Double(count)
            guard average.isFinite else { continue }
            result[currentDay] = RollingWindowStatistics(
                average: average,
                measuredDayCount: count,
                observedSpanDays: daysBetween(representatives[startIndex].dayStart, currentDay, calendar: calendar),
                windowDays: windowDays
            )
        }

        return result
    }

    static func trailingRegression(
        representatives: [DailyRepresentative],
        windowDays: Int,
        calendar: Calendar = .current
    ) -> [Date: LinearRegressionResult] {
        guard windowDays > 0 else { return [:] }
        let representatives = normalizedRepresentatives(representatives)
        guard representatives.count >= 6 else { return [:] }

        // Calendar conversion dominates long histories. Convert each measured day
        // once, then reuse exact calendar-day offsets in each trailing window.
        let anchor = representatives[0].dayStart
        let dayOffsets = representatives.map { daysBetween(anchor, $0.dayStart, calendar: calendar) }
        var results: [Date: LinearRegressionResult] = [:]
        results.reserveCapacity(representatives.count)
        var startIndex = 0

        for index in representatives.indices {
            let endDay = representatives[index].dayStart
            let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: endDay) ?? endDay

            while startIndex < index, representatives[startIndex].dayStart < windowStart {
                startIndex += 1
            }

            guard index - startIndex + 1 >= 6,
                  dayOffsets[index] - dayOffsets[startIndex] >= 7 else { continue }
            let windowOffset = dayOffsets[index] - daysBetween(windowStart, endDay, calendar: calendar)
            let pairs: [(Double, Double)] = (startIndex...index).map { sampleIndex in
                (Double(dayOffsets[sampleIndex] - windowOffset), representatives[sampleIndex].value)
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

        for rep in normalizedRepresentatives(representatives) {
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
        let sorted = normalizedPoints(points)
        guard let latest = sorted.last else { return [] }

        var deltas: [IntervalDelta] = []

        // Since range start
        if let firstInRange = sorted.first(where: { $0.date >= calendar.startOfDay(for: displayRangeStart) }),
           firstInRange.date < latest.date {
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
            // A nearby real reading is more honest than an arbitrarily stale baseline or interpolation.
            // A one-week comparison allows one day of tolerance; longer comparisons allow at most three.
            let tolerance = max(1, min(3, days / 7))
            let targetDay = calendar.startOfDay(for: target)
            let firstDay = calendar.date(byAdding: .day, value: -tolerance, to: targetDay) ?? targetDay
            let afterLastDay = calendar.date(byAdding: .day, value: tolerance + 1, to: targetDay) ?? targetDay
            let firstIndex = lowerBound(in: sorted, date: firstDay)
            let endIndex = lowerBound(in: sorted, date: min(afterLastDay, latest.date))
            let candidates = sorted[firstIndex..<max(firstIndex, endIndex)]
            let base = candidates.min { lhs, rhs in
                let lhsDistance = calendarDayDistance(lhs.date, target, calendar: calendar)
                let rhsDistance = calendarDayDistance(rhs.date, target, calendar: calendar)
                return lhsDistance == rhsDistance ? lhs.date < rhs.date : lhsDistance < rhsDistance
            }
            if let base {
                let elapsedDays = daysBetween(base.date, latest.date, calendar: calendar)
                guard elapsedDays > 0 else { continue }
                deltas.append(
                    IntervalDelta(
                        id: "\(days)d",
                        label: "\(elapsedDays)d",
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
        guard windowDays > 0 else { return nil }
        let representatives = normalizedRepresentatives(representatives)
        guard let latest = representatives.last else { return nil }

        let windowEnd = latest.dayStart
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: windowEnd) ?? windowEnd
        let window = representatives.filter { $0.dayStart >= windowStart && $0.dayStart <= windowEnd }
        guard hasEnoughTrendHistory(window, calendar: calendar) else { return nil }

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
            pointCount: reg.pointCount,
            observedSpanDays: reg.observedSpanDays,
            fittedValueAtEnd: reg.intercept + reg.slopePerDay * reg.latestDayOffset,
            endpointPredictionSigma: predictionSigma(regression: reg, dayOffset: reg.latestDayOffset),
            predictionIntervalMultiplier: predictionIntervalMultiplier(pointCount: reg.pointCount)
        )
    }

    static func forecast(
        latestDay: Date,
        currentValue: Double,
        regression: LinearRegressionResult,
        horizons: [Int] = [7, 14, 30],
        metricKind: BodyCompositionMetricKind? = nil,
        calendar: Calendar = .current
    ) -> [ForecastPoint] {
        guard isValidSampleValue(currentValue, metricKind: metricKind),
              regression.pointCount >= 6,
              regression.observedSpanDays >= 7,
              regression.slopePerDay.isFinite,
              regression.intercept.isFinite,
              regression.sumSquaredDayOffsets > 0 else { return [] }

        let maximumHorizon = min(30, regression.observedSpanDays)
        // Extend the fitted line, rather than amplifying the latest reading's temporary fluctuation.
        // These conditional projections do not claim that the recent pattern will continue.
        return Set(horizons).sorted().compactMap { days in
            guard days > 0, days <= maximumHorizon,
                  let date = calendar.date(byAdding: .day, value: days, to: latestDay) else { return nil }
            let dayOffset = regression.latestDayOffset + Double(days)
            let predicted = regression.intercept + regression.slopePerDay * dayOffset
            guard isValidSampleValue(predicted, metricKind: metricKind),
                  let sigma = predictionSigma(regression: regression, dayOffset: dayOffset) else { return nil }
            return ForecastPoint(
                id: "\(days)d",
                horizonDays: days,
                date: date,
                predicted: predicted,
                sigma: sigma,
                predictionIntervalMultiplier: predictionIntervalMultiplier(pointCount: regression.pointCount)
            )
        }
    }

    static func reportBuckets(
        points: [TimeSeriesPoint],
        granularity: ReportGranularity,
        calendar: Calendar = .current
    ) -> [ReportBucket] {
        let sorted = normalizedPoints(points)
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

            let avg = values.reduce(0) { $0 + $1 / Double(values.count) }
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

    private static func sampleOrder(_ lhs: BodyRawSample, _ rhs: BodyRawSample) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.value < rhs.value
    }

    private static func normalizedRepresentatives(_ representatives: [DailyRepresentative]) -> [DailyRepresentative] {
        var seenDays: Set<Date> = []
        return representatives.filter {
            isValidSampleValue($0.value) && $0.dayStart.timeIntervalSinceReferenceDate.isFinite
        }.sorted {
            $0.dayStart == $1.dayStart ? $0.timestamp < $1.timestamp : $0.dayStart < $1.dayStart
        }.filter { seenDays.insert($0.dayStart).inserted }
    }

    private static func normalizedPoints(_ points: [TimeSeriesPoint]) -> [TimeSeriesPoint] {
        var seenDates: Set<Date> = []
        return points.filter {
            isValidSampleValue($0.value) && $0.date.timeIntervalSinceReferenceDate.isFinite
        }.sorted { $0.date < $1.date }.filter { seenDates.insert($0.date).inserted }
    }

    private static func hasEnoughTrendHistory(_ window: [DailyRepresentative], calendar: Calendar) -> Bool {
        guard window.count >= 6, let first = window.first, let last = window.last else { return false }
        return daysBetween(first.dayStart, last.dayStart, calendar: calendar) >= 7
    }

    private static func predictionSigma(regression: LinearRegressionResult, dayOffset: Double) -> Double? {
        guard let residual = regression.residualStdDev,
              residual.isFinite, residual >= 0,
              regression.pointCount > 2,
              regression.sumSquaredDayOffsets > 0 else { return nil }
        let offset = dayOffset - regression.meanDay
        // Individual-observation prediction error includes residual variability and fit uncertainty.
        // https://www.itl.nist.gov/div898/handbook/pmd/section5/pmd512.htm
        let varianceFactor = 1 + 1 / Double(regression.pointCount)
            + offset * offset / regression.sumSquaredDayOffsets
        let sigma = residual * sqrt(varianceFactor)
        return sigma.isFinite ? sigma : nil
    }

    private static func predictionIntervalMultiplier(pointCount: Int) -> Double {
        // Two-sided 95% critical values for n - 2 fitted-line degrees of freedom.
        // https://www.itl.nist.gov/div898/handbook/eda/section3/eda3672.htm
        let criticalValues: [Double] = [
            12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228,
            2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
            2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042
        ]
        let degreesOfFreedom = max(1, pointCount - 2)
        if degreesOfFreedom <= criticalValues.count { return criticalValues[degreesOfFreedom - 1] }
        // Conservatively use the nearest lower tabulated degrees of freedom for longer windows.
        if degreesOfFreedom < 40 { return 2.042 }
        if degreesOfFreedom < 60 { return 2.021 }
        if degreesOfFreedom < 100 { return 2.000 }
        return 1.984
    }

    private static func linearRegression(pairs: [(Double, Double)]) -> LinearRegressionResult? {
        let pairs = pairs.filter { $0.0.isFinite && $0.1.isFinite }
        let sampleCount = pairs.count
        guard sampleCount >= 2 else { return nil }

        let count = Double(sampleCount)
        let meanX = pairs.reduce(0.0) { $0 + $1.0 / count }
        let meanY = pairs.reduce(0.0) { $0 + $1.1 / count }
        let sumSquaredDayOffsets = pairs.reduce(0.0) { $0 + pow($1.0 - meanX, 2) }
        let covariance = pairs.reduce(0.0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        guard sumSquaredDayOffsets.isFinite, sumSquaredDayOffsets > 1e-9 else { return nil }

        let slope = covariance / sumSquaredDayOffsets
        let intercept = meanY - slope * meanX
        guard slope.isFinite, intercept.isFinite else { return nil }
        var ssTot = 0.0
        var ssRes = 0.0
        for (x, y) in pairs {
            let pred = slope * x + intercept
            ssRes += (y - pred) * (y - pred)
            ssTot += (y - meanY) * (y - meanY)
        }

        let r2: Double?
        if ssTot > 1e-9 {
            r2 = min(1, max(0, 1 - (ssRes / ssTot)))
        } else {
            r2 = nil
        }

        let sigma: Double?
        if sampleCount >= 3 {
            let residual = sqrt(ssRes / Double(sampleCount - 2))
            sigma = residual.isFinite ? residual : nil
        } else {
            sigma = nil
        }

        return LinearRegressionResult(
            slopePerDay: slope,
            intercept: intercept,
            rSquared: r2,
            residualStdDev: sigma,
            pointCount: sampleCount,
            observedSpanDays: Int((pairs.map(\.0).max() ?? 0) - (pairs.map(\.0).min() ?? 0)),
            meanDay: meanX,
            sumSquaredDayOffsets: sumSquaredDayOffsets,
            latestDayOffset: pairs.map(\.0).max() ?? 0
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

    private static func lowerBound(in points: [TimeSeriesPoint], date: Date) -> Int {
        var lower = 0
        var upper = points.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if points[middle].date < date { lower = middle + 1 } else { upper = middle }
        }
        return lower
    }

    private static func calendarDayDistance(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Int {
        daysBetween(min(lhs, rhs), max(lhs, rhs), calendar: calendar)
    }
}
