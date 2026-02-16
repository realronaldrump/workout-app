import Foundation

enum ProgramGoal: String, CaseIterable, Codable, Identifiable, Sendable {
    case strength
    case hypertrophy
    case fatLoss
    case generalFitness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength:
            return "Strength"
        case .hypertrophy:
            return "Hypertrophy"
        case .fatLoss:
            return "Fat Loss"
        case .generalFitness:
            return "General Fitness"
        }
    }

    var repRange: ClosedRange<Int> {
        switch self {
        case .strength:
            return 4...6
        case .hypertrophy:
            return 8...12
        case .fatLoss:
            return 10...15
        case .generalFitness:
            return 6...10
        }
    }
}

enum ProgramSplit: String, CaseIterable, Codable, Identifiable, Sendable {
    case fullBody
    case upperLower
    case pushPullLegs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullBody:
            return "Full Body"
        case .upperLower:
            return "Upper / Lower"
        case .pushPullLegs:
            return "Push Pull Legs"
        }
    }

    static func defaultSplit(for daysPerWeek: Int) -> ProgramSplit {
        switch daysPerWeek {
        case 3:
            return .fullBody
        case 4:
            return .upperLower
        default:
            return .pushPullLegs
        }
    }
}

enum ProgramSessionState: String, Codable, CaseIterable, Sendable {
    case planned
    case completed
    case skipped
    case moved
}

enum ReadinessBand: String, Codable, CaseIterable, Sendable {
    case low
    case neutral
    case high
}

enum ReadinessSource: String, Codable, CaseIterable, Sendable {
    case healthKit
    case oura
}

struct ProgressionRule: Codable, Hashable, Sendable {
    var weightIncrement: Double
    var missThreshold: Int
    var deloadPercent: Double
    var lowReadinessMultiplier: Double
    var neutralReadinessMultiplier: Double
    var highReadinessMultiplier: Double

    static let `default` = ProgressionRule(
        weightIncrement: 2.5,
        missThreshold: 2,
        deloadPercent: 0.05,
        lowReadinessMultiplier: 0.92,
        neutralReadinessMultiplier: 1.00,
        highReadinessMultiplier: 1.03
    )

    func multiplier(for band: ReadinessBand) -> Double {
        switch band {
        case .low:
            return lowReadinessMultiplier
        case .neutral:
            return neutralReadinessMultiplier
        case .high:
            return highReadinessMultiplier
        }
    }
}

struct PlannedExerciseTarget: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var exerciseName: String
    var setCount: Int
    var repRangeLower: Int
    var repRangeUpper: Int
    var targetWeight: Double?
    var failureStreak: Int

    init(
        id: UUID = UUID(),
        exerciseName: String,
        setCount: Int,
        repRangeLower: Int,
        repRangeUpper: Int,
        targetWeight: Double?,
        failureStreak: Int = 0
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.setCount = setCount
        self.repRangeLower = repRangeLower
        self.repRangeUpper = repRangeUpper
        self.targetWeight = targetWeight
        self.failureStreak = failureStreak
    }

    var repRange: ClosedRange<Int> {
        min(repRangeLower, repRangeUpper)...max(repRangeLower, repRangeUpper)
    }

    var defaultReps: Int {
        (repRange.lowerBound + repRange.upperBound) / 2
    }
}

struct ProgramDayPlan: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var weekNumber: Int
    var dayNumber: Int
    var scheduledDate: Date
    var focusTitle: String
    var exercises: [PlannedExerciseTarget]
    var state: ProgramSessionState
    var movedFromDate: Date?
    var completedWorkoutId: UUID?
    var completionDate: Date?

    init(
        id: UUID = UUID(),
        weekNumber: Int,
        dayNumber: Int,
        scheduledDate: Date,
        focusTitle: String,
        exercises: [PlannedExerciseTarget],
        state: ProgramSessionState = .planned,
        movedFromDate: Date? = nil,
        completedWorkoutId: UUID? = nil,
        completionDate: Date? = nil
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.dayNumber = dayNumber
        self.scheduledDate = scheduledDate
        self.focusTitle = focusTitle
        self.exercises = exercises
        self.state = state
        self.movedFromDate = movedFromDate
        self.completedWorkoutId = completedWorkoutId
        self.completionDate = completionDate
    }
}

