import Foundation

enum WorkoutExportError: LocalizedError {
    case invalidDateRange
    case noWorkoutsInRange
    case noSetsInRange
    case noExercisesInRange
    case noColumnsSelected

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return "Invalid date range"
        case .noWorkoutsInRange:
            return "No workouts found in that date range"
        case .noSetsInRange:
            return "No logged sets found in that date range"
        case .noExercisesInRange:
            return "No exercises found in that date range"
        case .noColumnsSelected:
            return "Select at least one export field"
        }
    }
}

nonisolated enum WorkoutExportColumn: String, CaseIterable, Hashable, Identifiable, Sendable {
    case workoutStart
    case workoutName
    case gymName
    case duration
    case durationText
    case exercise
    case parentExercise
    case side
    case tags
    case setNumber
    case weight
    case reps
    case distance
    case seconds

    static let defaultColumns = WorkoutExportColumn.allCases

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workoutStart:
            return "Workout Start"
        case .workoutName:
            return "Workout Name"
        case .gymName:
            return "Gym"
        case .duration:
            return "Workout Duration (seconds)"
        case .durationText:
            return "Logged Duration"
        case .exercise:
            return "Exercise"
        case .parentExercise:
            return "Parent Exercise"
        case .side:
            return "Side"
        case .tags:
            return "Muscle Roles"
        case .setNumber:
            return "Set"
        case .weight:
            return "Weight"
        case .reps:
            return "Reps"
        case .distance:
            return "Distance (unit unspecified)"
        case .seconds:
            return "Set Duration (seconds)"
        }
    }

    var subtitle: String {
        switch self {
        case .workoutStart:
            return "Start date and time with a time-zone offset."
        case .workoutName:
            return "Workout title."
        case .gymName:
            return "Assigned gym profile name."
        case .duration:
            return "Numeric duration in seconds; blank when the logged value cannot be parsed."
        case .durationText:
            return "The original duration as logged, such as 45m or 1h 5m."
        case .exercise:
            return "Exercise name."
        case .parentExercise:
            return "Rollup parent for side-specific exercise variants."
        case .side:
            return "Left, right, or unilateral side metadata for variants."
        case .tags:
            return "Primary and secondary exercise muscles with their roles."
        case .setNumber:
            return "Set number."
        case .weight:
            return "Logged set weight."
        case .reps:
            return "Logged rep count."
        case .distance:
            return "Distance as logged. The app does not store a distance unit."
        case .seconds:
            return "Time for duration-based sets."
        }
    }

    var systemImage: String {
        switch self {
        case .workoutStart:
            return "calendar"
        case .workoutName:
            return "text.badge.checkmark"
        case .gymName:
            return "mappin.and.ellipse"
        case .duration, .durationText:
            return "timer"
        case .exercise:
            return "dumbbell"
        case .parentExercise:
            return "rectangle.stack"
        case .side:
            return "arrow.left.and.right"
        case .tags:
            return "tag"
        case .setNumber:
            return "number"
        case .weight:
            return "scalemass"
        case .reps:
            return "repeat"
        case .distance:
            return "ruler"
        case .seconds:
            return "stopwatch"
        }
    }

    func header(weightHeader: String) -> String {
        switch self {
        case .weight:
            return weightHeader
        default:
            return title
        }
    }
}

struct WorkoutCSVExporter {
    /// One complete record per set, with stable IDs, numeric values, and selected columns.
    /// Missing values are empty cells; no row inherits context from an earlier row.
    nonisolated static func exportWorkoutHistoryCSV(
        workouts: [Workout],
        startDate: Date,
        endDateInclusive: Date,
        exerciseTagsByName: [String: String] = [:],
        gymNamesByWorkoutID: [UUID: String] = [:],
        selectedColumns: [WorkoutExportColumn] = WorkoutExportColumn.defaultColumns,
        intentionalBreaks: [IntentionalBreakRange] = [],
        includeIntentionalBreaks: Bool = false,
        weightUnit: String? = nil,
        resolver: ExerciseIdentityResolver = .empty,
        calendar: Calendar = .current
    ) throws -> Data {
        var data = Data()
        var wroteAnyLine = false

        try writeWorkoutHistoryCSVLines(
            workouts: workouts,
            startDate: startDate,
            endDateInclusive: endDateInclusive,
            exerciseTagsByName: exerciseTagsByName,
            gymNamesByWorkoutID: gymNamesByWorkoutID,
            selectedColumns: selectedColumns,
            intentionalBreaks: intentionalBreaks,
            includeIntentionalBreaks: includeIntentionalBreaks,
            weightUnit: weightUnit,
            resolver: resolver,
            calendar: calendar
        ) { line in
            if wroteAnyLine {
                data.append(contentsOf: [0x0D, 0x0A])
            }
            data.append(contentsOf: line.utf8)
            wroteAnyLine = true
        }

        return data
    }

