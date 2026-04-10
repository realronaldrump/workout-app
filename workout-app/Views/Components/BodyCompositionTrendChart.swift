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

    @Environment(\.colorScheme) private var colorScheme

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
        let padding = span * 0.15
        return (minValue - padding)...(maxValue + padding)
    }

    // MARK: - Gradient fill

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [
                color.opacity(colorScheme == .dark ? 0.25 : 0.18),
                color.opacity(colorScheme == .dark ? 0.08 : 0.05),
                color.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            chartHeader
                .animation(.easeInOut(duration: 0.15), value: selectedPoint?.date)

            chart
                .frame(height: Theme.ChartHeight.expanded)
        }
        .onDisappear {
            selectionClearTask?.cancel()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var chartHeader: some View {
        if let selectedPoint {
            // Selection state — prominent value callout
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(headerValueText(selectedPoint.value))
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText())

                Text(selectedPoint.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textTertiary)

                Spacer()
            }
        } else {
            // Default state — date range
            HStack(alignment: .firstTextBaseline) {
                if let first = points.first?.date, let last = points.last?.date {
                    Text(first.formatted(.dateTime.month(.abbreviated).day()))
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("–")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(last.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Text("No data")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            // Area fill — gradient under the primary line
            if !points.isEmpty {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Baseline", yDomain.lowerBound),
                        yEnd: .value("Value", point.value),
                        series: .value("Series", "Actual")
                    )
                    .foregroundStyle(areaGradient)
                    .interpolationMethod(.monotone)
                }
            }

            // Forecast divider — subtle "now" marker
            if showForecast, !forecast.isEmpty, let latestDate = points.last?.date {
                RuleMark(x: .value("Latest", latestDate))
                    .foregroundStyle(Theme.Colors.border.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 4) {
                        Text("NOW")
                            .font(Theme.Typography.microLabel)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .tracking(1.2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.Colors.surfaceRaised)
                            )
                    }
            }

            // Primary data line
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    series: .value("Series", "Actual")
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            // 7-day moving average
            if showMA7 {
                ForEach(ma7) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("7d MA", point.value),
                        series: .value("Series", "7d MA")
                    )
                    .foregroundStyle(Theme.Colors.accentSecondary.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [4, 3]))
                    .interpolationMethod(.monotone)
                }
            }

            // 30-day rolling average
            if showRA30 {
                ForEach(ra30) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("30d RA", point.value),
                        series: .value("Series", "30d RA")
                    )
                    .foregroundStyle(Theme.Colors.accentTertiary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [7, 4]))
                    .interpolationMethod(.monotone)
                }
            }

            // Trend regression line
            if let trend, showTrend {
                let start = TimeSeriesPoint(date: trend.windowStart, value: trend.intercept)
                let end = TimeSeriesPoint(date: trend.windowEnd, value: predictedValue(on: trend.windowEnd, trend: trend))

                LineMark(
                    x: .value("Date", start.date),
                    y: .value("Trend", start.value),
                    series: .value("Series", "Trend")
                )
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))

                LineMark(
                    x: .value("Date", end.date),
                    y: .value("Trend", end.value),
                    series: .value("Series", "Trend")
                )
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }

            // 90-day forecast projection
            if let trend, showForecast, let day90 = forecast.first(where: { $0.horizonDays == 90 }) {
                let startDate = points.last?.date ?? trend.windowEnd
                let startValue = points.last?.value ?? predictedValue(on: trend.windowEnd, trend: trend)
                let start = TimeSeriesPoint(date: startDate, value: startValue)
                let end = TimeSeriesPoint(date: day90.date, value: day90.predicted)

                LineMark(
                    x: .value("Date", start.date),
                    y: .value("Forecast", start.value),
                    series: .value("Series", "Forecast")
                )
                .foregroundStyle(color.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [2, 4]))

                LineMark(
                    x: .value("Date", end.date),
                    y: .value("Forecast", end.value),
                    series: .value("Series", "Forecast")
                )
                .foregroundStyle(color.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [2, 4]))

                // Endpoint marker — ring style
                PointMark(
                    x: .value("Date", end.date),
                    y: .value("Forecast", end.value)
                )
                .foregroundStyle(color.opacity(0.5))
                .symbolSize(44)
                .symbol {
                    Circle()
                        .strokeBorder(color.opacity(0.5), lineWidth: 2)
                        .frame(width: 8, height: 8)
                }
            }

            // Selection — vertical scrubber line
            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(color.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            // Selection — highlighted data point with halo
            if let selectedPoint {
                PointMark(
                    x: .value("Selected", selectedPoint.date),
                    y: .value("Selected", selectedPoint.value)
                )
                .foregroundStyle(color)
                .symbolSize(64)
                .symbol {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 20, height: 20)
                        Circle()
                            .fill(Theme.Colors.cardBackground)
                            .frame(width: 9, height: 9)
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .chartXScale(domain: fullXDomain)
        .chartYScale(domain: yDomain)
        .chartPlotStyle { plotArea in
            plotArea
                .clipped()
                .background(
                    Theme.Colors.cardBackground.opacity(0.3)
                )
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: xAxisComponent, count: xAxisStride)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.Colors.border.opacity(0.4))
                AxisValueLabel(format: xAxisDateFormat)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.Colors.border.opacity(0.3))
                AxisValueLabel {
                    if let axisValue = value.as(Double.self) {
                        Text(axisValueText(axisValue))
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
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
    }

    // MARK: - Selection

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        guard frame.contains(location) else { return }
        let x = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: x) else { return }

        if let closest = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) {
            withAnimation(.easeOut(duration: 0.12)) {
                selectedPoint = closest
            }
        }
    }

    private func scheduleSelectionClear() {
        guard selectedPoint != nil else { return }
        selectionClearTask?.cancel()
        selectionClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
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

    // MARK: - Domain & Axis Computation

    private var fullXDomain: ClosedRange<Date> {
        if let fullDomain {
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
        if dateRangeInDays > 730 { return .year }
        if dateRangeInDays > 90 { return .month }
        if dateRangeInDays > 28 { return .weekOfYear }
        return .day
    }

    private var xAxisStride: Int {
        switch xAxisComponent {
        case .year:
            if dateRangeInDays > 3650 { return 2 }
            return 1
        case .month:
            if dateRangeInDays > 365 { return 2 }
            if dateRangeInDays > 180 { return 2 }
            return 1
        case .weekOfYear:
            return 2
        default:
            if dateRangeInDays <= 7 { return 1 }
            if dateRangeInDays <= 14 { return 2 }
            return 7
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
