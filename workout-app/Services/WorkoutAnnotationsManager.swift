import Combine
import Foundation

@MainActor
final class WorkoutAnnotationsManager: ObservableObject {
    @Published private(set) var annotations: [UUID: WorkoutAnnotation] = [:]

    private let database = AppDatabase.shared
    private let fileName = "workout_annotations.json"
    private let userDefaults = UserDefaults.standard
    private let migrationFlagKey = "workout_annotations_migrated_v2"

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

    private func fileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }

    private func persist() {
        let entries = Array(annotations.values)
        let database = database
        let legacyURL = fileURL()
        Task.detached(priority: .utility) {
            do {
                try database.replaceAnnotations(entries)
                if FileManager.default.fileExists(atPath: legacyURL.path) {
                    try? FileManager.default.removeItem(at: legacyURL)
                }
            } catch {
                print("Failed to persist annotations: \(error)")
            }
        }
    }

    private func load() {
        do {
            let stored = try database.loadAnnotations()
            if !stored.isEmpty || !FileManager.default.fileExists(atPath: fileURL().path) {
                annotations = Dictionary(uniqueKeysWithValues: stored.map { ($0.workoutId, $0) })
                removeLegacyFile()
                return
            }

            let data = try Data(contentsOf: fileURL())
            let decoder = JSONDecoder()
            let entries = try decoder.decode([WorkoutAnnotation].self, from: data)
            let filtered = entries.filter { $0.gymProfileId != nil }
            annotations = Dictionary(uniqueKeysWithValues: filtered.map { ($0.workoutId, $0) })
            try database.replaceAnnotations(filtered)
            removeLegacyFile()

            if !userDefaults.bool(forKey: migrationFlagKey) {
                userDefaults.set(true, forKey: migrationFlagKey)
            }
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
