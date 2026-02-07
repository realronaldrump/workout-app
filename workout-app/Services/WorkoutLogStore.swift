import Foundation
import Combine

@MainActor
final class WorkoutLogStore: ObservableObject {
    @Published private(set) var workouts: [LoggedWorkout] = []

    private let fileName = "logged_workouts_v1.json"

    func load() async {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            workouts = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([LoggedWorkout].self, from: data)
            workouts = decoded.sorted { $0.startedAt > $1.startedAt }
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
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }

    private func persist() {
        let snapshot = workouts
        let url = fileURL()
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            do {
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                print("Failed to persist logged workouts: \(error)")
            }
        }
    }
}
