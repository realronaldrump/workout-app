import Combine
import Foundation

@MainActor
final class WorkoutAnnotationsManager: ObservableObject {
    @Published private(set) var annotations: [UUID: WorkoutAnnotation] = [:]

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

    private func fileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }

    private func persist() {
        let entries = Array(annotations.values)
        let url = fileURL()
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            do {
                let data = try encoder.encode(entries)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                print("Failed to persist annotations: \(error)")
            }
        }
    }

    private func load() {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let entries = try decoder.decode([WorkoutAnnotation].self, from: data)
            // Purge any legacy habit-only annotations and keep only gym assignments.
            let filtered = entries.filter { $0.gymProfileId != nil }
            annotations = Dictionary(uniqueKeysWithValues: filtered.map { ($0.workoutId, $0) })

            // One-time rewrite to drop legacy keys from disk.
            if !userDefaults.bool(forKey: migrationFlagKey) {
                userDefaults.set(true, forKey: migrationFlagKey)
                persist()
            }
        } catch {
            print("Failed to load annotations: \(error)")
        }
    }

    // No-op placeholder: legacy code used to carry non-gym fields. Left intentionally blank.
}
