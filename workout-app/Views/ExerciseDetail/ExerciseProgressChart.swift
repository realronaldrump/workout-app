import SwiftUI
import Charts

struct ExerciseProgressChart: View {
    let exerciseName: String
    let history: [(date: Date, sets: [WorkoutSet])]
    let chartType: ExerciseDetailView.ChartType
    var countLabel: String?

    @State private var isAppearing = false
    @State private var selectedDataPoint: ChartPoint?
    @State private var lastPRHapticDate: Date?
    @State private var selectionClearTask: Task<Void, Never>?
    @State private var derived: DerivedChartData = .empty
    @State private var derivedCacheKey: Int?

    fileprivate struct ChartPoint: Equatable {
        let date: Date
        let value: Double
    }

    fileprivate struct IndexedChartPoint: Identifiable {
        let id: Int
        let point: ChartPoint

        var date: Date { point.date }
        var value: Double { point.value }
    }

    fileprivate struct TrendLine {
        let start: ChartPoint
        let end: ChartPoint
    }

    fileprivate struct VariabilityBandPoint {
        let date: Date
        let lower: Double
        let upper: Double
    }

    fileprivate struct DerivedChartData {
        let chartData: [ChartPoint]
        let indexedChartData: [IndexedChartPoint]
        let rollingAverageWindow: Int?
        let indexedRollingAverageData: [IndexedChartPoint]
        let prDate: Date?
        let trendLine: TrendLine?
        let variabilityBand: [VariabilityBandPoint]
        let yDomain: ClosedRange<Double>

        static let empty = DerivedChartData(
            chartData: [],
            indexedChartData: [],
            rollingAverageWindow: nil,
            indexedRollingAverageData: [],
            prDate: nil,
            trendLine: nil,
            variabilityBand: [],
            yDomain: 0...1
        )

        static func compute(
            history: [(date: Date, sets: [WorkoutSet])],
            chartType: ExerciseDetailView.ChartType,
            exerciseName: String
        ) -> DerivedChartData {
            let chartData: [ChartPoint] = history.compactMap { session in
                let value: Double
                switch chartType {
                case .weight:
                    value = ExerciseLoad.bestWeight(in: session.sets, exerciseName: exerciseName)
                case .volume:
                    value = session.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
                case .oneRepMax:
                    value = OneRepMax.bestEstimate(in: session.sets, exerciseName: exerciseName)
                case .reps:
                    value = Double(session.sets.map { $0.reps }.max() ?? 0)
                case .distance:
                    value = session.sets.reduce(0) { $0 + $1.distance }
                case .duration:
                    value = session.sets.reduce(0) { $0 + $1.seconds }
                case .count:
                    value = Double(session.sets.reduce(0) { $0 + $1.reps })
                }
                if chartType == .volume, value <= 0 { return nil }
                return ChartPoint(date: session.date, value: value)
            }

            let indexed = chartData.enumerated().map { IndexedChartPoint(id: $0.offset, point: $0.element) }

            let rollingWindow: Int? = {
                let count = chartData.count
                guard count >= 8 else { return nil }
                if count >= 60 { return 10 }
                if count >= 30 { return 7 }
                if count >= 14 { return 5 }
                return 3
            }()

            let indexedRolling: [IndexedChartPoint]
            if let window = rollingWindow, !chartData.isEmpty {
                let values = chartData.map(\.value)
                var rollingPoints: [ChartPoint] = []
                rollingPoints.reserveCapacity(chartData.count)
                var runningSum: Double = 0
                for index in chartData.indices {
                    runningSum += values[index]
                    if index >= window {
                        runningSum -= values[index - window]
                    }
                    let denom = Double(min(window, index + 1))
                    let mean = runningSum / denom
                    rollingPoints.append(ChartPoint(date: chartData[index].date, value: mean))
                }
                indexedRolling = rollingPoints.enumerated().map {
                    IndexedChartPoint(id: $0.offset, point: $0.element)
                }
            } else {
                indexedRolling = []
            }

            let prDate: Date?
            switch chartType {
            case .weight, .oneRepMax:
                prDate = chartData.max(by: { lhs, rhs in
                    ExerciseLoad.comparisonValue(for: lhs.value, exerciseName: exerciseName) <
                    ExerciseLoad.comparisonValue(for: rhs.value, exerciseName: exerciseName)
                })?.date
            default:
                prDate = chartData.max(by: { $0.value < $1.value })?.date
            }

            let trendLine: TrendLine? = {
                guard chartData.count >= 2 else { return nil }
                let pointCount = Double(chartData.count)
                var sumX: Double = 0
                var sumY: Double = 0
                var sumXY: Double = 0
                var sumXX: Double = 0
                for (offset, point) in chartData.enumerated() {
                    let x = Double(offset)
                    sumX += x
                    sumY += point.value
                    sumXY += x * point.value
                    sumXX += x * x
                }
                let denominator = pointCount * sumXX - sumX * sumX
                guard denominator != 0 else { return nil }
                let slope = (pointCount * sumXY - sumX * sumY) / denominator
                let intercept = (sumY - slope * sumX) / pointCount
                let startValue = intercept
                let endValue = slope * (pointCount - 1) + intercept
                return TrendLine(
                    start: ChartPoint(date: chartData[0].date, value: startValue),
                    end: ChartPoint(date: chartData[chartData.count - 1].date, value: endValue)
                )
            }()

            let variabilityBand: [VariabilityBandPoint]
            if chartType == .oneRepMax, chartData.count >= 2 {
                let values = chartData.map(\.value)
                let window = 3
                var band: [VariabilityBandPoint] = []
                band.reserveCapacity(chartData.count)
                for index in chartData.indices {
                    let start = max(0, index - (window - 1))
                    let slice = values[start...index]
                    let mean = slice.reduce(0, +) / Double(slice.count)
                    let variance = slice.reduce(0) { $0 + pow($1 - mean, 2) } / Double(slice.count)
                    let std = sqrt(variance)
                    band.append(VariabilityBandPoint(
                        date: chartData[index].date,
                        lower: max(0, mean - std),
                        upper: mean + std
                    ))
                }
                variabilityBand = band
            } else {
                variabilityBand = []
            }

            let yDomain: ClosedRange<Double> = {
                var values = chartData.map(\.value)
                if let trend = trendLine {
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
                    let lower = max(0, minValue - padding)
                    return lower...(maxValue + padding)
                }
                let span = maxValue - minValue
                let padding = span * 0.12
                let lower = max(0, minValue - padding)
                return lower...(maxValue + padding)
            }()

            return DerivedChartData(
                chartData: chartData,
                indexedChartData: indexed,
                rollingAverageWindow: rollingWindow,
                indexedRollingAverageData: indexedRolling,
                prDate: prDate,
                trendLine: trendLine,
                variabilityBand: variabilityBand,
                yDomain: yDomain
            )
        }
    }

