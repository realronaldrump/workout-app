import Foundation

enum SampleData {
    static let workouts: [Workout] = {
        let calendar = Calendar.current
        let now = Date()

        let pushDate = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let pullDate = calendar.date(byAdding: .day, value: -4, to: now) ?? now
        let legsDate = calendar.date(byAdding: .day, value: -6, to: now) ?? now

        let pushSets = [
            WorkoutSet(date: pushDate, workoutName: "Push Strength", duration: "58m", exerciseName: "Bench Press", setOrder: 1, weight: 185, reps: 8, distance: 0, seconds: 0, rpe: "8"),
            WorkoutSet(date: pushDate, workoutName: "Push Strength", duration: "58m", exerciseName: "Bench Press", setOrder: 2, weight: 195, reps: 6, distance: 0, seconds: 0, rpe: "8"),
            WorkoutSet(date: pushDate, workoutName: "Push Strength", duration: "58m", exerciseName: "Incline DB Press", setOrder: 1, weight: 65, reps: 10, distance: 0, seconds: 0, rpe: "7"),
            WorkoutSet(date: pushDate, workoutName: "Push Strength", duration: "58m", exerciseName: "Incline DB Press", setOrder: 2, weight: 70, reps: 8, distance: 0, seconds: 0, rpe: "8")
        ]

        let pullSets = [
            WorkoutSet(date: pullDate, workoutName: "Pull Power", duration: "52m", exerciseName: "Barbell Row", setOrder: 1, weight: 185, reps: 8, distance: 0, seconds: 0, rpe: "8"),
            WorkoutSet(date: pullDate, workoutName: "Pull Power", duration: "52m", exerciseName: "Barbell Row", setOrder: 2, weight: 195, reps: 6, distance: 0, seconds: 0, rpe: "8"),
            WorkoutSet(date: pullDate, workoutName: "Pull Power", duration: "52m", exerciseName: "Lat Pulldown", setOrder: 1, weight: 140, reps: 10, distance: 0, seconds: 0, rpe: "7"),
            WorkoutSet(date: pullDate, workoutName: "Pull Power", duration: "52m", exerciseName: "Lat Pulldown", setOrder: 2, weight: 150, reps: 8, distance: 0, seconds: 0, rpe: "8")
        ]

        let legsSets = [
            WorkoutSet(date: legsDate, workoutName: "Leg Day", duration: "64m", exerciseName: "Back Squat", setOrder: 1, weight: 245, reps: 8, distance: 0, seconds: 0, rpe: "8"),
            WorkoutSet(date: legsDate, workoutName: "Leg Day", duration: "64m", exerciseName: "Back Squat", setOrder: 2, weight: 265, reps: 6, distance: 0, seconds: 0, rpe: "8"),
            WorkoutSet(date: legsDate, workoutName: "Leg Day", duration: "64m", exerciseName: "Romanian Deadlift", setOrder: 1, weight: 185, reps: 10, distance: 0, seconds: 0, rpe: "7"),
            WorkoutSet(date: legsDate, workoutName: "Leg Day", duration: "64m", exerciseName: "Romanian Deadlift", setOrder: 2, weight: 195, reps: 8, distance: 0, seconds: 0, rpe: "8")
        ]

        let workouts = [
            makeWorkout(date: pushDate, name: "Push Strength", duration: "58m", sets: pushSets),
            makeWorkout(date: pullDate, name: "Pull Power", duration: "52m", sets: pullSets),
            makeWorkout(date: legsDate, name: "Leg Day", duration: "64m", sets: legsSets)
        ]

        return workouts.sorted { $0.date > $1.date }
    }()

    static let stats: WorkoutStats = {
        let totalVolume = workouts.reduce(0) { $0 + $1.totalVolume }
        let totalSets = workouts.reduce(0) { $0 + $1.totalSets }
        let totalExercises = workouts.reduce(0) { $0 + $1.exercises.count }

        return WorkoutStats(
            totalWorkouts: workouts.count,
            totalExercises: totalExercises,
            totalVolume: totalVolume,
            totalSets: totalSets,
            avgWorkoutDuration: "58m",
            favoriteExercise: "Bench Press",
            strongestExercise: (name: "Back Squat", weight: 265),
            mostImprovedExercise: (name: "Bench Press", improvement: 6.2),
            currentStreak: 3,
            longestStreak: 5,
            workoutsPerWeek: 3.4,
            lastWorkoutDate: workouts.first?.date
        )
    }()

