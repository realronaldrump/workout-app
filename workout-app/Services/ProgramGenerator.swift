import Foundation

enum ProgramGenerator {
    struct Config: Sendable {
        var goal: ProgramGoal
        var daysPerWeek: Int
        var startDate: Date
        var weightIncrement: Double
        var name: String?

        init(goal: ProgramGoal, daysPerWeek: Int, startDate: Date, weightIncrement: Double, name: String? = nil) {
            self.goal = goal
            self.daysPerWeek = daysPerWeek
            self.startDate = startDate
            self.weightIncrement = weightIncrement
            self.name = name
        }
    }

    private struct DayTemplate {
        var title: String
        var groups: [MuscleGroup]
        var fallback: [String]
    }

    static func generate(
        workouts: [Workout],
        config: Config,
        calendar: Calendar = .current
    ) -> ProgramPlan {
        let sanitizedDays = [3, 4, 5].contains(config.daysPerWeek) ? config.daysPerWeek : 4
        let increment = config.weightIncrement > 0 ? config.weightIncrement : 2.5
        let split = ProgramSplit.defaultSplit(for: sanitizedDays)
        let startDay = calendar.startOfDay(for: config.startDate)
        let templates = dayTemplates(for: split, daysPerWeek: sanitizedDays)

        let historySummary = makeHistorySummary(from: workouts)
        let groupedExercises = makeExercisesByGroup(from: workouts, historySummary: historySummary)

        let baseTargetsByTemplate = templates.map { template in
            makeBaseTargets(
                template: template,
                goal: config.goal,
                groupedExercises: groupedExercises,
                historySummary: historySummary,
                weightIncrement: increment
            )
        }

        let weekMultipliers: [Double] = [0.95, 1.00, 1.02, 1.04, 1.06, 1.08, 1.10, 0.90]
        let dayOffsets = trainingDayOffsets(for: sanitizedDays)

        var weeks: [ProgramWeek] = []
        weeks.reserveCapacity(8)

        for weekIndex in 0..<8 {
            let weekNumber = weekIndex + 1
            let weekStart = calendar.date(byAdding: .day, value: weekIndex * 7, to: startDay) ?? startDay
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

            var dayPlans: [ProgramDayPlan] = []
            dayPlans.reserveCapacity(templates.count)

            for dayIndex in 0..<templates.count {
                let dayNumber = dayIndex + 1
                let offset = dayOffsets[min(dayIndex, dayOffsets.count - 1)]
                let dayDate = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                let baseTargets = baseTargetsByTemplate[dayIndex]

                let weightedTargets = baseTargets.map { target -> PlannedExerciseTarget in
                    guard let baseWeight = target.targetWeight else { return target }
                    var copy = target
                    copy.targetWeight = roundToIncrement(
                        baseWeight * weekMultipliers[min(weekIndex, weekMultipliers.count - 1)],
                        increment: increment
                    )
                    return copy
                }

                dayPlans.append(
                    ProgramDayPlan(
                        weekNumber: weekNumber,
                        dayNumber: dayNumber,
                        scheduledDate: dayDate,
                        focusTitle: templates[dayIndex].title,
                        exercises: weightedTargets
                    )
                )
            }

            weeks.append(
                ProgramWeek(
                    weekNumber: weekNumber,
                    startDate: weekStart,
                    endDate: weekEnd,
                    days: dayPlans
                )
            )
        }

        let baseName = config.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (baseName?.isEmpty == false) ? (baseName ?? "") : "Adaptive \(config.goal.title)"
        var progressionRule = ProgressionRule.default
        progressionRule.weightIncrement = increment

        return ProgramPlan(
            name: name,
            goal: config.goal,
            split: split,
            daysPerWeek: sanitizedDays,
            startDate: startDay,
            weeks: weeks,
            progressionRule: progressionRule
        )
    }

