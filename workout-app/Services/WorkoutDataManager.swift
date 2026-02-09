import Foundation
import SwiftUI
import Combine

@MainActor
class WorkoutDataManager: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published private(set) var importedWorkouts: [Workout] = []
    @Published private(set) var loggedWorkouts: [Workout] = []
    @Published private(set) var loggedWorkoutIds: Set<UUID> = []
    @Published var isLoading = false
    @Published var error: String?

    private let identityStore = WorkoutIdentityStore()

    nonisolated func processImportedWorkoutSets(
        _ sets: [WorkoutSet],
        healthDataSnapshot: [WorkoutHealthData] = []
    ) async {
        let (existingImported, identitySnapshot): ([Workout], [String: UUID]) = await MainActor.run {
            self.isLoading = true
            self.error = nil
            return (self.importedWorkouts, self.identityStore.snapshot())
        }
        // Run heavy grouping logic on a background thread
        let task = Task.detached(priority: .userInitiated) {
            // Group sets by date (year-month-day-hour) using Calendar components
            // This is significantly faster than DateFormatter
            let calendar = Calendar.current

            let groupedByWorkout = Dictionary(grouping: sets) { set -> String in
                WorkoutIdentity.workoutKey(date: set.date, workoutName: set.workoutName, calendar: calendar)
            }

            var existingIdsByKey: [String: UUID] = [:]
            for workout in existingImported {
                let key = WorkoutIdentity.workoutKey(date: workout.date, workoutName: workout.name, calendar: calendar)
                existingIdsByKey[key] = workout.id
            }

            var legacyCandidatesByHour: [String: [(id: UUID, date: Date)]] = [:]
            for health in healthDataSnapshot {
                let bucket = WorkoutIdentity.hourBucket(for: health.workoutDate, calendar: calendar)
                legacyCandidatesByHour[bucket, default: []].append((health.workoutId, health.workoutDate))
            }

            var workouts: [Workout] = []
            var newIdentityEntries: [String: UUID] = [:]

            for (workoutKey, workoutSets) in groupedByWorkout {
                guard let firstSet = workoutSets.first else { continue }

                // Group by exercise within workout
                let groupedByExercise = Dictionary(grouping: workoutSets) { $0.exerciseName }

                var exercises: [Exercise] = []
                for (exerciseName, exerciseSets) in groupedByExercise {
                    let sortedSets = exerciseSets.sorted { $0.setOrder < $1.setOrder }
                    exercises.append(Exercise(name: exerciseName, sets: sortedSets))
                }

                let workoutDate = workoutSets.map { $0.date }.min() ?? firstSet.date
                let workoutName = firstSet.workoutName.trimmingCharacters(in: .whitespacesAndNewlines)

                let resolvedId: UUID
                if let existingId = existingIdsByKey[workoutKey] {
                    resolvedId = existingId
                } else if let mappedId = identitySnapshot[workoutKey] {
                    resolvedId = mappedId
                } else {
                    let hourBucket = WorkoutIdentity.hourBucket(for: workoutDate, calendar: calendar)
                    if var candidates = legacyCandidatesByHour[hourBucket], !candidates.isEmpty {
                        var bestIndex = 0
                        var bestDistance = abs(candidates[0].date.timeIntervalSince(workoutDate))
                        if candidates.count > 1 {
                            for index in 1..<candidates.count {
                                let distance = abs(candidates[index].date.timeIntervalSince(workoutDate))
                                if distance < bestDistance {
                                    bestDistance = distance
                                    bestIndex = index
                                }
                            }
                        }
                        let chosen = candidates.remove(at: bestIndex)
                        if candidates.isEmpty {
                            legacyCandidatesByHour.removeValue(forKey: hourBucket)
                        } else {
                            legacyCandidatesByHour[hourBucket] = candidates
                        }
                        resolvedId = chosen.id
                    } else {
                        resolvedId = UUID()
                    }
                }

                if identitySnapshot[workoutKey] != resolvedId {
                    newIdentityEntries[workoutKey] = resolvedId
                }

                let workout = Workout(
                    id: resolvedId,
                    date: workoutDate,
                    name: workoutName,
                    duration: firstSet.duration,
                    exercises: exercises
                )
                workouts.append(workout)
            }

            let sortedWorkouts = workouts.sorted { $0.date > $1.date }
            return (sortedWorkouts, newIdentityEntries)
        }
        let (processedWorkouts, newIdentityEntries) = await task.value

        // Update UI on MainActor
        await MainActor.run {
            self.importedWorkouts = processedWorkouts
            self.mergeSources()
            self.isLoading = false
            self.identityStore.merge(newIdentityEntries)
        }
    }

    func setLoggedWorkouts(_ logged: [LoggedWorkout]) {
        let mapped = logged.map(Self.mapLoggedWorkoutToAnalyticsWorkout)
        loggedWorkouts = mapped.sorted { $0.date > $1.date }
        loggedWorkoutIds = Set(logged.map(\.id))
        mergeSources()
    }

    private func mergeSources() {
        workouts = (importedWorkouts + loggedWorkouts).sorted { $0.date > $1.date }
    }

    func getExerciseHistory(for exerciseName: String) -> [(date: Date, sets: [WorkoutSet])] {
        var history: [(date: Date, sets: [WorkoutSet])] = []

        for workout in workouts {
            if let exercise = workout.exercises.first(where: { $0.name == exerciseName }) {
                history.append((date: workout.date, sets: exercise.sets))
            }
        }

        return history.sorted { $0.date < $1.date }
    }

    func calculateStats() -> WorkoutStats {
        return calculateStats(for: workouts)
    }

    func calculateStats(for filteredWorkouts: [Workout]) -> WorkoutStats {
        let allExercises = filteredWorkouts.flatMap { $0.exercises }
        let exerciseGroups = Dictionary(grouping: allExercises) { $0.name }

        // Calculate favorite exercise (most performed)
        let favoriteExercise = exerciseGroups
            .map { (name: $0.key, count: $0.value.count) }
            .max { $0.count < $1.count }?.name

        // Calculate strongest exercise
        let strongestExercise = exerciseGroups
            .map { (name: $0.key, maxWeight: $0.value.map { $0.maxWeight }.max() ?? 0) }
            .max { $0.maxWeight < $1.maxWeight }
            .map { (name: $0.name, weight: $0.maxWeight) }

        // Calculate improvement
        var mostImprovedExercise: (name: String, improvement: Double)?
        for (exerciseName, exercises) in exerciseGroups {
            let sortedByDate = exercises.sorted { exercise1, exercise2 in
                let date1 = exercise1.sets.map(\.date).min() ?? Date.distantPast
                let date2 = exercise2.sets.map(\.date).min() ?? Date.distantPast
                return date1 < date2
            }

            if let first = sortedByDate.first?.oneRepMax,
               let last = sortedByDate.last?.oneRepMax,
               first > 0 {
                let improvement = ((last - first) / first) * 100
                if let current = mostImprovedExercise {
                    if improvement > current.improvement {
                        mostImprovedExercise = (name: exerciseName, improvement: improvement)
                    }
                } else {
                    mostImprovedExercise = (name: exerciseName, improvement: improvement)
                }
            }
        }

        // Calculate streaks and consistency (use all workouts for streaks, filtered for other stats)
        let (currentStreak, longestStreak) = calculateStreaks()
        let workoutsPerWeek = calculateWorkoutsPerWeek(for: filteredWorkouts)

        // Calculate average duration
        let avgDuration = calculateAverageDuration(for: filteredWorkouts)

        return WorkoutStats(
            totalWorkouts: filteredWorkouts.count,
            totalExercises: allExercises.count,
            totalVolume: filteredWorkouts.reduce(0) { $0 + $1.totalVolume },
            totalSets: filteredWorkouts.reduce(0) { $0 + $1.totalSets },
            avgWorkoutDuration: avgDuration,
            favoriteExercise: favoriteExercise,
            strongestExercise: strongestExercise,
            mostImprovedExercise: mostImprovedExercise,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            workoutsPerWeek: workoutsPerWeek,
            lastWorkoutDate: filteredWorkouts.map(\.date).max()
        )
    }

    private func calculateStreaks() -> (current: Int, longest: Int) {
        guard !workouts.isEmpty else { return (0, 0) }

        let intentionalRestDays = max(0, UserDefaults.standard.integer(forKey: "intentionalRestDays"))
        let allowedGapDays = intentionalRestDays + 1 // e.g. 1 rest day => allow workout days 2 days apart

        // 1. Normalize all workout dates to start of day
        let calendar = Calendar.current
        let uniqueDays = Set(workouts.map { calendar.startOfDay(for: $0.date) })

        // 2. Sort unique days
        let sortedDays = uniqueDays.sorted()

        guard !sortedDays.isEmpty else { return (0, 0) }

        var currentStreak = 0
        var longestStreak = 0
        var tempStreak = 1
        var lastDay = sortedDays[0]

        // 3. Calculate consecutive workout-days, allowing a configurable rest window.
        for index in 1..<sortedDays.count {
            let currentDay = sortedDays[index]
            let daysDiff = calendar.dateComponents([.day], from: lastDay, to: currentDay).day ?? 0

            if daysDiff >= 1 && daysDiff <= allowedGapDays {
                // Within the allowed rest window, streak continues (streak counts workout days, not calendar span).
                tempStreak += 1
            } else {
                // Broken streak
                longestStreak = max(longestStreak, tempStreak)
                tempStreak = 1
            }
            lastDay = currentDay
        }

        longestStreak = max(longestStreak, tempStreak)

        // 4. Calculate current streak
        // Check if the streak is still active (last workout was today or yesterday or day before yesterday?)
        if let lastWorkoutDay = sortedDays.last {
            let today = calendar.startOfDay(for: Date())
            let daysSinceLast = calendar.dateComponents([.day], from: lastWorkoutDay, to: today).day ?? 0

            // If last workout was within the rest window, streak is still active.
            if daysSinceLast <= allowedGapDays {
                currentStreak = tempStreak
            }
        }

        return (currentStreak, longestStreak)
    }

    private func calculateWorkoutsPerWeek(for filteredWorkouts: [Workout]) -> Double {
        guard !filteredWorkouts.isEmpty else { return 0 }

        let calendar = Calendar.current
        let intentionalRestDays = max(0, UserDefaults.standard.integer(forKey: "intentionalRestDays"))
        let allowedGapDays = intentionalRestDays + 1

        // Use unique workout-days to avoid over-counting gaps when multiple sessions happen in one day.
        let uniqueDays = Set(filteredWorkouts.map { calendar.startOfDay(for: $0.date) })
        let sortedDays = uniqueDays.sorted()
        guard !sortedDays.isEmpty else { return 0 }

        // Effective span in days, capping gaps larger than the intentional rest window so long breaks don't
        // dilute consistency/session frequency.
        var effectiveDays = 1
        var lastDay = sortedDays[0]
        for index in 1..<sortedDays.count {
            let day = sortedDays[index]
            let diff = calendar.dateComponents([.day], from: lastDay, to: day).day ?? 0
            if diff > 0 {
                effectiveDays += min(diff, allowedGapDays)
            }
            lastDay = day
        }

        let effectiveWeeks = max(Double(effectiveDays) / 7.0, 1.0)
        return Double(filteredWorkouts.count) / effectiveWeeks
    }

    private func calculateAverageDuration(for filteredWorkouts: [Workout]) -> String {
        let durations = filteredWorkouts
            .map { WorkoutAnalytics.durationMinutes(from: $0.duration) }
            .filter { $0 > 0 }

        guard !durations.isEmpty else { return "0m" }

        let avgMinutes = durations.reduce(0, +) / Double(durations.count)
        let rounded = Int(round(avgMinutes))
        if rounded >= 60 {
            return "\(rounded / 60)h \(rounded % 60)m"
        }
        return "\(rounded)m"
    }
    func clearAllData() {
        self.workouts = []
        self.importedWorkouts = []
        self.loggedWorkouts = []
        self.loggedWorkoutIds = []
        self.isLoading = false
        self.error = nil
        self.identityStore.clear()
    }
}

