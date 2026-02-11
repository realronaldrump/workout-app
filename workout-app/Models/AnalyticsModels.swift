import Foundation
import SwiftUI

/// Minimal per-workout annotation state.
/// Intentionally excludes subjective check-ins (stress/caffeine/mood/soreness).
struct WorkoutAnnotation: Identifiable, Codable {
    let workoutId: UUID
    var gymProfileId: UUID?

    var id: UUID { workoutId }

    init(workoutId: UUID, gymProfileId: UUID? = nil) {
        self.workoutId = workoutId
        self.gymProfileId = gymProfileId
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

struct ChangeMetric: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let current: Double
    let previous: Double
    let delta: Double
    let percentChange: Double
    let isPositive: Bool
}

struct ChangeMetricWindow {
    let label: String
    let current: DateInterval
    let previous: DateInterval
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

// MARK: - Streak Runs

/// A contiguous run of workout days where the gap between workout days never exceeds the configured rest window.
/// `workoutDayCount` counts workout days, not calendar span.
struct StreakRun: Identifiable, Hashable {
    let id: String
    let start: Date
    let end: Date
    let workoutDayCount: Int

    init(start: Date, end: Date, workoutDayCount: Int) {
        self.start = start
        self.end = end
        self.workoutDayCount = workoutDayCount
        self.id = "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))-\(workoutDayCount)"
    }
}

struct SleepSummary: Codable {
    var totalSleep: TimeInterval
    var inBed: TimeInterval
    var stageDurations: [SleepStage: TimeInterval]
    var start: Date
    var end: Date
    // Populated for daily summaries when we select a single source to avoid multi-source double counting.
    var primarySourceName: String?
    var primarySourceBundleIdentifier: String?

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
