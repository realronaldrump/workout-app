import SwiftUI
import Charts

struct ExerciseProgressChart: View {
    let history: [(date: Date, sets: [WorkoutSet])]
    let chartType: ExerciseDetailView.ChartType
    var countLabel: String?

    @State private var isAppearing = false
    @State private var selectedDataPoint: ChartPoint?
    @State private var lastPRHapticDate: Date?
    @State private var selectionClearTask: Task<Void, Never>?

    private struct ChartPoint: Equatable {
        let date: Date
        let value: Double
    }

    private struct IndexedChartPoint: Identifiable {
        let id: Int
        let point: ChartPoint

        var date: Date { point.date }
        var value: Double { point.value }
    }

    private struct TrendLine {
        let start: ChartPoint
        let end: ChartPoint
    }

    private struct VariabilityBandPoint {
        let date: Date
        let lower: Double
        let upper: Double
    }

    private enum ChartSeries: String {
        case progress = "Progress"
        case rollingAverage = "Rolling Avg"
        case trend = "Trend"
    }

    private var chartData: [ChartPoint] {
        history.map { session in
            let value: Double
            switch chartType {
            case .weight:
                value = session.sets.map { $0.weight }.max() ?? 0
            case .volume:
                value = session.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
            case .oneRepMax:
                let bestSet = session.sets.max { set1, set2 in
                    OneRepMax.estimate(weight: set1.weight, reps: set1.reps) <
                    OneRepMax.estimate(weight: set2.weight, reps: set2.reps)
                }
                value = bestSet.map { OneRepMax.estimate(weight: $0.weight, reps: $0.reps) } ?? 0
            case .reps:
                value = Double(session.sets.map { $0.reps }.max() ?? 0)
            case .distance:
                value = session.sets.reduce(0) { $0 + $1.distance }
            case .duration:
                value = session.sets.reduce(0) { $0 + $1.seconds }
            case .count:
                value = Double(session.sets.reduce(0) { $0 + $1.reps })
            }
            return ChartPoint(date: session.date, value: value)
        }
    }

    private var indexedChartData: [IndexedChartPoint] {
        chartData.enumerated().map { index, point in
            IndexedChartPoint(id: index, point: point)
        }
    }

    private var rollingAverageWindow: Int? {
        let count = chartData.count
        guard count >= 8 else { return nil }

        if count >= 60 { return 10 }
        if count >= 30 { return 7 }
        if count >= 14 { return 5 }
        return 3
    }

    private var indexedRollingAverageData: [IndexedChartPoint] {
        guard let window = rollingAverageWindow else { return [] }
        guard !chartData.isEmpty else { return [] }

        let values = chartData.map(\.value)
        let points: [ChartPoint] = chartData.indices.map { index in
            let start = max(0, index - (window - 1))
            let slice = values[start...index]
            let mean = slice.reduce(0, +) / Double(slice.count)
            return ChartPoint(date: chartData[index].date, value: mean)
        }

        return points.enumerated().map { index, point in
            IndexedChartPoint(id: index, point: point)
        }
    }

    private var prDate: Date? {
        chartData.max(by: { $0.value < $1.value })?.date
    }

    private var chartColor: Color {
        switch chartType {
        case .weight: return Theme.Colors.chest
        case .volume: return Theme.Colors.quads
        case .oneRepMax: return Theme.Colors.gold
        case .reps: return Theme.Colors.back
        case .distance: return Theme.Colors.cardio
        case .duration: return Theme.Colors.cardio
        case .count: return Theme.Colors.cardio
        }
    }

    private var seriesColors: KeyValuePairs<String, Color> {
        [
            ChartSeries.progress.rawValue: chartColor,
            ChartSeries.rollingAverage.rawValue: chartColor.opacity(0.55),
            ChartSeries.trend.rawValue: Color.secondary.opacity(0.5)
        ]
    }

