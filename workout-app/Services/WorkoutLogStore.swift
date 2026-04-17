import Combine
import Foundation

@MainActor
final class WorkoutLogStore: ObservableObject {
    @Published private(set) var workouts: [LoggedWorkout] = []

    private let database = AppDatabase.shared
    private let fileName = "logged_workouts_v1.json"

    func load() async {
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { [database] in
                try database.loadLoggedWorkouts()
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

    func mergeWorkoutsFromBackup(_ backupWorkouts: [LoggedWorkout]) -> (inserted: Int, skipped: Int) {
        guard !backupWorkouts.isEmpty else { return (0, 0) }

        var existingIds = Set(workouts.map(\.id))
        var inserted = 0
        var skipped = 0

        for workout in backupWorkouts {
            guard !existingIds.contains(workout.id) else {
                skipped += 1
                continue
            }

            workouts.append(workout)
            existingIds.insert(workout.id)
            inserted += 1
        }

        if inserted > 0 {
            workouts.sort { $0.startedAt > $1.startedAt }
            persist()
        }

        return (inserted, skipped)
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
        Task.detached(priority: .utility) {
            do {
                try database.replaceLoggedWorkouts(snapshot)
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
