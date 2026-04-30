import Foundation
import SwiftUI

/// Minimal per-workout annotation state.
/// Intentionally excludes subjective check-ins (stress/caffeine/mood/soreness).
nonisolated struct WorkoutAnnotation: Identifiable, Codable {
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

struct ExerciseConsistencySummary: Identifiable, Hashable {
    let exerciseName: String
    let sessions: Int
    let weeksPerformed: Int
    let activeWeeks: Int

    var id: String { exerciseName }

    var weeklyCoverage: Double {
        guard activeWeeks > 0 else { return 0 }
        return Double(weeksPerformed) / Double(activeWeeks)
    }
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

nonisolated enum SleepSourceSelectionMode: String, Codable {
    case automatic
    case preferred
    case fallback
}

nonisolated struct SleepSummary: Codable {
    var totalSleep: TimeInterval
    var inBed: TimeInterval
    var stageDurations: [SleepStage: TimeInterval]
    var start: Date
    var end: Date
    // Populated for daily summaries when we select a single source to avoid multi-source double counting.
    var primarySourceName: String?
    var primarySourceBundleIdentifier: String?
    var sourceSelectionMode: SleepSourceSelectionMode?
    var preferredSourceName: String?
    var preferredSourceBundleIdentifier: String?

    var totalHours: Double {
        totalSleep / 3600
    }

    var usedFallbackSource: Bool {
        sourceSelectionMode == .fallback
    }

    var sourceStatusText: String? {
        switch sourceSelectionMode {
        case .automatic:
            return "Best available Apple Health source selected for this night."
        case .preferred:
            return "Your preferred sleep source supplied this night."
        case .fallback:
            if let preferredSourceName, let primarySourceName, preferredSourceName != primarySourceName {
                return "\(preferredSourceName) had no usable sleep data for this night, so \(primarySourceName) was used instead."
            }
            return "Your preferred sleep source had no usable data for this night, so a fallback source was used."
        case .none:
            return nil
        }
    }
}

nonisolated struct SleepSourceOption: Identifiable, Hashable {
    let key: String
    let name: String
    let bundleIdentifier: String?

    var id: String { key }
}

nonisolated enum SleepStage: String, Codable, CaseIterable {
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
    let date: Date
    let value: Double
    let label: String

    var id: String {
        "\(label)-\(date.timeIntervalSinceReferenceDate)"
    }
}
