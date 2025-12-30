import SwiftUI
import Charts

struct VolumeProgressChart: View {
    let workouts: [Workout]
    @State private var selectedMetric = VolumeMetric.totalVolume
    
    enum VolumeMetric: String, CaseIterable {
        case totalVolume = "Total Volume"
        case totalSets = "Total Sets"
        case avgVolume = "Avg Volume/Exercise"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Progress")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(VolumeMetric.allCases, id: \.self) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            Chart {
                ForEach(chartData, id: \.date) { dataPoint in
                    LineMark(
                        x: .value("Date", dataPoint.date),
                        y: .value(selectedMetric.rawValue, dataPoint.value)
                    )
                    .foregroundStyle(Color.accentColor)
                    
                    AreaMark(
                        x: .value("Date", dataPoint.date),
                        y: .value(selectedMetric.rawValue, dataPoint.value)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.2))
                    
                    PointMark(
                        x: .value("Date", dataPoint.date),
                        y: .value(selectedMetric.rawValue, dataPoint.value)
                    )
                    .foregroundStyle(Color.accentColor)
                }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if selectedMetric == .totalVolume || selectedMetric == .avgVolume {
                            if let v = value.as(Double.self) {
                                Text(formatAxisValue(v))
                            }
                        } else {
                            if let v = value.as(Int.self) {
                                Text("\(v)")
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private var chartData: [(date: Date, value: Double)] {
        let sortedWorkouts = workouts.sorted { $0.date < $1.date }
        
        switch selectedMetric {
        case .totalVolume:
            return sortedWorkouts.map { (date: $0.date, value: $0.totalVolume) }
        case .totalSets:
            return sortedWorkouts.map { (date: $0.date, value: Double($0.totalSets)) }
        case .avgVolume:
            return sortedWorkouts.map { 
                let avgVolume = $0.exercises.isEmpty ? 0 : $0.totalVolume / Double($0.exercises.count)
                return (date: $0.date, value: avgVolume)
            }
        }
    }
    
    private func formatAxisValue(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}