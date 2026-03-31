import Combine
import Foundation

@MainActor
final class WorkoutLogStore: ObservableObject {
    @Published private(set) var workouts: [LoggedWorkout] = []

    private let database = AppDatabase.shared
    private let fileName = "logged_workouts_v1.json"

    func load() async {
        let legacyURL = fileURL()
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { [database, legacyURL] in
                let stored = try database.loadLoggedWorkouts()
                if !stored.isEmpty || !FileManager.default.fileExists(atPath: legacyURL.path) {
                    return stored
                }

                let data = try Data(contentsOf: legacyURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode([LoggedWorkout].self, from: data)
                try database.replaceLoggedWorkouts(decoded)
                return decoded
            }.value
            workouts = loaded.sorted { $0.startedAt > $1.startedAt }
            removeLegacyFile()
        } catch {
            print("Failed to load logged workouts: \(error)")
            workouts = []
        }
    }

    func workout(id: UUID) -> LoggedWorkout? {
        workouts.first { $0.id == id }
    }

    func upsert(_ workout: LoggedWorkout) async {
        var copy = workout
        copy.updatedAt = Date()

        if let index = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[index] = copy
        } else {
            workouts.append(copy)
        }
        workouts.sort { $0.startedAt > $1.startedAt }
        persist()
    }

    func delete(id: UUID) async {
        workouts.removeAll { $0.id == id }
        persist()
    }

    func clearAll() async {
        workouts.removeAll()
        do {
            try database.clearLoggedWorkouts()
        } catch {
            print("Failed to clear logged workouts store: \(error)")
        }
        let url = fileURL()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("Failed to delete logged workouts store: \(error)")
        }
    }

    private func fileURL() -> URL {
        Self.staticFileURL(fileName: fileName)
    }

    private nonisolated static func staticFileURL(fileName: String) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }

    private func persist() {
        let snapshot = workouts
        let database = database
        let legacyURL = fileURL()
        Task.detached(priority: .utility) {
            do {
                try database.replaceLoggedWorkouts(snapshot)
                if FileManager.default.fileExists(atPath: legacyURL.path) {
                    try? FileManager.default.removeItem(at: legacyURL)
                }
            } catch {
                print("Failed to persist logged workouts: \(error)")
            }
        }
    }

    private func removeLegacyFile() {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("Failed to delete logged workouts store: \(error)")
        }
    }
}
