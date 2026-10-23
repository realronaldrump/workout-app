import Combine
import Foundation

@MainActor
final class WorkoutLogStore: ObservableObject {
    @Published private(set) var workouts: [LoggedWorkout] = []
    @Published private(set) var persistenceError: String?

    private var mutationRevision = 0
    private var workoutRevisions: [UUID: Int] = [:]

    private let database: AppDatabase
    private let legacyFileURL: URL
    private var persistenceTask: Task<Void, Error>?

    init(database: AppDatabase = .shared, legacyFileURL: URL? = nil) {
        self.database = database
        self.legacyFileURL = legacyFileURL ?? Self.staticFileURL(fileName: "logged_workouts_v1.json")
    }

    func load() async {
        if let persistenceTask {
            _ = try? await persistenceTask.value
        }
        let revision = mutationRevision
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { [database] in
                try database.loadLoggedWorkouts()
            }.value
            // A save may have started while the database read was suspended.
            // Never replace newer in-memory edits with an older snapshot.
            if revision == mutationRevision {
                workouts = loaded.sorted { $0.startedAt > $1.startedAt }
                persistenceError = nil
            }
            removeLegacyFile()
        } catch {
            persistenceError = error.localizedDescription
            print("Failed to load logged workouts: \(error)")
        }
    }

    func reloadPersistedWorkouts() async {
        await load()
    }

    func workout(id: UUID) -> LoggedWorkout? {
        workouts.first { $0.id == id }
    }

    func upsert(_ workout: LoggedWorkout) async {
        do {
            try await save(workout)
        } catch {
            // `save` retains the previous version and publishes the error.
        }
    }

    /// Like `upsert(_:)`, but waits for the write to reach the database and throws if it
    /// fails, rolling back the in-memory change. Use when the caller is about to discard
    /// the only other copy of the data (e.g. the in-progress session draft).
    func save(_ workout: LoggedWorkout) async throws {
        var copy = workout
        copy.updatedAt = Date()

        let previous = workouts.first { $0.id == workout.id }
        let revision = recordMutation(id: workout.id)
        if let index = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[index] = copy
        } else {
            workouts.append(copy)
        }
        workouts.sort { $0.startedAt > $1.startedAt }

        let persistedWorkout = copy
        do {
            try await enqueuePersistence { database in
                try database.saveLoggedWorkout(persistedWorkout)
            }.value
            if workoutRevisions[workout.id] == revision { persistenceError = nil }
        } catch {
            persistenceError = error.localizedDescription
            // A failed older write must not roll back a newer edit of the same workout.
            if workoutRevisions[workout.id] == revision {
                workouts.removeAll { $0.id == workout.id }
                if let previous { workouts.append(previous) }
                workouts.sort { $0.startedAt > $1.startedAt }
            }
            throw error
        }
    }

    func delete(id: UUID) async {
        let previous = workouts.first { $0.id == id }
        let revision = recordMutation(id: id)
        workouts.removeAll { $0.id == id }
        do {
            try await enqueuePersistence { database in
                try database.deleteLoggedWorkout(id: id)
            }.value
            if workoutRevisions[id] == revision { persistenceError = nil }
        } catch {
            persistenceError = error.localizedDescription
            if workoutRevisions[id] == revision, let previous {
                workouts.append(previous)
                workouts.sort { $0.startedAt > $1.startedAt }
            }
        }
    }

    func clearAll() async throws {
        let previous = workouts
        mutationRevision &+= 1
        let revision = mutationRevision
        for workout in previous { workoutRevisions[workout.id] = revision }
        workouts.removeAll()
        do {
            try await enqueuePersistence { database in
                try database.clearLoggedWorkouts()
            }.value
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
            if mutationRevision == revision { workouts = previous }
            throw error
        }
        // A legacy cleanup failure must not restore entries the database already deleted.
        try removeLegacyFileIfPresent()
    }

    /// Waits until every write enqueued so far has completed and surfaces the
    /// most recent persistence failure to callers that require durable state.
    func waitForPendingPersistence() async throws {
        if let persistenceTask {
            do {
                try await persistenceTask.value
                persistenceError = nil
            } catch {
                persistenceError = error.localizedDescription
                throw error
            }
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

            recordMutation(id: workout.id)
            workouts.append(workout)
            existingIds.insert(workout.id)
            inserted += 1
        }

        if inserted > 0 || persistenceError != nil {
            workouts.sort { $0.startedAt > $1.startedAt }
            // Retrying a failed restore must retry its write, even when the same IDs
            // are already present in memory from the first attempt.
            persistReplacement()
        }

        return (inserted, skipped)
    }

    @discardableResult
    private func recordMutation(id: UUID) -> Int {
        mutationRevision &+= 1
        workoutRevisions[id] = mutationRevision
        return mutationRevision
    }

    private func fileURL() -> URL {
        legacyFileURL
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
