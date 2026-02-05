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
    let valueText: (Double) -> String
    let dateText: (Date) -> String

    @State private var selectedPoint: HealthTrendPoint?
    @State private var selectionClearTask: Task<Void, Never>?

    @State private var visibleLength: TimeInterval
    @State private var visibleEnd: Date

    init(
        points: [HealthTrendPoint],
        color: Color,
        areaFill: Bool = false,
        height: CGFloat = 200,
        fullDomain: ClosedRange<Date>? = nil,
        clampYToZero: Bool = true,
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
        self.valueText = valueText
        self.dateText = dateText

        let computedDomain: ClosedRange<Date>
        if let fullDomain {
            computedDomain = fullDomain
        } else if let first = sorted.first?.date, let last = sorted.last?.date {
            computedDomain = first...last
        } else {
            let now = Date()
            computedDomain = now...now
        }

        let length = max(1, computedDomain.upperBound.timeIntervalSince(computedDomain.lowerBound))
        _visibleLength = State(initialValue: length)
        _visibleEnd = State(initialValue: computedDomain.upperBound)
    }

    private var fullXDomain: ClosedRange<Date> {
        if let fullDomain { return fullDomain }
        if let first = points.first?.date, let last = points.last?.date {
            if first == last {
                // Give the chart a little breathing room when there is only one point.
                let pad: TimeInterval = 12 * 60 * 60
                return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
            }
            return first...last
        }
        let now = Date()
        return now.addingTimeInterval(-24 * 60 * 60)...now
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
        min(max(visibleLength, minZoomLength), fullLength)
    }

    private var minVisibleEnd: Date {
        fullXDomain.lowerBound.addingTimeInterval(effectiveVisibleLength)
    }

    private var effectiveVisibleEnd: Date {
        clamp(visibleEnd, min: minVisibleEnd, max: fullXDomain.upperBound)
    }

    private var visibleStart: Date {
        effectiveVisibleEnd.addingTimeInterval(-effectiveVisibleLength)
    }

    private var xDomain: ClosedRange<Date> {
        visibleStart...effectiveVisibleEnd
    }

    private var visiblePoints: [HealthTrendPoint] {
        let filtered = points.filter { xDomain.contains($0.date) }
        return filtered.isEmpty ? points : filtered
    }

    private var yDomain: ClosedRange<Double> {
        let values = visiblePoints.map { $0.value }
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        if minValue == maxValue {
            let padding = max(abs(minValue) * 0.05, 1)
            let lowerRaw = minValue - padding
            let lower = clampYToZero ? max(0, lowerRaw) : lowerRaw
            return lower...(maxValue + padding)
        }

        let span = maxValue - minValue
        let padding = span * 0.12
        let lowerRaw = minValue - padding
        let lower = clampYToZero ? max(0, lowerRaw) : lowerRaw
        return lower...(maxValue + padding)
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
                selectedPoint = nil
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(headerText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Chart {
                if areaFill {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Baseline", yDomain.lowerBound),
                            yEnd: .value("Value", point.value)
                        )
                        .foregroundStyle(color.opacity(0.18))
                        .interpolationMethod(.catmullRom)
                    }
                }

                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)

                    if selectedPoint?.date == point.date {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(color)
                        .symbolSize(80)
                    }
                }

                if let selectedPoint {
                    RuleMark(x: .value("Selected", selectedPoint.date))
                        .foregroundStyle(color.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectionClearTask?.cancel()
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let frame = geometry[plotFrame]
                                    let x = value.location.x - frame.origin.x
                                    if let date: Date = proxy.value(atX: x) {
                                        if let closest = visiblePoints.min(by: {
                                            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                        }) {
                                            selectedPoint = closest
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    selectionClearTask?.cancel()
                                    selectionClearTask = Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                                        guard !Task.isCancelled else { return }
                                        withAnimation {
                                            selectedPoint = nil
                                        }
                                    }
                                }
                        )
                }
            }
            .frame(height: height)

            controls
        }
        .onDisappear {
            selectionClearTask?.cancel()
        }
        .onChange(of: points.first?.date) { _, _ in
            syncStateToDomain()
        }
        .onChange(of: points.last?.date) { _, _ in
            syncStateToDomain()
        }
    }

    private var headerText: String {
        if let selectedPoint {
            return "\(dateText(selectedPoint.date)) | \(valueText(selectedPoint.value))"
        }
        return "\(dateText(visibleStart)) - \(dateText(effectiveVisibleEnd))"
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: Theme.Spacing.md) {
            Menu {
                ForEach(zoomPresets) { preset in
                    Button {
                        setVisibleLength(preset.length, anchorToEnd: true)
                    } label: {
                        if abs(preset.length - effectiveVisibleLength) < 1 {
                            Label(preset.title, systemImage: "checkmark")
                        } else {
                            Text(preset.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                    Text("Zoom \(zoomLabel)")
                        .font(Theme.Typography.caption)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Button("Reset") {
                setVisibleLength(fullLength, anchorToEnd: true)
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .disabled(abs(effectiveVisibleLength - fullLength) < 1)
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
            }
        }
    }

    private func setVisibleLength(_ length: TimeInterval, anchorToEnd: Bool) {
        let clamped = min(max(length, minZoomLength), fullLength)
        visibleLength = clamped

        if anchorToEnd {
            visibleEnd = fullXDomain.upperBound
        } else {
            visibleEnd = clamp(visibleEnd, min: fullXDomain.lowerBound.addingTimeInterval(clamped), max: fullXDomain.upperBound)
        }

        selectedPoint = nil
    }

    private func syncStateToDomain() {
        // Keep the user on a valid window if the domain changes (e.g. range changes, new data).
        let isAll = abs(visibleLength - fullLength) < 1
        visibleLength = isAll ? fullLength : min(max(visibleLength, minZoomLength), fullLength)
        visibleEnd = clamp(visibleEnd, min: fullXDomain.lowerBound.addingTimeInterval(visibleLength), max: fullXDomain.upperBound)
        selectedPoint = nil
    }

    private func clamp(_ value: Date, min: Date, max: Date) -> Date {
        if value < min { return min }
        if value > max { return max }
        return value
    }
}
