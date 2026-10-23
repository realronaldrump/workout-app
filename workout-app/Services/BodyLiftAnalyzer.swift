import Foundation

/// A key lift's estimated one-rep max now and three months ago, beside trend weight,
/// so the Body screen can answer "did my strength hold while my weight moved?"
nonisolated struct BodyLiftRow: Sendable, Identifiable, Equatable {
    let name: String
    let estimatedMaxNow: Double
    let estimatedMaxThen: Double
    /// Estimated max divided by trend weight, when a weigh-in is close enough to the window.
    let multipleNow: Double?
    let multipleThen: Double?

    var id: String { name }
    var changePercent: Double {
        estimatedMaxThen > 0 ? (estimatedMaxNow - estimatedMaxThen) / estimatedMaxThen * 100 : 0
    }

    enum Direction: Sendable { case up, flat, down }

    var direction: Direction {
        if changePercent > 2 { return .up }
        if changePercent < -2 { return .down }
        return .flat
    }
}

nonisolated enum BodyLiftAnalyzer {
    static let windowDays = 28
    static let lookbackDays = 90
    static let maxRows = 4

    /// Up to four lifts with two qualifying sessions in each window: the last four weeks, and the
    /// four weeks ending three months ago. Favorites come first, then the most-trained lifts.
    /// Sets count only with load and 1 to 10 reps, because the Epley estimate is unreliable past that.
    static func rows(
        workouts: [Workout],
        resolver: ExerciseIdentityResolver,
        excludedNames: Set<String>,
        favorites: [String],
        weight: BodySeries,
        now: Date,
        calendar: Calendar = .current
    ) -> [BodyLiftRow] {
        let today = calendar.startOfDay(for: now)
        guard let nowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today),
              let thenEnd = calendar.date(byAdding: .day, value: -lookbackDays, to: today),
              let thenStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: thenEnd),
              let recentStart = calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: today),
              let thenEndExclusive = calendar.date(byAdding: .day, value: 1, to: thenEnd) else { return [] }

        struct Tally {
            var nowBest = 0.0
            var thenBest = 0.0
            var nowSessions = 0
            var thenSessions = 0
            var recentSessions = 0
        }

        var tallies: [String: Tally] = [:]
        for workout in workouts where workout.date >= thenStart {
            let inNow = workout.date >= nowStart
            let inThen = workout.date >= thenStart && workout.date < thenEndExclusive
            let inRecent = workout.date >= recentStart
            guard inNow || inThen || inRecent else { continue }
            for exercise in ExerciseAggregation.aggregateExercises(in: workout, resolver: resolver) {
                guard !excludedNames.contains(exercise.name) else { continue }
                let best = exercise.sets
                    .filter { $0.weight > 0 && (1...10).contains($0.reps) }
                    .map { OneRepMax.estimate(weight: $0.weight, reps: $0.reps) }
                    .max()
                guard let best else { continue }
                var tally = tallies[exercise.name] ?? Tally()
                if inNow {
                    tally.nowBest = max(tally.nowBest, best)
                    tally.nowSessions += 1
                }
                if inThen {
                    tally.thenBest = max(tally.thenBest, best)
                    tally.thenSessions += 1
                }
                if inRecent { tally.recentSessions += 1 }
                tallies[exercise.name] = tally
            }
        }

        let qualifying = tallies.filter { $0.value.nowSessions >= 2 && $0.value.thenSessions >= 2 }
        let favoriteNames = favorites.map { resolver.aggregateName(for: $0) }
        var chosen: [String] = []
        for name in favoriteNames where qualifying[name] != nil && !chosen.contains(name) {
            chosen.append(name)
            if chosen.count == maxRows { break }
        }
        let byUse = qualifying
            .sorted { lhs, rhs in
                lhs.value.recentSessions == rhs.value.recentSessions
                    ? lhs.key < rhs.key
                    : lhs.value.recentSessions > rhs.value.recentSessions
            }
            .map(\.key)
        for name in byUse where chosen.count < maxRows && !chosen.contains(name) {
            chosen.append(name)
        }

        let weightNow = weight.latest.flatMap { latest in
            weight.dayIndex(for: now) - latest.dayIndex <= 14 ? latest.trend : nil
        }
        let weightThen = weight.nearestGridDay(to: weight.dayIndex(for: thenEnd), tolerance: 7)?.trend

        return chosen.compactMap { name in
            guard let tally = qualifying[name] else { return nil }
            return BodyLiftRow(
                name: name,
                estimatedMaxNow: tally.nowBest,
                estimatedMaxThen: tally.thenBest,
                multipleNow: weightNow.map { tally.nowBest / $0 },
                multipleThen: weightThen.map { tally.thenBest / $0 }
            )
        }
    }

    /// One factual sentence, only when weight moved enough for the comparison to mean something.
    static func summary(rows: [BodyLiftRow], weightChange: BodyChange?) -> String? {
        guard rows.count >= 2, let weightChange, abs(weightChange.percent) >= 1.5 else { return nil }
        let up = rows.filter { $0.direction == .up }.count
        let flat = rows.filter { $0.direction == .flat }.count
        let down = rows.filter { $0.direction == .down }.count
        let direction = weightChange.delta < 0 ? "down" : "up"
        let percent = String(format: "%.1f", abs(weightChange.percent))
        var parts: [String] = []
        if up > 0 { parts.append("\(up) up") }
        if flat > 0 { parts.append("\(flat) flat") }
        if down > 0 { parts.append("\(down) down") }
        let lifts = rows.count == 1 ? "lift" : "lifts"
        return "Weight is \(direction) \(percent)% in 90 days. Of these \(rows.count) \(lifts): \(parts.joined(separator: ", "))."
    }
}
