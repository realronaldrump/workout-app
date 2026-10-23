import Charts
import SwiftUI

struct ConsistencySummaryView: View {
    let average: Double
    let weeks: [TimeSeriesPoint]
    let goalWeeks: Int
    let totalWeeks: Int
    let currentStreak: Int
    let bestStreak: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(average.formatted(.number.precision(.fractionLength(1))))
                        .font(Theme.Typography.heroNumber)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("workouts a week")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: Theme.Spacing.md)
                AppHelpButton(
                    title: "Consistency",
                    message: "Saved break days lower weekly goals. Workouts during a break still count. Streaks allow the rest days set in Settings."
                )
            }
            if !weeks.isEmpty {
                Chart(weeks) { week in
                    BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Workouts", week.value))
                        .foregroundStyle(Theme.Colors.accent)
                        .cornerRadius(1)
                }
                .frame(height: 160)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(weeks.count <= 13 ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).year(.twoDigits)))
                                    .font(Theme.Typography.caption2)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Theme.Colors.rule.opacity(0.6))
                        AxisValueLabel {
                            if let number = value.as(Double.self), number.rounded() == number {
                                Text(number.formatted(.number.precision(.fractionLength(0))))
                                    .font(Theme.Typography.caption2)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .accessibilityLabel("Workouts per week")
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
                : AnyLayout(StatColumns())
            layout {
                DisplayStat(value: "\(goalWeeks) of \(totalWeeks)", label: "weeks at goal")
                DisplayStat(value: "\(currentStreak)", unit: dayUnit(currentStreak), label: "current streak")
                DisplayStat(value: "\(bestStreak)", unit: dayUnit(bestStreak), label: "best streak")
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.vertical, Theme.Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("consistency-summary")
    }

    private func dayUnit(_ count: Int) -> String {
        count == 1 ? "day" : "days"
    }
}
