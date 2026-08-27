import SwiftUI
import Charts

/// The signature trend chart for health metrics.
///
/// What separates this from a stock line chart is context. Behind the data sits the
/// band your middle 50% of days actually occupy, so a glance answers "was that
/// normal for me?" rather than only "what was the number". Bars are shaded by where
/// they fall against that band, weekends are tinted, an in-progress today is drawn
/// as visibly incomplete, and the best day is marked.
struct MetricTrendChart: View {

    let metric: HealthMetric
    let analysis: MetricSeriesAnalysis
    let domain: ClosedRange<Date>
    var height: CGFloat = 220
    var showsBestDayMarker: Bool = true
    @Binding var selectedDate: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealProgress: CGFloat = 0

    private var render: MetricChartRenderModel {
        MetricChartRenderModel(analysis: analysis, domain: domain)
    }

    private var selectedPoint: MetricChartRenderModel.Point? {
        guard let selectedDate else { return nil }
        return render.closestPoint(to: selectedDate)
    }

    var body: some View {
        let model = render

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            readout(model: model)

            chart(model: model)
                .frame(height: height)
                .mask(alignment: .leading) {
                    // A left-to-right reveal reads as the series being drawn rather
                    // than a static image snapping into place.
                    GeometryReader { geometry in
                        Rectangle()
                            .frame(width: geometry.size.width * revealProgress)
                    }
                }

            legend(model: model)
        }
        .onAppear {
            guard revealProgress == 0 else { return }
            if reduceMotion {
                revealProgress = 1
            } else {
                withAnimation(.easeOut(duration: 0.7)) { revealProgress = 1 }
            }
        }
    }

    // MARK: - Readout

    @ViewBuilder
    private func readout(model: MetricChartRenderModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            if let point = selectedPoint {
                VStack(alignment: .leading, spacing: 2) {
                    Text(point.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(metric.formatWithUnit(point.value))
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .contentTransition(.numericText())
                        if let comparison = comparisonText(for: point, model: model) {
                            Text(comparison)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(domainLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    if let range = analysis.typicalRange {
                        Text("Typical \(metric.formatDisplay(range.lowerBound))–\(metric.formatWithUnit(range.upperBound))")
                            .font(Theme.Typography.footnoteStrong)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        Text("Drag across the chart to inspect a \(metric.dailyNoun)")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        // Reserve the taller of the two states so scrubbing never shifts the chart.
        .frame(minHeight: 44, alignment: .topLeading)
        .animation(reduceMotion ? nil : Theme.Animation.quick, value: selectedPoint?.date)
    }

    private var domainLabel: String {
        let start = domain.lowerBound.formatted(.dateTime.month(.abbreviated).day())
        let end = domain.upperBound.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    private func comparisonText(for point: MetricChartRenderModel.Point, model: MetricChartRenderModel) -> String? {
        guard let median = analysis.median, median != 0 else { return nil }
        if point.isPartial { return "so far today" }
        let change = (point.value - median) / abs(median) * 100
        guard abs(change) >= 1 else { return "right at your median" }
        let direction = change > 0 ? "above" : "below"
        return "\(Int(abs(change).rounded()))% \(direction) median"
    }

    // MARK: - Chart

    private func chart(model: MetricChartRenderModel) -> some View {
        Chart {
            // The band the middle half of days occupy. Everything else is read against it.
            if let band = analysis.typicalRange, band.lowerBound < band.upperBound {
                RectangleMark(
                    yStart: .value("Typical low", band.lowerBound),
                    yEnd: .value("Typical high", band.upperBound)
                )
                .foregroundStyle(metric.accentColor.opacity(0.10))
            }

            if let median = analysis.median {
                RuleMark(y: .value("Median", median))
                    .foregroundStyle(metric.accentColor.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
            }

            // Weekends get a faint column wash so the weekly rhythm is visible in
            // the shape of the data itself.
            if model.showsWeekendShading {
                ForEach(model.weekendPoints) { point in
                    RectangleMark(
                        x: .value("Date", point.date, unit: .day),
                        yStart: .value("Floor", model.yDomain.lowerBound),
                        yEnd: .value("Ceiling", model.yDomain.upperBound)
                    )
                    .foregroundStyle(Theme.Colors.textPrimary.opacity(0.035))
                }
            }

            switch analysis.suggestedChartForm {
            case .bars:
                barMarks(model: model)
            case .ribbon:
                ribbonMarks(model: model)
            }

            if showsBestDayMarker, let best = model.bestPoint, model.points.count >= 7 {
                PointMark(
                    x: .value("Date", best.date, unit: .day),
                    y: .value("Value", best.value)
                )
                .symbol {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Colors.gold)
                }
                .annotation(
                    position: .top,
                    spacing: 2,
                    // Without this the label is clipped when the best day sits at
                    // either edge of the range.
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    Text("best")
                        .font(Theme.Typography.microLabel)
                        .foregroundStyle(Theme.Colors.gold)
                }
            }

            if let point = selectedPoint {
                RuleMark(x: .value("Selected", point.date, unit: .day))
                    .foregroundStyle(Theme.Colors.textPrimary.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(
                    x: .value("Selected", point.date, unit: .day),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(metric.accentColor)
                .symbolSize(90)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: model.yDomain)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.border.opacity(0.3))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(metric.formatDisplay(number))
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .chartPlotStyle { $0.clipped() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title) trend")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Swipe up or down to inspect recorded days.")
        .accessibilityAdjustableAction(adjustSelection)
    }

    @ChartContentBuilder
    private func barMarks(model: MetricChartRenderModel) -> some ChartContent {
        ForEach(model.points) { point in
            BarMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Value", point.value),
                width: .ratio(model.barWidthRatio)
            )
            .foregroundStyle(barStyle(for: point))
            .cornerRadius(model.barCornerRadius)
            .opacity(point.isPartial ? 0.55 : 1)
        }
    }

    @ChartContentBuilder
    private func ribbonMarks(model: MetricChartRenderModel) -> some ChartContent {
        ForEach(model.points) { point in
            AreaMark(
                x: .value("Date", point.date),
                yStart: .value("Floor", model.yDomain.lowerBound),
                yEnd: .value("Value", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [metric.accentColor.opacity(0.28), metric.accentColor.opacity(0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)
        }

        ForEach(model.points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Value", point.value)
            )
            .foregroundStyle(metric.accentGradient)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }

        // A single emphasised dot on the most recent reading gives the series a
        // "you are here" anchor that a bare line never has.
        if let latest = model.points.last {
            PointMark(
                x: .value("Date", latest.date),
                y: .value("Value", latest.value)
            )
            .foregroundStyle(metric.accentColor)
            .symbolSize(70)
        }
    }

    private func barStyle(for point: MetricChartRenderModel.Point) -> AnyShapeStyle {
        switch point.band {
        case .above:
            return AnyShapeStyle(metric.accentGradient)
        case .typical:
            return AnyShapeStyle(metric.accentColor.opacity(0.62))
        case .below:
            return AnyShapeStyle(metric.accentColor.opacity(0.3))
        }
    }

    // MARK: - Legend

    @ViewBuilder
    private func legend(model: MetricChartRenderModel) -> some View {
        if analysis.suggestedChartForm == .bars, analysis.typicalRange != nil {
            HStack(spacing: Theme.Spacing.md) {
                legendSwatch(color: metric.accentColor.opacity(0.3), label: "Below typical")
                legendSwatch(color: metric.accentColor.opacity(0.62), label: "Typical")
                legendSwatch(color: metric.accentColor, label: "Above")
                Spacer(minLength: 0)
            }
            .font(Theme.Typography.caption2)
            .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
        }
    }

    private var accessibilitySummary: String {
        if let selectedPoint {
            return "Selected \(selectedPoint.date.formatted(date: .abbreviated, time: .omitted)), "
                + "\(metric.formatWithUnit(selectedPoint.value)). \(analysis.completed.count) recorded days."
        }
        guard let mean = analysis.mean else { return "No data in this range" }
        var parts = ["Average \(metric.formatWithUnit(mean)) over \(analysis.completed.count) days"]
        if let range = analysis.typicalRange {
            parts.append("typical range \(metric.formatWithUnit(range.lowerBound)) to \(metric.formatWithUnit(range.upperBound))")
        }
        if let best = analysis.bestDay {
            parts.append("best \(metric.formatWithUnit(best.value)) on \(best.date.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: ", ") + "."
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        let points = render.points
        guard !points.isEmpty else { return }
        let currentIndex = selectedPoint.flatMap { selected in
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

// MARK: - Render model

/// Pre-computes everything the chart needs so the view body stays cheap.
struct MetricChartRenderModel {

    enum Band {
        case below
        case typical
        case above
    }

    struct Point: Identifiable {
        let date: Date
        let value: Double
        let band: Band
        let isWeekend: Bool
        let isPartial: Bool

        var id: Date { date }
    }

    let points: [Point]
    let weekendPoints: [Point]
    let yDomain: ClosedRange<Double>
    let bestPoint: Point?
    let showsWeekendShading: Bool
    let barCornerRadius: CGFloat
    /// Dense charts need near-flush bars or the gaps swallow the data.
    let barWidthRatio: CGFloat

    init(analysis: MetricSeriesAnalysis, domain: ClosedRange<Date>) {
        let calendar = Calendar.current
        let band = analysis.typicalRange
        let partialDate = analysis.isTodayPartial ? analysis.todaySample?.date : nil

        // Charts stay responsive by capping drawn marks; statistics still use the
        // complete series, so nothing in the numbers depends on this.
        var source = MetricChartRenderModel.limited(analysis.samples, to: 180)
        if let best = analysis.bestDay,
           !source.contains(where: { calendar.isDate($0.date, inSameDayAs: best.date) }) {
            source.append(best)
            source.sort { $0.date < $1.date }
        }

        let builtPoints: [Point] = source.map { sample in
            let classification: Band
            if let band {
                if sample.value > band.upperBound {
                    classification = .above
                } else if sample.value < band.lowerBound {
                    classification = .below
                } else {
                    classification = .typical
                }
            } else {
                classification = .typical
            }

            return Point(
                date: sample.date,
                value: sample.value,
                band: classification,
                isWeekend: calendar.isDateInWeekend(sample.date),
                isPartial: partialDate.map { calendar.isDate(sample.date, inSameDayAs: $0) } ?? false
            )
        }

        points = builtPoints
        weekendPoints = builtPoints.filter(\.isWeekend)
        // Past roughly two months the weekend wash turns into visual noise.
        showsWeekendShading = builtPoints.count <= 62 && builtPoints.count >= 7
        barCornerRadius = builtPoints.count > 60 ? 1 : (builtPoints.count > 30 ? 2 : 4)
        barWidthRatio = builtPoints.count > 60 ? 0.94 : (builtPoints.count > 30 ? 0.8 : 0.68)

        bestPoint = analysis.bestDay.flatMap { best in
            builtPoints.first { calendar.isDate($0.date, inSameDayAs: best.date) }
        }

        yDomain = MetricChartRenderModel.makeYDomain(
            points: builtPoints,
            band: band,
            form: analysis.suggestedChartForm
        )
    }

    func closestPoint(to date: Date) -> Point? {
        points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private static func limited(_ samples: [MetricDaySample], to limit: Int) -> [MetricDaySample] {
        guard samples.count > limit else { return samples }
        let stride = Int(ceil(Double(samples.count) / Double(limit)))
        var reduced: [MetricDaySample] = []
        reduced.reserveCapacity(limit + 1)
        var index = 0
        while index < samples.count {
            // Keep the loudest day in each bucket so peaks survive downsampling.
            let end = min(index + stride, samples.count)
            if let peak = samples[index..<end].max(by: { $0.value < $1.value }) {
                reduced.append(peak)
            }
            index = end
        }
        if let last = samples.last, reduced.last?.date != last.date {
            reduced.append(last)
        }
        return reduced
    }

    private static func makeYDomain(
        points: [Point],
        band: ClosedRange<Double>?,
        form: MetricChartForm
    ) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }

        switch form {
        case .bars:
            // Bars must be read against zero or their heights lie about ratios.
            let top = maximum <= 0 ? 1 : maximum * 1.12
            return 0...top
        case .ribbon:
            // A continuous measure needs the band visible even when the line
            // wanders outside it, so the domain covers both.
            let low = min(minimum, band?.lowerBound ?? minimum)
            let high = max(maximum, band?.upperBound ?? maximum)
            if low == high {
                let padding = max(abs(low) * 0.05, 1)
                return (low - padding)...(high + padding)
            }
            let padding = (high - low) * 0.14
            return (low - padding)...(high + padding)
        }
    }
}