struct ProgramWeek: Identifiable, Codable, Hashable, Sendable {
    var weekNumber: Int
    var startDate: Date
    var endDate: Date
    var days: [ProgramDayPlan]

    var id: Int { weekNumber }
}

struct ProgramCompletionRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var planId: UUID
    var dayId: UUID
    var workoutId: UUID
    var completedAt: Date
    var readinessScore: Double
    var readinessBand: ReadinessBand
    var adherenceRatio: Double
    var successfulExerciseCount: Int
    var totalExerciseCount: Int

    init(
        id: UUID = UUID(),
        planId: UUID,
        dayId: UUID,
        workoutId: UUID,
        completedAt: Date,
        readinessScore: Double,
        readinessBand: ReadinessBand,
        adherenceRatio: Double,
        successfulExerciseCount: Int,
        totalExerciseCount: Int
    ) {
        self.id = id
        self.planId = planId
        self.dayId = dayId
        self.workoutId = workoutId
        self.completedAt = completedAt
        self.readinessScore = readinessScore
        self.readinessBand = readinessBand
        self.adherenceRatio = adherenceRatio
        self.successfulExerciseCount = successfulExerciseCount
        self.totalExerciseCount = totalExerciseCount
    }
}

struct ReadinessSnapshot: Codable, Hashable, Sendable {
    var dayStart: Date
    var score: Double
    var band: ReadinessBand
    var multiplier: Double
    var source: ReadinessSource
    var sleepHours: Double?
    var restingHeartRateDelta: Double?
    var hrvDelta: Double?
}

struct ProgramTodayPlan: Sendable {
    let planId: UUID
    let day: ProgramDayPlan
    let adjustedExercises: [PlannedExerciseTarget]
    let readiness: ReadinessSnapshot
}

struct ProgramWorkoutContext: Sendable {
    let planId: UUID
    let planName: String
    let dayId: UUID
    let weekNumber: Int
    let dayNumber: Int
    let readinessScore: Double?
    let readinessBand: ReadinessBand?
    let isArchivedPlan: Bool
}

struct ProgramPlan: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var name: String
    var goal: ProgramGoal
    var split: ProgramSplit
    var daysPerWeek: Int
    var startDate: Date
    var weeks: [ProgramWeek]
    var progressionRule: ProgressionRule
    var completionRecords: [ProgramCompletionRecord]
    var schemaVersion: Int

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil,
        name: String,
        goal: ProgramGoal,
        split: ProgramSplit,
        daysPerWeek: Int,
        startDate: Date,
        weeks: [ProgramWeek],
        progressionRule: ProgressionRule,
        completionRecords: [ProgramCompletionRecord] = [],
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.name = name
        self.goal = goal
        self.split = split
        self.daysPerWeek = daysPerWeek
        self.startDate = startDate
        self.weeks = weeks
        self.progressionRule = progressionRule
        self.completionRecords = completionRecords
        self.schemaVersion = schemaVersion
    }

    var allDays: [ProgramDayPlan] {
        weeks.flatMap(\.days).sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var completedDays: Int {
        allDays.filter { $0.state == .completed }.count
    }

    var totalDays: Int {
        allDays.count
    }

    var adherence: Double {
        guard totalDays > 0 else { return 0 }
        return Double(completedDays) / Double(totalDays)
    }

    var dueDayCount: Int {
        dueDays.count
    }

    var completedDueDays: Int {
        dueDays.filter { $0.state == .completed }.count
    }

    var adherenceToDate: Double {
        guard dueDayCount > 0 else { return 0 }
        return Double(completedDueDays) / Double(dueDayCount)
    }

    private var dueDays: [ProgramDayPlan] {
        let cutoffDate = Calendar.current.startOfDay(for: archivedAt ?? Date())
        return allDays.filter {
            Calendar.current.startOfDay(for: $0.scheduledDate) <= cutoffDate
        }
    }
}