    private var yDomain: ClosedRange<Double> {
        var values = chartData.map(\.value)

        if let trend = calculateTrendLine() {
            values.append(trend.start.value)
            values.append(trend.end.value)
        }

        if chartType == .oneRepMax {
            for point in variabilityBand {
                values.append(point.lower)
                values.append(point.upper)
            }
        }

        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        if minValue == maxValue {
            let padding = max(abs(minValue) * 0.05, 1)
            let lowerRaw = minValue - padding
            let lower = max(0, lowerRaw)
            return lower...(maxValue + padding)
        }

        let span = maxValue - minValue
        let padding = span * 0.12
        let lowerRaw = minValue - padding
        let lower = max(0, lowerRaw)
        return lower...(maxValue + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selected = selectedDataPoint {
                selectedPointHeader(selected: selected)
            }

            chartView
        }
        .onAppear {
            withAnimation(Theme.Animation.chartAppear) {
                isAppearing = true
            }
        }
        .onDisappear {
            selectionClearTask?.cancel()
        }
        .onChange(of: history.first?.date) { _, _ in
            selectedDataPoint = nil
            lastPRHapticDate = nil
        }
        .onChange(of: history.last?.date) { _, _ in
            selectedDataPoint = nil
            lastPRHapticDate = nil
        }
        .onChange(of: chartType) { _, _ in
            selectedDataPoint = nil
            lastPRHapticDate = nil
        }
    }

    @ViewBuilder
    private func selectedPointHeader(selected: ChartPoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                Text(formatValue(selected.value))
                    .font(Theme.Typography.title3)
                    .foregroundColor(chartColor)
            }

            Spacer()

