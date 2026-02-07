import Foundation

struct DailyHealthData: Identifiable, Codable {
    let dayStart: Date

    var steps: Double?
    var activeEnergy: Double?
    var basalEnergy: Double?
    var exerciseMinutes: Double?
    var moveMinutes: Double?
    var standMinutes: Double?
    var distanceWalkingRunning: Double?
    var flightsClimbed: Double?

    var sleepSummary: SleepSummary?

    var restingHeartRate: Double?
    var walkingHeartRateAverage: Double?
    var heartRateVariability: Double?
    var heartRateRecovery: Double?

    var bloodOxygen: Double?
    var respiratoryRate: Double?
    var bodyTemperature: Double?

    var vo2Max: Double?

    var bodyMass: Double?
    var bodyFatPercentage: Double?

    var id: Date { dayStart }

    init(
        dayStart: Date,
        steps: Double? = nil,
        activeEnergy: Double? = nil,
        basalEnergy: Double? = nil,
        exerciseMinutes: Double? = nil,
        moveMinutes: Double? = nil,
        standMinutes: Double? = nil,
        distanceWalkingRunning: Double? = nil,
        flightsClimbed: Double? = nil,
        sleepSummary: SleepSummary? = nil,
        restingHeartRate: Double? = nil,
        walkingHeartRateAverage: Double? = nil,
        heartRateVariability: Double? = nil,
        heartRateRecovery: Double? = nil,
        bloodOxygen: Double? = nil,
        respiratoryRate: Double? = nil,
        bodyTemperature: Double? = nil,
        vo2Max: Double? = nil,
        bodyMass: Double? = nil,
        bodyFatPercentage: Double? = nil
    ) {
        self.dayStart = dayStart
        self.steps = steps
        self.activeEnergy = activeEnergy
        self.basalEnergy = basalEnergy
        self.exerciseMinutes = exerciseMinutes
        self.moveMinutes = moveMinutes
        self.standMinutes = standMinutes
        self.distanceWalkingRunning = distanceWalkingRunning
        self.flightsClimbed = flightsClimbed
        self.sleepSummary = sleepSummary
        self.restingHeartRate = restingHeartRate
        self.walkingHeartRateAverage = walkingHeartRateAverage
        self.heartRateVariability = heartRateVariability
        self.heartRateRecovery = heartRateRecovery
        self.bloodOxygen = bloodOxygen
        self.respiratoryRate = respiratoryRate
        self.bodyTemperature = bodyTemperature
        self.vo2Max = vo2Max
        self.bodyMass = bodyMass
        self.bodyFatPercentage = bodyFatPercentage
    }
}

extension DailyHealthData {
    // swiftlint:disable:next cyclomatic_complexity
    func value(for metric: HealthMetric) -> Double? {
        switch metric {
        case .steps:
            return steps
        case .activeEnergy:
            return activeEnergy
        case .basalEnergy:
            return basalEnergy
        case .exerciseMinutes:
            return exerciseMinutes
        case .moveMinutes:
            return moveMinutes
        case .standMinutes:
            return standMinutes
        case .distanceWalkingRunning:
            return distanceWalkingRunning
        case .flightsClimbed:
            return flightsClimbed
        case .sleep:
            return sleepSummary?.totalHours
        case .restingHeartRate:
            return restingHeartRate
        case .walkingHeartRateAverage:
            return walkingHeartRateAverage
        case .heartRateVariability:
            return heartRateVariability
        case .heartRateRecovery:
            return heartRateRecovery
        case .bloodOxygen:
            return bloodOxygen
        case .respiratoryRate:
            return respiratoryRate
        case .bodyTemperature:
            return bodyTemperature
        case .vo2Max:
            return vo2Max
        case .bodyMass:
            return bodyMass
        case .bodyFatPercentage:
            return bodyFatPercentage
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    mutating func setValue(_ value: Double?, for metric: HealthMetric) {
        switch metric {
        case .steps:
            steps = value
        case .activeEnergy:
            activeEnergy = value
        case .basalEnergy:
            basalEnergy = value
        case .exerciseMinutes:
            exerciseMinutes = value
        case .moveMinutes:
            moveMinutes = value
        case .standMinutes:
            standMinutes = value
        case .distanceWalkingRunning:
            distanceWalkingRunning = value
        case .flightsClimbed:
            flightsClimbed = value
        case .sleep:
            break
        case .restingHeartRate:
            restingHeartRate = value
        case .walkingHeartRateAverage:
            walkingHeartRateAverage = value
        case .heartRateVariability:
            heartRateVariability = value
        case .heartRateRecovery:
            heartRateRecovery = value
        case .bloodOxygen:
            bloodOxygen = value
        case .respiratoryRate:
            respiratoryRate = value
        case .bodyTemperature:
            bodyTemperature = value
        case .vo2Max:
            vo2Max = value
        case .bodyMass:
            bodyMass = value
        case .bodyFatPercentage:
            bodyFatPercentage = value
        }
    }
}
