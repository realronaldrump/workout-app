import SwiftUI
import Charts

struct CorrelationDetailView: View {
    let insight: CorrelationInsight
    let workouts: [Workout]
    let healthData: [UUID: WorkoutHealthData]

    private struct Point: Identifiable {
        let id = UUID()
        let workoutId: UUID
        let date: Date
        let x: Double
        let y: Double
    }

    private var workoutStore: [UUID: Workout] {
        Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
    }

    private var points: [Point] {
        switch insight.kind {
        case .sleepVsOutput:
            return workouts.compactMap { workout in
                guard let sleep = healthData[workout.id]?.sleepSummary?.totalHours else { return nil }
                let density = WorkoutAnalytics.effortDensity(for: workout)
                guard density > 0 else { return nil }
                return Point(workoutId: workout.id, date: workout.date, x: sleep, y: density)
            }
            .sorted { $0.date < $1.date }

        case .readinessVsOutput:
            return workouts.compactMap { workout in
                guard let readiness = WorkoutAnalytics.readinessScore(for: healthData[workout.id]) else { return nil }
                let density = WorkoutAnalytics.effortDensity(for: workout)
                guard density > 0 else { return nil }
                return Point(workoutId: workout.id, date: workout.date, x: readiness, y: density)
            }
            .sorted { $0.date < $1.date }

        case .sleepVsTopExercise:
            guard let exerciseName = insight.exerciseName else { return [] }
            return workouts.compactMap { workout in
                guard let sleep = healthData[workout.id]?.sleepSummary?.totalHours else { return nil }
                guard let exercise = workout.exercises.first(where: { $0.name == exerciseName }) else { return nil }
                let best = exercise.sets.map { WorkoutAnalytics.estimateOneRepMaxForDetail(weight: $0.weight, reps: $0.reps) }.max() ?? 0
                guard best > 0 else { return nil }
                return Point(workoutId: workout.id, date: workout.date, x: sleep, y: best)
            }
            .sorted { $0.date < $1.date }
        }
    }

    private var xLabel: String {
        switch insight.kind {
        case .sleepVsOutput, .sleepVsTopExercise:
            return "Sleep (h)"
        case .readinessVsOutput:
            return "Readiness"
        }
    }

    private var yLabel: String {
        switch insight.kind {
        case .sleepVsOutput, .readinessVsOutput:
            return "Output"
        case .sleepVsTopExercise:
            return "1RM"
        }
    }

    private var threshold: Double {
        switch insight.kind {
        case .sleepVsOutput, .sleepVsTopExercise:
            return 7
        case .readinessVsOutput:
            return 70
        }
    }

    private var splitSummary: (high: Double, low: Double)? {
        guard points.count >= 2 else { return nil }
        let highs = points.filter { $0.x >= threshold }.map(\.y)
        let lows = points.filter { $0.x < threshold }.map(\.y)
        guard !highs.isEmpty, !lows.isEmpty else { return nil }
        let avgHigh = highs.reduce(0, +) / Double(highs.count)
        let avgLow = lows.reduce(0, +) / Double(lows.count)
        return (avgHigh, avgLow)
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    chartSection

                    supportingSection
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle("Correlation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(insight.title)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.5)

            Text(insight.detail)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.lg) {
                metricPill(title: "r", value: String(format: "%.2f", insight.correlation))
                metricPill(title: "n", value: "\(insight.supportingCount)")

                if let splitSummary {
                    metricPill(title: "High", value: formatY(splitSummary.high))
                    metricPill(title: "Low", value: formatY(splitSummary.low))
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Scatter")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if points.isEmpty {
                Text("Not enough data to chart.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                Chart(points) { point in
                    PointMark(
                        x: .value(xLabel, point.x),
                        y: .value(yLabel, point.y)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                    .symbolSize(70)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatX(v))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatY(v))
                            }
                        }
                    }
                }
                .frame(height: 260)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }

    private var supportingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Supporting Workouts")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if points.isEmpty {
                Text("No supporting points.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                ForEach(points.sorted { $0.date > $1.date }) { point in
                    if let workout = workoutStore[point.workoutId] {
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(workout.name)
                                        .font(Theme.Typography.headline)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(point.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(formatX(point.x))")
                                        .font(Theme.Typography.captionBold)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text("\(formatY(point.y))")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .padding(Theme.Spacing.lg)
                            .softCard(elevation: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func formatX(_ value: Double) -> String {
        switch insight.kind {
        case .sleepVsOutput, .sleepVsTopExercise:
            return String(format: "%.1f", value)
        case .readinessVsOutput:
            return "\(Int(value))"
        }
    }

    private func formatY(_ value: Double) -> String {
        switch insight.kind {
        case .sleepVsOutput, .readinessVsOutput:
            return String(format: "%.1f", value)
        case .sleepVsTopExercise:
            return "\(Int(value))"
        }
    }
}

private extension WorkoutAnalytics {
    // Kept private to detail views; avoids changing the public API surface of WorkoutAnalytics.
    nonisolated static func estimateOneRepMaxForDetail(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }
}

