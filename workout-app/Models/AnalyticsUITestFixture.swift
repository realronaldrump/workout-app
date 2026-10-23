#if DEBUG
import Foundation

@MainActor
enum AnalyticsUITestFixture {
    static let environmentKey = "WORKOUT_APP_ANALYTICS_FIXTURE"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    static func install(
        dataManager: WorkoutDataManager,
        healthManager: HealthKitManager
    ) {
        ExerciseRelationshipManager.shared.installTransientRelationships([
            ExerciseRelationship(
                exerciseName: "Single Arm Row - Left",
                parentName: "Single Arm Row",
                laterality: .left
            ),
            ExerciseRelationship(
                exerciseName: "Single Arm Row - Right",
                parentName: "Single Arm Row",
                laterality: .right
            )
        ])

        dataManager.installAnalyticsFixture(workouts)
        healthManager.authorizationStatus = .authorized
        healthManager.dailyHealthStore = dailyHealth
        healthManager.dailyHealthCoverage = Set(dailyHealth.keys)
        healthManager.lastDailySyncDate = Date()
    }

    static let workouts: [Workout] = {
        let calendar = Calendar.current
        let now = Date()
        return (0..<14).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: -(index * 7), to: now) else {
                return nil
            }

            var exercises: [Exercise] = [
                Exercise(
                    name: "Bench Press",
                    sets: [
                        set(
                            date: date,
                            exerciseName: "Bench Press",
                            order: 1,
                            weight: 135 + Double((13 - index) * 5),
                            reps: index.isMultiple(of: 3) ? 8 : 5
                        ),
                        set(
                            date: date,
                            exerciseName: "Bench Press",
                            order: 2,
                            weight: 125 + Double((13 - index) * 5),
                            reps: 10
                        )
                    ]
                )
            ]

            if index.isMultiple(of: 2) {
                exercises.append(
                    Exercise(
                        name: "Assisted Pull Up",
                        sets: [
                            set(
                                date: date,
                                exerciseName: "Assisted Pull Up",
                                order: 1,
                                weight: min(60, Double(index * 5)),
                                reps: 8
                            )
                        ]
                    )
                )
            }

            if index.isMultiple(of: 3) {
                exercises.append(
                    Exercise(
                        name: "Running (Treadmill)",
                        sets: [
                            WorkoutSet(
                                date: date,
                                workoutName: "Analytics Upper",
                                duration: "55m",
                                exerciseName: "Running (Treadmill)",
                                setOrder: 1,
                                weight: 0,
                                reps: 20 + index,
                                distance: 1 + Double(index) * 0.25,
                                seconds: 600 + Double(index * 30)
                            )
                        ]
                    )
                )
            }

            if index < 5 {
                exercises.append(
                    Exercise(
                        name: index.isMultiple(of: 2)
                            ? "Single Arm Row - Left"
                            : "Single Arm Row - Right",
                        sets: [
                            set(
                                date: date,
                                exerciseName: index.isMultiple(of: 2)
                                    ? "Single Arm Row - Left"
                                    : "Single Arm Row - Right",
                                order: 1,
                                weight: 45 + Double(index * 5),
                                reps: 10
                            )
                        ]
                    )
                )
            }

