import Charts
import SwiftUI

/// A compact view of the readings behind the overview's plain-language direction.
struct BodyRecentChart: View {
    let days: [BodyTrendDay]
    let domain: ClosedRange<Date>
    let rate: BodyRate?
    let calendar: Calendar

    var body: some View {
        Chart {
            ForEach(days) { day in
                if let pounds = day.reading {
                    PointMark(x: .value("Date", day.day), y: .value("Weight", pounds))
                        .symbolSize(20)
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.60))
                }
            }

            if let rate, let last = days.last, let endWeight = rate.fittedWeightAtEnd,
               !rate.isSteady || abs(rate.change) < 0.5,
               let start = calendar.date(byAdding: .day, value: 1 - rate.windowDays, to: last.day) {
                LineMark(x: .value("Date", start), y: .value("Trend", endWeight - rate.change))
                    .foregroundStyle(BodyFormat.weightTint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                LineMark(x: .value("Date", last.day), y: .value("Trend", endWeight))
                    .foregroundStyle(BodyFormat.weightTint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .chartXScale(domain: domain, range: .plotDimension(startPadding: 4, endPadding: 4))
        .chartYScale(domain: weightDomain)
        .chartXAxis {
            AxisMarks(values: tickDates) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.Colors.rule.opacity(0.6))
                AxisValueLabel()
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(height: 125)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent weight chart")
        .accessibilityValue(SharedFormatters.count(days.count, "weigh-in"))
        .accessibilityIdentifier("body-weight-chart")
    }

    private var tickDates: [Date] {
        let days = calendar.dateComponents([.day], from: domain.lowerBound, to: domain.upperBound).day ?? 0
        return [days / 5, days / 2, 4 * days / 5].compactMap {
            calendar.date(byAdding: .day, value: $0, to: domain.lowerBound)
        }
    }

    private var weightDomain: ClosedRange<Double> {
        var values = days.compactMap(\.reading)
        if let rate, let endWeight = rate.fittedWeightAtEnd {
            values.append(contentsOf: [endWeight, endWeight - rate.change])
        }
        let low = values.min() ?? 0
        let high = values.max() ?? low
        let center = (low + high) / 2
        let halfSpan = max(2, (high - low) * 0.58)
        return (center - halfSpan)...(center + halfSpan)
    }
}
