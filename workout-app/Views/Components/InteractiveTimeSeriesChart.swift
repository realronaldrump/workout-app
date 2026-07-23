import SwiftUI
import Charts

/// Interactive time-series chart with point inspection, zoom presets, and a pan scrubber.
/// Designed for use in the Health section where users want to zoom into a specific date window.
struct InteractiveTimeSeriesChart: View {
    struct ZoomPreset: Identifiable {
        let id: String
        let title: String
        let length: TimeInterval
    }

    let points: [HealthTrendPoint]
    let color: Color
    let areaFill: Bool
    let height: CGFloat
    let fullDomain: ClosedRange<Date>?
    let clampYToZero: Bool
    let showsControls: Bool
    let showsAverageLine: Bool
    let averageLineValue: Double?
    let valueText: (Double) -> String
    let dateText: (Date) -> String

    @State private var visibleEnd: Date
    /// `nil` means the user intends to see the complete range. Keeping the requested
    /// zoom separately preserves that intent when the supplied domain shrinks and grows.
    @State private var requestedZoomLength: TimeInterval?
    @State private var isAnchoredToLatest: Bool

    init(
        points: [HealthTrendPoint],
        color: Color,
        areaFill: Bool = false,
        height: CGFloat = 200,
        fullDomain: ClosedRange<Date>? = nil,
        clampYToZero: Bool = true,
        showsControls: Bool = true,
        showsAverageLine: Bool = false,
        averageLineValue: Double? = nil,
        valueText: @escaping (Double) -> String,
        dateText: @escaping (Date) -> String = { $0.formatted(date: .abbreviated, time: .omitted) }
    ) {
        let sorted = points.sorted { $0.date < $1.date }
        self.points = sorted
        self.color = color
        self.areaFill = areaFill
        self.height = height
        self.fullDomain = fullDomain
        self.clampYToZero = clampYToZero
        self.showsControls = showsControls
        self.showsAverageLine = showsAverageLine
        self.averageLineValue = averageLineValue
        self.valueText = valueText
        self.dateText = dateText

        let computedDomain = Self.resolvedFullDomain(points: sorted, explicitDomain: fullDomain)

        _visibleEnd = State(initialValue: computedDomain.upperBound)
        _requestedZoomLength = State(initialValue: nil)
        _isAnchoredToLatest = State(initialValue: true)
    }

    private var fullXDomain: ClosedRange<Date> {
        Self.resolvedFullDomain(points: points, explicitDomain: fullDomain)
    }

    private var fullLength: TimeInterval {
        max(1, fullXDomain.upperBound.timeIntervalSince(fullXDomain.lowerBound))
    }

    private var minZoomLength: TimeInterval {
        let hour: TimeInterval = 60 * 60
        let day: TimeInterval = 24 * 60 * 60

        let minLength: TimeInterval
        if fullLength <= day {
            minLength = max(fullLength * 0.25, hour)
        } else {
            minLength = day
        }

        return min(minLength, fullLength)
    }

    private var effectiveVisibleLength: TimeInterval {
        guard showsControls, let requestedZoomLength else { return fullLength }
        return min(max(requestedZoomLength, minZoomLength), fullLength)
    }

    private var minVisibleEnd: Date {
        fullXDomain.lowerBound.addingTimeInterval(effectiveVisibleLength)
    }

    private var effectiveVisibleEnd: Date {
        if !showsControls || requestedZoomLength == nil || isAnchoredToLatest {
            return fullXDomain.upperBound
        }
        return clamp(visibleEnd, min: minVisibleEnd, max: fullXDomain.upperBound)
    }

    private var visibleStart: Date {
        effectiveVisibleEnd.addingTimeInterval(-effectiveVisibleLength)
    }

    private var xDomain: ClosedRange<Date> {
        visibleStart...effectiveVisibleEnd
    }

    private var zoomPresets: [ZoomPreset] {
        let day: TimeInterval = 24 * 60 * 60
        let candidates: [(String, TimeInterval)] = [
            ("1D", day),
            ("3D", 3 * day),
            ("1W", 7 * day),
            ("2W", 14 * day),
            ("1M", 30 * day),
            ("3M", 90 * day)
        ]

        var presets: [ZoomPreset] = []
        for (title, length) in candidates {
            guard length < fullLength else { continue }
            presets.append(ZoomPreset(id: title, title: title, length: max(length, minZoomLength)))
        }
        presets.append(ZoomPreset(id: "All", title: "All", length: fullLength))
        return presets
    }

