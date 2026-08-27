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
    @Binding var selectedWeekStart: Date?
    var averageOverride: Double?

    private var average: Double {
        if let averageOverride {
            return averageOverride
        }
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
                        selectedWeekStart == nil || isSelected(week.weekStart)
                            ? Theme.Colors.accent
                            : Theme.Colors.accent.opacity(0.35)
                    )
                    .cornerRadius(3)
                    .opacity(
                        selectedWeekStart == nil && week.count < Int(ceil(average))
                            ? 0.45
                            : 1
                    )

                    if isSelected(week.weekStart) {
                        RuleMark(x: .value("Selected week", week.weekStart, unit: .weekOfYear))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }

                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .chartXSelection(value: $selectedWeekStart)
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
            .chartPlotStyle { plotArea in
                plotArea.clipped()
            }
            .frame(height: Theme.ChartHeight.standard)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly activity")
            .accessibilityValue(accessibilitySummary)
            .accessibilityHint("Swipe up or down to focus a week and its workouts.")
            .accessibilityAdjustableAction(adjustSelection)
        }
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedWeekStart else { return false }
        return Calendar.current.isDate(date, equalTo: selectedWeekStart, toGranularity: .weekOfYear)
    }

    private var accessibilitySummary: String {
        if let selectedWeekStart,
           let selected = weeks.first(where: { isSelected($0.weekStart) }) {
            return "Week of \(selectedWeekStart.formatted(date: .abbreviated, time: .omitted)), "
                + "\(selected.count) workouts."
        }
        return "\(weeks.reduce(0) { $0 + $1.count }) workouts across \(weeks.count) weeks."
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !weeks.isEmpty else { return }
        let currentIndex = selectedWeekStart.flatMap { selected in
            weeks.firstIndex {
                Calendar.current.isDate($0.weekStart, equalTo: selected, toGranularity: .weekOfYear)
            }
        }
        switch direction {
        case .increment:
            selectedWeekStart = weeks[min((currentIndex ?? -1) + 1, weeks.count - 1)].weekStart
        case .decrement:
            selectedWeekStart = weeks[max((currentIndex ?? weeks.count) - 1, 0)].weekStart
        @unknown default:
            return
        }
    }
}
