import Foundation

enum WorkoutIdentity {
    nonisolated static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func hourBucket(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0
        return String(format: "%04d-%02d-%02d-%02d", year, month, day, hour)
    }

    nonisolated static func workoutKey(date: Date, workoutName: String, calendar: Calendar = .current) -> String {
        let bucket = hourBucket(for: date, calendar: calendar)
        let normalized = normalizedName(workoutName)
        return "\(bucket)|\(normalized)"
    }
}

@MainActor
final class WorkoutIdentityStore {
    private let fileName = "workout_identity_map.json"
    private var cache: [String: String] = [:]

    init() {
        load()
    }

    func snapshot() -> [String: UUID] {
        var result: [String: UUID] = [:]
        for (key, value) in cache {
            if let uuid = UUID(uuidString: value) {
                result[key] = uuid
            }
        }
        return result
    }

    func merge(_ entries: [String: UUID]) {
        guard !entries.isEmpty else { return }
        var didChange = false
        for (key, value) in entries {
            let uuidString = value.uuidString
            if cache[key] != uuidString {
                cache[key] = uuidString
                didChange = true
            }
        }
        if didChange {
            persist()
        }
    }

    func clear() {
        cache.removeAll()
        let url = fileURL()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("Failed to delete workout identity map: \(error)")
        }
    }

    private func fileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }

    private func load() {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            cache = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            print("Failed to load workout identity map: \(error)")
        }
    }

    private func persist() {
        let url = fileURL()
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            print("Failed to persist workout identity map: \(error)")
        }
    }
}
