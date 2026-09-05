import Foundation

nonisolated enum WorkoutExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case json
    case report
    case pdf

    var id: String { rawValue }
    var fileExtension: String { self == .report ? "html" : rawValue }
    var title: String {
        switch self {
        case .csv: return "CSV"
        case .json: return "JSON"
        case .report: return "HTML"
        case .pdf: return "PDF"
        }
    }
    var subtitle: String {
        switch self {
        case .csv: return "A spreadsheet table with complete rows and consistent columns."
        case .json: return "Structured data with field definitions for AI tools and analysis."
        case .report: return "A formatted workout journal you can read in a browser or print."
        case .pdf: return "A visual training report with charts and an optional workout journal."
        }
    }
    var systemImage: String {
        switch self {
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        case .report: return "doc.richtext"
        case .pdf: return "chart.bar.doc.horizontal"
        }
    }

    func fileName(from csvFileName: String) -> String {
        URL(fileURLWithPath: csvFileName).deletingPathExtension().lastPathComponent + "." + fileExtension
    }
}

/// Typed cells are shared by CSV, JSON, and the report. Text escaping never changes numeric values.
nonisolated enum WorkoutExportValue: Encodable, Equatable, Sendable {
    case text(String)
    case number(Double)
    case integer(Int)
    case muscles([WorkoutExportMuscle])
    case empty

    var text: String {
        switch self {
        case .text(let value): return value
        case .number(let value):
            guard value.isFinite else { return "" }
            let result = String(value)
            return result.hasSuffix(".0") ? String(result.dropLast(2)) : result
        case .integer(let value): return String(value)
        case .muscles(let values): return values.map { "\($0.role): \($0.name)" }.joined(separator: "; ")
        case .empty: return ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value): try container.encode(value)
        case .number(let value):
            if value.isFinite { try container.encode(value) } else { try container.encodeNil() }
        case .integer(let value): try container.encode(value)
        case .muscles(let values): try container.encode(values)
        case .empty: try container.encodeNil()
        }
    }

    var csv: String {
        var value = text
        // Spreadsheet applications may execute formula-looking text even in quoted cells.
        // JSON and HTML retain the original text; only CSV text gets a literal-text prefix.
        if case .text = self,
           let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first,
           "=+-@".contains(first) {
            value = "'" + value
        }
        if value.contains(where: { "\",\r\n".contains($0) }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

nonisolated struct WorkoutExportMuscle: Encodable, Equatable, Sendable {
    let name: String
    let role: String
}

nonisolated struct WorkoutExportRecord: Sendable {
    let workoutID: UUID
    let exerciseID: UUID
    let setID: UUID
    let startedAt: Date
    let values: [WorkoutExportColumn: WorkoutExportValue]
    let muscles: [WorkoutExportMuscle]?

    func value(_ column: WorkoutExportColumn) -> WorkoutExportValue { values[column] ?? .empty }
}

nonisolated struct WorkoutExportBreak: Encodable, Sendable {
    let id: UUID
    let startDate: String
    let endDate: String
    let name: String?
    let days: Int
    // Used for chronological CSV ordering; the serialized dates are local calendar days.
    let sortDate: Date

    enum CodingKeys: String, CodingKey {
        case id, name, days
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

/// A single snapshot keeps all formats on the same filtering, ordering, and value contract.
nonisolated struct WorkoutExportDocument: Sendable {
    let columns: [WorkoutExportColumn]
    let records: [WorkoutExportRecord]
    let breaks: [WorkoutExportBreak]
    let includesBreaks: Bool
    let startDay: String
    let endDay: String
    let timeZone: String
    let weightUnit: String?

    init(
        workouts: [Workout], startDate: Date, endDateInclusive: Date,
        exerciseTagsByName: [String: String] = [:],
        exerciseMusclesByName: [String: [WorkoutExportMuscle]] = [:],
        gymNamesByWorkoutID: [UUID: String] = [:],
        selectedColumns: [WorkoutExportColumn] = WorkoutExportColumn.defaultColumns,
        intentionalBreaks: [IntentionalBreakRange] = [], includeIntentionalBreaks: Bool = false,
        weightUnit: String? = nil, resolver: ExerciseIdentityResolver = .empty, calendar: Calendar = .current
    ) throws {
        var seen = Set<WorkoutExportColumn>()
        columns = selectedColumns.filter { seen.insert($0).inserted }
        guard !columns.isEmpty else { throw WorkoutExportError.noColumnsSelected }
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDateInclusive)
        guard start <= end, let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) else {
            throw WorkoutExportError.invalidDateRange
        }
        let filtered = workouts.filter { $0.date >= start && $0.date < endExclusive }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard !filtered.isEmpty else { throw WorkoutExportError.noWorkoutsInRange }

        let dayFormatter = Self.formatter("yyyy-MM-dd", timeZone: calendar.timeZone)
        let timestampFormatter = Self.formatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", timeZone: calendar.timeZone)
        startDay = dayFormatter.string(from: start)
        endDay = dayFormatter.string(from: end)
        timeZone = calendar.timeZone.identifier
        let unit = weightUnit?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.weightUnit = unit.flatMap { $0.isEmpty ? nil : $0 }
        includesBreaks = includeIntentionalBreaks

        records = filtered.flatMap { workout in
            workout.exercises.flatMap { exercise -> [WorkoutExportRecord] in
                let identity = resolver.displayIdentity(for: exercise.name)
                let context: [WorkoutExportColumn: WorkoutExportValue] = [
                    .workoutStart: .text(timestampFormatter.string(from: workout.date)),
                    .workoutName: .text(workout.name),
                    .gymName: Self.optionalText(gymNamesByWorkoutID[workout.id]),
                    .duration: Self.durationSeconds(workout.duration).map(WorkoutExportValue.number) ?? .empty,
                    .durationText: .text(workout.duration),
                    .exercise: .text(exercise.name),
                    .parentExercise: identity.isVariant ? .text(identity.aggregateName) : .empty,
                    .side: Self.optionalText(identity.sideLabel),
                    .tags: Self.optionalText(exerciseTagsByName[exercise.name])
                ]
                return exercise.sets.sorted {
                    if $0.setOrder != $1.setOrder { return $0.setOrder < $1.setOrder }
                    if $0.date != $1.date { return $0.date < $1.date }
                    return $0.id.uuidString < $1.id.uuidString
                }.map { set in
                    let values = context.merging([
                        .setNumber: .integer(set.setOrder), .weight: .number(set.weight),
                        .reps: .integer(set.reps), .distance: .number(set.distance), .seconds: .number(set.seconds)
                    ]) { _, new in new }
                    return WorkoutExportRecord(
                        workoutID: workout.id, exerciseID: exercise.id, setID: set.id, startedAt: workout.date,
                        values: values, muscles: exerciseMusclesByName[exercise.name]
                    )
                }
            }
        }
        guard !records.isEmpty else { throw WorkoutExportError.noSetsInRange }

        breaks = includeIntentionalBreaks ? intentionalBreaks.compactMap { saved in
            let clippedStart = max(start, calendar.startOfDay(for: saved.startDate))
            let clippedEnd = min(end, calendar.startOfDay(for: saved.endDate))
            guard clippedStart <= clippedEnd else { return nil }
            return WorkoutExportBreak(
                id: saved.id, startDate: dayFormatter.string(from: clippedStart),
                endDate: dayFormatter.string(from: clippedEnd), name: saved.displayName,
                days: (calendar.dateComponents([.day], from: clippedStart, to: clippedEnd).day ?? 0) + 1,
                sortDate: clippedStart
            )
        }.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            if $0.endDate != $1.endDate { return $0.endDate < $1.endDate }
            return $0.id.uuidString < $1.id.uuidString
        } : []
    }

    static func formatter(_ pattern: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter
    }

    private static func optionalText(_ value: String?) -> WorkoutExportValue {
        guard let value, !value.isEmpty else { return .empty }
        return .text(value)
    }

    /// No estimated/default duration is exported as observed data. Unrecognized input stays null.
    static func durationSeconds(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains(":") {
            let parts = value.components(separatedBy: ":")
            let numbers = parts.compactMap(Double.init)
            guard (2...3).contains(parts.count), numbers.count == parts.count,
                  numbers.allSatisfy({ $0.isFinite && $0 >= 0 }),
                  numbers.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
            let total = numbers.reduce(0) { $0 * 60 + $1 }
            return total.isFinite ? total : nil
        }
        if let minutes = Double(value), minutes.isFinite, minutes >= 0 {
            return (minutes * 60).isFinite ? minutes * 60 : nil
        }
        guard let regex = try? NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)\\s*([hms])") else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        let matches = regex.matches(in: value, range: range)
        guard !matches.isEmpty,
              regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var total = 0.0
        var seenUnits = Set<String>()
        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: value),
                  let unitRange = Range(match.range(at: 2), in: value),
                  let number = Double(value[numberRange]) else { return nil }
            let unit = String(value[unitRange])
            guard seenUnits.insert(unit).inserted else { return nil }
            total += number * (unit == "h" ? 3600 : unit == "m" ? 60 : 1)
        }
        return total.isFinite ? total : nil
    }
}
