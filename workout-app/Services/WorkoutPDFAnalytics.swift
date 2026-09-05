import Foundation

/// Report metrics use only selected fields. Session totals are counted once, never once per set.
nonisolated struct WorkoutPDFAnalytics {
    struct Session {
        let id: UUID
        let date: Date
        let rows: Range<Int>
    }
    struct Category {
        let name: String
        var count: Double
        var secondary: Double = 0
    }
    struct Bucket {
        let start: Date
        let end: Date
        let label: String
        var workouts = 0
        var sets = 0
    }
    struct Trend {
        let name: String
        let metric: String
        let unit: String
        let values: [Double?]
        let sessionCount: Int
    }

    let sessions: [Session]
    let exercises: [Category]
    let muscles: [Category]
    let mappedSetCount: Int
    let durationSeconds: Double
    let durationCount: Int
    let totalReps: Double?
    let buckets: [Bucket]
    let intervalTitle: String
    let weekdays: [Int]
    let trends: [Trend]

    init(_ document: WorkoutExportDocument) {
        let selected = Set(document.columns)
        var sessions: [Session] = []
        var cursor = 0
        while cursor < document.records.count {
            let start = cursor
            let record = document.records[cursor]
            while cursor < document.records.count, document.records[cursor].workoutID == record.workoutID { cursor += 1 }
            sessions.append(Session(id: record.workoutID, date: record.startedAt, rows: start..<cursor))
        }
        self.sessions = sessions

        var exerciseCounts: [String: Double] = [:]
        var muscleCounts: [String: Category] = [:]
        var mapped = 0
        var reps = 0.0
        for row in document.records {
            if selected.contains(.exercise) {
                exerciseCounts[row.value(.exercise).text, default: 0] += 1
            }
            if selected.contains(.tags), let assignments = row.muscles {
                let valid = assignments.filter { $0.role == "primary" || $0.role == "secondary" }
                if !valid.isEmpty { mapped += 1 }
                for muscle in valid {
                    var value = muscleCounts[muscle.name] ?? Category(name: muscle.name, count: 0)
                    if muscle.role == "primary" { value.count += 1 } else { value.secondary += 0.5 }
                    muscleCounts[muscle.name] = value
                }
            }
            if selected.contains(.reps), let value = row.value(.reps).finiteNumber, value >= 0, (reps + value).isFinite {
                reps += value
            }
        }
        exercises = exerciseCounts.map { Category(name: $0.key, count: $0.value) }.sorted(by: Self.categoryOrder)
        muscles = muscleCounts.values.sorted(by: Self.categoryOrder)
        mappedSetCount = mapped
        totalReps = selected.contains(.reps) ? reps : nil

        var duration = 0.0
        var knownDurations = 0
        if selected.contains(.duration) || selected.contains(.durationText) {
            for session in sessions {
                if let seconds = document.records[session.rows.lowerBound].value(.duration).finiteNumber,
                   seconds >= 0, (duration + seconds).isFinite {
                    duration += seconds
                    knownDurations += 1
                }
            }
        }
        durationSeconds = duration
        durationCount = knownDurations

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: document.timeZone) ?? .gmt
        calendar.firstWeekday = 2
        let result = selected.contains(.workoutStart) ? Self.makeBuckets(document, calendar: calendar) : ([], "")
        var buckets = result.0
        var weekdays = Array(repeating: 0, count: 7)
        if selected.contains(.workoutStart) {
            for session in sessions {
                weekdays[(calendar.component(.weekday, from: session.date) + 5) % 7] += 1
                if let index = buckets.firstIndex(where: { session.date >= $0.start && session.date < $0.end }) {
                    buckets[index].workouts += 1
                    buckets[index].sets += session.rows.count
                }
            }
        }
        self.buckets = buckets
        self.weekdays = weekdays
        intervalTitle = result.1
        trends = Self.makeTrends(document, sessions: sessions, buckets: buckets, exerciseCounts: exerciseCounts)
    }

    private static func categoryOrder(_ lhs: Category, _ rhs: Category) -> Bool {
        let left = lhs.count + lhs.secondary
        let right = rhs.count + rhs.secondary
        if left != right { return left > right }
        return lhs.name < rhs.name
    }

    private static func makeBuckets(_ document: WorkoutExportDocument, calendar: Calendar) -> ([Bucket], String) {
        let formatter = WorkoutExportDocument.formatter("yyyy-MM-dd", timeZone: calendar.timeZone)
        guard let start = formatter.date(from: document.startDay), let end = formatter.date(from: document.endDay) else { return ([], "") }
        let days = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let component: Calendar.Component
        let stride: Int
        let title: String
        let pattern: String
        switch days {
        case ...31: (component, stride, title, pattern) = (.day, 1, "Daily", "MMM d")
        case ...210: (component, stride, title, pattern) = (.weekOfYear, 1, "Weekly", "MMM d")
        case ...900: (component, stride, title, pattern) = (.month, 1, "Monthly", "MMM yy")
        case ...2700: (component, stride, title, pattern) = (.month, 3, "Every 3 months", "MMM yy")
        default:
            let years = (calendar.dateComponents([.year], from: start, to: end).year ?? 0) + 1
            stride = max(1, Int(ceil(Double(years) / 30)))
            component = .year
            title = stride == 1 ? "Yearly" : "Every \(stride) years"
            pattern = "yyyy"
        }
        let label = WorkoutExportDocument.formatter(pattern, timeZone: calendar.timeZone)
        var cursor = calendar.dateInterval(of: component, for: start)?.start ?? start
        var buckets: [Bucket] = []
        while cursor <= end {
            guard let next = calendar.date(byAdding: component, value: stride, to: cursor), next > cursor else { break }
            buckets.append(Bucket(start: cursor, end: next, label: label.string(from: cursor)))
            cursor = next
        }
        return (buckets, title)
    }

    private static func makeTrends(
        _ document: WorkoutExportDocument, sessions: [Session], buckets: [Bucket], exerciseCounts: [String: Double]
    ) -> [Trend] {
        guard document.columns.contains(.exercise), document.columns.contains(.workoutStart), sessions.count >= 3 else { return [] }
        let selected = Set(document.columns)
        var byName: [String: [UUID: [WorkoutExportColumn: Double]]] = [:]
        for row in document.records {
            let name = row.value(.exercise).text
            for column in [WorkoutExportColumn.weight, .reps, .seconds] where selected.contains(column) {
                guard let value = row.value(column).finiteNumber, value > 0 else { continue }
                let current = byName[name]?[row.workoutID]?[column] ?? 0
                byName[name, default: [:]][row.workoutID, default: [:]][column] = max(current, value)
            }
        }
        let names = byName.keys.sorted {
            let left = exerciseCounts[$0] ?? 0
            let right = exerciseCounts[$1] ?? 0
            return left == right ? $0 < $1 : left > right
        }
        var results: [Trend] = []
        for name in names {
            guard let valuesBySession = byName[name] else { continue }
            let metric = [WorkoutExportColumn.weight, .reps, .seconds].first { column in
                valuesBySession.values.filter { $0[column] != nil }.count >= 3
            }
            guard let metric else { continue }
            var values: [Double?] = Array(repeating: nil, count: buckets.count)
            var count = 0
            for session in sessions {
                guard let value = valuesBySession[session.id]?[metric],
                      let index = buckets.firstIndex(where: { session.date >= $0.start && session.date < $0.end }) else { continue }
                values[index] = max(values[index] ?? value, value)
                count += 1
            }
            let title = metric == .weight ? "Heaviest logged set" : metric == .reps ? "Most reps in a set" : "Longest timed set"
            let unit = metric == .weight ? document.weightUnit ?? "logged weight" : metric == .reps ? "reps" : "seconds"
            guard values.compactMap({ $0 }).count >= 2 else { continue }
            results.append(Trend(name: name, metric: title, unit: unit, values: values, sessionCount: count))
            if results.count == 4 { break }
        }
        return results
    }
}

extension WorkoutExportValue {
    nonisolated var finiteNumber: Double? {
        switch self {
        case .number(let number): return number.isFinite ? number : nil
        case .integer(let number): return Double(number)
        default: return nil
        }
    }
}
