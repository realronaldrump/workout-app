import SwiftUI
import Charts

struct ExerciseBreakdownView: View {
    let workouts: [Workout]
    var onTap: (() -> Void)? = nil

    private var exerciseData: [(name: String, volume: Double, frequency: Int)] {
        let allExercises = workouts.flatMap { $0.exercises }
        let grouped = Dictionary(grouping: allExercises) { $0.name }

        return grouped.map { (name: String, exercises: [Exercise]) in
            let totalVolume = exercises.reduce(0) { $0 + $1.totalVolume }
            return (name: name, volume: totalVolume, frequency: exercises.count)
        }
        .sorted { $0.volume > $1.volume }
        .prefix(10)
        .reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Top Exercises by Volume")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if !exerciseData.isEmpty {
                Group {
                    if let onTap {
                        MetricTileButton(chevronPlacement: .bottomTrailing, action: onTap) {
                            chartContainer
                        }
                    } else {
                        chartContainer
                    }
                }
            }
        }
    }

    private var chartContainer: some View {
        Chart(exerciseData, id: \.name) { exercise in
            BarMark(
                x: .value("Volume", exercise.volume),
                y: .value("Exercise", exercise.name)
            )
            .foregroundStyle(Theme.Colors.accent)
            .annotation(position: .trailing) {
                Text(formatVolume(exercise.volume))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .frame(height: CGFloat(exerciseData.count) * 40)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatVolume(v))
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }
}