    private enum ChartSeries: String {
        case progress = "Progress"
        case rollingAverage = "Rolling Avg"
        case trend = "Trend"
    }

    private var chartLabel: String {
        switch chartType {
        case .weight:
            return ExerciseLoad.weightMetricTitle(for: exerciseName)
        case .oneRepMax:
            return ExerciseLoad.chartOneRepMaxTitle(for: exerciseName)
        default:
            return chartType.rawValue
        }
    }

    private var historyFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(exerciseName)
        hasher.combine(chartType.rawValue)
        for session in history {
            hasher.combine(session.date.timeIntervalSinceReferenceDate)
            hasher.combine(session.sets)
        }
        return hasher.finalize()
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
            ChartSeries.trend.rawValue: Theme.Colors.textTertiary.opacity(0.5)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selected = selectedDataPoint {
                selectedPointHeader(selected: selected)
            }

            chartView
        }
        .onAppear {
            recomputeIfNeeded()
            withAnimation(Theme.Animation.chartAppear) {
                isAppearing = true
            }
        }
        .onDisappear {
            selectionClearTask?.cancel()
        }
        .onChange(of: historyFingerprint) { _, _ in
            recomputeIfNeeded()
            selectedDataPoint = nil
            lastPRHapticDate = nil
        }
    }

    private func recomputeIfNeeded() {
        let key = historyFingerprint
        guard key != derivedCacheKey else { return }
        derived = DerivedChartData.compute(
            history: history,
            chartType: chartType,
            exerciseName: exerciseName
        )
        derivedCacheKey = key
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

            if selected.date == derived.prDate {
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
        .chartYScale(domain: derived.yDomain)
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

        if let closest = derived.chartData.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) {
            selectedDataPoint = closest
            if let prDate = derived.prDate, prDate == closest.date, lastPRHapticDate != prDate {
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
            ForEach(derived.variabilityBand, id: \.date) { point in
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
        ForEach(derived.indexedChartData, id: \.id) { dataPoint in
            AreaMark(
                x: .value("Date", dataPoint.date),
                yStart: .value("Baseline", derived.yDomain.lowerBound),
                yEnd: .value(chartLabel, isAppearing ? dataPoint.value : derived.yDomain.lowerBound)
            )
            .foregroundStyle(chartColor.opacity(0.15))
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(derived.indexedChartData, id: \.id) { dataPoint in
            LineMark(
                x: .value("Date", dataPoint.date),
                y: .value(chartLabel, isAppearing ? dataPoint.value : derived.yDomain.lowerBound)
            )
            .foregroundStyle(by: .value("Series", ChartSeries.progress.rawValue))
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder
    private var rollingAverageMarks: some ChartContent {
        if derived.rollingAverageWindow != nil {
            ForEach(derived.indexedRollingAverageData, id: \.id) { dataPoint in
                LineMark(
                    x: .value("Date", dataPoint.date),
                    y: .value(chartLabel, isAppearing ? dataPoint.value : derived.yDomain.lowerBound)
                )
                .foregroundStyle(by: .value("Series", ChartSeries.rollingAverage.rawValue))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 3]))
                .interpolationMethod(.catmullRom)
            }
        }
    }

    @ChartContentBuilder
    private var pointMarks: some ChartContent {
        ForEach(derived.indexedChartData, id: \.id) { dataPoint in
            PointMark(
                x: .value("Date", dataPoint.date),
                y: .value(chartLabel, isAppearing ? dataPoint.value : derived.yDomain.lowerBound)
            )
            .foregroundStyle(dataPoint.date == derived.prDate ? Theme.Colors.gold : chartColor)
            .symbolSize(dataPoint.date == derived.prDate ? 100 : 50)
            .annotation(position: .top) {
                if dataPoint.date == derived.prDate {
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
        if let trend = derived.trendLine, isAppearing {
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
            return ExerciseLoad.formatWeight(value, exerciseName: exerciseName)
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
}