            return Workout(
                date: date,
                name: "Analytics Upper \(14 - index)",
                duration: "\(45 + index)m",
                exercises: exercises
            )
        }
        .sorted { $0.date > $1.date }
    }()

    // MARK: - Body measurements

    /// Deterministic noise in -1...1, so fixture screenshots are stable run to run.
    private nonisolated static func fixtureNoise(_ index: Int, salt: Double) -> Double {
        let value = sin(Double(index) * 12.9898 + salt) * 43_758.5453
        return (value - value.rounded(.down)) * 2 - 1
    }

    /// A believable year of weigh-ins: a long cut from about 196 lb, a holiday regain,
    /// then a slower second cut. Daily water swings ride on top of the trend.
    private nonisolated static func fixtureMorningWeight(daysAgo: Int) -> Double {
        let day = Double(420 - daysAgo)
        let trend: Double
        switch day {
        case ..<240: trend = 196 - day * 0.066
        case ..<300: trend = 180.2 + (day - 240) * 0.05
        default: trend = 183.2 - (day - 300) * 0.04
        }
        return trend + 0.55 * sin(day / 4.1) + 0.8 * fixtureNoise(daysAgo, salt: 2)
    }

    private nonisolated static func fixtureBodyFat(daysAgo: Int) -> Double {
        let day = Double(420 - daysAgo)
        return 0.214 - day * 0.000_11 + 0.003 * fixtureNoise(daysAgo, salt: 4)
    }

    private nonisolated static func fixtureSampleID(_ index: Int, tag: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-%04d-%012d", tag, index)) ?? UUID()
    }

    /// Raw samples in storage units (kg and fractions), oldest first, like an `HKSampleQuery`.
    /// About one day in seven is skipped, with a three-week gap for a trip, and some days
    /// have a second, heavier evening reading.
    static let bodySamples: [HealthMetric: [HealthMetricSample]] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var mass: [HealthMetricSample] = []
        var fat: [HealthMetricSample] = []
        for daysAgo in stride(from: 420, through: 0, by: -1) {
            let skipped = daysAgo > 0 && (fixtureNoise(daysAgo, salt: 1) < -0.72 || (118..<139).contains(daysAgo))
            guard !skipped,
                  let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let morning = calendar.date(
                      byAdding: .minute,
                      value: 400 + Int(30 * fixtureNoise(daysAgo, salt: 3)),
                      to: day
                  ) else { continue }
            let pounds = fixtureMorningWeight(daysAgo: daysAgo)
            mass.append(HealthMetricSample(id: fixtureSampleID(daysAgo, tag: 1), timestamp: morning, value: pounds / 2.20462))
            if daysAgo % 11 == 4 {
                mass.append(HealthMetricSample(
                    id: fixtureSampleID(daysAgo, tag: 2),
                    timestamp: morning.addingTimeInterval(12 * 3_600),
                    value: (pounds + 1.6) / 2.20462
                ))
            }
            if daysAgo % 3 == 0 {
                fat.append(HealthMetricSample(
                    id: fixtureSampleID(daysAgo, tag: 3),
                    timestamp: morning.addingTimeInterval(60),
                    value: fixtureBodyFat(daysAgo: daysAgo)
                ))
            }
        }
        return [.bodyMass: mass, .bodyFatPercentage: fat]
    }()

    static let dailyHealth: [Date: DailyHealthData] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let entries = (0..<45).compactMap { index -> (Date, DailyHealthData)? in
            guard let date = calendar.date(byAdding: .day, value: -index, to: today) else {
                return nil
            }
            let sleepStart = calendar.date(byAdding: .hour, value: -8, to: date) ?? date
            let sleep = SleepSummary(
                totalSleep: (6.8 + Double(index % 5) * 0.2) * 3_600,
                inBed: 8 * 3_600,
                stageDurations: [
                    .deep: 1.2 * 3_600,
                    .core: 3.8 * 3_600,
                    .rem: 1.8 * 3_600
                ],
                start: sleepStart,
                end: date
            )
            return (
                date,
                DailyHealthData(
                    dayStart: date,
                    steps: 7_500 + Double((index % 8) * 600),
                    activeEnergy: 420 + Double((index % 6) * 35),
                    exerciseMinutes: 30 + Double(index % 5) * 5,
                    moveMinutes: 55 + Double(index % 7) * 4,
                    standMinutes: 680 + Double(index % 8) * 12,
                    distanceWalkingRunning: 4.2 + Double(index % 6) * 0.4,
                    flightsClimbed: Double(5 + index % 7),
                    sleepSummary: sleep,
                    restingHeartRate: 58 + Double(index % 4),
                    heartRateVariability: 42 + Double(index % 9),
                    bloodOxygen: 97 + Double(index % 2),
                    respiratoryRate: 14.5 + Double(index % 4) * 0.2,
                    vo2Max: 44 + Double(index % 5) * 0.2,
                    bodyMass: fixtureMorningWeight(daysAgo: index) / 2.20462,
                    bodyFatPercentage: fixtureBodyFat(daysAgo: index)
                )
            )
        }
        return Dictionary(uniqueKeysWithValues: entries)
    }()

    private static func set(
        date: Date,
        exerciseName: String,
        order: Int,
        weight: Double,
        reps: Int
    ) -> WorkoutSet {
        WorkoutSet(
            date: date,
            workoutName: "Analytics Upper",
            duration: "55m",
            exerciseName: exerciseName,
            setOrder: order,
            weight: weight,
            reps: reps,
            distance: 0,
            seconds: 0
        )
    }
}
#endif
