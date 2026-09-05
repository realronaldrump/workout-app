import Foundation

extension WorkoutExportColumn {
    nonisolated var key: String {
        switch self {
        case .workoutStart: return "workout_start"
        case .workoutName: return "workout_name"
        case .gymName: return "gym"
        case .duration: return "workout_duration_seconds"
        case .durationText: return "logged_duration"
        case .exercise: return "exercise"
        case .parentExercise: return "parent_exercise"
        case .side: return "side"
        case .tags: return "muscle_roles"
        case .setNumber: return "set_number"
        case .weight: return "weight"
        case .reps: return "reps"
        case .distance: return "distance"
        case .seconds: return "set_duration_seconds"
        }
    }

    nonisolated var valueType: String {
        switch self {
        case .setNumber, .reps: return "integer"
        case .duration, .weight, .distance, .seconds: return "number"
        default: return "string"
        }
    }

    nonisolated var isSetValue: Bool {
        switch self {
        case .setNumber, .weight, .reps, .distance, .seconds: return true
        default: return false
        }
    }
}

extension WorkoutExportDocument {
    nonisolated func header(for column: WorkoutExportColumn) -> String {
        column.header(weightHeader: weightUnit.map { "Weight (\($0))" } ?? "Weight (unit unspecified)")
    }

    nonisolated func writeCSVLines(_ writeLine: (String) throws -> Void) throws {
        let identifiers = ["Workout ID", "Exercise ID", "Set ID"]
        let breakHeaders = includesBreaks ? ["Break ID", "Break Start", "Break End", "Break Name", "Break Days"] : []
        let headers = ["Record Type"] + columns.map { header(for: $0) } + identifiers + breakHeaders
        try writeLine(headers.map { WorkoutExportValue.text($0).csv }.joined(separator: ","))
        var nextBreak = 0

        func writeBreak(_ item: WorkoutExportBreak) throws {
            let cells: [WorkoutExportValue] = [.text("break")] +
                Array(repeating: .empty, count: columns.count + identifiers.count) + [
                    .text(item.id.uuidString), .text(item.startDate), .text(item.endDate),
                    item.name.map(WorkoutExportValue.text) ?? .empty, .integer(item.days)
                ]
            try writeLine(cells.map(\.csv).joined(separator: ","))
        }

        for record in records {
            while nextBreak < breaks.count, breaks[nextBreak].sortDate <= record.startedAt {
                try writeBreak(breaks[nextBreak])
                nextBreak += 1
            }
            let cells: [WorkoutExportValue] = [.text("set")] + columns.map { record.value($0) } + [
                .text(record.workoutID.uuidString), .text(record.exerciseID.uuidString), .text(record.setID.uuidString)
            ] + Array(repeating: .empty, count: breakHeaders.count)
            try writeLine(cells.map(\.csv).joined(separator: ","))
        }
        while nextBreak < breaks.count {
            try writeBreak(breaks[nextBreak])
            nextBreak += 1
        }
    }

    nonisolated func jsonData() throws -> Data {
        let rows = records.map { record in
            var row = Dictionary(uniqueKeysWithValues: columns.map { ($0.key, record.value($0)) })
            row["workout_id"] = .text(record.workoutID.uuidString)
            row["exercise_id"] = .text(record.exerciseID.uuidString)
            row["set_id"] = .text(record.setID.uuidString)
            if columns.contains(.tags) {
                row["muscle_assignments"] = record.muscles.map(WorkoutExportValue.muscles) ?? .empty
            }
            return row
        }
        let payload = WorkoutExportJSON(
            schemaVersion: 2, dataset: "workout_history", dateRange: .init(start: startDay, endInclusive: endDay),
            timeZone: timeZone, includesBreaks: includesBreaks,
            notes: [
                "Each record is one set. Workout and exercise fields repeat on every record.",
                "Dates use the Gregorian calendar. Workout timestamps include a UTC offset in the export time zone, not a recorded workout location.",
                "Null means missing, unrecognized, or non-finite. Stored zero values are preserved.",
                "Distance units are not stored by the app. Values are exported as logged without conversion.",
                "Workout duration is repeated per set; aggregate it once per workout_id.",
                "Break dates are inclusive and clipped to the export range. Breaks are context, not sets."
            ], fields: jsonFields, records: rows, breaks: breaks
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(payload)
    }

    private nonisolated var jsonFields: [WorkoutExportJSON.Field] {
        var fields = columns.map { column in
            let unit: String?
            switch column {
            case .duration, .seconds: unit = "seconds"
            case .weight: unit = weightUnit
            default: unit = nil
            }
            return WorkoutExportJSON.Field(
                key: column.key, label: header(for: column), type: column.valueType,
                unit: unit, description: column.subtitle
            )
        }
        for name in ["workout", "exercise", "set"] {
            fields.append(.init(key: "\(name)_id", label: "\(name.capitalized) ID", type: "string", unit: nil,
                                description: "The stored UUID of this \(name) record."))
        }
        if columns.contains(.tags) {
            fields.append(.init(key: "muscle_assignments", label: "Muscle Assignments", type: "array", unit: nil,
                                description: "Objects with name and role (primary or secondary); null if unavailable."))
        }
        return fields
    }

    nonisolated func write(to destination: URL, format: WorkoutExportFormat, includePDFJournal: Bool = false) throws {
        try iCloudDocumentManager.writeFileAtomically(to: destination) { handle in
            switch format {
            case .csv:
                var first = true
                try writeCSVLines { line in
                    if !first { try handle.write(contentsOf: Data([0x0D, 0x0A])) }
                    try handle.write(contentsOf: Data(line.utf8))
                    first = false
                }
            case .json:
                try handle.write(contentsOf: jsonData())
            case .report:
                try handle.write(contentsOf: Data(WorkoutReportRenderer.render(self).utf8))
            case .pdf:
                try WorkoutPDFRenderer.write(self, to: handle, includeJournal: includePDFJournal)
            }
        }
    }
}

private nonisolated struct WorkoutExportJSON: Encodable {
    struct DateRange: Encodable { let start: String; let endInclusive: String }
    struct Field: Encodable {
        let key: String
        let label: String
        let type: String
        let unit: String?
        let description: String
    }
    let schemaVersion: Int
    let dataset: String
    let dateRange: DateRange
    let timeZone: String
    let includesBreaks: Bool
    let notes: [String]
    let fields: [Field]
    let records: [[String: WorkoutExportValue]]
    let breaks: [WorkoutExportBreak]
}
