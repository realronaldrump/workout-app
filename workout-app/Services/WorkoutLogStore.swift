import Combine
import Foundation

@MainActor
final class WorkoutLogStore: ObservableObject {
    @Published private(set) var workouts: [LoggedWorkout] = []

    private let database: AppDatabase
    private let fileName = "logged_workouts_v1.json"
    private var persistenceTask: Task<Void, Error>?

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func load() async {
        if let persistenceTask {
            _ = try? await persistenceTask.value
        }
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

    func reloadPersistedWorkouts() async {
        await load()
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
        let persistedWorkout = copy
        _ = try? await enqueuePersistence { database in
            try database.saveLoggedWorkout(persistedWorkout)
        }.value
    }

    func delete(id: UUID) async {
        workouts.removeAll { $0.id == id }
        _ = try? await enqueuePersistence { database in
            try database.deleteLoggedWorkout(id: id)
        }.value
    }

    func clearAll() async throws {
        workouts.removeAll()
        try await enqueuePersistence { database in
            try database.clearLoggedWorkouts()
        }.value
        try removeLegacyFileIfPresent()
    }

    /// Waits until every write enqueued so far has completed and surfaces the
    /// most recent persistence failure to callers that require durable state.
    func waitForPendingPersistence() async throws {
        if let persistenceTask {
            try await persistenceTask.value
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
            persistReplacement()
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

    private func persistReplacement() {
        let snapshot = workouts
        enqueuePersistence { database in
            try database.replaceLoggedWorkouts(snapshot)
        }
    }

    @discardableResult
    private func enqueuePersistence(
        _ operation: @escaping @Sendable (AppDatabase) throws -> Void
    ) -> Task<Void, Error> {
        let previous = persistenceTask
        let database = database
        let task: Task<Void, Error> = Task.detached(priority: .utility) {
            if let previous {
                _ = try? await previous.value
            }
            do {
                try operation(database)
            } catch {
                print("Failed to persist logged workouts: \(error)")
                throw error
            }
        }
        persistenceTask = task
        return task
    }

    private func removeLegacyFile() {
        do {
            try removeLegacyFileIfPresent()
        } catch {
            print("Failed to delete logged workouts store: \(error)")
        }
    }

    private func removeLegacyFileIfPresent() throws {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
