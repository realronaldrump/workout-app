import Foundation

enum WorkoutExportError: LocalizedError {
    case invalidDateRange
    case noWorkoutsInRange

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return "Invalid date range"
        case .noWorkoutsInRange:
            return "No workouts found in that date range"
        }
    }
}

struct WorkoutCSVExporter {
    /// A compact, human-friendly export:
    /// - One CSV header.
    /// - Workout-level fields are only populated on the first set row of each workout.
    /// - Exercise + muscle tags are only populated on the first set row of each exercise.
    /// - Distance/Seconds columns are only included if any set uses them.
    // swiftlint:disable:next cyclomatic_complexity
    nonisolated static func exportWorkoutHistoryCSV(
        workouts: [Workout],
        startDate: Date,
        endDateInclusive: Date,
        exerciseTagsByName: [String: String] = [:],
        weightUnit: String? = nil,
        calendar: Calendar = .current
    ) throws -> Data {
        let range = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let filtered = workouts
            .filter { workout in
                workout.date >= range.start && workout.date < range.endExclusive
            }
            .sorted { $0.date < $1.date }

        guard !filtered.isEmpty else {
            throw WorkoutExportError.noWorkoutsInRange
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let allSets = filtered.flatMap { $0.exercises.flatMap(\.sets) }
        let includesDistance = allSets.contains { $0.distance > 0 }
        let includesSeconds = allSets.contains { $0.seconds > 0 }

        let trimmedUnit = weightUnit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let weightHeader: String
        if let unit = trimmedUnit, !unit.isEmpty {
            weightHeader = "Weight (\(unit))"
        } else {
            weightHeader = "Weight"
        }

        var lines: [String] = []
        lines.reserveCapacity(filtered.count * 8)

        var header = [
            "Workout Start",
            "Workout Name",
            "Duration",
            "Exercise",
            "Tags",
            "Set",
            weightHeader,
            "Reps"
        ]
        if includesDistance { header.append("Distance") }
        if includesSeconds { header.append("Seconds") }

        lines.append(header.joined(separator: ","))

        for workout in filtered {
            var didPrintWorkoutInfo = false
            let exercises = workout.exercises.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

                    var row = [
                        workoutStart,
                        workoutName,
                        duration,
                        exerciseName,
                        muscles,
                        setOrder,
                        weight,
                        reps
                    ]
                    if includesDistance { row.append(set.distance > 0 ? formatCompactNumber(set.distance, decimals: 1) : "") }
                    if includesSeconds { row.append(set.seconds > 0 ? formatCompactNumber(set.seconds, decimals: 1) : "") }

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

    nonisolated static func makeBasicExportFileName(
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
        return "workout_export_basic_\(start)_\(end)_\(stamp).csv"
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
