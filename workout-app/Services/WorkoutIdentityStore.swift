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
    static let shared = WorkoutIdentityStore()

    private let database = AppDatabase.shared
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

    @discardableResult
    func mergeMissing(_ entries: [String: UUID]) -> Int {
        do {
            return try mergeMissingReportingErrors(entries)
        } catch {
            print("Failed to persist workout identity map: \(error)")
            return 0
        }
    }

    @discardableResult
    func mergeMissingReportingErrors(_ entries: [String: UUID]) throws -> Int {
        guard !entries.isEmpty else { return 0 }
        var inserted = 0
        for (key, value) in entries where cache[key] == nil {
            cache[key] = value.uuidString
            inserted += 1
        }
        if inserted > 0 {
            try persistReportingErrors()
        }
        return inserted
    }

    func clear() {
        do {
            try clearReportingErrors()
        } catch {
            print("Failed to clear workout identity map: \(error)")
        }
    }

    func clearReportingErrors() throws {
        cache.removeAll()
        try database.clearWorkoutIdentities()
        try removeLegacyFileIfPresent()
    }

    func reload() {
        load()
    }

    private func fileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }

    private func load() {
        do {
            let stored = try database.loadWorkoutIdentities()
            cache = Dictionary(uniqueKeysWithValues: stored.map { ($0.key, $0.value.uuidString) })
            removeLegacyFile()
        } catch {
            print("Failed to load workout identity map: \(error)")
        }
    }

    private func persist() {
        do {
            try persistReportingErrors()
        } catch {
            print("Failed to persist workout identity map: \(error)")
        }
    }

    private func persistReportingErrors() throws {
        let entries = cache.compactMapValues(UUID.init(uuidString:))
        try database.mergeWorkoutIdentities(entries)
        try removeLegacyFileIfPresent()
    }

    private func removeLegacyFile() {
        do {
            try removeLegacyFileIfPresent()
        } catch {
            print("Failed to delete workout identity map: \(error)")
        }
    }

    private func removeLegacyFileIfPresent() throws {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
