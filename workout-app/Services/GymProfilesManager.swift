import Combine
import Foundation
import SwiftUI

@MainActor
final class GymProfilesManager: ObservableObject {
    @Published private(set) var gyms: [GymProfile] = []

    @AppStorage("lastUsedGymProfileId") private var lastUsedGymProfileIdString: String = ""

    private let fileName = "gym_profiles.json"
    private let annotationsManager: WorkoutAnnotationsManager

    init(annotationsManager: WorkoutAnnotationsManager) {
        self.annotationsManager = annotationsManager
        load()
    }

    var sortedGyms: [GymProfile] {
        gyms.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var lastUsedGymProfileId: UUID? {
        get {
            let trimmed = lastUsedGymProfileIdString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return UUID(uuidString: trimmed)
        }
        set {
            lastUsedGymProfileIdString = newValue?.uuidString ?? ""
        }
    }

    func setLastUsedGymProfileId(_ id: UUID?) {
        lastUsedGymProfileId = id
    }

    func gymName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return gyms.first { $0.id == id }?.name
    }

    func gymNameSnapshot() -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: gyms.map { ($0.id, $0.name) })
    }

    @discardableResult
    func addGym(
        name: String,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> GymProfile {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedAddress = (trimmedAddress?.isEmpty ?? true) ? nil : trimmedAddress
        let profile = GymProfile(
            name: trimmedName.isEmpty ? "Gym" : trimmedName,
            address: storedAddress,
            latitude: latitude,
            longitude: longitude
        )
        gyms.append(profile)
        persist()
        return profile
    }

    func updateGym(
        id: UUID,
        name: String,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        guard let index = gyms.firstIndex(where: { $0.id == id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedAddress = (trimmedAddress?.isEmpty ?? true) ? nil : trimmedAddress
        gyms[index].name = trimmedName.isEmpty ? gyms[index].name : trimmedName
        gyms[index].address = storedAddress
        gyms[index].latitude = latitude
        gyms[index].longitude = longitude
        gyms[index].updatedAt = Date()
        persist()
    }

    func deleteGym(_ gym: GymProfile) {
        gyms.removeAll { $0.id == gym.id }
        if lastUsedGymProfileId == gym.id {
            lastUsedGymProfileId = nil
        }
        persist()
        annotationsManager.clearGymAssignments(for: gym.id)
    }

    private func fileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }

    private func persist() {
        let entries = gyms
        let url = fileURL()
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            do {
                let data = try encoder.encode(entries)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                print("Failed to persist gym profiles: \(error)")
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
            gyms = try decoder.decode([GymProfile].self, from: data)
        } catch {
            print("Failed to load gym profiles: \(error)")
        }
    }
}
