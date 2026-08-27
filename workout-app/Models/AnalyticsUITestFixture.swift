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
                    bodyMass: (181 - Double(index) * 0.05) / 2.20462,
                    bodyFatPercentage: 0.18 - Double(index) * 0.000_2
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
