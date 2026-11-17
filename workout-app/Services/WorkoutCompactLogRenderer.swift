import Foundation

/// A lossless analytical log. Short, export-local references replace repeated workout
/// context and exercise metadata. Column names appear once; constant columns move to
/// defaults. Only identical consecutive sets may be run-length encoded.
///
/// This is an analysis format, not a restore format: database UUIDs and derived totals
/// are deliberately absent. Text cells use JSON escaping, never sanitization.
nonisolated enum WorkoutCompactLogRenderer {
    static let formatVersion = 1

    /// A rough planning aid, not a tokenizer. Numeric density and model vocabulary vary.
    static func estimatedTokenCount(characters: Int) -> Int {
        Int((Double(max(0, characters)) / 3).rounded(.up))
    }

    static func render(_ document: WorkoutExportDocument) -> String {
        let selected = Set(document.columns)
        let contextColumns = document.columns.filter { [.workoutName, .gymName].contains($0) }
        let exerciseColumns = document.columns.filter {
            [.exercise, .parentExercise, .side, .tags].contains($0)
        }
        let workoutColumns = document.columns.filter {
            [.workoutStart, .duration, .durationText].contains($0)
        }
        let setColumns = document.columns.filter(\.isSetValue)
        let workouts = group(document.records)
        let includesSetTimestamps = selected.contains(.workoutStart) && document.records.contains { record in
            record.loggedAt.map { $0 != record.startedAt } ?? false
        }
        let timestamp = WorkoutExportDocument.formatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", timeZone: TimeZone(identifier: document.timeZone) ?? .gmt)
        let includesEndTimestamps = selected.contains(.workoutStart) && document.records.contains { $0.endedAt != nil }
        let implicitSetNumbers = selected.contains(.setNumber) && workouts.allSatisfy { workout in
            workout.allSatisfy { exercise in
                exercise.enumerated().allSatisfy { index, record in
                    record.value(.setNumber) == .integer(index + 1)
                }
            }
        }

        let includesCountLabels = selected.contains(.reps) && document.records.contains { $0.countLabel != nil }
        var contexts = DictionaryTable(prefix: "c", fields: contextColumns.map(\.key))
        var exercises = DictionaryTable(
            prefix: "e", fields: exerciseColumns.map(\.key)
                + (selected.contains(.tags) ? ["muscle_assignments"] : [])
                + (includesCountLabels ? ["reps_label"] : [])
        )
        var contextIDs: [String] = []
        var exerciseIDs: [[String]] = []
        var workoutRows: [[WorkoutExportValue]] = []
        var setRows: [[WorkoutExportValue]] = []
        let explicitSetColumns = setColumns.filter { $0 != .setNumber || !implicitSetNumbers }

        for workout in workouts {
            guard let first = workout.first?.first else { continue }
            contextIDs.append(contexts.insert(contextColumns.map { first.value($0) }))
            var workoutValues = workoutColumns.map { first.value($0) }
            if includesEndTimestamps {
                workoutValues.append(first.endedAt.map { .text(timestamp.string(from: $0)) } ?? .empty)
            }
            workoutRows.append(workoutValues)
            exerciseIDs.append(workout.map { exercise in
                let record = exercise[0]
                var values = exerciseColumns.map { record.value($0) }
                if selected.contains(.tags) {
                    values.append(record.muscles.map(WorkoutExportValue.muscles) ?? .empty)
                }
                if includesCountLabels { values.append(.text(record.countLabel ?? "reps")) }
                return exercises.insert(values)
            })
            setRows += workout.flatMap { $0.map { record in
                var values = explicitSetColumns.map { record.value($0) }
                if includesSetTimestamps {
                    values.append(record.loggedAt.map { .text(timestamp.string(from: $0)) } ?? .empty)
                }
                return values
            } }
        }

        let workoutTable = Columns(fields: workoutColumns.map(\.key) + (includesEndTimestamps ? ["workout_ended_at"] : []), rows: workoutRows)
        let setTable = Columns(fields: explicitSetColumns.map(\.key) + (includesSetTimestamps ? ["set_timestamp"] : []), rows: setRows)
        let contextTable = Columns(fields: contexts.fields, rows: contexts.rows)
        let exerciseTable = Columns(fields: exercises.fields, rows: exercises.rows)
        let hasContext = !contextTable.fields.isEmpty
        var defaults = contextTable.defaults.merging(exerciseTable.defaults) { first, _ in first }
        defaults.merge(workoutTable.defaults) { first, _ in first }
        defaults.merge(setTable.defaults) { first, _ in first }

        var lines = [
            "TRAINING_LOG \(formatVersion)",
            "range \(document.startDay)..\(document.endDay); timezone \(quoted(document.timeZone)); breaks \(document.includesBreaks ? "included" : "excluded")",
            "scope \(quoted(document.selectionScope)); workout durations describe whole sessions, including when exercises are filtered.",
            "Tabs separate cells; text is JSON-quoted; null means missing, never zero. Defaults apply to every record.",
            "C and E are lookup tables; W and S declare workout and set column order.",
            "Each W starts a workout. Each e row is one exercise occurrence; semicolons separate sets in logged order. N*(tuple) repeats N consecutive sets."
        ]
        if selected.contains(.weight) {
            lines.append("weight_unit \(document.weightUnit.map(quoted) ?? "null")")
        }
        if selected.contains(.distance) { lines.append("distance_unit null (not recorded)") }
        if selected.contains(.duration) || selected.contains(.seconds) {
            lines.append("Durations ending in seconds are seconds; logged_duration is original text (bare numbers mean minutes).")
        }
        if includesCountLabels { lines.append("reps_label gives the meaning of count values stored in reps (for example, floors or steps).") }
        if selected.contains(.tags) { lines.append("muscle_assignments: current [name,role] pairs; null=unavailable, []=none.") }
        if includesSetTimestamps { lines.append("set_timestamp preserves a distinct recorded set time; it is not an inferred rest interval.") }
        if implicitSetNumbers { lines.append("set_number: 1..N within each exercise occurrence, after expanding repeats.") }
        if !defaults.isEmpty {
            lines.append("defaults {" + defaults.keys.sorted().map { quoted($0) + ":" + cell(defaults[$0]!) }.joined(separator: ",") + "}")
        }

        if hasContext {
            lines += ["", "C[" + (["id"] + contextTable.fields).joined(separator: ",") + "]"]
            for (index, row) in contextTable.rows.enumerated() {
                lines.append((["c\(index + 1)"] + row.map(cell)).joined(separator: "\t"))
            }
        }
        lines += ["", "E[" + (["id"] + exerciseTable.fields).joined(separator: ",") + "]"]
        for (index, row) in exerciseTable.rows.enumerated() {
            lines.append((["e\(index + 1)"] + row.map(cell)).joined(separator: "\t"))
        }
        lines += [
            "", "W[" + ((hasContext ? ["context"] : []) + workoutTable.fields).joined(separator: ",") + "]",
            "S[" + setTable.fields.joined(separator: ",") + "]"
        ]
        var setIndex = 0
        for (index, workout) in workouts.enumerated() {
            lines.append((["W"] + (hasContext ? [contextIDs[index]] : []) + workoutTable.rows[index].map(cell)).joined(separator: "\t"))
            for (exerciseIndex, exercise) in workout.enumerated() {
                let tokens = exercise.map { _ in
                    defer { setIndex += 1 }
                    return setTable.rows[setIndex].map(cell).joined(separator: ",")
                }
                lines.append(exerciseIDs[index][exerciseIndex] + "\t" + runs(tokens))
            }
        }
        if document.includesBreaks {
            lines += ["", "B[start_date,end_date,name,days] (inclusive, clipped to range; planned time off)"]
            for item in document.breaks {
                lines.append(["B", quoted(item.startDate), quoted(item.endDate), item.name.map(quoted) ?? "null", String(item.days)].joined(separator: "\t"))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func group(_ records: [WorkoutExportRecord]) -> [[[WorkoutExportRecord]]] {
        var result: [[[WorkoutExportRecord]]] = []
        var workoutID: UUID?
        var exerciseID: UUID?
        for record in records {
            if record.workoutID != workoutID {
                result.append([])
                workoutID = record.workoutID
                exerciseID = nil
            }
            if record.exerciseID != exerciseID {
                result[result.count - 1].append([])
                exerciseID = record.exerciseID
            }
            let w = result.count - 1
            result[w][result[w].count - 1].append(record)
        }
        return result
    }

    private static func runs(_ values: [String]) -> String {
        var result: [String] = []
        var start = 0
        while start < values.count {
            var end = start + 1
            while end < values.count, values[end] == values[start] { end += 1 }
            // Empty tuples still represent real sets when every set field is constant.
            let tuple = values[start].isEmpty ? "()" : values[start]
            result.append(end - start > 1 ? "\(end - start)*(\(values[start]))" : tuple)
            start = end
        }
        return result.joined(separator: ";")
    }

    /// JSON strings preserve delimiters, newlines, Unicode, and significant whitespace.
    private static func quoted(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        // Encoding a Swift String cannot fail: it has no unsupported numeric values.
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }

    private static func cell(_ value: WorkoutExportValue) -> String {
        switch value {
        case .text(let text): return quoted(text)
        case .empty: return "null"
        case .number(let number): return number.isFinite ? value.text : "null"
        case .integer: return value.text
        case .muscles(let muscles):
            return "[" + muscles.map { "[\(quoted($0.name)),\(quoted($0.role))]" }.joined(separator: ",") + "]"
        }
    }

    private struct DictionaryTable {
        let prefix: String
        let fields: [String]
        var rows: [[WorkoutExportValue]] = []
        private var ids: [String: String] = [:]

        init(prefix: String, fields: [String]) {
            self.prefix = prefix
            self.fields = fields
        }

        mutating func insert(_ values: [WorkoutExportValue]) -> String {
            let key = values.map(cell).joined(separator: "\t")
            if let id = ids[key] { return id }
            let id = prefix + String(rows.count + 1)
            rows.append(values)
            ids[key] = id
            return id
        }
    }

    /// Repeated values (including zero, null, and empty strings) are declared once,
    /// without converting missing values into observations.
    private struct Columns {
        let fields: [String]
        let rows: [[WorkoutExportValue]]
        let defaults: [String: WorkoutExportValue]

        init(fields: [String], rows: [[WorkoutExportValue]]) {
            var constants: [String: WorkoutExportValue] = [:]
            var retained: [Int] = []
            for (index, field) in fields.enumerated() {
                if let first = rows.first?[index], rows.allSatisfy({ cell($0[index]) == cell(first) }) {
                    constants[field] = first
                } else {
                    retained.append(index)
                }
            }
            self.fields = retained.map { fields[$0] }
            self.rows = rows.map { row in retained.map { row[$0] } }
            defaults = constants
        }
    }
}