    private var zoomLabel: String {
        if abs(effectiveVisibleLength - fullLength) < 1 {
            return "All"
        }

        if let preset = zoomPresets.first(where: { abs($0.length - effectiveVisibleLength) < 1 }) {
            return preset.title
        }

        let hour: TimeInterval = 60 * 60
        let day: TimeInterval = 24 * 60 * 60
        if effectiveVisibleLength < day {
            let hours = max(1, Int(round(effectiveVisibleLength / hour)))
            return "\(hours)h"
        }
        let days = max(1, Int(round(effectiveVisibleLength / day)))
        return "\(days)d"
    }

    private var visibleEndTimeBinding: Binding<Double> {
        Binding(
            get: { effectiveVisibleEnd.timeIntervalSinceReferenceDate },
            set: { newValue in
                let candidate = Date(timeIntervalSinceReferenceDate: newValue)
                visibleEnd = clamp(candidate, min: minVisibleEnd, max: fullXDomain.upperBound)
                isAnchoredToLatest = abs(visibleEnd.timeIntervalSince(fullXDomain.upperBound)) < 1
            }
        )
    }

    var body: some View {
        let currentXDomain = xDomain
        let renderData = InteractiveChartRenderData(
            points: points,
            xDomain: currentXDomain,
            clampYToZero: clampYToZero
        )

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            InteractiveChartCanvas(
                data: renderData,
                color: color,
                areaFill: areaFill,
                height: height,
                showsAverageLine: showsAverageLine,
                averageLineValue: averageLineValue,
                valueText: valueText,
                dateText: dateText
            )
            // A point/domain change should clear stale selection state. Selection-only
            // updates stay inside the canvas and do not rebuild the O(n) render data.
            .id(renderData.key)

            if showsControls {
                controls
            }
        }
        .onChange(of: fullXDomain) { _, newDomain in
            syncStateToDomain(newDomain)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: Theme.Spacing.md) {
            Menu {
                ForEach(zoomPresets) { preset in
                    Button {
                        setVisibleLength(preset.length, anchorToEnd: true)
                    } label: {
                        if isSelectedZoomPreset(preset) {
                            Label(preset.title, systemImage: "checkmark")
                        } else {
                            Text(preset.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(Theme.Typography.caption)
                    Text("Zoom \(zoomLabel)")
                        .font(Theme.Typography.caption)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom level: \(zoomLabel)")

            Spacer()

            Button("Reset") {
                setVisibleLength(fullLength, anchorToEnd: true)
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .textCase(.uppercase)
            .tracking(0.8)
            .buttonStyle(.plain)
            .disabled(requestedZoomLength == nil)
            .accessibilityLabel("Reset zoom")
            .accessibilityHint("Show all data points")
        }

        if fullLength - effectiveVisibleLength > 60 {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text(dateText(visibleStart))
                    Spacer()
                    Text(dateText(effectiveVisibleEnd))
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)

                Slider(
                    value: visibleEndTimeBinding,
                    in: minVisibleEnd.timeIntervalSinceReferenceDate...fullXDomain.upperBound.timeIntervalSinceReferenceDate
                )
                .tint(color)
                .accessibilityLabel("Pan chart date range")
            }
        }
    }

    private func setVisibleLength(_ length: TimeInterval, anchorToEnd: Bool) {
        let clamped = min(max(length, minZoomLength), fullLength)
        requestedZoomLength = abs(length - fullLength) < 1 ? nil : max(length, minZoomLength)

        if anchorToEnd {
            isAnchoredToLatest = true
            visibleEnd = fullXDomain.upperBound
        } else {
            isAnchoredToLatest = false
            visibleEnd = clamp(visibleEnd, min: fullXDomain.lowerBound.addingTimeInterval(clamped), max: fullXDomain.upperBound)
        }
    }

    private func syncStateToDomain(_ newDomain: ClosedRange<Date>) {
        // Charts without controls represent a caller-selected period, so every new
        // period must fill the chart rather than inheriting an old internal window.
        guard showsControls else {
            requestedZoomLength = nil
            isAnchoredToLatest = true
            visibleEnd = newDomain.upperBound
            return
        }

        if isAnchoredToLatest || requestedZoomLength == nil {
            visibleEnd = newDomain.upperBound
        } else {
            let earliestEnd = newDomain.lowerBound.addingTimeInterval(effectiveVisibleLength)
            visibleEnd = clamp(visibleEnd, min: earliestEnd, max: newDomain.upperBound)
        }
    }

    private func isSelectedZoomPreset(_ preset: ZoomPreset) -> Bool {
        if preset.id == "All" {
            return requestedZoomLength == nil
        }
        guard let requestedZoomLength else { return false }
        return abs(preset.length - requestedZoomLength) < 1
    }

    private func clamp(_ value: Date, min: Date, max: Date) -> Date {
        if value < min { return min }
        if value > max { return max }
        return value
    }

    private static func resolvedFullDomain(
        points: [HealthTrendPoint],
        explicitDomain: ClosedRange<Date>?
    ) -> ClosedRange<Date> {
        if let explicitDomain { return explicitDomain }
        if let first = points.first?.date, let last = points.last?.date {
            if first == last {
                // Give the chart a little breathing room when there is only one point.
                let pad: TimeInterval = 12 * 60 * 60
                return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
            }
            return first...last
        }
        let dayStart = Calendar.current.startOfDay(for: Date())
        return dayStart...dayStart.addingTimeInterval(24 * 60 * 60)
    }
}

private struct InteractiveChartRenderData {
    struct Key: Hashable {
        let lowerBound: Date
        let upperBound: Date
        let pointsDigest: Int
    }

    let key: Key
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    let visiblePoints: [HealthTrendPoint]
    let renderedPoints: [HealthTrendPoint]
    let minimumValue: Double?
    let maximumValue: Double?
    let averageValue: Double?

    init(
        points: [HealthTrendPoint],
        xDomain: ClosedRange<Date>,
        clampYToZero: Bool
    ) {
        let filtered = points.filter { xDomain.contains($0.date) }
        let visiblePoints = filtered.isEmpty ? points : filtered

        var digest = Hasher()
        digest.combine(visiblePoints.count)
        var minimumValue: Double?
        var maximumValue: Double?
        var total = 0.0
        for point in visiblePoints {
            digest.combine(point.date)
            digest.combine(point.value.bitPattern)
            digest.combine(point.label)
            minimumValue = min(minimumValue ?? point.value, point.value)
            maximumValue = max(maximumValue ?? point.value, point.value)
            total += point.value
        }

        self.key = Key(
            lowerBound: xDomain.lowerBound,
            upperBound: xDomain.upperBound,
            pointsDigest: digest.finalize()
        )
        self.xDomain = xDomain
        self.visiblePoints = visiblePoints
        self.renderedPoints = HealthChartPointSampler.sampled(visiblePoints, limit: 400)
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.averageValue = visiblePoints.isEmpty
            ? nil
            : total / Double(visiblePoints.count)
        self.yDomain = Self.makeYDomain(
            minimumValue: minimumValue,
            maximumValue: maximumValue,
            clampToZero: clampYToZero
        )
    }

    private static func makeYDomain(
        minimumValue: Double?,
        maximumValue: Double?,
        clampToZero: Bool
    ) -> ClosedRange<Double> {
        guard let minimumValue, let maximumValue else { return 0...1 }

        if minimumValue == maximumValue {
            let padding = max(abs(minimumValue) * 0.05, 1)
            let lowerRaw = minimumValue - padding
            let lower = clampToZero ? max(0, lowerRaw) : lowerRaw
            return lower...(maximumValue + padding)
        }

        let span = maximumValue - minimumValue
        let padding = span * 0.12
        let lowerRaw = minimumValue - padding
        let lower = clampToZero ? max(0, lowerRaw) : lowerRaw
        return lower...(maximumValue + padding)
    }
}

private struct InteractiveChartCanvas: View {
    let data: InteractiveChartRenderData
    let color: Color
    let areaFill: Bool
    let height: CGFloat
    let showsAverageLine: Bool
    let averageLineValue: Double?
    let valueText: (Double) -> String
    let dateText: (Date) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPoint: HealthTrendPoint?
    @State private var selectionClearTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(headerText)
                .font(selectedPoint == nil ? Theme.Typography.caption : Theme.Typography.calloutStrong)
                .foregroundStyle(selectedPoint == nil ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)

            Chart {
                if areaFill {
                    ForEach(data.renderedPoints) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Baseline", data.yDomain.lowerBound),
                            yEnd: .value("Value", point.value)
                        )
                        .foregroundStyle(color.opacity(0.18))
                        .interpolationMethod(.catmullRom)
                    }
                }

                ForEach(data.renderedPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }

                if showsAverageLine, let average = averageLineValue ?? data.averageValue {
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(color.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .annotation(position: .top, alignment: .trailing, spacing: 4) {
                            Text("avg \(valueText(average))")
                                .font(Theme.Typography.caption2Bold)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Theme.Colors.surface.opacity(0.86))
                                )
                        }
                }

                if let selectedPoint {
                    PointMark(
                        x: .value("Date", selectedPoint.date),
                        y: .value("Value", selectedPoint.value)
                    )
                    .foregroundStyle(color)
                    .symbolSize(80)

                    RuleMark(x: .value("Selected", selectedPoint.date))
                        .foregroundStyle(color.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXScale(domain: data.xDomain)
            .chartYScale(domain: data.yDomain)
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
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Trend chart")
            .accessibilityValue(accessibilitySummary)
        }
        .onDisappear {
            selectionClearTask?.cancel()
        }
    }

    private var headerText: String {
        if let selectedPoint {
            return "\(dateText(selectedPoint.date)) | \(valueText(selectedPoint.value))"
        }
        return "\(dateText(data.xDomain.lowerBound)) - \(dateText(data.xDomain.upperBound))"
    }

    private var accessibilitySummary: String {
        if let selectedPoint {
            return "\(dateText(selectedPoint.date)), \(valueText(selectedPoint.value))"
        }

        guard let minimum = data.minimumValue,
              let maximum = data.maximumValue,
              let average = data.averageValue else {
            return "No data in the selected date range"
        }

        let dateWindow = "from \(dateText(data.xDomain.lowerBound)) to \(dateText(data.xDomain.upperBound))"
        let valueSummary = "Low \(valueText(minimum)), high \(valueText(maximum)), average \(valueText(average))."
        return "\(data.visiblePoints.count) data points \(dateWindow). \(valueSummary)"
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        guard frame.contains(location) else { return }
        let x = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: x),
              let closest = closestPoint(to: date) else { return }
        selectedPoint = closest
    }

