import Foundation

class CSVParser {
    nonisolated static func parseStrongWorkoutsCSV(from data: Data) throws -> [WorkoutSet] {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw CSVParserError.invalidData
        }

        // Handle \n and \r\n safely, and skip empty trailing lines.
        let lines = csvString
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        guard lines.count > 1 else {
            throw CSVParserError.emptyFile
        }

        // Skip header
        let dataLines = lines.dropFirst()

        var workoutSets: [WorkoutSet] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        for line in dataLines {
            let components = parseCSVLine(line).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard components.count >= 9 else { continue }

            guard let date = dateFormatter.date(from: components[0]),
                  let setOrder = Int(components[4]),
                  let weight = Double(components[5]),
                  let reps = Int(components[6].replacingOccurrences(of: ".0", with: "")) else {
                continue
            }

            // Distance and seconds are optional - default to 0 if empty or invalid
            let distance = Double(components[7]) ?? 0.0
            let seconds = Double(components[8]) ?? 0.0

            let workoutSet = WorkoutSet(
                date: date,
                workoutName: components[1],
                duration: components[2],
                exerciseName: components[3],
                setOrder: setOrder,
                weight: weight,
                reps: reps,
                distance: distance,
                seconds: seconds
            )

            workoutSets.append(workoutSet)
        }

        return workoutSets
    }

    private nonisolated static func parseCSVLine(_ line: String) -> [String] {
        // Minimal RFC 4180-ish parser for a single line.
        // Supports quoted fields, commas inside quotes, and escaped quotes via "".
        var result: [String] = []
        var currentField = ""
        var inQuotes = false

        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]

            if char == "\"" {
                if inQuotes {
                    let nextIndex = line.index(after: index)
                    if nextIndex < line.endIndex, line[nextIndex] == "\"" {
                        // Escaped quote within a quoted field.
                        currentField.append("\"")
                        index = nextIndex
                    } else {
                        // Closing quote.
                        inQuotes = false
                    }
                } else {
                    // Opening quote.
                    inQuotes = true
                }
            } else if char == "," && !inQuotes {
                result.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }

            index = line.index(after: index)
        }

        result.append(currentField)
        return result
    }
}

enum CSVParserError: LocalizedError {
    case invalidData
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Unable to read CSV data"
        case .emptyFile:
            return "CSV file is empty or invalid"
        }
    }
}