// MARK: - LoggedWorkout mapping

private extension WorkoutDataManager {
    nonisolated static func mapLoggedWorkoutToAnalyticsWorkout(_ logged: LoggedWorkout) -> Workout {
        let duration = formatDuration(start: logged.startedAt, end: logged.endedAt)

        let exercises: [Exercise] = logged.exercises.map { loggedExercise in
            let sets: [WorkoutSet] = loggedExercise.sets.map { loggedSet in
                WorkoutSet(
                    date: logged.startedAt,
                    workoutName: logged.name,
                    duration: duration,
                    exerciseName: loggedExercise.name,
                    setOrder: loggedSet.order,
                    weight: loggedSet.weight,
                    reps: loggedSet.reps,
                    distance: loggedSet.distance ?? 0,
                    seconds: loggedSet.seconds ?? 0
                )
            }
            return Exercise(id: loggedExercise.id, name: loggedExercise.name, sets: sets.sorted { $0.setOrder < $1.setOrder })
        }

        return Workout(
            id: logged.id,
            date: logged.startedAt,
            name: logged.name,
            duration: duration,
            exercises: exercises
        )
    }

    nonisolated static func formatDuration(start: Date, end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        let minutes = Int(ceil(seconds / 60.0))
        if minutes >= 60 {
            let hours = minutes / 60
            let minutesRemainder = minutes % 60
            return minutesRemainder == 0 ? "\(hours)h" : "\(hours)h \(minutesRemainder)m"
        }
        return "\(minutes)m"
    }

}
