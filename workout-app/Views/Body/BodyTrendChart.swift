import Charts
import SwiftUI

/// Scale readings as dots, the trend as one bold line, the usual range as a pale band, the goal as a
/// dashed line, and workout days as ticks along the floor. Drag sideways to read any day.
struct BodyTrendChart: View {
    let series: BodySeries
    let domain: ClosedRange<Date>
    let showsReadings: Bool
    let goal: Double?
    let workoutDays: [Date]
    let tint: Color
    var height: CGFloat = 240
    @Binding var selection: BodyTrendDay?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isScrubbing = false
    @State private var clearTask: Task<Void, Never>?

    private let days: [BodyTrendDay]
    private let readingDays: [BodyTrendDay]
    private let yDomain: ClosedRange<Double>
    private let goalInView: Bool

    init(
        series: BodySeries,
        domain: ClosedRange<Date>,
        showsReadings: Bool,
        goal: Double?,
        workoutDays: [Date],
        tint: Color,
        height: CGFloat = 240,
        selection: Binding<BodyTrendDay?>
    ) {
        self.series = series
        self.domain = domain
        self.showsReadings = showsReadings
        self.goal = goal
        self.workoutDays = workoutDays
        self.tint = tint
        self.height = height
        _selection = selection

        let visible = series.gridDays(in: DateInterval(start: domain.lowerBound, end: domain.upperBound))
        days = BodyTrendEngine.thinned(visible, limit: 420)
        readingDays = visible.filter(\.hasReading)

        var values = visible.map(\.trend)
        values.append(contentsOf: readingDays.compactMap(\.reading))
        if let sigma = series.residualSigma {
            values.append(contentsOf: visible.flatMap { [$0.trend - 1.28 * sigma, $0.trend + 1.28 * sigma] })
        }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let center = (low + high) / 2
        let minimumSpan = max(series.kind == .weight ? 4 : 1.5, center * 0.025)
        var span = max(high - low, minimumSpan) * 1.16
        var lower = center - span / 2
        var upper = center + span / 2

        var goalVisible = false
        if let goal, abs(goal - center) <= span * 1.5 {
            lower = min(lower, goal - span * 0.06)
            upper = max(upper, goal + span * 0.06)
            span = upper - lower
            goalVisible = true
        }
        yDomain = lower...upper
        goalInView = goalVisible
    }

