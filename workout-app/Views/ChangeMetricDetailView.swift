import SwiftUI
import Charts

struct ChangeMetricDetailView: View {
    let metric: ChangeMetric
    let windowDays: Int
    let workouts: [Workout]

    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager

    private enum Window: String {
        case previous
        case current
    }

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let window: Window
    }

    private var endDate: Date? {
        workouts.map(\.date).max()
    }

    private var currentStart: Date? {
        guard let endDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: -windowDays, to: endDate)
    }

    private var previousStart: Date? {
        guard let endDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: -(windowDays * 2), to: endDate)
    }

    private var currentWorkouts: [Workout] {
        guard let currentStart else { return [] }
        return workouts.filter { $0.date >= currentStart }
    }

    private var previousWorkouts: [Workout] {
        guard let currentStart, let previousStart else { return [] }
        return workouts.filter { $0.date >= previousStart && $0.date < currentStart }
    }

    private var windowLabel: String {
        if windowDays <= 14 { return "Last 2w" }
        if windowDays <= 28 { return "Last 4w" }
        return "Last \(windowDays)d"
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    headerSection

                    chartSection

                    supportingSection
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(windowLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(formatValue(metric.current))
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Previous")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(formatValue(metric.previous))
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(deltaLabel)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(metric.isPositive ? Theme.Colors.success : Theme.Colors.error)
                    Text(percentLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 2)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Trend")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if chartPoints.isEmpty {
                Text("Not enough data to chart.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 1)
            } else {
                Chart {
                    ForEach(chartPoints) { point in
                        if metric.title == "Sessions" {
                            BarMark(
                                x: .value("Date", point.date),
                                y: .value("Count", point.value)
                            )
                            .foregroundStyle(point.window == .current ? Theme.Colors.accent : Theme.Colors.elevated)
                            .cornerRadius(3)
                        } else {
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(point.window == .current ? Theme.Colors.accent : Theme.Colors.textTertiary)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(point.window == .current ? Theme.Colors.accent : Theme.Colors.textTertiary)
                        }
                    }

                    if let currentStart {
                        RuleMark(x: .value("Current start", currentStart))
                            .foregroundStyle(Theme.Colors.textTertiary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
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
                            if let v = value.as(Double.self) {
                                Text(axisLabel(v))
                            }
                        }
                    }
                }
                .frame(height: 220)
                .padding(Theme.Spacing.lg)
                .glassBackground(elevation: 2)
            }
        }
    }

    private var supportingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Supporting")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            switch metric.title {
            case "Sessions":
                sessionsSupporting
            case "Total Volume":
                volumeSupporting
            case "Avg Duration":
                durationSupporting
            case "Effort Density":
                densitySupporting
            default:
                Text("No supporting view for this metric.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 1)
            }
        }
    }

    private var sessionsSupporting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if currentWorkouts.isEmpty {
                Text("No sessions in this window.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 1)
            } else {
                ForEach(currentWorkouts.sorted { $0.date > $1.date }) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(workout.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .glassBackground(elevation: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var volumeSupporting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            let topWorkouts = currentWorkouts
                .sorted { $0.totalVolume > $1.totalVolume }
                .prefix(8)

            if topWorkouts.isEmpty {
                Text("No volume data in this window.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 1)
            } else {
                Text("Top Workouts")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                ForEach(Array(topWorkouts), id: \.id) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("\(formatVolume(workout.totalVolume)) volume")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .glassBackground(elevation: 1)
                    }
                    .buttonStyle(.plain)
                }

                let exerciseTotals = Dictionary(grouping: currentWorkouts.flatMap { $0.exercises }, by: { $0.name })
                    .map { name, exercises in
                        (name: name, volume: exercises.reduce(0) { $0 + $1.totalVolume })
                    }
                    .sorted { $0.volume > $1.volume }

                if !exerciseTotals.isEmpty {
                    Text("Top Exercises")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.top, Theme.Spacing.sm)

                    ForEach(exerciseTotals.prefix(8), id: \.name) { exercise in
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
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(formatVolume(exercise.volume))
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .padding(Theme.Spacing.lg)
                            .glassBackground(elevation: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var durationSupporting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            let longest = currentWorkouts
                .map { (workout: $0, minutes: WorkoutAnalytics.durationMinutes(from: $0.duration)) }
                .sorted { $0.minutes > $1.minutes }
                .prefix(10)

            if longest.isEmpty {
                Text("No duration data in this window.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 1)
            } else {
                ForEach(Array(longest), id: \.workout.id) { item in
                    NavigationLink(destination: WorkoutDetailView(workout: item.workout)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.workout.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(formatDurationMinutes(item.minutes))
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .glassBackground(elevation: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var densitySupporting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            let top = currentWorkouts
                .map { (workout: $0, density: WorkoutAnalytics.effortDensity(for: $0)) }
                .sorted { $0.density > $1.density }
                .prefix(10)

            if top.isEmpty {
                Text("No density data in this window.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .glassBackground(elevation: 1)
            } else {
                ForEach(Array(top), id: \.workout.id) { item in
                    NavigationLink(destination: WorkoutDetailView(workout: item.workout)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.workout.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("density \(String(format: "%.1f", item.density))")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(Theme.Spacing.lg)
                        .glassBackground(elevation: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var chartPoints: [ChartPoint] {
        switch metric.title {
        case "Sessions":
            return sessionChartPoints
        case "Total Volume":
            return seriesPoints(from: workouts, value: { $0.totalVolume })
        case "Avg Duration":
            return seriesPoints(from: workouts, value: { WorkoutAnalytics.durationMinutes(from: $0.duration) })
        case "Effort Density":
            return seriesPoints(from: workouts, value: { WorkoutAnalytics.effortDensity(for: $0) })
        default:
            return []
        }
    }

    private func seriesPoints(from workouts: [Workout], value: (Workout) -> Double) -> [ChartPoint] {
        guard let currentStart else { return [] }
        let sorted = workouts.sorted { $0.date < $1.date }
        return sorted.compactMap { workout in
            let v = value(workout)
            guard v > 0 else { return nil }
            return ChartPoint(date: workout.date, value: v, window: workout.date >= currentStart ? .current : .previous)
        }
    }

    private var sessionChartPoints: [ChartPoint] {
        guard let currentStart, let previousStart else { return [] }
        let calendar = Calendar.current
        let filtered = workouts.filter { $0.date >= previousStart }
        let buckets: [Date: (count: Int, window: Window)] = filtered.reduce(into: [:]) { result, workout in
            let day = calendar.startOfDay(for: workout.date)
            let window: Window = workout.date >= currentStart ? .current : .previous
            let current = result[day] ?? (0, window)
            result[day] = (current.count + 1, window)
        }

        return buckets
            .map { ChartPoint(date: $0.key, value: Double($0.value.count), window: $0.value.window) }
            .sorted { $0.date < $1.date }
    }

    private var deltaLabel: String {
        let sign = metric.delta >= 0 ? "+" : ""
        switch metric.title {
        case "Sessions":
            return "\(sign)\(Int(metric.delta))"
        case "Total Volume":
            return "\(sign)\(formatVolume(abs(metric.delta)))"
        case "Avg Duration":
            return "\(sign)\(formatDurationMinutes(abs(metric.delta)))"
        default:
            return "\(sign)\(String(format: "%.1f", metric.delta))"
        }
    }

    private var percentLabel: String {
        "\(String(format: "%.0f", metric.percentChange))%"
    }

    private func formatValue(_ value: Double) -> String {
        switch metric.title {
        case "Sessions":
            return "\(Int(value))"
        case "Total Volume":
            return formatVolume(value)
        case "Avg Duration":
            return formatDurationMinutes(value)
        case "Effort Density":
            return String(format: "%.1f", value)
        default:
            return String(format: "%.1f", value)
        }
    }

    private func axisLabel(_ value: Double) -> String {
        switch metric.title {
        case "Sessions":
            return "\(Int(value))"
        case "Total Volume":
            return formatVolume(value)
        case "Avg Duration":
            return formatDurationMinutes(value)
        default:
            return String(format: "%.1f", value)
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        }
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }

    private func formatDurationMinutes(_ minutes: Double) -> String {
        let value = Int(round(minutes))
        if value >= 60 {
            return "\(value / 60)h \(value % 60)m"
        }
        return "\(value)m"
    }
}
