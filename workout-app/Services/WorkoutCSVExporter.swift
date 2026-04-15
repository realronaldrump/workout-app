import Foundation

enum WorkoutExportError: LocalizedError {
    case invalidDateRange
    case noWorkoutsInRange
    case noExercisesInRange
    case noColumnsSelected

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return "Invalid date range"
        case .noWorkoutsInRange:
            return "No workouts found in that date range"
        case .noExercisesInRange:
            return "No exercises found in that date range"
        case .noColumnsSelected:
            return "Select at least one CSV column"
        }
    }
}

nonisolated enum WorkoutExportColumn: String, CaseIterable, Hashable, Identifiable, Sendable {
    case workoutStart
    case workoutName
    case gymName
    case duration
    case exercise
    case tags
    case setNumber
    case weight
    case reps
    case distance
    case seconds

    static let defaultColumns: [WorkoutExportColumn] = [
        .workoutStart,
        .workoutName,
        .duration,
        .exercise,
        .tags,
        .setNumber,
        .weight,
        .reps,
        .distance,
        .seconds
    ]

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
            return "Duration"
        case .exercise:
            return "Exercise"
        case .tags:
            return "Tags"
        case .setNumber:
            return "Set"
        case .weight:
            return "Weight"
        case .reps:
            return "Reps"
        case .distance:
            return "Distance"
        case .seconds:
            return "Seconds"
        }
    }

    var subtitle: String {
        switch self {
        case .workoutStart:
            return "Start date and time for the workout."
        case .workoutName:
            return "Workout title."
        case .gymName:
            return "Assigned gym profile name."
        case .duration:
            return "Logged workout duration."
        case .exercise:
            return "Exercise name."
        case .tags:
            return "Exercise muscle tags."
        case .setNumber:
            return "Set number."
        case .weight:
            return "Logged set weight."
        case .reps:
            return "Logged rep count."
        case .distance:
            return "Distance for cardio sets."
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
        case .duration:
            return "timer"
        case .exercise:
            return "dumbbell"
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

private nonisolated struct WorkoutExportRowContext {
    let workoutStart: String
    let workoutName: String
    let gymName: String
    let duration: String
    let exerciseName: String
    let muscles: String
    let setOrder: String
    let weight: String
    let reps: String
    let distance: String
    let seconds: String
}

struct WorkoutCSVExporter {
    /// A compact, human-friendly export:
    /// - One CSV header.
    /// - Workout-level fields are only populated on the first set row of each workout.
    /// - Exercise + muscle tags are only populated on the first set row of each exercise.
    /// - Distance/Seconds columns are only included if selected and any set uses them.
    /// - Columns are emitted in the selected order.
    nonisolated static func exportWorkoutHistoryCSV(
        workouts: [Workout],
        startDate: Date,
        endDateInclusive: Date,
        exerciseTagsByName: [String: String] = [:],
        gymNamesByWorkoutID: [UUID: String] = [:],
        selectedColumns: [WorkoutExportColumn] = WorkoutExportColumn.defaultColumns,
        weightUnit: String? = nil,
        calendar: Calendar = .current
    ) throws -> Data {
        let requestedColumns = uniqueColumns(selectedColumns)
        guard !requestedColumns.isEmpty else {
            throw WorkoutExportError.noColumnsSelected
        }

        let range = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let filtered = workouts
            .filter { workout in
                workout.date >= range.start && workout.date < range.endExclusive
            }
            .sorted { $0.date < $1.date }

        guard !filtered.isEmpty else {
            throw WorkoutExportError.noWorkoutsInRange
        }

        let columns = columnsWithAvailableData(requestedColumns, for: filtered)
        guard !columns.isEmpty else {
            throw WorkoutExportError.noColumnsSelected
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let trimmedUnit = weightUnit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let weightHeader: String
        if let unit = trimmedUnit, !unit.isEmpty {
            weightHeader = "Weight (\(unit))"
        } else {
            weightHeader = "Weight"
        }

        var lines: [String] = []
        lines.reserveCapacity(filtered.count * 8)

        let header = columns.map { $0.header(weightHeader: weightHeader) }
        lines.append(header.joined(separator: ","))

        for workout in filtered {
            var didPrintWorkoutInfo = false
            // Preserve the order exercises were logged/recorded in the workout model.
            // (Some previous versions alphabetized here, which made exports differ from what users logged.)
            let exercises = workout.exercises
            for exercise in exercises {
                var didPrintExerciseInfo = false
                let sets = exercise.sets.sorted { lhs, rhs in
                    if lhs.setOrder != rhs.setOrder { return lhs.setOrder < rhs.setOrder }
                    return lhs.date < rhs.date
                }

                for set in sets {
                    let workoutStart = didPrintWorkoutInfo ? "" : dateFormatter.string(from: workout.date)
                    let workoutName = didPrintWorkoutInfo ? "" : workout.name
                    let duration = didPrintWorkoutInfo ? "" : workout.duration

                    let exerciseName = didPrintExerciseInfo ? "" : exercise.name
                    let muscles = didPrintExerciseInfo ? "" : (exerciseTagsByName[exercise.name] ?? "")

                    let setOrder = String(set.setOrder)
                    let weight = formatCompactNumber(set.weight, decimals: 1)
                    let reps = String(set.reps)

                    let context = WorkoutExportRowContext(
                        workoutStart: workoutStart,
                        workoutName: workoutName,
                        gymName: didPrintWorkoutInfo ? "" : (gymNamesByWorkoutID[workout.id] ?? ""),
                        duration: duration,
                        exerciseName: exerciseName,
                        muscles: muscles,
                        setOrder: setOrder,
                        weight: weight,
                        reps: reps,
                        distance: set.distance > 0 ? formatCompactNumber(set.distance, decimals: 1) : "",
                        seconds: set.seconds > 0 ? formatCompactNumber(set.seconds, decimals: 1) : ""
                    )
                    let row = columns.map { value(for: $0, context: context) }

                    let rowString = row
                        .map(csvEscape)
                        .joined(separator: ",")
                    lines.append(rowString)
                    didPrintWorkoutInfo = true
                    didPrintExerciseInfo = true
                }
            }
        }

        let csvString = lines.joined(separator: "\n")
        guard let data = csvString.data(using: .utf8) else {
            // Should never fail for ASCII-ish content; use a generic message if it does.
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    nonisolated static func makeWorkoutExportFileName(
        startDate: Date,
        endDateInclusive: Date,
        calendar: Calendar = .current
    ) throws -> String {
        _ = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let start = dateFormatter.string(from: calendar.startOfDay(for: startDate))
        let end = dateFormatter.string(from: calendar.startOfDay(for: endDateInclusive))
        let stamp = Int(Date().timeIntervalSince1970)
        return "workout_export_\(start)_\(end)_\(stamp).csv"
    }

    /// Export a unique list of exercise names within a date range.
    /// If `includeTags` is true, adds a `Tags` column (blank if no tags).
    nonisolated static func exportExerciseListCSV(
        workouts: [Workout],
        startDate: Date,
        endDateInclusive: Date,
        includeTags: Bool,
        exerciseTagsByName: [String: String] = [:],
        calendar: Calendar = .current
    ) throws -> Data {
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

        var lines: [String] = []
        lines.reserveCapacity(sortedNames.count + 1)

        if includeTags {
            lines.append(["Exercise", "Tags"].joined(separator: ","))
            for name in sortedNames {
                let tags = exerciseTagsByName[name] ?? ""
                lines.append([csvEscape(name), csvEscape(tags)].joined(separator: ","))
            }
        } else {
            lines.append("Exercise")
            for name in sortedNames {
                lines.append(csvEscape(name))
            }
        }

        let csvString = lines.joined(separator: "\n")
        guard let data = csvString.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
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
        dateFormatter.timeZone = TimeZone.current
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
        dateFormatter.timeZone = TimeZone.current
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
        dateFormatter.timeZone = TimeZone.current
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
        dateFormatter.timeZone = TimeZone.current
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

    private nonisolated static func uniqueColumns(_ columns: [WorkoutExportColumn]) -> [WorkoutExportColumn] {
        var seen = Set<WorkoutExportColumn>()
        return columns.filter { column in
            seen.insert(column).inserted
        }
    }

    private nonisolated static func columnsWithAvailableData(
        _ columns: [WorkoutExportColumn],
        for workouts: [Workout]
    ) -> [WorkoutExportColumn] {
        let allSets = workouts.flatMap { $0.exercises.flatMap(\.sets) }
        let includesDistance = allSets.contains { $0.distance > 0 }
        let includesSeconds = allSets.contains { $0.seconds > 0 }

        return columns.filter { column in
            switch column {
            case .distance:
                return includesDistance
            case .seconds:
                return includesSeconds
            default:
                return true
            }
        }
    }

    private nonisolated static func value(for column: WorkoutExportColumn, context: WorkoutExportRowContext) -> String {
        switch column {
        case .workoutStart:
            return context.workoutStart
        case .workoutName:
            return context.workoutName
        case .gymName:
            return context.gymName
        case .duration:
            return context.duration
        case .exercise:
            return context.exerciseName
        case .tags:
            return context.muscles
        case .setNumber:
            return context.setOrder
        case .weight:
            return context.weight
        case .reps:
            return context.reps
        case .distance:
            return context.distance
        case .seconds:
            return context.seconds
        }
    }

    private nonisolated static func csvEscape(_ field: String) -> String {
        if field.contains("\"") || field.contains(",") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    private nonisolated static func formatCompactNumber(_ value: Double, decimals: Int) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        let format = "%.\(decimals)f"
        return String(format: format, locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