    /// Points are date-sorted, so scrubbing can use a binary search instead of
    /// scanning the complete visible series for every drag event.
    private func closestPoint(to date: Date) -> HealthTrendPoint? {
        guard !data.visiblePoints.isEmpty else { return nil }

        var lower = 0
        var upper = data.visiblePoints.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if data.visiblePoints[middle].date < date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        if lower == 0 { return data.visiblePoints[0] }
        if lower == data.visiblePoints.count { return data.visiblePoints[data.visiblePoints.count - 1] }

        let earlier = data.visiblePoints[lower - 1]
        let later = data.visiblePoints[lower]
        return abs(earlier.date.timeIntervalSince(date)) <= abs(later.date.timeIntervalSince(date))
            ? earlier
            : later
    }

    private func scheduleSelectionClear() {
        guard selectedPoint != nil else { return }
        selectionClearTask?.cancel()
        selectionClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            if reduceMotion {
                selectedPoint = nil
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedPoint = nil
                }
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
}

enum HealthChartPointSampler {
    /// Reduces render-only chart marks while retaining each bucket's extrema.
    /// Statistics and point inspection continue to use the complete series.
    static func sampled(_ points: [HealthTrendPoint], limit: Int) -> [HealthTrendPoint] {
        sampled(points, limit: limit, value: \.value)
    }

