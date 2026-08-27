import Charts
import SwiftUI

struct SelectableMetricChart: View {
    enum Style {
        case bars
        case line
        case points
        case step
    }

    let points: [MetricObservation]
    let style: Style
    let tint: Color
    let title: String
    let valueText: (Double) -> String
    @Binding var selectedDate: Date?

    var selectedObservation: MetricObservation? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) <
                abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        Chart(points) { point in
            switch style {
            case .bars:
                BarMark(
                    x: .value("Date", point.date),
                    y: .value(title, point.value)
                )
                .foregroundStyle(tint)
                .cornerRadius(3)
            case .line:
                LineMark(
                    x: .value("Date", point.date),
                    y: .value(title, point.value)
                )
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Date", point.date),
                    y: .value(title, point.value)
                )
                .foregroundStyle(tint)
                .symbolSize(points.count > 40 ? 14 : 28)
            case .points:
                PointMark(
                    x: .value("Date", point.date),
                    y: .value(title, point.value)
                )
                .foregroundStyle(tint)
                .symbolSize(48)
            case .step:
                LineMark(
                    x: .value("Date", point.date),
                    y: .value(title, point.value)
                )
                .foregroundStyle(tint)
                .interpolationMethod(.stepEnd)
                .lineStyle(StrokeStyle(lineWidth: 3))
                PointMark(
                    x: .value("Date", point.date),
                    y: .value(title, point.value)
                )
                .foregroundStyle(tint)
                .symbol(.diamond)
                .symbolSize(58)
            }

            if let selected = selectedObservation, selected.id == point.id {
                RuleMark(x: .value("Selected date", point.date))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartScrollableAxes(isScrollable ? .horizontal : [])
        .chartXVisibleDomain(length: visibleDomainLength)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.border)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.border)
                AxisValueLabel {
                    if let numeric = value.as(Double.self) {
                        Text(valueText(numeric))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .frame(height: Theme.ChartHeight.standard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Swipe up or down to inspect recorded sessions.")
        .accessibilityAdjustableAction(adjustSelection)
    }

    private var isScrollable: Bool {
        points.count > 20 && fullDomainLength > 180 * 86_400
    }

    private var fullDomainLength: TimeInterval {
        guard let first = points.first?.date, let last = points.last?.date else {
            return 86_400
        }
        return max(last.timeIntervalSince(first), 86_400)
    }

    private var visibleDomainLength: TimeInterval {
        isScrollable ? 180 * 86_400 : fullDomainLength
    }

    private var yDomain: ClosedRange<Double> {
        guard let minimum = points.map(\.value).min(),
              let maximum = points.map(\.value).max() else {
            return 0...1
        }
        if style == .bars {
            return 0...max(maximum * 1.12, 1)
        }
        if minimum == maximum {
            let padding = max(abs(minimum) * 0.08, 1)
            return max(0, minimum - padding)...(maximum + padding)
        }
        let padding = (maximum - minimum) * 0.14
        return max(0, minimum - padding)...(maximum + padding)
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let latest = points.last else {
            return "No observations"
        }
        if let selectedObservation {
            return "Selected \(selectedObservation.date.formatted(date: .abbreviated, time: .omitted)), "
                + "\(valueText(selectedObservation.value)), \(selectedObservation.workoutName). "
                + "\(points.count) observations."
        }
        let best = points.max(by: { $0.value < $1.value }) ?? latest
        return "\(points.count) observations. First \(valueText(first.value)); " +
            "latest \(valueText(latest.value)); highest \(valueText(best.value))."
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !points.isEmpty else { return }
        let currentIndex = selectedObservation.flatMap { selected in
            points.firstIndex(where: { $0.id == selected.id })
        }
        let nextIndex: Int
        switch direction {
        case .increment:
            nextIndex = min((currentIndex ?? -1) + 1, points.count - 1)
        case .decrement:
            nextIndex = max((currentIndex ?? points.count) - 1, 0)
        @unknown default:
            return
        }
        selectedDate = points[nextIndex].date
    }
}