            if selected.date == prDate {
                PRMarkerView(date: selected.date)
            }
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }

    private var chartView: some View {
        Chart {
            variabilityBandMarks
            areaMarks
            lineMarks
            rollingAverageMarks
            pointMarks
            trendLineMarks
            selectionRuleMark
        }
        .chartForegroundStyleScale(seriesColors)
        .chartYScale(domain: yDomain)
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let axisValue = value.as(Double.self) {
                        Text(formatAxisValue(axisValue))
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
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        guard frame.contains(location) else { return }
        let x = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: x) else { return }

        if let closest = chartData.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) {
            selectedDataPoint = closest
            if let prDate, prDate == closest.date, lastPRHapticDate != prDate {
                Haptics.notify(.success)
                lastPRHapticDate = prDate
            }
        }
    }

    private func scheduleSelectionClear() {
        guard selectedDataPoint != nil else { return }
        selectionClearTask?.cancel()
        selectionClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                selectedDataPoint = nil
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

    @ChartContentBuilder
    private var variabilityBandMarks: some ChartContent {
        if chartType == .oneRepMax {
            ForEach(variabilityBand, id: \.date) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Lower", point.lower),
                    yEnd: .value("Upper", point.upper)
                )
                .foregroundStyle(chartColor.opacity(0.12))
                .interpolationMethod(.catmullRom)
            }
        }
    }

    @ChartContentBuilder
    private var areaMarks: some ChartContent {
        ForEach(indexedChartData, id: \.id) { dataPoint in
            AreaMark(
                x: .value("Date", dataPoint.date),
                yStart: .value("Baseline", yDomain.lowerBound),
                yEnd: .value(chartType.rawValue, isAppearing ? dataPoint.value : yDomain.lowerBound)
            )
            .foregroundStyle(chartColor.opacity(0.15))
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(indexedChartData, id: \.id) { dataPoint in
            LineMark(
                x: .value("Date", dataPoint.date),
                y: .value(chartType.rawValue, isAppearing ? dataPoint.value : yDomain.lowerBound)
            )
            .foregroundStyle(by: .value("Series", ChartSeries.progress.rawValue))
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder
    private var rollingAverageMarks: some ChartContent {
        if rollingAverageWindow != nil {
            ForEach(indexedRollingAverageData, id: \.id) { dataPoint in
                LineMark(
                    x: .value("Date", dataPoint.date),
                    y: .value(chartType.rawValue, isAppearing ? dataPoint.value : yDomain.lowerBound)
                )
                .foregroundStyle(by: .value("Series", ChartSeries.rollingAverage.rawValue))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 3]))
                .interpolationMethod(.catmullRom)
            }
        }
    }

    @ChartContentBuilder
    private var pointMarks: some ChartContent {
        ForEach(indexedChartData, id: \.id) { dataPoint in
            PointMark(
                x: .value("Date", dataPoint.date),
                y: .value(chartType.rawValue, isAppearing ? dataPoint.value : yDomain.lowerBound)
            )
            .foregroundStyle(dataPoint.date == prDate ? Theme.Colors.gold : chartColor)
            .symbolSize(dataPoint.date == prDate ? 100 : 50)
            .annotation(position: .top) {
                if dataPoint.date == prDate {
                    Image(systemName: "trophy.fill")
                        .font(Theme.Typography.caption2)
                        .foregroundColor(Theme.Colors.gold)
                        .opacity(isAppearing ? 1 : 0)
                }
            }
        }
    }

    @ChartContentBuilder
    private var trendLineMarks: some ChartContent {
        if let trend = calculateTrendLine(), isAppearing {
            LineMark(
                x: .value("Date", trend.start.date),
                y: .value("Trend", trend.start.value)
            )
            .foregroundStyle(by: .value("Series", ChartSeries.trend.rawValue))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

            LineMark(
                x: .value("Date", trend.end.date),
                y: .value("Trend", trend.end.value)
            )
            .foregroundStyle(by: .value("Series", ChartSeries.trend.rawValue))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }

    @ChartContentBuilder
    private var selectionRuleMark: some ChartContent {
        if let selected = selectedDataPoint {
            RuleMark(x: .value("Selected", selected.date))
                .foregroundStyle(chartColor.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    private func formatValue(_ value: Double) -> String {
        switch chartType {
        case .weight, .oneRepMax:
            return "\(Int(value)) lbs"
        case .volume:
            if value >= 1000 {
                return String(format: "%.1fk lbs", value / 1000)
            }
            return "\(Int(value)) lbs"
        case .reps:
            return "\(Int(value)) reps"
        case .distance:
            return "\(WorkoutValueFormatter.distanceText(value)) dist"
        case .duration:
            return WorkoutValueFormatter.durationText(seconds: value)
        case .count:
            let label = (countLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? (countLabel ?? "count")
                : "count"
            return "\(Int(value)) \(label)"
        }
    }

    private func formatAxisValue(_ value: Double) -> String {
        switch chartType {
        case .duration:
            return WorkoutValueFormatter.durationText(seconds: value)
        default:
            return formatValue(value)
        }
    }

    private func calculateTrendLine() -> TrendLine? {
        guard chartData.count >= 2 else { return nil }

        let pointCount = Double(chartData.count)
        let sumX = chartData.enumerated().reduce(0.0) { $0 + Double($1.offset) }
        let sumY = chartData.reduce(0.0) { $0 + $1.value }
        let sumXY = chartData.enumerated().reduce(0.0) { $0 + (Double($1.offset) * $1.element.value) }
        let sumXX = chartData.enumerated().reduce(0.0) { $0 + (Double($1.offset) * Double($1.offset)) }

        let slope = (pointCount * sumXY - sumX * sumY) / (pointCount * sumXX - sumX * sumX)
        let intercept = (sumY - slope * sumX) / pointCount

        let startValue = intercept
        let endValue = slope * (pointCount - 1) + intercept

        let startDate = chartData[0].date
        let endDate = chartData[chartData.count - 1].date
        return TrendLine(
            start: ChartPoint(date: startDate, value: startValue),
            end: ChartPoint(date: endDate, value: endValue)
        )
    }

    private var variabilityBand: [VariabilityBandPoint] {
        guard chartData.count >= 2 else { return [] }
        let values = chartData.map { $0.value }
        let window = 3
        return chartData.indices.map { index in
            let start = max(0, index - (window - 1))
            let slice = values[start...index]
            let mean = slice.reduce(0, +) / Double(slice.count)
            let variance = slice.reduce(0) { $0 + pow($1 - mean, 2) } / Double(slice.count)
            let std = sqrt(variance)
            return VariabilityBandPoint(date: chartData[index].date, lower: max(0, mean - std), upper: mean + std)
        }
    }
}
