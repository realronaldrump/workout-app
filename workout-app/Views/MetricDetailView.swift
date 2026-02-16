import SwiftUI
import Charts

struct MetricDetailView: View {
    let kind: WorkoutMetricDetailKind
    let workouts: [Workout]
    var scrollTarget: MetricDetailScrollTarget?

    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1
    @State private var hasAutoScrolled = false
    @State private var selectedStreakRunId: String?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        header

                        switch kind {
                        case .sessions:
                            sessionsSection
                        case .streak:
                            streakSection
                        case .totalVolume:
                            totalVolumeSection
                        case .avgDuration:
                            avgDurationSection
                        }
                    }
                    .padding(Theme.Spacing.xl)
                }
                .onAppear {
                    guard !hasAutoScrolled else { return }
                    guard let scrollTarget else { return }
                    hasAutoScrolled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(Theme.Animation.smooth) {
                            proxy.scrollTo(scrollTarget, anchor: .top)
                        }
                    }
                }
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
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sessionsChart

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
            let stats = dataManager.calculateStats(for: dataManager.workouts)
            HStack(spacing: Theme.Spacing.xl) {
                MetricPill(title: "Current Streak", value: "\(stats.currentStreak) days")
                MetricPill(title: "Longest Streak", value: "\(stats.longestStreak) days")
            }

            LongestStreaksSection(
                workouts: dataManager.workouts,
                collapsedCount: 4,
                maxExpandedCount: 12,
                selectedRunId: selectedStreakRun?.id
            ) { run in
                selectedStreakRunId = run.id
            }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)

            if let run = selectedStreakRun {
                HStack {
                    Text("Viewing \(run.workoutDayCount)-day streak")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Text(streakDateLabel(run))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            CalendarHeatmap(
                workouts: selectedStreakWorkouts,
                anchorDate: selectedStreakRun?.end
            )
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)

            Text("sessions \(selectedStreakWorkouts.count)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)

            ForEach(selectedStreakWorkouts) { workout in
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

    private var totalVolumeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            totalVolumeChart

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
                    .id(MetricDetailScrollTarget.topExercisesByVolume)

                ForEach(exerciseTotals.prefix(6), id: \.name) { exercise in
                    NavigationLink(
                        destination: ExerciseDetailView(
                            exerciseName: exercise.name,
                            dataManager: dataManager,
                            annotationsManager: annotationsManager,
                            gymProfilesManager: gymProfilesManager
                        )
                    ) {
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
                        .softCard(elevation: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var avgDurationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            durationChart

            let minutes = durationPoints.map(\.value)
            if let avg = average(minutes), let min = minutes.min(), let max = minutes.max() {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.md) {
                        MetricPill(title: "Average", value: formatDurationMinutes(avg))
                        MetricPill(title: "Min", value: formatDurationMinutes(min))
                        MetricPill(title: "Max", value: formatDurationMinutes(max))
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                        MetricPill(title: "Average", value: formatDurationMinutes(avg))
                        MetricPill(title: "Min", value: formatDurationMinutes(min))
                        MetricPill(title: "Max", value: formatDurationMinutes(max))
                    }
                }
            }

            let longest = sortedWorkouts
                .map { (workout: $0, minutes: WorkoutAnalytics.durationMinutes(from: $0.duration)) }
                .sorted { $0.minutes > $1.minutes }
                .prefix(10)

            if !longest.isEmpty {
                Text("Longest Sessions")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(Array(longest), id: \.workout.id) { item in
                    NavigationLink(destination: WorkoutDetailView(workout: item.workout)) {
                        MetricWorkoutRow(
                            workout: item.workout,
                            subtitle: "\(formatDurationMinutes(item.minutes)) | \(timeOfDayLabel(for: item.workout.date))"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sortedWorkouts: [Workout] {
        workouts.sorted { $0.date > $1.date }
    }

    private var title: String {
        switch kind {
        case .sessions: return "Sessions"
        case .streak: return "Streak"
        case .totalVolume: return "Total Volume"
        case .avgDuration: return "Avg Duration"
        }
    }

    private var subtitle: String {
        switch kind {
        case .sessions:
            return "sessions \(workouts.count)"
        case .streak:
            if let run = selectedStreakRun {
                return "\(run.workoutDayCount)-day streak | sessions \(selectedStreakWorkouts.count)"
            }
            return "sessions \(workouts.count)"
        case .totalVolume:
            let total = workouts.reduce(0) { $0 + $1.totalVolume }
            return "sessions \(workouts.count) | total \(formatVolume(total))"
        case .avgDuration:
            return "sessions \(workouts.count)"
        }
    }

    private var streakRuns: [StreakRun] {
        WorkoutAnalytics.streakRuns(
            for: dataManager.workouts,
            intentionalRestDays: intentionalRestDays
        )
    }

    private var streakRunsByLength: [StreakRun] {
        streakRuns.sorted {
            if $0.workoutDayCount != $1.workoutDayCount {
                return $0.workoutDayCount > $1.workoutDayCount
            }
            return $0.end > $1.end
        }
    }

    private var streakRunsByRecency: [StreakRun] {
        streakRuns.sorted { $0.end > $1.end }
    }

    private var currentStreakRun: StreakRun? {
        let allowedGapDays = max(0, intentionalRestDays) + 1
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return streakRunsByRecency.first { run in
            let endDay = calendar.startOfDay(for: run.end)
            let daysSince = calendar.dateComponents([.day], from: endDay, to: today).day ?? Int.max
            return daysSince <= allowedGapDays
        }
    }

    private var selectedStreakRun: StreakRun? {
        if let selectedStreakRunId,
           let matched = streakRuns.first(where: { $0.id == selectedStreakRunId }) {
            return matched
        }
        return currentStreakRun ?? streakRunsByLength.first ?? streakRunsByRecency.first
    }

    private var selectedStreakWorkouts: [Workout] {
        guard let run = selectedStreakRun else { return sortedWorkouts }
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: run.start)
        let endDay = calendar.startOfDay(for: run.end)

        return dataManager.workouts
            .filter { workout in
                let day = calendar.startOfDay(for: workout.date)
                return day >= startDay && day <= endDay
            }
            .sorted { $0.date > $1.date }
    }

    private func streakDateLabel(_ run: StreakRun) -> String {
        let calendar = Calendar.current
        if calendar.isDate(run.start, inSameDayAs: run.end) {
            return run.start.formatted(date: .abbreviated, time: .omitted)
        }
        let start = run.start.formatted(Date.FormatStyle().month(.abbreviated).day())
        let end = run.end.formatted(Date.FormatStyle().month(.abbreviated).day().year())
        return "\(start) - \(end)"
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

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func formatDurationMinutes(_ minutes: Double) -> String {
        let value = Int(round(minutes))
        if value >= 60 {
            return "\(value / 60)h \(value % 60)m"
        }
        return "\(value)m"
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
        .softCard(elevation: 1)
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
        .softCard(elevation: 1)
    }
}

// MARK: - Charts

private extension MetricDetailView {
    struct MetricPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    struct SessionBucket: Identifiable {
        let weekStart: Date
        let count: Int
        var id: Date { weekStart }
    }

    struct DaySessionBucket: Identifiable {
        let dayStart: Date
        let count: Int
        var id: Date { dayStart }
    }

    var sundayCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    func weekStart(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    var durationPoints: [MetricPoint] {
        sortedWorkouts.map { workout in
            MetricPoint(date: workout.date, value: WorkoutAnalytics.durationMinutes(from: workout.duration))
        }
        .filter { $0.value > 0 }
        .sorted { $0.date < $1.date }
    }

    var volumePoints: [MetricPoint] {
        sortedWorkouts.map { workout in
            MetricPoint(date: workout.date, value: workout.totalVolume)
        }
        .sorted { $0.date < $1.date }
    }

    var weeklySessions: [SessionBucket] {
        let calendar = sundayCalendar
        let buckets: [Date: Int] = sortedWorkouts.reduce(into: [:]) { result, workout in
            let weekStart = weekStart(for: workout.date, calendar: calendar)
            result[weekStart, default: 0] += 1
        }

        return buckets
            .map { SessionBucket(weekStart: $0.key, count: $0.value) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    var singleWeekDailySessions: [DaySessionBucket]? {
        guard let earliest = sortedWorkouts.last?.date,
              let latest = sortedWorkouts.first?.date else {
            return nil
        }

        let calendar = sundayCalendar
        let earliestWeekStart = weekStart(for: earliest, calendar: calendar)
        let latestWeekStart = weekStart(for: latest, calendar: calendar)
        guard calendar.isDate(earliestWeekStart, inSameDayAs: latestWeekStart) else {
            return nil
        }

        let countsByDay: [Date: Int] = sortedWorkouts.reduce(into: [:]) { result, workout in
            let dayStart = calendar.startOfDay(for: workout.date)
            result[dayStart, default: 0] += 1
        }

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: latestWeekStart) else {
                return nil
            }
            let dayStart = calendar.startOfDay(for: day)
            return DaySessionBucket(dayStart: dayStart, count: countsByDay[dayStart, default: 0])
        }
    }

    var sessionsChart: some View {
        Group {
            if weeklySessions.isEmpty {
                EmptyChartCard(title: "Weekly Sessions", message: "Not enough sessions to chart yet.")
            } else if let dailySessions = singleWeekDailySessions {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Daily Sessions")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Chart(dailySessions) { bucket in
                        BarMark(
                            x: .value("Day", bucket.dayStart),
                            y: .value("Sessions", bucket.count)
                        )
                        .foregroundStyle(Theme.Colors.accent)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: dailySessions.map(\.dayStart)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let intValue = value.as(Int.self) {
                                    Text("\(intValue)")
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Weekly Sessions")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Chart(weeklySessions) { bucket in
                        BarMark(
                            x: .value("Week", bucket.weekStart),
                            y: .value("Sessions", bucket.count)
                        )
                        .foregroundStyle(Theme.Colors.accent)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear, count: max(1, weeklySessions.count / 4))) { _ in
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let intValue = value.as(Int.self) {
                                    Text("\(intValue)")
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }

    var totalVolumeChart: some View {
        Group {
            if volumePoints.isEmpty {
                EmptyChartCard(title: "Volume Trend", message: "Not enough volume data to chart yet.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Volume Trend")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Chart(volumePoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Volume", point.value)
                        )
                        .foregroundStyle(Theme.Colors.accent)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Volume", point.value)
                        )
                        .foregroundStyle(Theme.Colors.accent.opacity(0.18))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let axisValue = value.as(Double.self) {
                                    Text(formatVolume(axisValue))
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }

    var durationChart: some View {
        Group {
            if durationPoints.isEmpty {
                EmptyChartCard(title: "Duration Trend", message: "Not enough duration data to chart yet.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Duration Trend")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Chart(durationPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Minutes", point.value)
                        )
                        .foregroundStyle(Theme.Colors.accentSecondary)
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let axisValue = value.as(Double.self) {
                                    Text(formatDurationMinutes(axisValue))
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }
}

private struct EmptyChartCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}
