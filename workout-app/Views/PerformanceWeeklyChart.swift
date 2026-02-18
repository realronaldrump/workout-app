import SwiftUI
import Charts

// MARK: - Weekly Activity Chart

struct PerformanceWeeklyCount: Identifiable {
    let weekStart: Date
    let count: Int
    var id: Date { weekStart }
}

struct PerformanceWeeklyChart: View {
    let weeks: [PerformanceWeeklyCount]

    private var average: Double {
        guard !weeks.isEmpty else { return 0 }
        return Double(weeks.map(\.count).reduce(0, +)) / Double(weeks.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last \(weeks.count) weeks")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Text("Avg \(String(format: "%.1f", average))/wk")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.accent)
            }

            Chart {
                ForEach(weeks) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Workouts", week.count)
                    )
                    .foregroundStyle(
                        week.count >= Int(ceil(average))
                            ? Theme.Colors.accent
                            : Theme.Colors.accent.opacity(0.35)
                    )
                    .cornerRadius(3)
                }

                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let countValue = value.as(Int.self) {
                            Text("\(countValue)")
                        }
                    }
                }
            }
            .frame(height: 180)
        }
    }
}