    private static func dayTemplates(for split: ProgramSplit, daysPerWeek: Int) -> [DayTemplate] {
        switch split {
        case .fullBody:
            return [
                DayTemplate(
                    title: "Full Body A",
                    groups: [.chest, .back, .quads, .shoulders],
                    fallback: [
                        "Bench Press (Barbell)",
                        "Lat Pulldown (Machine)",
                        "Leg Press",
                        "Overhead Press (Dumbbell)",
                        "Bicep Curl (Dumbbell)"
                    ]
                ),
                DayTemplate(
                    title: "Full Body B",
                    groups: [.back, .hamstrings, .chest, .triceps],
                    fallback: [
                        "Seated Row (Cable)",
                        "Romanian Deadlift (Dumbbell)",
                        "Chest Press (Machine)",
                        "Triceps Pushdown (Cable - Straight Bar)",
                        "Lateral Raise (Dumbbell)"
                    ]
                ),
                DayTemplate(
                    title: "Full Body C",
                    groups: [.quads, .shoulders, .back, .core],
                    fallback: [
                        "Squat (Smith Machine)",
                        "Shoulder Press (Machine)",
                        "MTS Row",
                        "Crunch (Machine)",
                        "Hammer Curl (Dumbbell)"
                    ]
                )
            ]
        case .upperLower:
            return [
                DayTemplate(
                    title: "Upper A",
                    groups: [.chest, .back, .shoulders, .triceps],
                    fallback: [
                        "Bench Press (Barbell)",
                        "Seated Row (Cable)",
                        "Lateral Raise (Dumbbell)",
                        "Triceps Extension (Machine)",
                        "Bicep Curl (Dumbbell)"
                    ]
                ),
                DayTemplate(
                    title: "Lower A",
                    groups: [.quads, .hamstrings, .glutes, .calves],
                    fallback: [
                        "Leg Press",
                        "Lying Leg Curl (Machine)",
                        "Hip Thrust Machine",
                        "Standing Calf Raise (Machine)",
                        "Crunch"
                    ]
                ),
                DayTemplate(
                    title: "Upper B",
                    groups: [.back, .chest, .biceps, .shoulders],
                    fallback: [
                        "Lat Pulldown (Machine)",
                        "Incline Bench Press (Smith Machine)",
                        "EZ Bar Curl",
                        "Overhead Press (Machine)",
                        "Face Pull (Cable)"
                    ]
                ),
                DayTemplate(
                    title: "Lower B",
                    groups: [.quads, .glutes, .hamstrings, .core],
                    fallback: [
                        "Hack Squat",
                        "Glute Kickback (Machine)",
                        "Romanian Deadlift (Dumbbell)",
                        "Calf Extension Machine",
                        "Plank"
                    ]
                )
            ]
        case .pushPullLegs:
            var templates: [DayTemplate] = [
                DayTemplate(
                    title: "Push",
                    groups: [.chest, .shoulders, .triceps],
                    fallback: [
                        "Bench Press (Barbell)",
                        "Incline Bench Press (Smith Machine)",
                        "Overhead Press (Dumbbell)",
                        "Lateral Raise (Cable)",
                        "Triceps Pushdown (Cable - Straight Bar)"
                    ]
                ),
                DayTemplate(
                    title: "Pull",
                    groups: [.back, .biceps, .shoulders],
                    fallback: [
                        "Seated Row (Cable)",
                        "Lat Pulldown (Machine)",
                        "Bicep Curl (Dumbbell)",
                        "Face Pull (Cable)",
                        "Hammer Curl (Dumbbell)"
                    ]
                ),
                DayTemplate(
                    title: "Legs",
                    groups: [.quads, .hamstrings, .glutes, .calves],
                    fallback: [
                        "Leg Press",
                        "Lying Leg Curl (Machine)",
                        "Hip Thrust Machine",
                        "Standing Calf Raise (Machine)",
                        "Crunch"
                    ]
                ),
                DayTemplate(
                    title: "Upper",
                    groups: [.chest, .back, .shoulders, .biceps],
                    fallback: [
                        "Chest Press (Machine)",
                        "MTS Row",
                        "Shoulder Press (Machine)",
                        "Bicep Curl (Cable)",
                        "Triceps Extension (Machine)"
                    ]
                ),
                DayTemplate(
                    title: "Lower",
                    groups: [.quads, .glutes, .hamstrings, .core],
                    fallback: [
                        "Hack Squat",
                        "Bulgarian Split Squat",
                        "Romanian Deadlift (Dumbbell)",
                        "Calf Extension Machine",
                        "Plank"
                    ]
                )
            ]

            if daysPerWeek < templates.count {
                templates = Array(templates.prefix(daysPerWeek))
            }
            return templates
        }
    }

    private static func trainingDayOffsets(for daysPerWeek: Int) -> [Int] {
        switch daysPerWeek {
        case 3:
            return [0, 2, 4]
        case 4:
            return [0, 1, 3, 4]
        default:
            return [0, 1, 2, 4, 5]
        }
    }

