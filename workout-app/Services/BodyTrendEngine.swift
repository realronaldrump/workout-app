import Foundation

// MARK: - Model

/// One calendar day on the trend grid. Days with a weigh-in carry the day's first reading.
/// Days between weigh-ins (up to two weeks apart) are filled by a straight line between the
/// readings on either side, so the trend keeps moving through a missed day instead of stalling.
nonisolated struct BodyTrendDay: Sendable, Identifiable, Equatable {
    let dayIndex: Int
    let day: Date
    /// The first valid reading of the day. `nil` on a filled day.
    let reading: Double?
    let trend: Double
    /// A new segment starts after a gap of more than two weeks without a reading.
    let segment: Int
    /// The first week of a segment, while the trend is still mostly the first few readings.
    let isSettling: Bool

    var id: Int { dayIndex }
    var hasReading: Bool { reading != nil }
}

nonisolated enum BodyDayFlag: Sendable, Equatable {
    case high
    case low
}

/// The trend's weekly rate with a plus-or-minus that holds about eight times in ten.
nonisolated struct BodyRate: Sendable, Equatable {
    let perWeek: Double
    let halfWidth: Double
    let readingCount: Int
    let windowDays: Int

    /// The rate can't be told apart from flat.
    var isSteady: Bool { abs(perWeek) <= halfWidth }
}

nonisolated struct BodyChange: Sendable, Identifiable, Equatable {
    let id: String
    let label: String
    let baselineDate: Date
    let baseline: Double
    let current: Double

    var delta: Double { current - baseline }
    var percent: Double { baseline != 0 ? delta / baseline * 100 : 0 }
}

nonisolated struct BodyRangeStats: Sendable, Equatable {
    let heaviest: BodyTrendDay
    let lightest: BodyTrendDay
    let average: Double
    let readingDayCount: Int
}

// MARK: - Series

