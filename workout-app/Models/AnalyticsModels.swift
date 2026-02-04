import Foundation
import SwiftUI

enum StressLevel: String, Codable, CaseIterable {
    case low
    case moderate
    case high

    var label: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }

    var tint: Color {
        switch self {
        case .low: return Theme.Colors.success
        case .moderate: return Theme.Colors.warning
        case .high: return Theme.Colors.error
        }
    }
}

enum SorenessLevel: String, Codable, CaseIterable {
    case none
    case mild
    case heavy

    var label: String {
        switch self {
        case .none: return "None"
        case .mild: return "Mild"
        case .heavy: return "Heavy"
        }
    }

    var tint: Color {
        switch self {
        case .none: return Theme.Colors.success
        case .mild: return Theme.Colors.warning
        case .heavy: return Theme.Colors.error
        }
    }
}

enum CaffeineIntake: String, Codable, CaseIterable {
    case none
    case light
    case heavy

    var label: String {
        switch self {
        case .none: return "None"
        case .light: return "Light"
        case .heavy: return "Heavy"
        }
    }

    var tint: Color {
        switch self {
        case .none: return Theme.Colors.textTertiary
        case .light: return Theme.Colors.accent
        case .heavy: return Theme.Colors.warning
        }
    }
}

enum MoodLevel: String, Codable, CaseIterable {
    case low
    case steady
    case high

    var label: String {
        switch self {
        case .low: return "Low"
        case .steady: return "Steady"
        case .high: return "High"
        }
    }

    var tint: Color {
        switch self {
        case .low: return Theme.Colors.warning
        case .steady: return Theme.Colors.textSecondary
        case .high: return Theme.Colors.accentSecondary
        }
    }
}

struct WorkoutAnnotation: Identifiable, Codable {
    let id: UUID
    let workoutId: UUID
    let createdAt: Date
    var gymProfileId: UUID?
    var stress: StressLevel?
    var soreness: SorenessLevel?
    var caffeine: CaffeineIntake?
    var mood: MoodLevel?
    var notes: String?

    init(
        id: UUID = UUID(),
        workoutId: UUID,
        createdAt: Date = Date(),
        gymProfileId: UUID? = nil,
        stress: StressLevel? = nil,
        soreness: SorenessLevel? = nil,
        caffeine: CaffeineIntake? = nil,
        mood: MoodLevel? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.createdAt = createdAt
        self.gymProfileId = gymProfileId
        self.stress = stress
        self.soreness = soreness
        self.caffeine = caffeine
        self.mood = mood
        self.notes = notes
    }
}

enum ProgressContributionCategory: String, Codable {
    case exercise
    case muscleGroup
    case workoutType
}

struct ProgressContribution: Identifiable {
    let id = UUID()
    let name: String
    let delta: Double
    let current: Double
    let previous: Double
    let percentChange: Double
    let category: ProgressContributionCategory
    let tint: Color
}

struct ChangeMetric: Identifiable {
    let id = UUID()
    let title: String
    let current: Double
    let previous: Double
    let delta: Double
    let percentChange: Double
    let isPositive: Bool
}

enum ConsistencyIssueType: String {
    case missedDay
    case shortenedSession
    case skippedExercises
}

struct ConsistencyIssue: Identifiable {
    let id = UUID()
    let type: ConsistencyIssueType
    let title: String
    let detail: String
    let workoutId: UUID?
    let date: Date?
}

struct EffortDensityPoint: Identifiable {
    let id = UUID()
    let workoutId: UUID
    let date: Date
    let value: Double
    let durationMinutes: Double
    let volume: Double
}

struct RepRangeBucket: Identifiable {
    let id = UUID()
    let label: String
    let range: ClosedRange<Int>
    let count: Int
    let percent: Double
    let tint: Color
}

struct IntensityZoneBucket: Identifiable {
    let id = UUID()
    let label: String
    let range: ClosedRange<Double>
    let count: Int
    let percent: Double
    let tint: Color
}

struct FatigueEntry: Identifiable {
    let id = UUID()
    let exerciseName: String
    let dropPercent: Double
    let setCount: Int
    let note: String
}

struct FatigueSummary {
    let workoutId: UUID
    let entries: [FatigueEntry]
    let restTimeIndex: Double?
    let restTimeTrend: String?
    let effortDensity: Double?
    let averageRPE: Double?
}

struct CorrelationInsight: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let correlation: Double
    let supportingCount: Int
}

struct HabitImpactInsight: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let value: String
    let tint: Color
}

struct RecoveryDebtSnapshot {
    let score: Int
    let label: String
    let detail: String
    let tint: Color
}

struct SleepSummary: Codable {
    var totalSleep: TimeInterval
    var inBed: TimeInterval
    var stageDurations: [SleepStage: TimeInterval]
    var start: Date
    var end: Date

    var totalHours: Double {
        totalSleep / 3600
    }
}

enum SleepStage: String, Codable, CaseIterable {
    case awake
    case inBed
    case core
    case deep
    case rem
    case unknown

    var label: String {
        switch self {
        case .awake: return "Awake"
        case .inBed: return "In Bed"
        case .core: return "Core"
        case .deep: return "Deep"
        case .rem: return "REM"
        case .unknown: return "Other"
        }
    }
}

struct HealthTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String
}

struct ReadinessPoint: Identifiable {
    let id = UUID()
    let date: Date
    let score: Double
    let label: String
}