    nonisolated static func exportWorkoutHistoryCSV(
        to destinationURL: URL,
        workouts: [Workout],
        startDate: Date,
        endDateInclusive: Date,
        exerciseTagsByName: [String: String] = [:],
        gymNamesByWorkoutID: [UUID: String] = [:],
        selectedColumns: [WorkoutExportColumn] = WorkoutExportColumn.defaultColumns,
        intentionalBreaks: [IntentionalBreakRange] = [],
        includeIntentionalBreaks: Bool = false,
        weightUnit: String? = nil,
        resolver: ExerciseIdentityResolver = .empty,
        calendar: Calendar = .current
    ) throws {
        try iCloudDocumentManager.writeFileAtomically(to: destinationURL) { handle in
            var wroteAnyLine = false

            try writeWorkoutHistoryCSVLines(
                workouts: workouts,
                startDate: startDate,
                endDateInclusive: endDateInclusive,
                exerciseTagsByName: exerciseTagsByName,
                gymNamesByWorkoutID: gymNamesByWorkoutID,
                selectedColumns: selectedColumns,
                intentionalBreaks: intentionalBreaks,
                includeIntentionalBreaks: includeIntentionalBreaks,
                weightUnit: weightUnit,
                resolver: resolver,
                calendar: calendar
            ) { line in
                if wroteAnyLine {
                    try handle.write(contentsOf: Data([0x0D, 0x0A]))
                }
                try handle.write(contentsOf: Data(line.utf8))
                wroteAnyLine = true
            }
        }
    }

    nonisolated static func makeWorkoutExportFileName(
        startDate: Date,
        endDateInclusive: Date,
        calendar: Calendar = .current
    ) throws -> String {
        _ = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let start = dateFormatter.string(from: calendar.startOfDay(for: startDate))
        let end = dateFormatter.string(from: calendar.startOfDay(for: endDateInclusive))
        let stamp = Int(Date().timeIntervalSince1970)
        return "workout_export_\(start)_\(end)_\(stamp).csv"
    }

    /// Export a unique list of exercise names within a date range.
    /// If `includeTags` is true, adds a `Tags` column with primary and secondary roles.
    nonisolated static func exportExerciseListCSV(
        workouts: [Workout],
        startDate: Date,
        endDateInclusive: Date,
        includeTags: Bool,
        exerciseTagsByName: [String: String] = [:],
        resolver: ExerciseIdentityResolver = .empty,
        calendar: Calendar = .current
    ) throws -> Data {
        var data = Data()
        var wroteAnyLine = false

        try writeExerciseListCSVLines(
            workouts: workouts,
            startDate: startDate,
            endDateInclusive: endDateInclusive,
            includeTags: includeTags,
            exerciseTagsByName: exerciseTagsByName,
            resolver: resolver,
            calendar: calendar
        ) { line in
            if wroteAnyLine {
                data.append(contentsOf: [0x0D, 0x0A])
            }
            data.append(contentsOf: line.utf8)
            wroteAnyLine = true
        }

        return data
    }

    nonisolated static func exportExerciseListCSV(
        to destinationURL: URL,
        workouts: [Workout],
        startDate: Date,
        endDateInclusive: Date,
        includeTags: Bool,
        exerciseTagsByName: [String: String] = [:],
        resolver: ExerciseIdentityResolver = .empty,
        calendar: Calendar = .current
    ) throws {
        try iCloudDocumentManager.writeFileAtomically(to: destinationURL) { handle in
            var wroteAnyLine = false

            try writeExerciseListCSVLines(
                workouts: workouts,
                startDate: startDate,
                endDateInclusive: endDateInclusive,
                includeTags: includeTags,
                exerciseTagsByName: exerciseTagsByName,
                resolver: resolver,
                calendar: calendar
            ) { line in
                if wroteAnyLine {
                    try handle.write(contentsOf: Data([0x0D, 0x0A]))
                }
                try handle.write(contentsOf: Data(line.utf8))
                wroteAnyLine = true
            }
        }
    }

    nonisolated static func makeExerciseListExportFileName(
        startDate: Date,
        endDateInclusive: Date,
        includeTags: Bool,
        calendar: Calendar = .current
    ) throws -> String {
        _ = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let start = dateFormatter.string(from: calendar.startOfDay(for: startDate))
        let end = dateFormatter.string(from: calendar.startOfDay(for: endDateInclusive))
        let stamp = Int(Date().timeIntervalSince1970)
        let suffix = includeTags ? "tags" : "names"
        return "exercise_export_\(suffix)_\(start)_\(end)_\(stamp).csv"
    }

