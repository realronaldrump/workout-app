import SwiftUI
import Charts

struct VolumeProgressChart: View {
    let workouts: [Workout]
    var onTap: (() -> Void)?
    @State private var selectedMetric = VolumeMetric.totalVolume
    private let maxChartWidth: CGFloat = 720
    @State private var isHorizontalSwipeActive = false

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
        Group {
            if chartData.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("No workouts in this range.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text("Log a workout to see volume trends.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            } else {
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
                        .symbolSize(pointSymbolSize)
                    }
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .stride(by: xAxisComponent, count: xAxisStride)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: xAxisDateFormat)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let numericValue = value.as(Double.self) {
                                Text(formatAxisValue(numericValue))
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            let dx = abs(value.translation.width)
                            let dy = abs(value.translation.height)
                            isHorizontalSwipeActive = dx > max(30, dy * 1.25)
                        }
                        .onEnded { value in
                            defer { isHorizontalSwipeActive = false }
                            guard isHorizontalSwipeActive else { return }
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
        }
        .frame(maxWidth: maxChartWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Dynamic Axis Configuration

    private var dateRangeInDays: Int {
        guard let earliest = chartData.first?.date,
              let latest = chartData.last?.date else { return 7 }
        return max(1, Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 7)
    }

    private var xAxisComponent: Calendar.Component {
        if dateRangeInDays > 180 { return .month }       // 6+ months: monthly ticks
        if dateRangeInDays > 28 { return .weekOfYear }   // 1-6 months: weekly ticks
        return .day                                       // Under 1 month: daily ticks
    }

    private var xAxisStride: Int {
        if dateRangeInDays > 365 { return 2 }            // Over a year: every 2 months
        if dateRangeInDays > 180 { return 1 }            // 6-12 months: every month
        if dateRangeInDays > 60 { return 2 }             // 2-6 months: every 2 weeks
        if dateRangeInDays > 28 { return 1 }             // 1-2 months: every week
        return 7                                          // Under 1 month: every 7 days
    }

    private var xAxisDateFormat: Date.FormatStyle {
        if dateRangeInDays > 180 {
            return .dateTime.month(.abbreviated)         // "Jan", "Feb"
        }
        return .dateTime.month(.abbreviated).day()       // "Jan 5"
    }

    private var pointSymbolSize: CGFloat {
        // Smaller points for dense data
        if chartData.count > 50 { return 12 }
        if chartData.count > 20 { return 20 }
        return 30
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
        if selectedMetric == .totalSets {
            return String(Int(value.rounded()))
        }
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}