    static func sampled(_ points: [TimeSeriesPoint], limit: Int) -> [TimeSeriesPoint] {
        sampled(points, limit: limit, value: \.value)
    }

    private static func sampled<Point>(
        _ points: [Point],
        limit: Int,
        value: (Point) -> Double
    ) -> [Point] {
        guard limit > 0 else { return [] }
        guard points.count > limit else { return points }
        guard let first = points.first, let last = points.last else { return [] }
        if limit == 1 { return [first] }
        if limit == 2 { return [first, last] }

        let interior = points.dropFirst().dropLast()
        let bucketCount = max(1, (limit - 2) / 2)
        let bucketSize = max(1, Int(ceil(Double(interior.count) / Double(bucketCount))))
        var sampled: [Point] = [first]
        sampled.reserveCapacity(limit)

        var start = interior.startIndex
        while start < interior.endIndex {
            let end = interior.index(start, offsetBy: bucketSize, limitedBy: interior.endIndex) ?? interior.endIndex
            let bucket = interior[start..<end]

            if let minimum = bucket.indices.min(by: { value(bucket[$0]) < value(bucket[$1]) }),
               let maximum = bucket.indices.max(by: { value(bucket[$0]) < value(bucket[$1]) }) {
                if minimum <= maximum {
                    sampled.append(bucket[minimum])
                    if maximum != minimum { sampled.append(bucket[maximum]) }
                } else {
                    sampled.append(bucket[maximum])
                    sampled.append(bucket[minimum])
                }
            }

            start = end
        }

        sampled.append(last)
        return sampled
    }
}
