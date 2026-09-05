import CoreGraphics
import CoreText
import Foundation

nonisolated enum WorkoutPDFJournal {
    typealias Canvas = WorkoutPDFCanvas
    typealias Style = WorkoutPDFStyle

    static func render(_ document: WorkoutExportDocument, sessions: [WorkoutPDFAnalytics.Session], canvas: Canvas) throws {
        canvas.newPage("Workout journal")
        canvas.bookmark("Complete workout journal")
        try canvas.flowText("Workout journal", size: 29, font: .display)
        canvas.cursor += 8
        var introduction = "\(Style.count(sessions.count, "workout")). \(Style.count(document.records.count, "selected set"))."
        if document.columns.contains(.distance) { introduction += " Distance is shown as logged; its unit is not stored." }
        try canvas.flowText(introduction, size: 9, color: Style.muted)
        canvas.cursor += 25
        let selected = Set(document.columns)
        let dateFormatter = WorkoutExportDocument.formatter(
            "MMM d, yyyy 'at' h:mm a 'UTC'XXXXX", timeZone: TimeZone(identifier: document.timeZone) ?? .gmt
        )

        for (sessionIndex, session) in sessions.enumerated() {
            let first = document.records[session.rows.lowerBound]
            let name = selected.contains(.workoutName) ? first.value(.workoutName).text : "Workout \(sessionIndex + 1)"
            canvas.ensureSpace(120)
            canvas.bookmark("\(sessionIndex + 1). \(name)")
            canvas.audit.workoutHeadings += 1
            canvas.fill(CGRect(x: 42, y: canvas.cursor, width: 528, height: 3), color: Style.green)
            canvas.cursor += 12
            try canvas.flowText(name.isEmpty ? "Untitled workout" : name, size: 16, font: .medium)
            var details: [String] = []
            if selected.contains(.workoutStart) { details.append(dateFormatter.string(from: first.startedAt)) }
            if selected.contains(.gymName), !first.value(.gymName).text.isEmpty { details.append(first.value(.gymName).text) }
            if selected.contains(.durationText) {
                details.append(first.value(.durationText).text)
            } else if selected.contains(.duration), !first.value(.duration).text.isEmpty {
                details.append("\(first.value(.duration).text) seconds")
            }
            canvas.cursor += 3
            try canvas.flowText(details.filter { !$0.isEmpty }.joined(separator: "  |  "), size: 8, color: Style.muted)
            canvas.cursor += 15
            let continuation = selected.contains(.workoutStart)
                ? "\(dateFormatter.string(from: first.startedAt))  |  \(name)" : name
            var index = session.rows.lowerBound
            var exerciseNumber = 0
            while index < session.rows.upperBound {
                let start = index
                let exerciseID = document.records[index].exerciseID
                while index < session.rows.upperBound, document.records[index].exerciseID == exerciseID { index += 1 }
                exerciseNumber += 1
                try exercise(document, range: start..<index, number: exerciseNumber, workoutName: continuation, canvas: canvas)
            }
            canvas.cursor += 15
        }
    }

    private static func exercise(
        _ document: WorkoutExportDocument, range: Range<Int>, number: Int, workoutName: String, canvas: Canvas
    ) throws {
        let columns = document.columns.filter(\.isSetValue)
        let first = document.records[range.lowerBound]
        let name = document.columns.contains(.exercise) ? first.value(.exercise).text : "Exercise \(number)"
        let context = [WorkoutExportColumn.parentExercise, .side, .tags].compactMap { column -> String? in
            guard document.columns.contains(column), !first.value(column).text.isEmpty else { return nil }
            if column == .tags { return first.value(column).text }
            return "\(column.title): \(first.value(column).text)"
        }.joined(separator: "  |  ")
        let headingHeight = canvas.height(name, width: 528, size: 11, font: .medium) +
            canvas.height(context, width: 528, size: 8) + 36
        // Move a short exercise together. Long exercises continue across as many pages as needed.
        let blockHeight = headingHeight + CGFloat(range.count) * 18
        let startingPage = canvas.audit.pages
        canvas.ensureSpace(min(blockHeight, min(headingHeight + 18, 200)))
        if blockHeight < Canvas.bottom - 78 { canvas.ensureSpace(blockHeight) }
        if startingPage != canvas.audit.pages {
            canvas.oneLine(workoutName + " (continued)", x: 42, y: canvas.cursor, width: 528, size: 9, font: .medium)
            canvas.cursor += 24
        }
        try canvas.flowText(name.isEmpty ? "Unnamed exercise" : name, size: 11, font: .medium)
        canvas.cursor += 2
        try canvas.flowText(context, size: 8, color: Style.muted)
        canvas.cursor += 6
        let headingPage = canvas.audit.pages
        canvas.ensureSpace(45)
        if headingPage != canvas.audit.pages {
            canvas.oneLine(workoutName + " (continued)", x: 42, y: canvas.cursor, width: 528, size: 10, font: .medium)
            canvas.cursor += 23
            canvas.oneLine(name + " (continued)", x: 42, y: canvas.cursor, width: 528, size: 9, color: Style.muted)
            canvas.cursor += 22
        }
        tableHeader(columns, document: document, canvas: canvas)
        for (ordinal, recordIndex) in range.enumerated() {
            let record = document.records[recordIndex]
            let values = columns.isEmpty ? ["Entry \(ordinal + 1)"] : columns.map { record.value($0).text }
            let width = columnWidths(max(1, values.count))
            let wrapped = values.map { canvas.lineWidth($0, size: 8.5, font: .mono) > width - 16 }
            let rowHeight = max(18, values.enumerated().map { index, value in
                wrapped[index] ? canvas.height(value, width: width - 16, size: 8.5, font: .mono) + 6 : 18
            }.max() ?? 18)
            if canvas.cursor + rowHeight > Canvas.bottom {
                canvas.newPage()
                canvas.oneLine(workoutName + " (continued)", x: 42, y: canvas.cursor, width: 528, size: 10, font: .medium)
                canvas.cursor += 23
                canvas.oneLine(name + " (continued)", x: 42, y: canvas.cursor, width: 528, size: 9, color: Style.muted)
                canvas.cursor += 22
                tableHeader(columns, document: document, canvas: canvas)
            }
            if ordinal % 2 == 0 {
                canvas.fill(CGRect(x: 42, y: canvas.cursor, width: 528, height: rowHeight),
                            color: Style.sage.copy(alpha: 0.46) ?? Style.sage)
            }
            for (index, value) in values.enumerated() {
                if wrapped[index] {
                    canvas.text(value, x: 50 + width * CGFloat(index), y: canvas.cursor + 3,
                                width: width - 16, size: 8.5, font: .mono)
                } else {
                    canvas.oneLine(value.isEmpty ? "-" : value, x: 50 + width * CGFloat(index), y: canvas.cursor + 3,
                                   width: width - 16, size: 8.5, font: .mono, align: index == 0 ? .left : .right)
                }
            }
            canvas.audit.setRows += 1
            canvas.cursor += rowHeight
        }
        canvas.cursor += 13
    }

    private static func tableHeader(_ columns: [WorkoutExportColumn], document: WorkoutExportDocument, canvas: Canvas) {
        let headers = columns.isEmpty ? ["Set entries"] : columns.map { column -> String in
            switch column {
            case .seconds: return "Time (s)"
            case .distance: return "Distance"
            default: return document.header(for: column)
            }
        }
        let width = columnWidths(headers.count)
        for (index, header) in headers.enumerated() {
            canvas.oneLine(header, x: 50 + width * CGFloat(index), y: canvas.cursor + 2,
                           width: width - 16, size: 7, font: .medium, color: Style.muted, align: index == 0 ? .left : .right)
        }
        canvas.line(CGPoint(x: 42, y: canvas.cursor + 18), CGPoint(x: 570, y: canvas.cursor + 18), color: Style.rule)
        canvas.cursor += 21
    }

    private static func columnWidths(_ count: Int) -> CGFloat { 528 / CGFloat(max(1, count)) }
}
