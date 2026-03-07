import Foundation

struct IntentionalBreakRange: Identifiable, Codable, Hashable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let name: String?

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        name: String? = nil,
        calendar: Calendar = .current
    ) {
        let normalizedStart = calendar.startOfDay(for: min(startDate, endDate))
        let normalizedEnd = calendar.startOfDay(for: max(startDate, endDate))

        self.id = id
        self.startDate = normalizedStart
        self.endDate = normalizedEnd
        self.name = Self.normalizedName(name)
    }

    func dayCount(calendar: Calendar = .current) -> Int {
        let span = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return max(span + 1, 1)
    }

    var displayName: String? {
        Self.normalizedName(name)
    }

    private static func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct IntentionalBreakSuggestion: Identifiable, Hashable {
    let startDate: Date
    let endDate: Date

    var id: String {
        "\(Int(startDate.timeIntervalSince1970))-\(Int(endDate.timeIntervalSince1970))"
    }

    func asRange(name: String? = nil) -> IntentionalBreakRange {
        IntentionalBreakRange(startDate: startDate, endDate: endDate, name: name)
    }

    func dayCount(calendar: Calendar = .current) -> Int {
        asRange().dayCount(calendar: calendar)
    }
}
