import Charts
import SwiftUI

struct BodyCompositionTrendChart: View {
    let points: [TimeSeriesPoint]
    let ma7: [TimeSeriesPoint]
    let ra30: [TimeSeriesPoint]
    let trend: TrendSummary?
    let forecast: [ForecastPoint]

    let color: Color
    let fullDomain: ClosedRange<Date>?

    let showMA7: Bool
    let showRA30: Bool
    let showTrend: Bool
    let showForecast: Bool

    let headerValueText: (Double) -> String
    let axisValueText: (Double) -> String

    @State private var selectedPoint: TimeSeriesPoint?
    @State private var selectionClearTask: Task<Void, Never>?

    init(
        points: [TimeSeriesPoint],
        ma7: [TimeSeriesPoint],
        ra30: [TimeSeriesPoint],
        trend: TrendSummary?,
        forecast: [ForecastPoint],
        color: Color,
        fullDomain: ClosedRange<Date>? = nil,
        showMA7: Bool,
        showRA30: Bool,
        showTrend: Bool,
        showForecast: Bool,
        headerValueText: @escaping (Double) -> String,
        axisValueText: @escaping (Double) -> String
    ) {
        self.points = points.sorted { $0.date < $1.date }
        self.ma7 = ma7.sorted { $0.date < $1.date }
        self.ra30 = ra30.sorted { $0.date < $1.date }
        self.trend = trend
        self.forecast = forecast
        self.color = color
        self.fullDomain = fullDomain
        self.showMA7 = showMA7
        self.showRA30 = showRA30
        self.showTrend = showTrend
        self.showForecast = showForecast
        self.headerValueText = headerValueText
        self.axisValueText = axisValueText
    }

    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.value)
        if showMA7 { values.append(contentsOf: ma7.map(\.value)) }
        if showRA30 { values.append(contentsOf: ra30.map(\.value)) }

        if let trend, showTrend {
            values.append(predictedValue(on: trend.windowStart, trend: trend))
            values.append(predictedValue(on: trend.windowEnd, trend: trend))
        }

        if showForecast, !forecast.isEmpty {
            values.append(contentsOf: forecast.map(\.predicted))
        }

        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        if minValue == maxValue {
            let padding = max(abs(minValue) * 0.05, 1)
            return (minValue - padding)...(maxValue + padding)
        }

        let span = maxValue - minValue
        let padding = span * 0.12
        return (minValue - padding)...(maxValue + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(headerText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Chart {
                if !points.isEmpty {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Baseline", yDomain.lowerBound),
                            yEnd: .value("Value", point.value)
                        )
                        .foregroundStyle(color.opacity(0.14))
                        .interpolationMethod(.catmullRom)
                    }
                }

                if showForecast, !forecast.isEmpty, let latestDate = points.last?.date {
                    RuleMark(x: .value("Latest", latestDate))
                        .foregroundStyle(Theme.Colors.border.opacity(0.22))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("LATEST")
                                .font(Theme.Typography.metricLabel)
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .textCase(.uppercase)
                                .tracking(0.8)
                        }
                }

                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }

                if showMA7 {
                    ForEach(ma7) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("7d MA", point.value)
                        )
                        .foregroundStyle(Theme.Colors.accentSecondary.opacity(0.9))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 3]))
                        .interpolationMethod(.catmullRom)
                    }
                }

                if showRA30 {
                    ForEach(ra30) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("30d RA", point.value)
                        )
                        .foregroundStyle(Theme.Colors.accentTertiary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 3]))
                        .interpolationMethod(.catmullRom)
                    }
                }

                if let trend, showTrend {
                    let start = TimeSeriesPoint(date: trend.windowStart, value: trend.intercept)
                    let end = TimeSeriesPoint(date: trend.windowEnd, value: predictedValue(on: trend.windowEnd, trend: trend))

                    LineMark(
                        x: .value("Date", start.date),
                        y: .value("Trend", start.value)
                    )
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                    LineMark(
                        x: .value("Date", end.date),
                        y: .value("Trend", end.value)
                    )
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }

                if let trend, showForecast, let day90 = forecast.first(where: { $0.horizonDays == 90 }) {
                    let startDate = points.last?.date ?? trend.windowEnd
                    let startValue = points.last?.value ?? predictedValue(on: trend.windowEnd, trend: trend)
                    let start = TimeSeriesPoint(date: startDate, value: startValue)
                    let end = TimeSeriesPoint(date: day90.date, value: day90.predicted)

                    LineMark(
                        x: .value("Date", start.date),
                        y: .value("Forecast", start.value)
                    )
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [1, 4]))

                    LineMark(
                        x: .value("Date", end.date),
                        y: .value("Forecast", end.value)
                    )
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [1, 4]))

                    PointMark(
                        x: .value("Date", end.date),
                        y: .value("Forecast", end.value)
                    )
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .symbolSize(55)
                }

                if let selectedPoint {
                    PointMark(
                        x: .value("Selected", selectedPoint.date),
                        y: .value("Selected", selectedPoint.value)
                    )
                    .foregroundStyle(color)
                    .symbolSize(85)
                }

                if let selectedPoint {
                    RuleMark(x: .value("Selected", selectedPoint.date))
                        .foregroundStyle(color.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXScale(domain: fullXDomain)
            .chartYScale(domain: yDomain)
            .chartPlotStyle { plotArea in
                plotArea.clipped()
            }
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
                        if let axisValue = value.as(Double.self) {
                            Text(axisValueText(axisValue))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectionClearTask?.cancel()
                                    guard isPrimarilyHorizontalDrag(value.translation) else { return }
                                    updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                }
                                .onEnded { value in
                                    let tapped = isTapLike(value.translation)
                                    guard tapped || isPrimarilyHorizontalDrag(value.translation) else { return }
                                    if tapped {
                                        updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                                    scheduleSelectionClear()
                                }
                        )
                }
            }
            .frame(height: 220)
        }
        .onDisappear {
            selectionClearTask?.cancel()
        }
    }

    private var headerText: String {
        if let selectedPoint {
            let date = selectedPoint.date.formatted(date: .abbreviated, time: .omitted)
            return "\(date) | \(headerValueText(selectedPoint.value))"
        }

        guard let first = points.first?.date, let last = points.last?.date else { return "No data" }
        let start = first.formatted(date: .abbreviated, time: .omitted)
        let end = last.formatted(date: .abbreviated, time: .omitted)
        return "\(start) - \(end)"
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        guard frame.contains(location) else { return }
        let x = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: x) else { return }

        if let closest = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) {
            selectedPoint = closest
        }
    }

    private func scheduleSelectionClear() {
        guard selectedPoint != nil else { return }
        selectionClearTask?.cancel()
        selectionClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                selectedPoint = nil
            }
        }
    }

    private func isTapLike(_ translation: CGSize) -> Bool {
        abs(translation.width) < 10 && abs(translation.height) < 10
    }

    private func isPrimarilyHorizontalDrag(_ translation: CGSize) -> Bool {
        let dx = abs(translation.width)
        let dy = abs(translation.height)
        return dx > max(14, dy * 1.2)
    }

    private var fullXDomain: ClosedRange<Date> {
        if let fullDomain {
            // Only pad when we have an endpoint mark that would otherwise be pinned to the boundary
            // (notably the +90d forecast point when Forecast is enabled).
            let pad: TimeInterval = 12 * 60 * 60

            var upperPad: TimeInterval = 0

            if showForecast, let maxForecastDate = forecast.map(\.date).max(), abs(maxForecastDate.timeIntervalSince(fullDomain.upperBound)) < 1 {
                upperPad = pad
            }

            return fullDomain.lowerBound...fullDomain.upperBound.addingTimeInterval(upperPad)
        }
        guard let first = points.first?.date, let last = points.last?.date else {
            let now = Date()
            return now...now
        }

        if first == last {
            let pad: TimeInterval = 12 * 60 * 60
            return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
        }

        return first...last
    }

    private var dateRangeInDays: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: fullXDomain.lowerBound)
        let end = calendar.startOfDay(for: fullXDomain.upperBound)
        return max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    private var xAxisComponent: Calendar.Component {
        if dateRangeInDays > 730 { return .year }       // 2+ years: yearly ticks
        if dateRangeInDays > 180 { return .month }      // 6m-2y: monthly ticks
        if dateRangeInDays > 28 { return .weekOfYear }  // 1-6m: weekly ticks
        return .day                                      // under 1 month: daily ticks
    }

    private var xAxisStride: Int {
        switch xAxisComponent {
        case .year:
            if dateRangeInDays > 3650 { return 2 }       // 10+ years: every 2 years
            return 1
        case .month:
            if dateRangeInDays > 365 { return 2 }        // 1-2y: every 2 months
            return 1                                     // 6-12m: monthly
        case .weekOfYear:
            if dateRangeInDays > 90 { return 2 }         // 3-6m: every 2 weeks
            return 1                                     // 1-3m: weekly
        default:
            if dateRangeInDays <= 7 { return 1 }         // under 1w: daily
            if dateRangeInDays <= 14 { return 2 }        // 1-2w: every 2 days
            return 7                                     // 2-4w: weekly labels
        }
    }

    private var xAxisDateFormat: Date.FormatStyle {
        switch xAxisComponent {
        case .year:
            return .dateTime.year()
        case .month:
            if dateRangeInDays > 365 {
                return .dateTime.year().month(.abbreviated)
            }
            return .dateTime.month(.abbreviated)
        default:
            return .dateTime.month(.abbreviated).day()
        }
    }

    private func predictedValue(on date: Date, trend: TrendSummary) -> Double {
        let calendar = Calendar.current
        let xDays = Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: trend.windowStart), to: calendar.startOfDay(for: date)).day ?? 0)
        return (trend.slopePerDay * xDays) + trend.intercept
    }
}
