import Foundation

class CSVParser {
    nonisolated static func parseStrongWorkoutsCSV(from data: Data) throws -> [WorkoutSet] {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw CSVParserError.invalidData
        }
        
        let lines = csvString.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
        
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
            let components = parseCSVLine(line)
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
                workoutName: components[1].trimmingCharacters(in: .whitespaces),
                duration: components[2],
                exerciseName: components[3].trimmingCharacters(in: .whitespaces),
                setOrder: setOrder,
                weight: weight,
                reps: reps,
                distance: distance,
                seconds: seconds,
                rpe: components.count > 9 && !components[9].isEmpty ? components[9] : nil
            )
            
            workoutSets.append(workoutSet)
        }
        
        return workoutSets
    }
    
    private nonisolated static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var currentField = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
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
