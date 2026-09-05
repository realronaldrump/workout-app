import CoreGraphics
import CoreText
import Foundation

nonisolated enum WorkoutPDFCharts {
    typealias Canvas = WorkoutPDFCanvas
    typealias Style = WorkoutPDFStyle

    static func activity(_ buckets: [WorkoutPDFAnalytics.Bucket], in rect: CGRect, on canvas: Canvas) {
        let plot = rect.insetBy(dx: 28, dy: 22)
        let scale = axis(maximum: Double(buckets.map(\.workouts).max() ?? 0), integer: true)
        grid(plot, scale: scale, canvas: canvas)
        guard !buckets.isEmpty else { return }
        let step = plot.width / CGFloat(buckets.count)
        let width = min(25, max(2, step * 0.64))
        for (index, bucket) in buckets.enumerated() {
            let height = CGFloat(Double(bucket.workouts) / scale.top) * plot.height
            let x = plot.minX + CGFloat(index) * step + (step - width) / 2
            if height > 0 {
                canvas.fill(CGRect(x: x, y: plot.maxY - height, width: width, height: height),
                            color: index == buckets.count - 1 ? Style.purple : Style.green, radius: min(3, height / 2))
            }
        }
        labels(buckets.map(\.label), plot: plot, centeredBins: true, canvas: canvas)
    }

    static func weekdays(_ counts: [Int], in rect: CGRect, on canvas: Canvas) {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let maximum = max(1, counts.max() ?? 1)
        let step = rect.width / 7
        for index in 0..<7 {
            let x = rect.minX + step * (CGFloat(index) + 0.5)
            let height = CGFloat(counts[index]) / CGFloat(maximum) * (rect.height - 40)
            canvas.line(CGPoint(x: x, y: rect.maxY - 22), CGPoint(x: x, y: rect.maxY - 22 - height),
                        color: Style.purple.copy(alpha: 0.35) ?? Style.lilac, width: 7)
            canvas.circle(center: CGPoint(x: x, y: rect.maxY - 22 - height), radius: 4, color: Style.purple)
            canvas.oneLine(String(counts[index]), x: x - 28, y: rect.maxY - height - 41, width: 56,
                           size: 9, font: .medium, align: .center)
            canvas.oneLine(names[index], x: x - 28, y: rect.maxY - 12, width: 56, size: 8, color: Style.muted, align: .center)
        }
    }

    static func categories(
        _ values: [WorkoutPDFAnalytics.Category], in rect: CGRect, limit: Int = 6,
        stacked: Bool = false, on canvas: Canvas
    ) {
        let shown = Array(values.prefix(limit))
        let maximum = max(1, shown.map { $0.count + $0.secondary }.max() ?? 1)
        let step = rect.height / CGFloat(max(1, shown.count))
        for (index, value) in shown.enumerated() {
            let y = rect.minY + CGFloat(index) * step
            canvas.oneLine(value.name.isEmpty ? "Unnamed exercise" : value.name,
                           x: rect.minX, y: y, width: rect.width - 65, size: 10, font: .medium)
            canvas.oneLine(Style.number(value.count + value.secondary, decimals: stacked ? 1 : 0),
                           x: rect.maxX - 65, y: y, width: 65, size: 10, font: .mono, align: .right)
            let bar = CGRect(x: rect.minX, y: y + 18, width: rect.width, height: 7)
            canvas.fill(bar, color: Style.rule, radius: 3)
            let first = rect.width * CGFloat(value.count / maximum)
            let second = rect.width * CGFloat(value.secondary / maximum)
            canvas.fill(CGRect(x: bar.minX, y: bar.minY, width: first, height: bar.height),
                        color: stacked ? Style.green : Style.palette[index % Style.palette.count], radius: 2)
            if second > 0 {
                canvas.fill(CGRect(x: bar.minX + first, y: bar.minY, width: second, height: bar.height), color: Style.purple, radius: 2)
            }
        }
    }

    static func composition(_ categories: [WorkoutPDFAnalytics.Category], total: Int, in rect: CGRect, on canvas: Canvas) {
        var slices = Array(categories.prefix(5))
        if categories.count > 5 {
            slices.append(.init(name: "Other exercises", count: categories.dropFirst(5).reduce(0) { $0 + $1.count }))
        }
        let center = CGPoint(x: rect.minX + 108, y: rect.midY)
        let radius: CGFloat = 90
        var angle = -Double.pi / 2
        for (index, slice) in slices.enumerated() {
            let next = angle + slice.count / Double(max(1, total)) * .pi * 2
            canvas.context.setFillColor(Style.palette[index])
            canvas.context.beginPath()
            canvas.context.move(to: center)
            canvas.context.addArc(center: center, radius: radius, startAngle: angle, endAngle: next, clockwise: false)
            canvas.context.closePath()
            canvas.context.fillPath()
            angle = next
        }
        canvas.circle(center: center, radius: 67, color: Style.paper)
        canvas.oneLine(Style.number(Double(total)), x: center.x - 62, y: center.y - 25, width: 124, size: 28, font: .display, align: .center)
        canvas.oneLine("SELECTED SETS", x: center.x - 60, y: center.y + 19, width: 120, size: 7.5, color: Style.muted, align: .center)
        let top = rect.midY - CGFloat(slices.count) * 18
        for (index, slice) in slices.enumerated() {
            let y = top + CGFloat(index) * 36
            canvas.circle(center: CGPoint(x: rect.minX + 236, y: y + 6), radius: 3, color: Style.palette[index])
            canvas.oneLine(slice.name, x: rect.minX + 249, y: y - 2, width: rect.width - 254, size: 9, font: .medium)
            canvas.oneLine(Style.count(Int(slice.count), "set"), x: rect.minX + 249, y: y + 12,
                           width: rect.width - 254, size: 8, color: Style.muted)
        }
    }

    static func trend(_ trend: WorkoutPDFAnalytics.Trend, labels: [String], in rect: CGRect, on canvas: Canvas) {
        let plot = rect.insetBy(dx: 25, dy: 22)
        let scale = axis(maximum: trend.values.compactMap { $0 }.max() ?? 0, integer: false)
        grid(plot, scale: scale, canvas: canvas)
        let step = plot.width / CGFloat(max(1, trend.values.count - 1))
        var segment: [CGPoint] = []
        func drawSegment() {
            guard let first = segment.first, let last = segment.last else { return }
            if segment.count > 1 {
                canvas.context.setFillColor(Style.green.copy(alpha: 0.10) ?? Style.sage)
                canvas.context.beginPath()
                canvas.context.move(to: CGPoint(x: first.x, y: plot.maxY))
                segment.forEach { canvas.context.addLine(to: $0) }
                canvas.context.addLine(to: CGPoint(x: last.x, y: plot.maxY))
                canvas.context.closePath()
                canvas.context.fillPath()
                for index in 1..<segment.count { canvas.line(segment[index - 1], segment[index], color: Style.green, width: 1.6) }
            }
            segment.forEach { canvas.circle(center: $0, radius: 2.3, color: Style.green) }
            segment.removeAll(keepingCapacity: true)
        }
        for (index, value) in trend.values.enumerated() {
            guard let value else { drawSegment(); continue }
            segment.append(CGPoint(x: plot.minX + CGFloat(index) * step, y: plot.maxY - CGFloat(value / scale.top) * plot.height))
        }
        drawSegment()
        self.labels(labels, plot: plot, centeredBins: false, canvas: canvas, limit: 3)
    }

    private static func axis(maximum: Double, integer: Bool) -> (top: Double, step: Double) {
        guard maximum > 0, maximum.isFinite else { return (1, 1) }
        let rough = maximum / 3
        let magnitude = pow(10, floor(log10(rough)))
        let factor = [1.0, 2, 5, 10].first { $0 * magnitude >= rough } ?? 10
        let step = max(integer ? 1 : Double.leastNormalMagnitude, factor * magnitude)
        let top = ceil(maximum / step) * step
        return (top.isFinite ? top : maximum, step)
    }

    private static func grid(_ plot: CGRect, scale: (top: Double, step: Double), canvas: Canvas) {
        let count = Int((scale.top / scale.step).rounded())
        for index in 0...min(count, 5) {
            let value = Double(index) * scale.step
            guard value.isFinite, value <= scale.top else { continue }
            let y = plot.maxY - CGFloat(value / scale.top) * plot.height
            canvas.line(CGPoint(x: plot.minX, y: y), CGPoint(x: plot.maxX, y: y), color: Style.rule)
            let decimals = scale.step < 1 ? min(8, max(0, Int(-floor(log10(scale.step))))) : 0
            canvas.oneLine(Style.number(value, decimals: decimals),
                           x: plot.minX - 31, y: y - 5, width: 26, size: 7, color: Style.muted, align: .right)
        }
    }

    private static func labels(_ labels: [String], plot: CGRect, centeredBins: Bool, canvas: Canvas, limit: Int = 6) {
        guard !labels.isEmpty else { return }
        let indices = Set((0..<min(limit, labels.count)).map { index in
            labels.count == 1 ? 0 : Int((Double(index) * Double(labels.count - 1) / Double(min(limit, labels.count) - 1)).rounded())
        })
        for index in indices.sorted() {
            let fraction = centeredBins ? (CGFloat(index) + 0.5) / CGFloat(labels.count) : CGFloat(index) / CGFloat(max(1, labels.count - 1))
            canvas.oneLine(labels[index], x: plot.minX + fraction * plot.width - 28, y: plot.maxY + 10,
                           width: 56, size: 7, color: Style.muted, align: .center)
        }
    }
}