/// A body measurement's history, analyzed once: daily readings on a calendar-day grid, an
/// exponentially smoothed trend, and the residual noise used for the usual-range band.
/// Every query is a cheap slice of these arrays, so changing the chart range never refetches.
nonisolated struct BodySeries: Sendable {
    let kind: BodyCompositionMetricKind
    let grid: [BodyTrendDay]
    /// Every valid reading, oldest first, including repeat weigh-ins on the same day.
    let readings: [BodyRawSample]
    /// Readings that failed validation, so the method sheet can say so instead of hiding them.
    let ignoredReadingCount: Int
    /// Robust spread of readings around the trend over the last 90 days. `nil` until there are
    /// 14 residuals to estimate it from.
    let residualSigma: Double?
    /// Reading minus the previous day's trend, per reading day.
    let residuals: [Int: Double]
    let flags: [Int: BodyDayFlag]
    let calendar: Calendar

    static let empty = BodySeries.empty(.weight)

    static func empty(_ kind: BodyCompositionMetricKind) -> BodySeries {
        BodySeries(
            kind: kind,
            grid: [],
            readings: [],
            ignoredReadingCount: 0,
            residualSigma: nil,
            residuals: [:],
            flags: [:],
            calendar: .current
        )
    }

    var isEmpty: Bool { grid.isEmpty }
    var latest: BodyTrendDay? { grid.last }
    var readingDayCount: Int { grid.reduce(0) { $0 + ($1.hasReading ? 1 : 0) } }

    /// Days on the grid that have a weigh-in, oldest first.
    var readingDays: [BodyTrendDay] { grid.filter(\.hasReading) }

    /// The first grid day of the segment the latest reading belongs to.
    var currentSegmentStart: BodyTrendDay? {
        guard let latest else { return nil }
        return grid.first { $0.segment == latest.segment }
    }

    func dayIndex(for date: Date) -> Int {
        BodyTrendEngine.dayIndex(of: date, calendar: calendar)
    }

    func gridDay(at dayIndex: Int) -> BodyTrendDay? {
        guard let position = position(of: dayIndex) else { return nil }
        return grid[position]
    }

    /// The grid day nearest `dayIndex` within `tolerance` days, preferring the earlier day on a tie.
    func nearestGridDay(to dayIndex: Int, tolerance: Int) -> BodyTrendDay? {
        let lower = lowerBound(dayIndex - tolerance)
        var best: BodyTrendDay?
        var position = lower
        while position < grid.count, grid[position].dayIndex <= dayIndex + tolerance {
            let candidate = grid[position]
            if let current = best {
                if abs(candidate.dayIndex - dayIndex) < abs(current.dayIndex - dayIndex) { best = candidate }
            } else {
                best = candidate
            }
            position += 1
        }
        return best
    }

    /// Grid days whose day falls inside the interval, oldest first.
    func gridDays(in interval: DateInterval) -> ArraySlice<BodyTrendDay> {
        let start = lowerBound(dayIndex(for: interval.start))
        let end = upperBound(dayIndex(for: interval.end))
        guard start < end else { return [] }
        return grid[start..<end]
    }

    func readings(on day: BodyTrendDay) -> [BodyRawSample] {
        let start = calendar.startOfDay(for: day.day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return readings.filter { $0.timestamp >= start && $0.timestamp < end }
    }

    /// The trend plus or minus 1.28 residual deviations: about eight normal readings in ten land inside.
    func band(for day: BodyTrendDay) -> ClosedRange<Double>? {
        guard let residualSigma else { return nil }
        let half = 1.28 * residualSigma
        return (day.trend - half)...(day.trend + half)
    }

    // MARK: Rate

    /// Least-squares slope of the trend over the last `windowDays` of the current segment, with a
    /// plus-or-minus from the raw readings' own regression. Needs eight weigh-ins over two weeks,
    /// and a weigh-in in the last week, because a rate from less is mostly noise.
    func rate(asOf now: Date, windowDays: Int = 28) -> BodyRate? {
        guard let latest, let segmentStart = currentSegmentStart else { return nil }
        let today = dayIndex(for: now)
        guard today - latest.dayIndex <= 7 else { return nil }

        let windowStart = max(latest.dayIndex - (windowDays - 1), segmentStart.dayIndex)
        guard latest.dayIndex - windowStart >= 13 else { return nil }
        let window = grid[lowerBound(windowStart)...].prefix { $0.dayIndex <= latest.dayIndex }
        let readingDays = window.filter(\.hasReading)
        guard readingDays.count >= 8,
              let first = readingDays.first, let last = readingDays.last,
              last.dayIndex - first.dayIndex >= 13,
              let trendFit = BodyTrendEngine.leastSquares(window.map { (Double($0.dayIndex), $0.trend) }),
              let rawFit = BodyTrendEngine.leastSquares(readingDays.compactMap { day in
                  day.reading.map { (Double(day.dayIndex), $0) }
              }) else { return nil }

        let halfWidth = 1.25 * (rawFit.slopeStandardError ?? 0) * 7
        return BodyRate(
            perWeek: trendFit.slope * 7,
            halfWidth: halfWidth,
            readingCount: readingDays.count,
            windowDays: latest.dayIndex - windowStart + 1
        )
    }

    // MARK: Change

    /// Trend now against the trend `days` ago. Each window needs a minimum number of weigh-ins
    /// inside it, so a row never compares against a stretch with almost no readings.
    func change(days: Int) -> BodyChange? {
        guard let latest else { return nil }
        let required: Int
        switch days {
        case ...7: required = 4
        case ...30: required = 8
        case ...90: required = 13
        default: required = 26
        }
        let windowStart = latest.dayIndex - days
        let readingsInWindow = grid[lowerBound(windowStart + 1)...]
            .prefix { $0.dayIndex <= latest.dayIndex }
            .reduce(0) { $0 + ($1.hasReading ? 1 : 0) }
        guard readingsInWindow >= required,
              let baseline = nearestGridDay(to: windowStart, tolerance: max(1, min(3, days / 7))) else {
            return nil
        }
        let label: String
        switch days {
        case 365: label = "1 year"
        default: label = "\(days) days"
        }
        return BodyChange(
            id: "\(days)",
            label: label,
            baselineDate: baseline.day,
            baseline: baseline.trend,
            current: latest.trend
        )
    }

    /// The whole history: the trend now against the first reading.
    func changeSinceStart() -> BodyChange? {
        guard let latest, let first = grid.first,
              readingDayCount >= 8, latest.dayIndex - first.dayIndex >= 14 else { return nil }
        let sameYear = calendar.isDate(first.day, equalTo: latest.day, toGranularity: .year)
        let dateText = sameYear
            ? first.day.formatted(.dateTime.month(.abbreviated).day())
            : first.day.formatted(.dateTime.month(.abbreviated).day().year())
        return BodyChange(
            id: "start",
            label: "Since \(dateText)",
            baselineDate: first.day,
            baseline: first.trend,
            current: latest.trend
        )
    }

    // MARK: Range statistics

    func stats(in interval: DateInterval) -> BodyRangeStats? {
        let days = gridDays(in: interval).filter(\.hasReading)
        guard let heaviest = days.max(by: { ($0.reading ?? 0) < ($1.reading ?? 0) }),
              let lightest = days.min(by: { ($0.reading ?? 0) < ($1.reading ?? 0) }) else { return nil }
        let total = days.reduce(0) { $0 + ($1.reading ?? 0) }
        return BodyRangeStats(
            heaviest: heaviest,
            lightest: lightest,
            average: total / Double(days.count),
            readingDayCount: days.count
        )
    }

    /// The average daily reading in `interval` minus the average in the equal stretch before it.
    func changeFromPreviousPeriod(_ interval: DateInterval) -> Double? {
        let previous = DateInterval(start: interval.start.addingTimeInterval(-interval.duration), end: interval.start)
        let current = gridDays(in: interval).compactMap(\.reading)
        let prior = gridDays(in: previous).compactMap(\.reading)
        guard current.count >= 4, prior.count >= 4 else { return nil }
        return current.reduce(0, +) / Double(current.count) - prior.reduce(0, +) / Double(prior.count)
    }

    /// Distinct weigh-in days in the last four weeks, per week.
    func weighInsPerWeek(asOf now: Date) -> Double {
        let today = dayIndex(for: now)
        let count = grid[lowerBound(today - 27)...]
            .prefix { $0.dayIndex <= today }
            .reduce(0) { $0 + ($1.hasReading ? 1 : 0) }
        return Double(count) / 4
    }

    // MARK: Binary search

    private func position(of dayIndex: Int) -> Int? {
        let position = lowerBound(dayIndex)
        guard position < grid.count, grid[position].dayIndex == dayIndex else { return nil }
        return position
    }

    /// First position whose day index is at least `dayIndex`.
    private func lowerBound(_ dayIndex: Int) -> Int {
        var low = 0
        var high = grid.count
        while low < high {
            let mid = (low + high) / 2
            if grid[mid].dayIndex < dayIndex { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// First position whose day index is greater than `dayIndex`.
    private func upperBound(_ dayIndex: Int) -> Int {
        var low = 0
        var high = grid.count
        while low < high {
            let mid = (low + high) / 2
            if grid[mid].dayIndex <= dayIndex { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

// MARK: - Engine

nonisolated enum BodyTrendEngine {
    /// Each day the trend moves a tenth of the way toward that day's weight (The Hacker's Diet).
    /// It lags a real change by about nine days and settles 90% of a step in about three weeks.
    static let smoothing = 0.1
    /// Longer gaps restart the trend instead of drawing a straight line across them.
    static let maxInterpolatedGapDays = 14
    static let settlingDays = 7

    static func build(
        samples: [BodyRawSample],
        kind: BodyCompositionMetricKind,
        calendar: Calendar = .current
    ) -> BodySeries {
        let plausible = samples.filter { isPlausible($0.value, kind: kind) }
        let representatives = BodyCompositionAnalytics.dailyRepresentatives(
            from: plausible,
            metricKind: kind,
            calendar: calendar
        )
        let readings = representatives.flatMap(\.samples)
        let ignored = samples.count - plausible.count

        guard !representatives.isEmpty else {
            return BodySeries(
                kind: kind, grid: [], readings: [], ignoredReadingCount: ignored,
                residualSigma: nil, residuals: [:], flags: [:], calendar: calendar
            )
        }

        var grid: [BodyTrendDay] = []
        grid.reserveCapacity(representatives.count * 2)
        var residuals: [Int: Double] = [:]
        var segment = 0
        var segmentStartIndex = 0
        var trend = 0.0
        var previous: (index: Int, value: Double)?

        for representative in representatives {
            let index = dayIndex(of: representative.dayStart, calendar: calendar)
            let value = representative.value

            if let last = previous, index - last.index <= maxInterpolatedGapDays {
                // Fill the missed days on a straight line, then fold in today's reading.
                let gap = index - last.index
                if gap > 1 {
                    for step in 1..<gap {
                        let filled = last.value + (value - last.value) * Double(step) / Double(gap)
                        trend += smoothing * (filled - trend)
                        let filledIndex = last.index + step
                        grid.append(BodyTrendDay(
                            dayIndex: filledIndex,
                            day: date(forDayIndex: filledIndex, calendar: calendar),
                            reading: nil,
                            trend: trend,
                            segment: segment,
                            isSettling: filledIndex - segmentStartIndex < settlingDays
                        ))
                    }
                }
                residuals[index] = value - trend
                trend += smoothing * (value - trend)
            } else {
                if previous != nil { segment += 1 }
                segmentStartIndex = index
                trend = value
            }

            grid.append(BodyTrendDay(
                dayIndex: index,
                day: representative.dayStart,
                reading: value,
                trend: trend,
                segment: segment,
                isSettling: index - segmentStartIndex < settlingDays
            ))
            previous = (index, value)
        }

        let latestIndex = grid.last?.dayIndex ?? 0
        let recentResiduals = residuals.filter { latestIndex - $0.key < 90 }.map(\.value)
        let sigma = robustSigma(recentResiduals)

        var flags: [Int: BodyDayFlag] = [:]
        if let sigma {
            var readingByIndex: [Int: Double] = [:]
            for day in grid { if let reading = day.reading { readingByIndex[day.dayIndex] = reading } }
            for (index, residual) in residuals {
                guard let reading = readingByIndex[index] else { continue }
                let priorTrend = reading - residual
                let threshold = max(2.5 * sigma, 0.01 * priorTrend)
                if residual >= threshold {
                    flags[index] = .high
                } else if residual <= -threshold {
                    flags[index] = .low
                }
            }
        }

        return BodySeries(
            kind: kind,
            grid: grid,
            readings: readings,
            ignoredReadingCount: ignored,
            residualSigma: sigma,
            residuals: residuals,
            flags: flags,
            calendar: calendar
        )
    }

    /// Rejects values no scale reports for a person, which usually mean a unit mix-up.
    static func isPlausible(_ value: Double, kind: BodyCompositionMetricKind) -> Bool {
        guard value.isFinite else { return false }
        switch kind {
        case .weight: return (20...1_000).contains(value)
        case .bodyFat: return value > 2 && value <= 70
        }
    }

    /// 1.4826 times the median absolute deviation: a standard deviation that one wild reading
    /// can't inflate. Needs 14 residuals.
    static func robustSigma(_ values: [Double]) -> Double? {
        guard values.count >= 14 else { return nil }
        let center = median(values)
        let deviation = median(values.map { abs($0 - center) })
        let sigma = 1.4826 * deviation
        return sigma > 0 ? sigma : nil
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    // MARK: Days

    /// Whole calendar days since the reference date, counted on the calendar so a daylight
    /// saving change never shifts a reading onto the wrong day.
    static func dayIndex(of date: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: referenceDay(calendar), to: start).day ?? 0
    }

    static func date(forDayIndex index: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: index, to: referenceDay(calendar)) ?? referenceDay(calendar)
    }

    private static func referenceDay(_ calendar: Calendar) -> Date {
        calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
    }

    // MARK: Regression

    struct LineFit {
        let slope: Double
        let intercept: Double
        let slopeStandardError: Double?
    }

    static func leastSquares(_ points: [(Double, Double)]) -> LineFit? {
        let points = points.filter { $0.0.isFinite && $0.1.isFinite }
        guard points.count >= 2 else { return nil }
        let count = Double(points.count)
        let meanX = points.reduce(0) { $0 + $1.0 } / count
        let meanY = points.reduce(0) { $0 + $1.1 } / count
        let sxx = points.reduce(0) { $0 + ($1.0 - meanX) * ($1.0 - meanX) }
        guard sxx > 1e-9 else { return nil }
        let sxy = points.reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        var standardError: Double?
        if points.count > 2 {
            let residualSquares = points.reduce(0) { total, point in
                let error = point.1 - (intercept + slope * point.0)
                return total + error * error
            }
            standardError = sqrt(residualSquares / (count - 2)) / sqrt(sxx)
        }
        return LineFit(slope: slope, intercept: intercept, slopeStandardError: standardError)
    }

    /// Keeps at most about `limit` days for drawing, always keeping each segment's first and last day.
    static func thinned(_ days: ArraySlice<BodyTrendDay>, limit: Int) -> [BodyTrendDay] {
        let days = Array(days)
        guard days.count > limit, limit > 1 else { return days }
        let stride = Int((Double(days.count) / Double(limit)).rounded(.up))
        var result: [BodyTrendDay] = []
        result.reserveCapacity(limit + 8)
        for (offset, day) in days.enumerated() {
            let startsSegment = offset == 0 || days[offset - 1].segment != day.segment
            let endsSegment = offset == days.count - 1 || days[offset + 1].segment != day.segment
            if startsSegment || endsSegment || offset.isMultiple(of: stride) {
                result.append(day)
            }
        }
        return result
    }
}

// MARK: - Goal

/// Progress toward an optional goal weight, and when the current pace would reach it.
nonisolated struct BodyGoalStatus: Sendable, Equatable {
    enum Arrival: Sendable, Equatable {
        /// Between two dates, from the rate plus and minus its uncertainty.
        case between(Date, Date)
        /// The slow end can't be bounded, only the earliest date.
        case from(Date)
        case beyondAYear
        /// The trend isn't clearly moving toward the goal.
        case noEstimate
    }

    let goal: Double
    let start: Double
    let current: Double
    let arrival: Arrival

    /// Share of the way from the starting trend to the goal, 0...1.
    var progress: Double {
        let span = start - goal
        guard abs(span) > 1e-6 else { return 1 }
        return min(1, max(0, (start - current) / span))
    }

    var platesLoaded: Int { Int((progress * 10).rounded(.down)) }
    var isReached: Bool { progress >= 1 }
    var remaining: Double { goal - current }

    static func make(goal: Double, start: Double, current: Double, rate: BodyRate?, now: Date, calendar: Calendar = .current) -> BodyGoalStatus {
        let distance = goal - current
        var arrival = Arrival.noEstimate
        if let rate, abs(distance) > 1e-6 {
            let towardGoal = (distance < 0 && rate.perWeek < 0) || (distance > 0 && rate.perWeek > 0)
            let pace = abs(rate.perWeek)
            let margin = rate.halfWidth
            if towardGoal, pace > margin {
                let fastWeeks = abs(distance) / (pace + margin)
                if fastWeeks > 52 {
                    arrival = .beyondAYear
                } else if pace - margin <= 0.1 * pace {
                    arrival = .from(weeks(fastWeeks, from: now, calendar: calendar))
                } else {
                    let slowWeeks = abs(distance) / (pace - margin)
                    arrival = slowWeeks > 104
                        ? .from(weeks(fastWeeks, from: now, calendar: calendar))
                        : .between(weeks(fastWeeks, from: now, calendar: calendar), weeks(slowWeeks, from: now, calendar: calendar))
                }
            }
        }
        return BodyGoalStatus(goal: goal, start: start, current: current, arrival: arrival)
    }

    private static func weeks(_ count: Double, from now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: Int(count.rounded()) * 7, to: calendar.startOfDay(for: now)) ?? now
    }
}

// MARK: - Composition

/// Fat and lean mass from trend weight split by trend body fat, on the latest day both exist.
nonisolated struct BodyComposition: Sendable, Equatable {
    let date: Date
    let weight: Double
    let bodyFatPercent: Double

    var fatMass: Double { weight * bodyFatPercent / 100 }
    var leanMass: Double { weight - fatMass }

    static func latest(weight: BodySeries, bodyFat: BodySeries) -> BodyComposition? {
        guard let fat = bodyFat.latest else { return nil }
        return at(dayIndex: fat.dayIndex, weight: weight, bodyFat: bodyFat)
    }

    /// The composition on (or within three days of) a day, using each series' trend.
    static func at(dayIndex: Int, weight: BodySeries, bodyFat: BodySeries) -> BodyComposition? {
        guard let fatDay = bodyFat.nearestGridDay(to: dayIndex, tolerance: 3),
              let weightDay = weight.nearestGridDay(to: fatDay.dayIndex, tolerance: 3) else { return nil }
        return BodyComposition(date: fatDay.day, weight: weightDay.trend, bodyFatPercent: fatDay.trend)
    }

    /// Composition now against `days` ago. Body fat needs four readings in 30 days or eight in 90,
    /// because scale estimates swing with hydration.
    static func change(days: Int, weight: BodySeries, bodyFat: BodySeries) -> (from: BodyComposition, to: BodyComposition)? {
        guard let latestFat = bodyFat.latest,
              let now = at(dayIndex: latestFat.dayIndex, weight: weight, bodyFat: bodyFat) else { return nil }
        let required = days <= 30 ? 4 : 8
        let count = bodyFat.grid
            .filter { $0.hasReading && $0.dayIndex > latestFat.dayIndex - days && $0.dayIndex <= latestFat.dayIndex }
            .count
        guard count >= required,
              let then = at(dayIndex: latestFat.dayIndex - days, weight: weight, bodyFat: bodyFat) else { return nil }
        return (then, now)
    }
}
