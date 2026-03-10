import Foundation

enum ExerciseRepLane: String, CaseIterable, Codable, Hashable, Identifiable {
    case oneToThree
    case fourToSix
    case sevenToTen
    case elevenToFifteen
    case sixteenPlus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneToThree: return "1-3"
        case .fourToSix: return "4-6"
        case .sevenToTen: return "7-10"
        case .elevenToFifteen: return "11-15"
        case .sixteenPlus: return "16+"
        }
    }

    func contains(_ reps: Int) -> Bool {
        switch self {
        case .oneToThree:
            return (1...3).contains(reps)
        case .fourToSix:
            return (4...6).contains(reps)
        case .sevenToTen:
            return (7...10).contains(reps)
        case .elevenToFifteen:
            return (11...15).contains(reps)
        case .sixteenPlus:
            return reps >= 16
        }
    }

    static func lane(for reps: Int) -> ExerciseRepLane {
        switch reps {
        case ...3:
            return .oneToThree
        case 4...6:
            return .fourToSix
        case 7...10:
            return .sevenToTen
        case 11...15:
            return .elevenToFifteen
        default:
            return .sixteenPlus
        }
    }
}

enum ExerciseOrderBand: String, Codable, Hashable {
    case first
    case secondToThird
    case fourthPlus

    var label: String {
        switch self {
        case .first: return "1st"
        case .secondToThird: return "2nd-3rd"
        case .fourthPlus: return "4th+"
        }
    }
}

enum ExerciseBlockOutcomeStatus: String, Codable, Hashable {
    case improved
    case flat
    case regressed
    case notComparable

    var title: String {
        switch self {
        case .improved: return "Improved"
        case .flat: return "Held Flat"
        case .regressed: return "Regressed"
        case .notComparable: return "Not Directly Comparable"
        }
    }
}

enum ExerciseBlockPrimaryMetricKind: String, Codable, Hashable {
    case bestWeight
    case repsAtRepeatedLoad
    case laneVolume
    case notComparable
}

struct ExerciseBlockOutcome: Hashable {
    let lane: ExerciseRepLane
    let bestWeight: Double
    let repeatedLoad: Double?
    let repsAtRepeatedLoad: Int?
    let laneVolume: Double
}

struct ExerciseTrainingBlock: Identifiable, Hashable {
    let id: String
    let startDate: Date
    let endDate: Date
    let sessionCount: Int
    let sessionsPerWeek: Double
    let dominantRepLane: ExerciseRepLane
    let commonOrderBand: ExerciseOrderBand
    let commonGymId: UUID?
    let commonGym: String?
    let medianSetsPerSession: Double
    let medianVolumePerSession: Double
    let medianBodyweight: Double?
    let outcome: ExerciseBlockOutcome
}

struct ExerciseForensicsFinding: Identifiable, Hashable {
    let id: String
    let title: String
    let message: String
}

struct ExerciseBlockComparison: Hashable {
    let previousBlockId: String
    let currentBlockId: String
    let outcomeStatus: ExerciseBlockOutcomeStatus
    let primaryMetricKind: ExerciseBlockPrimaryMetricKind
    let primaryObservedMetric: String
    let delta: Double
    let deltaLabel: String
    let summary: String
    let supportingEvidence: [String]
}

struct ExerciseForensicsReview: Hashable {
    let exerciseName: String
    let latestComparableBlocks: [ExerciseTrainingBlock]
    let comparison: ExerciseBlockComparison?
    let findings: [ExerciseForensicsFinding]
    let hasBodyweightContext: Bool
}
