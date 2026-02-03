import SwiftUI
import Charts

struct MetricDetailView: View {
    let type: MetricDrilldown
    let workouts: [Workout]

    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var dataManager: WorkoutDataManager

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header

                    switch type {
                    case .sessions:
                        sessionsSection
                    case .streak:
                        streakSection
                    case .volume:
                        volumeSection
                    case .readiness:
                        readinessSection
                    }
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(sortedWorkouts) { workout in
                NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                    MetricWorkoutRow(
                        workout: workout,
                        subtitle: "\(workout.date.formatted(date: .abbreviated, time: .omitted)) | \(timeOfDayLabel(for: workout.date))"
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            let stats = dataManager.calculateStats(for: workouts)
            HStack(spacing: Theme.Spacing.xl) {
                MetricPill(title: "Current Streak", value: "\(stats.currentStreak) days")
                MetricPill(title: "Longest Streak", value: "\(stats.longestStreak) days")
            }

            CalendarHeatmap(workouts: workouts)
                .padding(Theme.Spacing.lg)
                .glassBackground(elevation: 2)

            Text("sessions \(sortedWorkouts.count)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)

            ForEach(sortedWorkouts) { workout in
                NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                    MetricWorkoutRow(
                        workout: workout,
                        subtitle: timeOfDayLabel(for: workout.date)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            let topWorkouts = sortedWorkouts.prefix(8)
            VStack(spacing: Theme.Spacing.md) {
                ForEach(topWorkouts) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        MetricWorkoutRow(
                            workout: workout,
                            subtitle: "\(formatVolume(workout.totalVolume)) volume | \(timeOfDayLabel(for: workout.date))"
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            let exerciseTotals = Dictionary(grouping: workouts.flatMap { $0.exercises }, by: { $0.name })
                .map { name, exercises in
                    (name: name, volume: exercises.reduce(0) { $0 + $1.totalVolume })
                }
                .sorted { $0.volume > $1.volume }

            if !exerciseTotals.isEmpty {
                Text("Top Exercises by Volume")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(exerciseTotals.prefix(6), id: \.name) { exercise in
                    NavigationLink(destination: ExerciseDetailView(exerciseName: exercise.name, dataManager: dataManager)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Text(formatVolume(exercise.volume))
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .glassBackground(elevation: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var readinessSection: some View {
        let points = readinessPoints

        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if points.isEmpty {
                Text("health samples 0")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 2)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Readiness", point.score)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Readiness", point.score)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 180)
                .padding(Theme.Spacing.lg)
                .glassBackground(elevation: 2)

                ForEach(sortedWorkouts) { workout in
                    if let readiness = WorkoutAnalytics.readinessScore(for: healthManager.getHealthData(for: workout.id)) {
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            MetricWorkoutRow(
                                workout: workout,
                                subtitle: "Readiness \(Int(readiness)) | \(timeOfDayLabel(for: workout.date))"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    private var sortedWorkouts: [Workout] {
        workouts.sorted { $0.date > $1.date }
    }

    private var readinessPoints: [ReadinessPoint] {
        sortedWorkouts.compactMap { workout in
            guard let score = WorkoutAnalytics.readinessScore(for: healthManager.getHealthData(for: workout.id)) else { return nil }
            return ReadinessPoint(date: workout.date, score: score, label: "Readiness")
        }
        .sorted { $0.date < $1.date }
    }

    private var title: String {
        switch type {
        case .sessions: return "Sessions"
        case .streak: return "Streak"
        case .volume: return "Total Volume"
        case .readiness: return "Readiness"
        }
    }

    private var subtitle: String {
        switch type {
        case .sessions:
            return "sessions \(workouts.count)"
        case .streak:
            return "sessions \(workouts.count)"
        case .volume:
            let total = workouts.reduce(0) { $0 + $1.totalVolume }
            return "sessions \(workouts.count) | total \(formatVolume(total))"
        case .readiness:
            return "health samples \(healthManager.healthDataStore.count)"
        }
    }

    private func timeOfDayLabel(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        case 17..<22:
            return "Evening"
        default:
            return "Late"
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
}

private struct MetricWorkoutRow: View {
    let workout: Workout
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(workout.duration)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("\(workout.exercises.count) exercises")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 1)
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.md)
        .glassBackground(elevation: 1)
    }
}
