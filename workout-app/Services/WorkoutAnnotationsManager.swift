import Combine
import Foundation

@MainActor
final class WorkoutAnnotationsManager: ObservableObject {
    @Published private(set) var annotations: [UUID: WorkoutAnnotation] = [:]

    private let database: AppDatabase
    private let fileName = "workout_annotations.json"
    private var persistenceTask: Task<Void, Error>?

    init(database: AppDatabase = .shared, loadOnInit: Bool = true) {
        self.database = database
        if loadOnInit {
            load()
        }
    }

    func annotation(for workoutId: UUID) -> WorkoutAnnotation? {
        annotations[workoutId]
    }

    func setGym(for workoutId: UUID, gymProfileId: UUID?) {
        if gymProfileId == nil {
            annotations.removeValue(forKey: workoutId)
        } else {
            annotations[workoutId] = WorkoutAnnotation(workoutId: workoutId, gymProfileId: gymProfileId)
        }
        persist()
    }

    func setGym(for workoutIds: [UUID], gymProfileId: UUID?) {
        guard !workoutIds.isEmpty else { return }
        for workoutId in workoutIds {
            if gymProfileId == nil {
                annotations.removeValue(forKey: workoutId)
            } else {
                annotations[workoutId] = WorkoutAnnotation(workoutId: workoutId, gymProfileId: gymProfileId)
            }
        }
        persist()
    }

    func clearGymAssignments(for gymId: UUID) {
        let affectedIds = annotations.compactMap { key, value in
            value.gymProfileId == gymId ? key : nil
        }

        guard !affectedIds.isEmpty else { return }

        for workoutId in affectedIds {
            annotations.removeValue(forKey: workoutId)
        }
        persist()
    }

    /// Applies multiple per-workout gym assignments, persisting once at the end.
    func applyGymAssignments(_ assignments: [UUID: UUID?]) {
        guard !assignments.isEmpty else { return }

        for (workoutId, gymProfileId) in assignments {
            if gymProfileId == nil {
                annotations.removeValue(forKey: workoutId)
            } else {
                annotations[workoutId] = WorkoutAnnotation(workoutId: workoutId, gymProfileId: gymProfileId)
            }
        }

        persist()
    }

    func clearAll() async throws {
        annotations = [:]
        try await enqueuePersistence { database in
            try database.clearAnnotations()
        }.value
        try removeLegacyFileIfPresent()
    }

    /// Drains writes already queued by annotation mutations or backup import.
    func waitForPendingPersistence() async throws {
        if let persistenceTask {
            try await persistenceTask.value
        }
    }

    func reloadPersistedAnnotations() async {
        if let persistenceTask {
            _ = try? await persistenceTask.value
        }
        do {
            let stored = try await Task.detached(priority: .userInitiated) { [database] in
                try database.loadAnnotations()
            }.value
            annotations = Dictionary(uniqueKeysWithValues: stored.map { ($0.workoutId, $0) })
            removeLegacyFile()
        } catch {
            print("Failed to load annotations: \(error)")
        }
    }

    func mergeAnnotationsFromBackup(
        _ backupAnnotations: [WorkoutAnnotation],
        workoutIdMap: [UUID: UUID],
        gymIdMap: [UUID: UUID]
    ) -> (inserted: Int, skipped: Int) {
        guard !backupAnnotations.isEmpty else { return (0, 0) }

        var inserted = 0
        var skipped = 0

        for annotation in backupAnnotations {
            let workoutId = workoutIdMap[annotation.workoutId] ?? annotation.workoutId
            let gymId = annotation.gymProfileId.map { gymIdMap[$0] ?? $0 }

            guard gymId != nil else {
                skipped += 1
                continue
            }

            guard annotations[workoutId] == nil else {
                skipped += 1
                continue
            }

            annotations[workoutId] = WorkoutAnnotation(workoutId: workoutId, gymProfileId: gymId)
            inserted += 1
        }

        if inserted > 0 {
            persist()
        }

        return (inserted, skipped)
    }

    private func fileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }

    private func persist() {
        let entries = Array(annotations.values)
        enqueuePersistence { database in
            try database.replaceAnnotations(entries)
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
                print("Failed to persist annotations: \(error)")
                throw error
            }
        }
        persistenceTask = task
        return task
    }

    private func load() {
        do {
            let stored = try database.loadAnnotations()
            annotations = Dictionary(uniqueKeysWithValues: stored.map { ($0.workoutId, $0) })
            removeLegacyFile()
        } catch {
            print("Failed to load annotations: \(error)")
        }
    }

    // No-op placeholder: legacy code used to carry non-gym fields. Left intentionally blank.

    private func removeLegacyFile() {
        do {
            try removeLegacyFileIfPresent()
        } catch {
            print("Failed to delete workout annotations store: \(error)")
        }
    }

    private func removeLegacyFileIfPresent() throws {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
