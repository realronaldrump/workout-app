import SwiftUI
import Charts

struct ExerciseBreakdownView: View {
    let workouts: [Workout]
    
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Exercises by Volume")
                .font(.title2)
                .fontWeight(.bold)
            
            if !exerciseData.isEmpty {
                Chart(exerciseData, id: \.name) { exercise in
                    BarMark(
                        x: .value("Volume", exercise.volume),
                        y: .value("Exercise", exercise.name)
                    )
                    .foregroundStyle(Color.accentColor)
                    .annotation(position: .trailing) {
                        Text(formatVolume(exercise.volume))
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }
}