    private static func makeBaseTargets(
        template: DayTemplate,
        goal: ProgramGoal,
        groupedExercises: [MuscleGroup: [String]],
        historySummary: [String: ExerciseHistorySummary],
        weightIncrement: Double
    ) -> [PlannedExerciseTarget] {
        let repRange = goal.repRange
        let setCount: Int = goal == .strength ? 4 : 3

        var picked: [String] = []
        picked.reserveCapacity(6)
        var seenNormalizedNames: Set<String> = []
        seenNormalizedNames.reserveCapacity(6)

        @discardableResult
        func appendUniqueExerciseName(_ candidate: String) -> Bool {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }

            let normalized = normalizeExerciseName(trimmed)
            guard !seenNormalizedNames.contains(normalized) else { return false }

            seenNormalizedNames.insert(normalized)
            picked.append(trimmed)
            return true
        }

        for group in template.groups {
            if let candidates = groupedExercises[group] {
                for candidate in candidates where appendUniqueExerciseName(candidate) {
                    break
                }
            }
        }

        for fallback in template.fallback {
            _ = appendUniqueExerciseName(fallback)
            if picked.count >= 5 {
                break
            }
        }

        let globalSorted = historySummary.keys.sorted { lhs, rhs in
            let lCount = historySummary[lhs]?.frequency ?? 0
            let rCount = historySummary[rhs]?.frequency ?? 0
            if lCount != rCount {
                return lCount > rCount
            }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        for candidate in globalSorted {
            _ = appendUniqueExerciseName(candidate)
            if picked.count >= 5 {
                break
            }
        }

        let names = Array(picked.prefix(5))

        return names.map { name in
            let baseWeight = historySummary[name]?.lastTopWeight
            return PlannedExerciseTarget(
                exerciseName: name,
                setCount: setCount,
                repRangeLower: repRange.lowerBound,
                repRangeUpper: repRange.upperBound,
                targetWeight: baseWeight.map { roundToIncrement($0, increment: weightIncrement) }
            )
        }
    }

    private struct ExerciseHistorySummary {
        var frequency: Int
        var lastDate: Date
        var lastTopWeight: Double?
    }

    private static func makeHistorySummary(from workouts: [Workout]) -> [String: ExerciseHistorySummary] {
        var summary: [String: ExerciseHistorySummary] = [:]

        for workout in workouts {
            for exercise in workout.exercises {
                let nonCardioSets = exercise.sets.filter { $0.weight > 0 && $0.reps > 0 }
                let topWeight = nonCardioSets.map(\.weight).max()

                if var existing = summary[exercise.name] {
                    existing.frequency += 1
                    if workout.date > existing.lastDate {
                        existing.lastDate = workout.date
                        existing.lastTopWeight = topWeight
                    }
                    summary[exercise.name] = existing
                } else {
                    summary[exercise.name] = ExerciseHistorySummary(
                        frequency: 1,
                        lastDate: workout.date,
                        lastTopWeight: topWeight
                    )
                }
            }
        }

        return summary
    }

    private static func makeExercisesByGroup(
        from workouts: [Workout],
        historySummary: [String: ExerciseHistorySummary]
    ) -> [MuscleGroup: [String]] {
        let workoutNames = Set(workouts.flatMap { $0.exercises.map(\.name) })
        let fallbackNames = Set(ExerciseMetadataManager.defaultExerciseNames)
        let allNames = workoutNames.union(fallbackNames)

        let mappings = ExerciseMetadataManager.shared.resolvedMappings(for: allNames, includeUntagged: false)
        var grouped: [MuscleGroup: [String]] = [:]

        for (name, tags) in mappings {
            for tag in tags {
                guard let group = tag.builtInGroup, group != .cardio else { continue }
                grouped[group, default: []].append(name)
            }
        }

        for group in grouped.keys {
            grouped[group] = (grouped[group] ?? []).sorted { lhs, rhs in
                let lCount = historySummary[lhs]?.frequency ?? 0
                let rCount = historySummary[rhs]?.frequency ?? 0
                if lCount != rCount {
                    return lCount > rCount
                }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        }

        return grouped
    }

    private static func roundToIncrement(_ value: Double, increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }

    private static func normalizeExerciseName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
