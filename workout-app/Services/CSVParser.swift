import Foundation

class CSVParser {
    /// Column positions for the Strong export format. Resolved from the header row when
    /// possible so reordered or extended exports still import, with the classic layout as fallback.
    private nonisolated struct StrongColumns {
        var date = 0
        var workoutName = 1
        var duration = 2
        var exerciseName = 3
        var setOrder = 4
        var weight = 5
        var reps = 6
        var distance = 7
        var seconds = 8

        var requiredCount: Int {
            [date, workoutName, duration, exerciseName, setOrder, weight, reps].max().map { $0 + 1 } ?? 9
        }

        init() {}

        init(header: [String]) {
            let normalized = header.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
                    .lowercased()
            }
            func index(_ prefix: String) -> Int? {
                normalized.firstIndex { $0 == prefix || $0.hasPrefix(prefix + " ") || $0.hasPrefix(prefix + "(") }
            }
            if let value = index("date") { date = value }
            if let value = index("workout name") { workoutName = value }
            if let value = index("duration") { duration = value }
            if let value = index("exercise name") { exerciseName = value }
            if let value = index("set order") { setOrder = value }
            if let value = index("weight") { weight = value }
            if let value = index("reps") { reps = value }
            if let value = index("distance") { distance = value }
            if let value = index("seconds") { seconds = value }
        }
    }

    nonisolated static func parseStrongWorkoutsCSV(from data: Data) throws -> [WorkoutSet] {
        guard let csvString = decodeText(data) else {
            throw CSVParserError.invalidData
        }

        let delimiter = detectDelimiter(in: csvString)
        let records = parseCSVRecords(csvString, delimiter: delimiter)
            .filter { record in
                // Skip blank lines.
                !(record.count == 1 && record[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

        guard records.count > 1, let header = records.first else {
            throw CSVParserError.emptyFile
        }

        let columns = StrongColumns(header: header)
        let dataRecords = records.dropFirst()

        var workoutSets: [WorkoutSet] = []
        workoutSets.reserveCapacity(dataRecords.count)
        let primaryFormatter = makeDateFormatter("yyyy-MM-dd HH:mm:ss")
        let fallbackFormatter = makeDateFormatter("yyyy-MM-dd HH:mm")

        for record in dataRecords {
            let components = record.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard components.count >= columns.requiredCount else { continue }

            let dateText = components[columns.date]
            guard let date = primaryFormatter.date(from: dateText) ?? fallbackFormatter.date(from: dateText),
                  let setOrder = Int(components[columns.setOrder]),
                  let weight = parseNumber(components[columns.weight]),
                  let repsValue = parseNumber(components[columns.reps]),
                  repsValue >= 0, repsValue < Double(Int32.max) else {
                continue
            }
            let reps = Int(repsValue.rounded())

            // Distance and seconds are optional - default to 0 if missing, empty or invalid.
            let distance = value(at: columns.distance, in: components).flatMap(parseNumber) ?? 0.0
            let seconds = value(at: columns.seconds, in: components).flatMap(parseNumber) ?? 0.0

            let workoutSet = WorkoutSet(
                date: date,
                workoutName: components[columns.workoutName],
                duration: components[columns.duration],
                exerciseName: components[columns.exerciseName],
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

    private nonisolated static func decodeText(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        }
        // UTF-16 exports start with a byte order mark.
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        }
        // Files re-saved by spreadsheet apps are sometimes Latin-1/Windows-1252.
        return String(data: data, encoding: .windowsCP1252)
    }

    /// Strong uses `;` as the separator in locales where `,` is the decimal separator.
    private nonisolated static func detectDelimiter(in text: String) -> Character {
        let headerLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let commas = headerLine.filter { $0 == "," }.count
        let semicolons = headerLine.filter { $0 == ";" }.count
        return semicolons > commas ? ";" : ","
    }

    private nonisolated static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    private nonisolated static func value(at index: Int, in components: [String]) -> String? {
        components.indices.contains(index) ? components[index] : nil
    }

    /// Parses numbers written with either `.` or `,` as the decimal separator.
    private nonisolated static func parseNumber(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed), value.isFinite { return value }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value.isFinite else {
            return nil
        }
        return value
    }

    /// RFC 4180-style parser over the whole document. Supports quoted fields containing
    /// delimiters, escaped quotes (`""`) and line breaks (e.g. multi-line workout notes),
    /// which a line-by-line split would corrupt.
    private nonisolated static func parseCSVRecords(_ text: String, delimiter: Character) -> [[String]] {
        var records: [[String]] = []
        var currentRecord: [String] = []
        var currentField = ""
        var inQuotes = false

        var iterator = text.makeIterator()
        var pending: Character?

        func nextCharacter() -> Character? {
            if let character = pending {
                pending = nil
                return character
            }
            return iterator.next()
        }

        while let char = nextCharacter() {
            if inQuotes {
                if char == "\"" {
                    if let following = nextCharacter() {
                        if following == "\"" {
                            currentField.append("\"")
                        } else {
                            inQuotes = false
                            pending = following
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
                continue
            }

            if char == "\"" {
                inQuotes = true
            } else if char == delimiter {
                currentRecord.append(currentField)
                currentField = ""
            } else if char.isNewline {
                // "\r\n" is a single grapheme in Swift, so one newline check covers both.
                currentRecord.append(currentField)
                records.append(currentRecord)
                currentRecord = []
                currentField = ""
            } else {
                currentField.append(char)
            }
        }

        if !currentField.isEmpty || !currentRecord.isEmpty {
            currentRecord.append(currentField)
            records.append(currentRecord)
        }

        return records
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
