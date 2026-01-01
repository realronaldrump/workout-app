import Combine
import Foundation

@MainActor
final class WorkoutAnnotationsManager: ObservableObject {
    @Published private(set) var annotations: [UUID: WorkoutAnnotation] = [:]

    private let fileName = "workout_annotations.json"

    init() {
        load()
    }

    func annotation(for workoutId: UUID) -> WorkoutAnnotation? {
        annotations[workoutId]
    }

    func upsertAnnotation(
        for workoutId: UUID,
        stress: StressLevel?,
        soreness: SorenessLevel?,
        caffeine: CaffeineIntake?,
        mood: MoodLevel?,
        notes: String?
    ) {
        let existing = annotations[workoutId]
        let updated = WorkoutAnnotation(
            id: existing?.id ?? UUID(),
            workoutId: workoutId,
            createdAt: existing?.createdAt ?? Date(),
            stress: stress,
            soreness: soreness,
            caffeine: caffeine,
            mood: mood,
            notes: notes
        )
        annotations[workoutId] = updated
        persist()
    }

    func removeAnnotation(for workoutId: UUID) {
        annotations.removeValue(forKey: workoutId)
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
            encoder.dateEncodingStrategy = .iso8601
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
            decoder.dateDecodingStrategy = .iso8601
            let entries = try decoder.decode([WorkoutAnnotation].self, from: data)
            annotations = Dictionary(uniqueKeysWithValues: entries.map { ($0.workoutId, $0) })
        } catch {
            print("Failed to load annotations: \(error)")
        }
    }
}
