import SwiftUI
import Charts

struct ExerciseBreakdownView: View {
    let workouts: [Workout]
    var onTap: (() -> Void)?

    // swiftlint:disable:next large_tuple
    private var exerciseData: [(name: String, volume: Double, frequency: Int)] {
        let allExercises = workouts.flatMap { $0.exercises }
        let grouped = Dictionary(grouping: allExercises) { $0.name }

        return grouped.map { (name: String, exercises: [Exercise]) in
            let totalVolume = exercises.reduce(0) { $0 + $1.totalVolume }
            return (name: name, volume: totalVolume, frequency: exercises.count)
        }
        .filter { $0.volume > 0 }
        .sorted { $0.volume > $1.volume }
        .prefix(10)
        .reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Top Exercises by Volume")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Group {
                if !exerciseData.isEmpty {
                    if let onTap {
                        MetricTileButton(chevronPlacement: .bottomTrailing, action: onTap) {
                            chartContainer
                        }
                    } else {
                        chartContainer
                    }
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("No exercise volume data in this range.")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Text("Log workouts to see your top exercises.")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
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
                Text(SharedFormatters.volumeCompact(exercise.volume))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .frame(height: CGFloat(exerciseData.count) * 44)
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let axisValue = value.as(Double.self) {
                        Text(SharedFormatters.volumeCompact(axisValue))
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

}
