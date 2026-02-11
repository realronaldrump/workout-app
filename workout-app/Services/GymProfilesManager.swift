import Combine
import Foundation
import SwiftUI
import CoreLocation
import MapKit

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

    /// Finds an existing gym near the selected coordinate and updates it, or creates a new profile.
    @discardableResult
    func upsertGymFromMapSelection(
        name: String,
        address: String?,
        coordinate: CLLocationCoordinate2D,
        proximityThresholdMeters: Double = 120
    ) -> GymProfile {
        let normalizedName = normalizedLookupValue(name)
        let normalizedAddress = normalizedLookupValue(address)
        let selectedLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        if let nearbyMatch = gyms.first(where: { gym in
            guard let lat = gym.latitude, let lon = gym.longitude else { return false }
            let existingLocation = CLLocation(latitude: lat, longitude: lon)
            return existingLocation.distance(from: selectedLocation) <= proximityThresholdMeters
        }) {
            updateGym(
                id: nearbyMatch.id,
                name: normalizedName.isEmpty ? nearbyMatch.name : name,
                address: normalizedAddress.isEmpty ? nearbyMatch.address : address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            return gyms.first(where: { $0.id == nearbyMatch.id }) ?? nearbyMatch
        }

        if !normalizedAddress.isEmpty,
           let addressMatch = gyms.first(where: { normalizedLookupValue($0.address) == normalizedAddress }) {
            updateGym(
                id: addressMatch.id,
                name: normalizedName.isEmpty ? addressMatch.name : name,
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            return gyms.first(where: { $0.id == addressMatch.id }) ?? addressMatch
        }

        if !normalizedName.isEmpty,
           let nameMatchWithoutCoordinates = gyms.first(where: {
               normalizedLookupValue($0.name) == normalizedName && ($0.latitude == nil || $0.longitude == nil)
           }) {
            updateGym(
                id: nameMatchWithoutCoordinates.id,
                name: name,
                address: address ?? nameMatchWithoutCoordinates.address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            return gyms.first(where: { $0.id == nameMatchWithoutCoordinates.id }) ?? nameMatchWithoutCoordinates
        }

        return addGym(
            name: normalizedName.isEmpty ? "Gym" : name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
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

    /// Best-effort coordinate lookup for all gyms.
    /// If a gym has no lat/lon but has an address, attempts a geocode and persists the result.
    func resolveGymCoordinates() async -> [UUID: CLLocationCoordinate2D] {
        var resolved: [UUID: CLLocationCoordinate2D] = [:]
        let gymsSnapshot = gyms
        resolved.reserveCapacity(gymsSnapshot.count)

        for gym in gymsSnapshot {
            if let lat = gym.latitude, let lon = gym.longitude {
                resolved[gym.id] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                continue
            }

            guard let address = gym.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else {
                continue
            }

            if let coordinate = await geocodeAddress(address) {
                resolved[gym.id] = coordinate
                // Persist the geocoded coordinate for future runs.
                updateGym(
                    id: gym.id,
                    name: gym.name,
                    address: gym.address,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }

        return resolved
    }

    private func geocodeAddress(_ address: String) async -> CLLocationCoordinate2D? {
        if #available(iOS 26.0, *) {
            guard let request = MKGeocodingRequest(addressString: address) else { return nil }
            return await withCheckedContinuation { continuation in
                request.getMapItems { mapItems, _ in
                    continuation.resume(returning: mapItems?.first?.location.coordinate)
                }
            }
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        request.resultTypes = [.address, .pointOfInterest]
        do {
            let response = try await MKLocalSearch(request: request).start()
            if #available(iOS 26.0, *) {
                return response.mapItems.first?.location.coordinate
            } else {
                return response.mapItems.first?.placemark.coordinate
            }
        } catch {
            return nil
        }
    }

    private func normalizedLookupValue(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
