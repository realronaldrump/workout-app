import Foundation

nonisolated enum WorkoutReportRenderer {
    static func render(_ document: WorkoutExportDocument) throws -> String {
        let workoutGroups = grouped(document.records, by: \.workoutID)
        let workouts = workoutGroups.enumerated().map { index, rows in
            workoutSection(rows, number: index + 1, document: document)
        }.joined(separator: "\n")
        // The same selected data is embedded for tools that read this human-facing report.
        // JSONEncoder always produces valid UTF-8.
        let json = String(data: try document.jsonData(), encoding: .utf8)!
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
        let dateRange = "\(document.startDay) – \(document.endDay)"
        let unitNote = document.weightUnit.map { "Weight in \($0). " } ?? "Weight unit unspecified. "
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light">
          <title>Workout journal · \(escape(dateRange))</title>
          <style>\(styles)</style>
        </head>
        <body>
          <main>
            <header class="journal-header">
              <p class="eyebrow">Workout history</p>
              <h1>Workout journal</h1>
              <p class="date-range">\(escape(dateRange))</p>
              <p class="totals"><strong>\(workoutGroups.count)</strong> workouts <span>·</span>
                <strong>\(document.records.count)</strong> sets</p>
              <p class="units">\(escape(unitNote))Dates in \(escape(document.timeZone)).
                Distance values retain their logged units, which the app does not store.</p>
            </header>
            \(breakSection(document.breaks))
            <div class="workouts">\(workouts)</div>
            <footer>Workout history · \(escape(dateRange))</footer>
          </main>
          <script type="application/json" id="workout-data">\(json)</script>
        </body>
        </html>
        """
    }

    private static func workoutSection(
        _ rows: [WorkoutExportRecord], number: Int, document: WorkoutExportDocument
    ) -> String {
        guard let first = rows.first else { return "" }
        let selected = Set(document.columns)
        let name = selected.contains(.workoutName) ? first.value(.workoutName).text : "Workout \(number)"
        var details: [String] = []
        if selected.contains(.workoutStart) {
            let formatter = WorkoutExportDocument.formatter(
                "EEE, MMM d, yyyy 'at' h:mm a", timeZone: TimeZone(identifier: document.timeZone) ?? .gmt
            )
            details.append(formatter.string(from: first.startedAt))
        }
        if selected.contains(.gymName), !first.value(.gymName).text.isEmpty {
            details.append(first.value(.gymName).text)
        }
        if selected.contains(.durationText), !first.value(.durationText).text.isEmpty {
            details.append(first.value(.durationText).text)
        } else if selected.contains(.duration), !first.value(.duration).text.isEmpty {
            details.append("\(first.value(.duration).text) seconds")
        }
        let exerciseSections = grouped(rows, by: \.exerciseID).enumerated().map { index, sets in
            exerciseSection(sets, number: index + 1, document: document)
        }.joined(separator: "\n")
        return """
        <section class="workout" data-workout-id="\(first.workoutID.uuidString)">
          <header class="workout-header">
            <p class="workout-number">Workout \(number)</p>
            <h2>\(escape(name))</h2>
            <p class="workout-details">\(details.map(escape).joined(separator: " <span>·</span> "))</p>
          </header>
          \(exerciseSections)
        </section>
        """
    }

    private static func exerciseSection(
        _ rows: [WorkoutExportRecord], number: Int, document: WorkoutExportDocument
    ) -> String {
        guard let first = rows.first else { return "" }
        let selected = Set(document.columns)
        let name = selected.contains(.exercise) ? first.value(.exercise).text : "Exercise \(number)"
        let context = [WorkoutExportColumn.parentExercise, .side, .tags].compactMap { column -> String? in
            let value = first.value(column).text
            guard selected.contains(column), !value.isEmpty else { return nil }
            return column == .parentExercise ? "Parent: \(value)" : value
        }
        let selectedSetColumns = document.columns.filter(\.isSetValue)
        let usefulColumns = selectedSetColumns.filter { column in
            guard column == .distance || column == .seconds else { return true }
            return rows.contains { row in
                if case .number(let value) = row.value(column) { return value.isFinite && value != 0 }
                return false
            }
        }
        // Keep the journal compact for strength exercises. The embedded JSON keeps all selected values.
        let setColumns = usefulColumns.isEmpty ? selectedSetColumns : usefulColumns
        let headers = setColumns.map { column in
            let label = column == .seconds ? "Time (seconds)" : column == .distance ? "Distance" : document.header(for: column)
            return "<th scope=\"col\">\(escape(label))</th>"
        }.joined()
        let setRows = rows.map { row in
            let cells = setColumns.map { column in
                let value = row.value(column).text
                return "<td>\(value.isEmpty ? "—" : escape(value))</td>"
            }.joined()
            return "<tr data-set-id=\"\(row.setID.uuidString)\">\(cells)</tr>"
        }.joined(separator: "\n")
        let table = setColumns.isEmpty ? "<p class=\"exercise-context\">\(rows.count) sets</p>" : """
        <div class="table-scroll" role="region" aria-label="\(escape(name)) sets" tabindex="0">
          <table>
            <caption class="sr-only">\(escape(name)) sets</caption>
            <thead><tr>\(headers)</tr></thead>
            <tbody>\(setRows)</tbody>
          </table>
        </div>
        """
        return """
        <section class="exercise" data-exercise-id="\(first.exerciseID.uuidString)">
          <h3>\(escape(name))</h3>
          <p class="exercise-context">\(context.map(escape).joined(separator: " <span>·</span> "))</p>
          \(table)
        </section>
        """
    }

    private static func breakSection(_ breaks: [WorkoutExportBreak]) -> String {
        guard !breaks.isEmpty else { return "" }
        let rows = breaks.map { item in
            """
            <li><strong>\(escape(item.name ?? "Saved break"))</strong>
              <span>\(item.startDate) – \(item.endDate) · \(item.days) \(item.days == 1 ? "day" : "days")</span></li>
            """
        }.joined(separator: "\n")
        return """
        <aside class="breaks" aria-label="Saved breaks">
          <h2>Saved breaks</h2><ul>\(rows)</ul>
          <p class="units">Dates are inclusive and limited to this export range.</p>
        </aside>
        """
    }

    private static func grouped(
        _ records: [WorkoutExportRecord], by key: KeyPath<WorkoutExportRecord, UUID>
    ) -> [[WorkoutExportRecord]] {
        var order: [UUID] = []
        var groups: [UUID: [WorkoutExportRecord]] = [:]
        for record in records {
            let id = record[keyPath: key]
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(record)
        }
        return order.compactMap { groups[$0] }
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static let styles = """
    :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #272633; background: #f6f5f1; font-size: 15px; line-height: 1.5; }
    * { box-sizing: border-box; }
    body { margin: 0; }
    main { max-width: 940px; margin: 0 auto; padding: 56px 28px 32px; }
    h1, h2, h3, p { margin: 0; }
    h1 { font-size: clamp(32px, 6vw, 46px); line-height: 1.15; letter-spacing: -1.5px; font-weight: 650; }
    h2 { font-size: 23px; line-height: 1.3; letter-spacing: -.4px; overflow-wrap: anywhere; }
    h3 { font-size: 16px; font-weight: 650; overflow-wrap: anywhere; }
    .journal-header { margin-bottom: 36px; padding-bottom: 28px; border-bottom: 2px solid #34313f; }
    .eyebrow { font-size: 12px; text-transform: uppercase; letter-spacing: 1.6px; color: #65606f; margin-bottom: 10px; }
    .date-range { margin-top: 12px; font-size: 18px; color: #5d5968; }
    .totals { margin-top: 24px; font-size: 17px; }
    .totals strong { font-variant-numeric: tabular-nums; }
    span { margin: 0 4px; }
    .units { font-size: 12px; line-height: 1.6; color: #696573; margin-top: 12px; max-width: 680px; }
    .workout { background: #fff; border: 1px solid #e1dfe5; border-radius: 16px; margin-bottom: 26px; overflow: hidden; }
    .workout-header { padding: 24px 28px; background: #efedf5; border-bottom: 1px solid #e1dfe5; }
    .workout-number { color: #6b607c; font-size: 12px; letter-spacing: .9px; text-transform: uppercase; margin-bottom: 6px; }
    .workout-details { color: #635d70; font-size: 13px; margin-top: 9px; overflow-wrap: anywhere; }
    .exercise { padding: 22px 28px; }
    .exercise + .exercise { border-top: 1px solid #ecebf0; }
    .exercise-context { margin: 4px 0 12px; color: #68636f; font-size: 12px; overflow-wrap: anywhere; }
    .exercise-context:empty { display: none; }
    .table-scroll { overflow-x: auto; margin-top: 12px; }
    .table-scroll:focus-visible { outline: 2px solid #7e6c9e; outline-offset: 3px; }
    table { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }
    th { color: #645d70; font-size: 11px; font-weight: 600; padding: 8px 12px; border-bottom: 1px solid #dedbe5; }
    td { font-size: 14px; padding: 9px 12px; }
    th, td { text-align: right; }
    th:first-child, td:first-child { text-align: left; }
    tbody tr:nth-child(even) { background: #f7f6f9; }
    .breaks { margin-bottom: 28px; background: #edf1eb; border-radius: 12px; padding: 20px 24px; }
    .breaks h2 { font-size: 17px; }
    .breaks ul { list-style: none; padding: 0; margin: 10px 0 0; }
    .breaks li { display: flex; flex-wrap: wrap; gap: 4px 16px; padding: 5px 0; font-size: 13px; }
    .breaks li span { color: #52634e; margin: 0; }
    footer { font-size: 12px; color: #6e6977; padding-top: 12px; }
    .sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); }
    @media (max-width: 600px) { main { padding: 28px 12px; } .workout-header, .exercise { padding: 18px 16px; }
      h2 { font-size: 20px; } th, td { padding: 8px; } }
    @media print { :root { background: white; font-size: 12px; } main { max-width: none; padding: 0; }
      .workout { border-radius: 0; } .exercise { break-inside: avoid; } h2, h3 { break-after: avoid; }
      .workout-header { break-after: avoid; } thead { display: table-header-group; }
      tr { break-inside: avoid; } .table-scroll { overflow: visible; } }
    """
}
