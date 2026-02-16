import Foundation
import SwiftUI

enum OuraConnectionStatus: Equatable {
    case notConnected
    case connecting
    case connected
    case syncing
    case error(String)

    var displayText: String {
        switch self {
        case .notConnected:
            return "Not Connected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .syncing:
            return "Syncing"
        case .error:
            return "Connection Error"
        }
    }

    var iconName: String {
        switch self {
        case .notConnected:
            return "link.badge.plus"
        case .connecting:
            return "hourglass"
        case .connected:
            return "link.circle.fill"
        case .syncing:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notConnected:
            return Theme.Colors.textTertiary
        case .connecting:
            return Theme.Colors.warning
        case .connected:
            return Theme.Colors.success
        case .syncing:
            return Theme.Colors.accent
        case .error:
            return Theme.Colors.error
        }
    }
}

struct OuraDailyScoreDay: Identifiable, Codable, Equatable, Hashable {
    let dayStart: Date
    var sleepScore: Double?
    var readinessScore: Double?
    var activityScore: Double?

    var sleepContributors: [String: Double]?
    var readinessContributors: [String: Double]?
    var activityContributors: [String: Double]?

    var sleepTimestamp: Date?
    var readinessTimestamp: Date?
    var activityTimestamp: Date?

    var updatedAt: Date?

    var id: Date { dayStart }

    init(
        dayStart: Date,
        sleepScore: Double? = nil,
        readinessScore: Double? = nil,
        activityScore: Double? = nil,
        sleepContributors: [String: Double]? = nil,
        readinessContributors: [String: Double]? = nil,
        activityContributors: [String: Double]? = nil,
        sleepTimestamp: Date? = nil,
        readinessTimestamp: Date? = nil,
        activityTimestamp: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.dayStart = dayStart
        self.sleepScore = sleepScore
        self.readinessScore = readinessScore
        self.activityScore = activityScore
        self.sleepContributors = sleepContributors
        self.readinessContributors = readinessContributors
        self.activityContributors = activityContributors
        self.sleepTimestamp = sleepTimestamp
        self.readinessTimestamp = readinessTimestamp
        self.activityTimestamp = activityTimestamp
        self.updatedAt = updatedAt
    }
}

extension OuraDailyScoreDay {
    static func == (lhs: OuraDailyScoreDay, rhs: OuraDailyScoreDay) -> Bool {
        lhs.dayStart == rhs.dayStart
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(dayStart)
    }
}

extension OuraDailyScoreDay {
    var hasAnyScore: Bool {
        sleepScore != nil || readinessScore != nil || activityScore != nil
    }

    func score(for type: OuraScoreType) -> Double? {
        switch type {
        case .sleep:
            return sleepScore
        case .readiness:
            return readinessScore
        case .activity:
            return activityScore
        }
    }

    func contributors(for type: OuraScoreType) -> [String: Double]? {
        switch type {
        case .sleep:
            return sleepContributors
        case .readiness:
            return readinessContributors
        case .activity:
            return activityContributors
        }
    }
}

enum OuraScoreType: String, CaseIterable, Identifiable {
    case sleep
    case readiness
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            return "Sleep"
        case .readiness:
            return "Readiness"
        case .activity:
            return "Activity"
        }
    }

    var icon: String {
        switch self {
        case .sleep:
            return "moon.zzz.fill"
        case .readiness:
            return "bolt.heart.fill"
        case .activity:
            return "figure.walk.motion"
        }
    }

    var tint: Color {
        switch self {
        case .sleep:
            return Theme.Colors.accentSecondary
        case .readiness:
            return Theme.Colors.success
        case .activity:
            return Theme.Colors.warning
        }
    }
}

struct OuraBackendRegisterResponse: Codable {
    let installId: String
    let installToken: String

    enum CodingKeys: String, CodingKey {
        case installId = "install_id"
        case installToken = "install_token"
    }
}

struct OuraBackendConnectURLResponse: Codable {
    let url: String
    let state: String
}

struct OuraBackendStatusResponse: Codable {
    let connected: Bool
    let stale: Bool
    let status: String
    let connectedAt: Date?
    let lastSyncAt: Date?
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case connected
        case stale
        case status
        case connectedAt = "connected_at"
        case lastSyncAt = "last_sync_at"
        case lastError = "last_error"
    }
}

struct OuraBackendScoresResponse: Codable {
    let data: [OuraBackendScoreDay]
}

struct OuraBackendScoreDay: Codable {
    let day: String
    let sleepScore: Double?
    let readinessScore: Double?
    let activityScore: Double?
    let sleepContributors: [String: Double]?
    let readinessContributors: [String: Double]?
    let activityContributors: [String: Double]?
    let sleepTimestamp: Date?
    let readinessTimestamp: Date?
    let activityTimestamp: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case day
        case sleepScore = "sleep_score"
        case readinessScore = "readiness_score"
        case activityScore = "activity_score"
        case sleepContributors = "sleep_contributors"
        case readinessContributors = "readiness_contributors"
        case activityContributors = "activity_contributors"
        case sleepTimestamp = "sleep_timestamp"
        case readinessTimestamp = "readiness_timestamp"
        case activityTimestamp = "activity_timestamp"
        case updatedAt = "updated_at"
    }
}

struct OuraBackendSyncResponse: Codable {
    let accepted: Bool
    let startDate: String
    let endDate: String

    enum CodingKeys: String, CodingKey {
        case accepted
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

enum OuraCallbackOutcome {
    case success
    case failure(reason: String)
}

enum OuraDateCoding {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension OuraBackendScoreDay {
    func asDailyScoreDay(calendar: Calendar = .current) -> OuraDailyScoreDay? {
        guard let parsed = OuraDateCoding.dayFormatter.date(from: day) else { return nil }
        let dayStart = calendar.startOfDay(for: parsed)
        return OuraDailyScoreDay(
            dayStart: dayStart,
            sleepScore: sleepScore,
            readinessScore: readinessScore,
            activityScore: activityScore,
            sleepContributors: sleepContributors,
            readinessContributors: readinessContributors,
            activityContributors: activityContributors,
            sleepTimestamp: sleepTimestamp,
            readinessTimestamp: readinessTimestamp,
            activityTimestamp: activityTimestamp,
            updatedAt: updatedAt
        )
    }
}
