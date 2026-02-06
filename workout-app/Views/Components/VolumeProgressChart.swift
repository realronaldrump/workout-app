import SwiftUI
import Charts

struct VolumeProgressChart: View {
    let workouts: [Workout]
    var onTap: (() -> Void)? = nil
    @State private var selectedMetric = VolumeMetric.totalVolume
    
    enum VolumeMetric: String, CaseIterable {
        case totalVolume = "Total Volume"
        case totalSets = "Total Sets"
        case avgVolume = "Avg Volume/Exercise"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Progress")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .tracking(1.0)
                
                BrutalistSegmentedPicker(
                    title: "Metric",
                    selection: $selectedMetric,
                    options: VolumeMetric.allCases.map { ($0.rawValue, $0) }
                )
            }
            
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
        .onChange(of: selectedMetric) { _, _ in
            Haptics.selection()
        }
    }

    private var chartContainer: some View {
        Chart {
            ForEach(chartData, id: \.date) { dataPoint in
                LineMark(
                    x: .value("Date", dataPoint.date),
                    y: .value(selectedMetric.rawValue, dataPoint.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.Colors.accent)
                
                AreaMark(
                    x: .value("Date", dataPoint.date),
                    y: .value(selectedMetric.rawValue, dataPoint.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.Colors.accent.opacity(0.2))
                
                PointMark(
                    x: .value("Date", dataPoint.date),
                    y: .value(selectedMetric.rawValue, dataPoint.value)
                )
                .foregroundStyle(Theme.Colors.accent)
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
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let direction = value.translation.width
                    guard abs(direction) > 40 else { return }
                    let all = VolumeMetric.allCases
                    guard let index = all.firstIndex(of: selectedMetric) else { return }
                    let nextIndex = direction < 0 ? min(index + 1, all.count - 1) : max(index - 1, 0)
                    if nextIndex != index {
                        selectedMetric = all[nextIndex]
                        Haptics.selection()
                    }
                }
        )
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