    var body: some View {
        chart
            .frame(height: height)
            .overlay(alignment: offChartGoalAlignment) {
                if let goal, !goalInView {
                    Label(
                        "Goal \(BodyFormat.number(goal)), \(goal < yDomain.lowerBound ? "below" : "above") this view",
                        systemImage: goal < yDomain.lowerBound ? "arrow.down" : "arrow.up"
                    )
                    .font(Theme.Typography.caption2Bold)
                    .foregroundStyle(Theme.Colors.plateGreen)
                    .padding(.bottom, goal < yDomain.lowerBound ? 42 : 0)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(series.kind == .weight ? "Weight trend chart" : "Body fat trend chart")
            .accessibilityValue(accessibilitySummary)
            .accessibilityAdjustableAction { direction in
                step(direction == .increment ? 1 : -1)
            }
    }

    private var chart: some View {
        Chart {
            bandMarks
            if let goal, goalInView {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Theme.Colors.plateGreen)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(
                        position: .top,
                        alignment: .leading,
                        spacing: 2,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text("Goal \(BodyFormat.number(goal))")
                            .font(Theme.Typography.caption2Bold)
                            .foregroundStyle(Theme.Colors.plateGreen)
                    }
            }
            tickMarks
            if showsReadings { readingMarks }
            trendMarks
            endMarks
            selectionMarks
        }
        .chartXScale(domain: domain, range: .plotDimension(startPadding: 4, endPadding: 10))
        .chartYScale(domain: yDomain)
        .chartPlotStyle { $0.clipped() }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.Colors.rule.opacity(0.6))
                AxisValueLabel(format: xAxisFormat)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.Colors.rule.opacity(0.6))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(BodyFormat.number(number, decimals: yDomain.upperBound - yDomain.lowerBound < 6 ? 1 : 0))
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .simultaneousGesture(scrubGesture(proxy: proxy, geometry: geometry))
            }
        }
    }

    private var offChartGoalAlignment: Alignment {
        guard let goal else { return .bottomLeading }
        return goal < yDomain.lowerBound ? .bottomLeading : .topLeading
    }

    // MARK: Marks

    @ChartContentBuilder
    private var bandMarks: some ChartContent {
        if let sigma = series.residualSigma {
            ForEach(days) { day in
                AreaMark(
                    x: .value("Day", day.day),
                    yStart: .value("Low", day.trend - 1.28 * sigma),
                    yEnd: .value("High", day.trend + 1.28 * sigma),
                    series: .value("Band", "band-\(day.segment)")
                )
                .foregroundStyle(tint.opacity(0.13))
                .interpolationMethod(.monotone)
            }
        }
    }

    @ChartContentBuilder
    private var tickMarks: some ChartContent {
        let tickHeight = (yDomain.upperBound - yDomain.lowerBound) * 0.05
        ForEach(workoutDays, id: \.self) { day in
            RectangleMark(
                x: .value("Workout", day),
                yStart: .value("Floor", yDomain.lowerBound),
                yEnd: .value("Tick", yDomain.lowerBound + tickHeight),
                width: .fixed(showsReadings ? 2 : 1.25)
            )
            .foregroundStyle(Theme.Colors.ink.opacity(0.28))
        }
    }

    @ChartContentBuilder
    private var readingMarks: some ChartContent {
        ForEach(readingDays.filter { series.flags[$0.dayIndex] == nil }) { day in
            PointMark(x: .value("Day", day.day), y: .value("Scale", day.reading ?? day.trend))
                .symbolSize(18)
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.55))
        }
        ForEach(readingDays.filter { series.flags[$0.dayIndex] != nil }) { day in
            PointMark(x: .value("Day", day.day), y: .value("Scale", day.reading ?? day.trend))
                .symbol {
                    Circle()
                        .strokeBorder(Theme.Colors.textPrimary, lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                }
        }
    }

    @ChartContentBuilder
    private var trendMarks: some ChartContent {
        // Settled stretches are solid; a segment's first week is dashed while it settles.
        ForEach(days.filter { !$0.isSettling }) { day in
            LineMark(
                x: .value("Day", day.day),
                y: .value("Trend", day.trend),
                series: .value("Segment", "trend-\(day.segment)")
            )
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
        ForEach(settlingDays) { day in
            LineMark(
                x: .value("Day", day.day),
                y: .value("Trend", day.trend),
                series: .value("Segment", "settling-\(day.segment)")
            )
            .foregroundStyle(tint.opacity(0.8))
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
            .interpolationMethod(.monotone)
        }
    }

    /// A segment's settling days plus its first settled day, so the dashed and solid lines meet.
    private var settlingDays: [BodyTrendDay] {
        var result: [BodyTrendDay] = []
        var previous: BodyTrendDay?
        for day in days {
            if day.isSettling {
                result.append(day)
            } else if let previous, previous.isSettling, previous.segment == day.segment {
                result.append(day)
            }
            previous = day
        }
        return result
    }

    @ChartContentBuilder
    private var endMarks: some ChartContent {
        if let last = days.last {
            PointMark(x: .value("Day", last.day), y: .value("Trend", last.trend))
                .symbolSize(70)
                .foregroundStyle(tint)
                .annotation(
                    position: .top,
                    alignment: .trailing,
                    spacing: 6,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    Text(BodyFormat.number(last.trend))
                        .font(Theme.Typography.caption2Bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
        }
        if let first = days.first, first.dayIndex != days.last?.dayIndex {
            PointMark(x: .value("Day", first.day), y: .value("Trend", first.trend))
                .symbolSize(0)
                .annotation(
                    position: .top,
                    alignment: .leading,
                    spacing: 6,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    Text(BodyFormat.number(first.trend))
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
        }
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let selection {
            RuleMark(x: .value("Selected", selection.day))
                .foregroundStyle(Theme.Colors.ink.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1))
            PointMark(x: .value("Selected", selection.day), y: .value("Trend", selection.trend))
                .symbolSize(60)
                .foregroundStyle(tint)
            if let reading = selection.reading {
                PointMark(x: .value("Selected", selection.day), y: .value("Scale", reading))
                    .symbol {
                        Circle()
                            .strokeBorder(Theme.Colors.textPrimary, lineWidth: 2)
                            .background(Circle().fill(Theme.Colors.panel))
                            .frame(width: 11, height: 11)
                    }
            }
        }
    }

    // MARK: Scrub

    private func scrubGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = abs(value.translation.width)
                let dy = abs(value.translation.height)
                if !isScrubbing {
                    // Only a sideways drag reads the chart, so vertical scrolling still scrolls.
                    guard dx > 10, dx > dy * 1.2 else { return }
                    isScrubbing = true
                }
                select(at: value.location, proxy: proxy, geometry: geometry)
            }
            .onEnded { value in
                if !isScrubbing, abs(value.translation.width) < 6, abs(value.translation.height) < 6 {
                    select(at: value.location, proxy: proxy, geometry: geometry)
                }
                isScrubbing = false
                scheduleClear()
            }
    }

    private func select(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let originX = geometry[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: location.x - originX) else { return }
        let target = series.dayIndex(for: date)
        guard let nearest = readingDays.min(by: { abs($0.dayIndex - target) < abs($1.dayIndex - target) }) else { return }
        clearTask?.cancel()
        if nearest != selection {
            selection = nearest
            Haptics.selection()
        }
    }

    private func scheduleClear() {
        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, !isScrubbing else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { selection = nil }
        }
    }

    private func step(_ offset: Int) {
        guard !readingDays.isEmpty else { return }
        let current = selection.flatMap { selected in readingDays.firstIndex { $0.dayIndex == selected.dayIndex } }
        let next = current.map { min(max($0 + offset, 0), readingDays.count - 1) } ?? (readingDays.count - 1)
        selection = readingDays[next]
    }

    // MARK: Labels

    private var xAxisFormat: Date.FormatStyle {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound) / 86_400
        if span <= 45 { return .dateTime.month(.abbreviated).day() }
        if span <= 400 { return .dateTime.month(.abbreviated) }
        return .dateTime.month(.abbreviated).year(.twoDigits)
    }

    private var accessibilitySummary: String {
        guard let first = days.first, let last = days.last else { return "No readings in this range" }
        let unit = series.kind == .weight ? "pounds" : "percent"
        var parts = [
            "Trend from \(BodyFormat.number(first.trend)) to \(BodyFormat.number(last.trend)) \(unit)",
            "\(readingDays.count) weigh-ins"
        ]
        if let selection {
            parts.insert("Selected \(BodyFormat.weekdayDate(selection.day)), trend \(BodyFormat.number(selection.trend))", at: 0)
        }
        return parts.joined(separator: ". ")
    }
}
