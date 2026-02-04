import Foundation

struct GymProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