    static let insights: [Insight] = [
        Insight(
            id: UUID(),
            type: .personalRecord,
            title: "PR",
            message: "Bench Press 195 lbs | delta +10",
            exerciseName: "Bench Press",
            date: workouts.first?.date ?? Date(),
            priority: 10,
            actionLabel: "Trend",
            metric: 195
        ),
        Insight(
            id: UUID(),
            type: .recommendation,
            title: "Readiness",
            message: "hrv 42 ms | rhr 58 bpm",
            exerciseName: nil,
            date: workouts.first?.date ?? Date(),
            priority: 7,
            actionLabel: nil,
            metric: 42
        ),
        Insight(
            id: UUID(),
            type: .plateau,
            title: "Plateau",
            message: "Lat Pulldown max 150 lbs | delta 0 | n=4",
            exerciseName: "Lat Pulldown",
            date: workouts.last?.date ?? Date(),
            priority: 6,
            actionLabel: "History",
            metric: 150
        )
    ]

    static let healthData: WorkoutHealthData = {
        let workout = workouts.first ?? Workout(date: Date(), name: "Sample", duration: "45m", exercises: [])
        let start = Calendar.current.date(byAdding: .minute, value: -55, to: workout.date) ?? workout.date
        let end = workout.date
        let sleepStart = Calendar.current.date(byAdding: .hour, value: -8, to: workout.date) ?? workout.date
        let sleepSummary = SleepSummary(
            totalSleep: 7.2 * 3600,
            inBed: 8.0 * 3600,
            stageDurations: [
                .deep: 1.4 * 3600,
                .core: 3.6 * 3600,
                .rem: 2.2 * 3600
            ],
            start: sleepStart,
            end: workout.date
        )

        return WorkoutHealthData(
            workoutId: workout.id,
            workoutDate: workout.date,
            workoutStartTime: start,
            workoutEndTime: end,
            avgHeartRate: 142,
            maxHeartRate: 176,
            minHeartRate: 98,
            heartRateSamples: heartRateSamples(start: start, end: end),
            activeCalories: 420,
            basalCalories: 80,
            distance: 820,
            avgSpeed: 1.4,
            avgPower: 210,
            stepCount: 2100,
            flightsClimbed: 4,
            hrvSamples: hrvSamples(date: workout.date),
            restingHeartRate: 58,
            bloodOxygenSamples: [BloodOxygenSample(timestamp: workout.date, value: 98)],
            respiratoryRateSamples: [RespiratoryRateSample(timestamp: workout.date, value: 15.2)],
            bodyMass: 81.2,
            bodyFatPercentage: 0.18,
            bodyTemperature: 36.7,
            sleepSummary: sleepSummary,
            dailyActiveEnergy: 620,
            dailyBasalEnergy: 1450,
            dailySteps: 8400,
            dailyExerciseMinutes: 48,
            dailyMoveMinutes: 70,
            dailyStandMinutes: 690,
            vo2Max: 42.5,
            heartRateRecovery: 28,
            walkingHeartRateAverage: 88,
            appleWorkoutType: "Strength Training",
            appleWorkoutDuration: 3300
        )
    }()

    private static func makeWorkout(date: Date, name: String, duration: String, sets: [WorkoutSet]) -> Workout {
        let grouped = Dictionary(grouping: sets) { $0.exerciseName }
        let exercises = grouped.map { Exercise(name: $0.key, sets: $0.value.sorted { $0.setOrder < $1.setOrder }) }
        return Workout(date: date, name: name, duration: duration, exercises: exercises)
    }

    private static func heartRateSamples(start: Date, end: Date) -> [HeartRateSample] {
        let totalSeconds = max(end.timeIntervalSince(start), 1)
        let steps = 24
        let stepDuration = totalSeconds / Double(steps)

        return (0..<steps).map { index in
            let timestamp = start.addingTimeInterval(Double(index) * stepDuration)
            let baseline = 118 + (index % 5) * 6
            let peak = index > 12 ? 20 : 0
            return HeartRateSample(timestamp: timestamp, value: Double(baseline + peak))
        }
    }

    private static func hrvSamples(date: Date) -> [HRVSample] {
        return (0..<4).map { index in
            let timestamp = Calendar.current.date(byAdding: .hour, value: -index * 6, to: date) ?? date
            let value = 48.0 + Double(index * 3)
            return HRVSample(timestamp: timestamp, value: value)
        }
    }
}