    nonisolated static func makeExerciseHistoryExportFileName(
        startDate: Date,
        endDateInclusive: Date,
        selectedExerciseCount: Int,
        calendar: Calendar = .current
    ) throws -> String {
        _ = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let start = dateFormatter.string(from: calendar.startOfDay(for: startDate))
        let end = dateFormatter.string(from: calendar.startOfDay(for: endDateInclusive))
        let stamp = Int(Date().timeIntervalSince1970)
        return "exercise_history_\(selectedExerciseCount)_\(start)_\(end)_\(stamp).csv"
    }

    nonisolated static func makeWorkoutDatesExportFileName(
        startDate: Date,
        endDateInclusive: Date,
        selectedDateCount: Int,
        calendar: Calendar = .current
    ) throws -> String {
        _ = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let start = dateFormatter.string(from: calendar.startOfDay(for: startDate))
        let end = dateFormatter.string(from: calendar.startOfDay(for: endDateInclusive))
        let stamp = Int(Date().timeIntervalSince1970)
        return "workout_dates_\(selectedDateCount)_\(start)_\(end)_\(stamp).csv"
    }

    nonisolated static func makeMuscleGroupExportFileName(
        startDate: Date,
        endDateInclusive: Date,
        selectedGroupCount: Int,
        calendar: Calendar = .current
    ) throws -> String {
        _ = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let start = dateFormatter.string(from: calendar.startOfDay(for: startDate))
        let end = dateFormatter.string(from: calendar.startOfDay(for: endDateInclusive))
        let stamp = Int(Date().timeIntervalSince1970)
        return "muscle_group_export_\(selectedGroupCount)_\(start)_\(end)_\(stamp).csv"
    }

    // MARK: - Helpers

    private nonisolated static func normalizedDayRange(
        startDate: Date,
        endDateInclusive: Date,
        calendar: Calendar
    ) throws -> (start: Date, endExclusive: Date) {
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDateInclusive)
        guard startDay <= endDay else {
            throw WorkoutExportError.invalidDateRange
        }
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        return (startDay, endExclusive)
    }

    // swiftlint:disable:next function_parameter_count
    private nonisolated static func writeWorkoutHistoryCSVLines(
        workouts: [Workout],
        startDate: Date,
        endDateInclusive: Date,
        exerciseTagsByName: [String: String],
        gymNamesByWorkoutID: [UUID: String],
        selectedColumns: [WorkoutExportColumn],
        intentionalBreaks: [IntentionalBreakRange],
        includeIntentionalBreaks: Bool,
        weightUnit: String?,
        resolver: ExerciseIdentityResolver,
        calendar: Calendar,
        writeLine: (String) throws -> Void
    ) throws {
        let document = try WorkoutExportDocument(
            workouts: workouts, startDate: startDate, endDateInclusive: endDateInclusive,
            exerciseTagsByName: exerciseTagsByName, gymNamesByWorkoutID: gymNamesByWorkoutID,
            selectedColumns: selectedColumns, intentionalBreaks: intentionalBreaks,
            includeIntentionalBreaks: includeIntentionalBreaks, weightUnit: weightUnit,
            resolver: resolver, calendar: calendar
        )
        try document.writeCSVLines(writeLine)
    }

    private nonisolated static func writeExerciseListCSVLines(
        workouts: [Workout],
        startDate: Date,
        endDateInclusive: Date,
        includeTags: Bool,
        exerciseTagsByName: [String: String],
        resolver: ExerciseIdentityResolver,
        calendar: Calendar,
        writeLine: (String) throws -> Void
    ) throws {
        let range = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let filtered = workouts
            .filter { workout in
                workout.date >= range.start && workout.date < range.endExclusive
            }

        let exerciseNames = Set(filtered.flatMap { $0.exercises.map(\.name) })
        let sortedNames = exerciseNames.sorted { lhs, rhs in
            let insensitive = lhs.localizedCaseInsensitiveCompare(rhs)
            if insensitive != .orderedSame { return insensitive == .orderedAscending }
            return lhs.localizedCompare(rhs) == .orderedAscending
        }

        guard !sortedNames.isEmpty else {
            throw WorkoutExportError.noExercisesInRange
        }

        if includeTags {
            try writeLine("Exercise,Tags,Parent Exercise,Side")
            for name in sortedNames {
                let identity = resolver.displayIdentity(for: name)
                let row = [
                    name, exerciseTagsByName[name] ?? "",
                    identity.isVariant ? identity.aggregateName : "", identity.sideLabel ?? ""
                ]
                try writeLine(row.map(csvEscape).joined(separator: ","))
            }
        } else {
            try writeLine("Exercise")
            for name in sortedNames {
                try writeLine(csvEscape(name))
            }
        }
    }

    private nonisolated static func csvEscape(_ field: String) -> String {
        WorkoutExportValue.text(field).csv
    }
}
