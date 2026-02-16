import Foundation

struct ExerciseProgressEvaluation: Sendable {
    var nextTarget: PlannedExerciseTarget
    var wasSuccessful: Bool
}

enum ProgramAutoregulationEngine {
    static func readinessSnapshot(
        dailyHealthStore: [Date: DailyHealthData],
        ouraScores: [Date: OuraDailyScoreDay]? = nil,
        on date: Date,
        rule: ProgressionRule,
        calendar: Calendar = .current
    ) -> ReadinessSnapshot {
        let dayStart = calendar.startOfDay(for: date)
        if let ouraScore = ouraScores?[dayStart]?.readinessScore {
            let band = bandForOuraScore(ouraScore)
            return ReadinessSnapshot(
                dayStart: dayStart,
                score: clamp(ouraScore, min: 0, max: 100),
                band: band,
                multiplier: rule.multiplier(for: band),
                source: .oura,
                sleepHours: nil,
                restingHeartRateDelta: nil,
                hrvDelta: nil
            )
        }

        let current = dailyHealthStore[dayStart]

        let lookbackValues = dailyHealthStore
            .filter { key, _ in
                key < dayStart && key >= (calendar.date(byAdding: .day, value: -14, to: dayStart) ?? dayStart)
            }
            .map(\.value)

        let baselineSleep = average(lookbackValues.compactMap { $0.sleepSummary?.totalHours })
        let baselineRHR = average(lookbackValues.compactMap { $0.restingHeartRate })
        let baselineHRV = average(lookbackValues.compactMap { $0.heartRateVariability })

        let sleepHours = current?.sleepSummary?.totalHours
        let restingHR = current?.restingHeartRate
        let hrv = current?.heartRateVariability

        let sleepComponent = componentScore(current: sleepHours, baseline: baselineSleep, slope: 15, invert: false)
        let rhrComponent = componentScore(current: restingHR, baseline: baselineRHR, slope: 10, invert: true)
        let hrvComponent = componentScore(current: hrv, baseline: baselineHRV, slope: 4, invert: false)

        let availableComponents = [sleepComponent, rhrComponent, hrvComponent].compactMap { $0 }
        let score = availableComponents.isEmpty ? 50 : clamp(availableComponents.reduce(0, +) / Double(availableComponents.count), min: 0, max: 100)

        let band: ReadinessBand
        if score < 35 {
            band = .low
        } else if score > 70 {
            band = .high
        } else {
            band = .neutral
        }

        return ReadinessSnapshot(
            dayStart: dayStart,
            score: score,
            band: band,
            multiplier: rule.multiplier(for: band),
            source: .healthKit,
            sleepHours: sleepHours,
            restingHeartRateDelta: delta(current: restingHR, baseline: baselineRHR),
            hrvDelta: delta(current: hrv, baseline: baselineHRV)
        )
    }

    static func adjustedTargets(
        from targets: [PlannedExerciseTarget],
        readiness: ReadinessSnapshot,
        roundingIncrement: Double
    ) -> [PlannedExerciseTarget] {
        targets.map { target in
            guard let weight = target.targetWeight, weight > 0 else { return target }
            var adjusted = target
            adjusted.targetWeight = roundToIncrement(weight * readiness.multiplier, increment: roundingIncrement)
            return adjusted
        }
    }

    static func evaluateCompletion(
        planned: PlannedExerciseTarget,
        completedSets: [WorkoutSet],
        rule: ProgressionRule
    ) -> ExerciseProgressEvaluation {
        var next = planned
        guard let plannedWeight = planned.targetWeight, plannedWeight > 0 else {
            return ExerciseProgressEvaluation(nextTarget: next, wasSuccessful: true)
        }

        let topSet = completedSets.max { lhs, rhs in
            if lhs.weight == rhs.weight {
                return lhs.reps < rhs.reps
            }
            return lhs.weight < rhs.weight
        }

        guard let topSet else {
            next.failureStreak += 1
            if next.failureStreak >= rule.missThreshold {
                next.targetWeight = roundToIncrement(plannedWeight * (1 - rule.deloadPercent), increment: rule.weightIncrement)
                next.failureStreak = 0
            }
            return ExerciseProgressEvaluation(nextTarget: next, wasSuccessful: false)
        }

        let hitWeight = topSet.weight >= (plannedWeight * 0.985)
        let hitReps = topSet.reps >= planned.repRange.upperBound
        let failedReps = topSet.reps < planned.repRange.lowerBound
        let underLoaded = topSet.weight < (plannedWeight * 0.97)

        let success = hitWeight && hitReps
        let miss = failedReps || underLoaded

        if success {
            next.targetWeight = roundToIncrement(plannedWeight + rule.weightIncrement, increment: rule.weightIncrement)
            next.failureStreak = 0
        } else if miss {
            next.failureStreak += 1
            if next.failureStreak >= rule.missThreshold {
                next.targetWeight = roundToIncrement(plannedWeight * (1 - rule.deloadPercent), increment: rule.weightIncrement)
                next.failureStreak = 0
            }
        }

        return ExerciseProgressEvaluation(nextTarget: next, wasSuccessful: success)
    }

    private static func componentScore(current: Double?, baseline: Double?, slope: Double, invert: Bool) -> Double? {
        guard let current, let baseline else { return nil }
        let rawDelta = current - baseline
        let deltaValue = invert ? -rawDelta : rawDelta
        return clamp(50 + (deltaValue * slope), min: 0, max: 100)
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func delta(current: Double?, baseline: Double?) -> Double? {
        guard let current, let baseline else { return nil }
        return current - baseline
    }

    private static func roundToIncrement(_ value: Double, increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.max(lower, Swift.min(upper, value))
    }

    private static func bandForOuraScore(_ score: Double) -> ReadinessBand {
        if score < 70 {
            return .low
        }
        if score >= 85 {
            return .high
        }
        return .neutral
    }
}
