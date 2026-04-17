import Combine
import Foundation

@MainActor
final class WorkoutAnnotationsManager: ObservableObject {
    @Published private(set) var annotations: [UUID: WorkoutAnnotation] = [:]

    private let database = AppDatabase.shared
    private let fileName = "workout_annotations.json"

    init() {
        load()
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

    func clearAll() {
        annotations = [:]
        try? database.clearAnnotations()
        removeLegacyFile()
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
        let database = database
        Task.detached(priority: .utility) {
            do {
                try database.replaceAnnotations(entries)
            } catch {
                print("Failed to persist annotations: \(error)")
            }
        }
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
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("Failed to delete workout annotations store: \(error)")
        }
    }
}
