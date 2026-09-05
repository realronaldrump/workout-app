import CoreGraphics
import Foundation

nonisolated enum WorkoutPDFRenderer {
    typealias Canvas = WorkoutPDFCanvas
    typealias Style = WorkoutPDFStyle

    private struct Metric {
        let label: String
        let value: String
        let detail: String
    }

    @discardableResult
    static func write(
        _ document: WorkoutExportDocument, to handle: FileHandle, includeJournal: Bool = false, sourceNote: String? = nil
    ) throws -> WorkoutPDFAudit {
        let analytics = WorkoutPDFAnalytics(document)
        let range = displayRange(document)
        let canvas = try Canvas(handle: handle, rangeLabel: range)
        defer { canvas.finish() }
        overview(document, analytics: analytics, range: range, sourceNote: sourceNote, canvas: canvas)
        if analytics.sessions.count > 1, analytics.exercises.count > 1 || !analytics.muscles.isEmpty {
            trainingMix(document, analytics: analytics, canvas: canvas)
        }
        if !analytics.trends.isEmpty { progress(analytics, canvas: canvas) }
        if !document.breaks.isEmpty { try savedBreaks(document.breaks, canvas: canvas) }
        if includeJournal { try WorkoutPDFJournal.render(document, sessions: analytics.sessions, canvas: canvas) }
        canvas.finish()
        try canvas.checkWrite()
        return canvas.audit
    }

    private static func overview(
        _ document: WorkoutExportDocument, analytics: WorkoutPDFAnalytics, range: String, sourceNote: String?, canvas: Canvas
    ) {
        canvas.newPage("Overview")
        canvas.bookmark("Training overview")
        canvas.text("Your training", x: 42, y: 79, width: 528, size: 35, font: .display)
        canvas.text(range, x: 43, y: 132, width: 525, size: 11, color: Style.muted)
        if analytics.durationCount > 0 {
            let useHours = analytics.durationSeconds >= 3600
            let value = Style.number(analytics.durationSeconds / (useHours ? 3600 : 60), decimals: 1)
            let unit = useHours ? "hours" : "minutes"
            let coverage = "\(analytics.durationCount) of \(Style.count(analytics.sessions.count, "workout"))"
            canvas.oneLine("\(value) recorded \(unit)  |  Duration available for \(coverage)",
                           x: 43, y: 156, width: 525, size: 8, color: Style.muted)
        }
        let metrics = overviewMetrics(document, analytics: analytics)
        let width = (528 - CGFloat(metrics.count - 1) * 10) / CGFloat(metrics.count)
        for (index, metric) in metrics.enumerated() {
            let x = 42 + CGFloat(index) * (width + 10)
            let background = index == 0 ? Style.ink : index == 1 ? Style.sage : Style.lilac
            let foreground = index == 0 ? Style.white : Style.ink
            canvas.fill(CGRect(x: x, y: 181, width: width, height: 98), color: background, radius: 10)
            canvas.oneLine(metric.label.uppercased(), x: x + 16, y: 197, width: width - 32, size: 8, font: .medium, color: foreground)
            canvas.oneLine(metric.value, x: x + 16, y: 218, width: width - 32, size: 29, font: .display, color: foreground)
            canvas.oneLine(metric.detail, x: x + 16, y: 259, width: width - 32, size: 7.5, color: foreground)
        }

        if analytics.sessions.count > 1, !analytics.buckets.isEmpty {
            canvas.text("A rhythm over time", x: 42, y: 309, width: 528, size: 20, font: .display)
            canvas.text("\(analytics.intervalTitle) workout counts. Empty intervals stay visible.",
                        x: 42, y: 342, width: 528, size: 9, color: Style.muted)
            WorkoutPDFCharts.activity(analytics.buckets, in: CGRect(x: 42, y: 363, width: 528, height: 180), on: canvas)
            canvas.line(CGPoint(x: 42, y: 568), CGPoint(x: 570, y: 568), color: Style.rule)
            canvas.text("When you train", x: 42, y: 587, width: 528, size: 17, font: .display)
            WorkoutPDFCharts.weekdays(analytics.weekdays, in: CGRect(x: 42, y: 625, width: 528, height: 82), on: canvas)
            let note = sourceNote ?? "By workout start day in \(document.timeZone). First and last chart intervals may be partial."
            canvas.oneLine(note,
                           x: 42, y: 720, width: 528, size: 7, color: Style.muted)
        } else if !analytics.exercises.isEmpty {
            canvas.text(analytics.sessions.count == 1 ? "Inside this workout" : "Set composition",
                        x: 42, y: 312, width: 528, size: 20, font: .display)
            canvas.text("Selected sets by exercise", x: 42, y: 345, width: 528, size: 9, color: Style.muted)
            WorkoutPDFCharts.composition(analytics.exercises, total: document.records.count,
                                         in: CGRect(x: 42, y: 380, width: 528, height: 220), on: canvas)
            sessionNote(analytics, canvas: canvas)
        } else {
            canvas.text("Session overview", x: 42, y: 316, width: 528, size: 20, font: .display)
            canvas.fill(CGRect(x: 42, y: 366, width: 528, height: 172), color: Style.sage, radius: 12)
            canvas.oneLine(Style.number(Double(document.records.count) / Double(max(1, analytics.sessions.count)), decimals: 1),
                           x: 66, y: 389, width: 470, size: 50, font: .display, color: Style.green)
            canvas.text("Selected sets per workout", x: 68, y: 464, width: 460, size: 13, font: .medium)
            canvas.text("Session totals reflect the selected sets.", x: 68, y: 493, width: 460, size: 9, color: Style.muted)
            sessionNote(analytics, canvas: canvas)
        }
    }

    private static func overviewMetrics(_ document: WorkoutExportDocument, analytics: WorkoutPDFAnalytics) -> [Metric] {
        var metrics = [
            Metric(label: "Workouts", value: Style.number(Double(analytics.sessions.count)), detail: "in this export"),
            Metric(label: "Sets", value: Style.number(Double(document.records.count)), detail: "selected entries")
        ]
        if !analytics.exercises.isEmpty {
            metrics.append(Metric(label: "Exercises", value: Style.number(Double(analytics.exercises.count)), detail: "distinct logged names"))
        } else if analytics.durationCount > 0 {
            metrics.append(Metric(label: "Recorded hours", value: Style.number(analytics.durationSeconds / 3600, decimals: 1),
                                  detail: "\(analytics.durationCount) timed workouts"))
        } else if let reps = analytics.totalReps {
            metrics.append(Metric(label: "Reps", value: Style.number(reps), detail: "across selected sets"))
        }
        return metrics
    }

    private static func sessionNote(_ analytics: WorkoutPDFAnalytics, canvas: Canvas) {
        canvas.line(CGPoint(x: 42, y: 628), CGPoint(x: 570, y: 628), color: Style.rule)
        let title = analytics.sessions.count == 1 ? "One workout, every selected set." : "Your selected training, at a glance."
        canvas.text(title, x: 42, y: 649, width: 528, size: 15, font: .display)
        var detail = analytics.sessions.count < 3
            ? "Exercise trends appear once an exercise has three recorded workouts."
            : "Charts reflect the fields selected for export."
        if analytics.durationCount > 0 {
            detail += " Recorded session time: \(Style.number(analytics.durationSeconds / 60, decimals: 1)) minutes " +
                "across \(Style.count(analytics.durationCount, "workout"))."
        }
        canvas.text(detail, x: 42, y: 679, width: 528, size: 9, color: Style.muted)
    }

    private static func trainingMix(_ document: WorkoutExportDocument, analytics: WorkoutPDFAnalytics, canvas: Canvas) {
        canvas.newPage("Training mix")
        canvas.bookmark("Training mix")
        canvas.text("How you trained", x: 42, y: 79, width: 528, size: 31, font: .display)
        canvas.text("An overview of the exercises and muscle roles in your selected sets.",
                    x: 42, y: 127, width: 528, size: 10, color: Style.muted)
        if !analytics.muscles.isEmpty {
            canvas.text("Muscle exposure", x: 42, y: 172, width: 380, size: 18, font: .display)
            canvas.circle(center: CGPoint(x: 391, y: 184), radius: 3, color: Style.green)
            canvas.oneLine("Primary", x: 400, y: 178, width: 60, size: 8, color: Style.muted)
            canvas.circle(center: CGPoint(x: 474, y: 184), radius: 3, color: Style.purple)
            canvas.oneLine("Secondary x 0.5", x: 483, y: 178, width: 90, size: 8, color: Style.muted)
            WorkoutPDFCharts.categories(analytics.muscles, in: CGRect(x: 42, y: 217, width: 528, height: 230),
                                         limit: 7, stacked: true, on: canvas)
            let coverage = "\(analytics.mappedSetCount) of \(document.records.count) sets have muscle roles. " +
                "A set can contribute to several muscles. " +
                "Showing the top \(min(7, analytics.muscles.count)) of \(analytics.muscles.count) groups."
            canvas.text(coverage, x: 42, y: 465, width: 528, size: 8, color: Style.muted)
            if !analytics.exercises.isEmpty {
                canvas.text("Most practiced", x: 42, y: 509, width: 528, size: 18, font: .display)
                WorkoutPDFCharts.categories(analytics.exercises, in: CGRect(x: 42, y: 547, width: 528, height: 146), limit: 4, on: canvas)
                canvas.oneLine("Top \(min(4, analytics.exercises.count)) of \(analytics.exercises.count) exercises by selected set count.",
                               x: 42, y: 714, width: 528, size: 8, color: Style.muted)
            }
        } else {
            canvas.text("Most practiced", x: 42, y: 176, width: 528, size: 19, font: .display)
            WorkoutPDFCharts.categories(analytics.exercises, in: CGRect(x: 42, y: 222, width: 528, height: 330), limit: 8, on: canvas)
            canvas.text("Top \(min(8, analytics.exercises.count)) of \(analytics.exercises.count) exercises by selected set count.",
                        x: 42, y: 574, width: 528, size: 9, color: Style.muted)
            canvas.fill(CGRect(x: 42, y: 623, width: 528, height: 91), color: Style.lilac, radius: 10)
            canvas.text("Recorded session time", x: 60, y: 639, width: 400, size: 12, font: .medium)
            let time = analytics.durationCount > 0
                ? "\(Style.number(analytics.durationSeconds / 3600, decimals: 1)) hours across " +
                    "\(analytics.durationCount) of \(analytics.sessions.count) workouts."
                : "Workout duration is unavailable or excluded from this export."
            canvas.text(time, x: 60, y: 665, width: 490, size: 10, color: Style.muted)
        }
    }

    private static func progress(_ analytics: WorkoutPDFAnalytics, canvas: Canvas) {
        canvas.newPage("Exercise history")
        canvas.bookmark("Exercise history charts")
        canvas.text("Exercise history", x: 42, y: 79, width: 528, size: 31, font: .display)
        canvas.text("A selection of your most logged exercises with at least three workouts.", x: 42, y: 127, width: 528, size: 10, color: Style.muted)
        let rows = Int(ceil(Double(analytics.trends.count) / 2))
        let cardHeight: CGFloat = rows == 1 ? 300 : 249
        for (index, trend) in analytics.trends.enumerated() {
            let x: CGFloat = index % 2 == 0 ? 42 : 315
            let y = 177 + CGFloat(index / 2) * (cardHeight + 15)
            canvas.fill(CGRect(x: x, y: y, width: 255, height: cardHeight), color: Style.white, radius: 10)
            canvas.oneLine(trend.name, x: x + 14, y: y + 16, width: 226, size: 11, font: .medium)
            canvas.oneLine("\(trend.metric) (\(trend.unit))", x: x + 14, y: y + 38, width: 226, size: 8, color: Style.muted)
            canvas.oneLine(Style.count(trend.sessionCount, "workout"), x: x + 14, y: y + 56, width: 226, size: 8, color: Style.muted)
            WorkoutPDFCharts.trend(trend, labels: analytics.buckets.map(\.label),
                                   in: CGRect(x: x + 14, y: y + 81, width: 226, height: cardHeight - 97), on: canvas)
        }
        let note = "\(analytics.intervalTitle) maximum recorded values. Gaps mean no selected observation. " +
            "Heaviest-set values are not adjusted for rep count."
        canvas.text(note, x: 42, y: 706, width: 528, size: 8, color: Style.muted)
    }

    private static func savedBreaks(_ breaks: [WorkoutExportBreak], canvas: Canvas) throws {
        canvas.newPage("Saved breaks")
        canvas.bookmark("Saved breaks")
        try canvas.flowText("Space between sessions", size: 30, font: .display)
        canvas.cursor += 13
        try canvas.flowText("Saved breaks are context, not missed workouts. Dates are inclusive and clipped to the selected range.",
                            size: 10, color: Style.muted)
        canvas.cursor += 28
        for saved in breaks {
            canvas.ensureSpace(76)
            canvas.fill(CGRect(x: 30, y: canvas.cursor, width: 3, height: 40), color: Style.green, radius: 1.5)
            try canvas.flowText(saved.name ?? "Saved break", size: 14, font: .medium)
            canvas.cursor += 3
            try canvas.flowText("\(saved.startDate) - \(saved.endDate)    \(Style.count(saved.days, "day"))", size: 10, color: Style.muted)
            canvas.cursor += 25
        }
    }

    private static func displayRange(_ document: WorkoutExportDocument) -> String {
        let parser = WorkoutExportDocument.formatter("yyyy-MM-dd", timeZone: .gmt)
        let display = WorkoutExportDocument.formatter("MMM d, yyyy", timeZone: .gmt)
        guard let start = parser.date(from: document.startDay), let end = parser.date(from: document.endDay) else {
            return "\(document.startDay) - \(document.endDay)"
        }
        return start == end ? display.string(from: start) : "\(display.string(from: start)) - \(display.string(from: end))"
    }
}
