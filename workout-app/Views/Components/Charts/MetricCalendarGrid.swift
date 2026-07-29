import SwiftUI

/// A week-by-week intensity grid for a single metric.
///
/// The timeline chart answers "how much"; this answers "when, and did I miss any".
/// Empty cells are drawn as empty rather than skipped, which makes sync gaps
/// obvious instead of silently dragging the averages down.
struct MetricCalendarGrid: View {

    let metric: HealthMetric
    let analysis: MetricSeriesAnalysis
    var maxWeeks: Int = 26

    private var calendar: Calendar { .current }

    private struct Cell: Identifiable {
        let date: Date
        let value: Double?
        let isToday: Bool
        let isFuture: Bool
        var id: Date { date }
    }

    private struct Week: Identifiable {
        let start: Date
        let cells: [Cell]
        var id: Date { start }
    }

    var body: some View {
        let weeks = buildWeeks()

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            if weeks.isEmpty {
                Text("Not enough history yet.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else {
                // Cells grow to fill the card rather than huddling in the top-left
                // corner when the range is only a handful of weeks.
                ViewThatFits(in: .horizontal) {
                    grid(weeks: weeks, side: sideLength(for: weeks.count, available: 320))
                    grid(weeks: weeks, side: sideLength(for: weeks.count, available: 260))
                    grid(weeks: weeks, side: 10)
                }

                legend
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Day Grid")
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(coverageSentence)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var coverageSentence: String {
        let recorded = analysis.samples.count
        let total = analysis.calendarDayCount
        guard total > 0 else { return "Every recorded \(metric.dailyNoun), shaded by size." }
        let missing = max(0, total - recorded)
        if missing == 0 {
            return "Every one of the last \(total) days has a reading."
        }
        return "\(recorded) of \(total) days recorded — \(missing) with no data."
    }

    private func sideLength(for weekCount: Int, available: CGFloat) -> CGFloat {
        let spacing = Self.cellSpacing
        let usable = available - Self.labelWidth - spacing * CGFloat(max(weekCount - 1, 0))
        return min(30, max(9, usable / CGFloat(max(weekCount, 1))))
    }

    private func grid(weeks: [Week], side: CGFloat) -> some View {
        HStack(alignment: .top, spacing: Self.cellSpacing) {
            VStack(spacing: Self.cellSpacing) {
                ForEach(weekdayLabels, id: \.offset) { entry in
                    Text(entry.element)
                        .font(Theme.Typography.microLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(width: Self.labelWidth, height: side, alignment: .trailing)
                }
            }

            ForEach(weeks) { week in
                VStack(spacing: Self.cellSpacing) {
                    ForEach(week.cells) { cell in
                        cellView(cell, side: side)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Row labels follow the locale's first weekday so they line up with the cells.
    private var weekdayLabels: [(offset: Int, element: String)] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday
        return (0..<7).map { offset in
            let index = (first - 1 + offset) % 7
            return (offset, symbols.indices.contains(index) ? symbols[index] : "")
        }
    }

    private static let cellSpacing: CGFloat = 3
    private static let labelWidth: CGFloat = 16

    private var legend: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Lower")
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.Colors.textTertiary)

            HStack(spacing: 3) {
                ForEach([0.18, 0.38, 0.62, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(metric.accentColor.opacity(level))
                        .frame(width: 12, height: 12)
                }
            }

            Text("Higher")
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.Colors.textTertiary)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
                    .frame(width: 12, height: 12)
                Text("No data")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private func cellView(_ cell: Cell, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: max(2, side * 0.24), style: .continuous)
            .fill(fill(for: cell))
            .frame(width: side, height: side)
            .overlay {
                if cell.value == nil && !cell.isFuture {
                    RoundedRectangle(cornerRadius: max(2, side * 0.24), style: .continuous)
                        .strokeBorder(Theme.Colors.border.opacity(0.7), lineWidth: 1)
                }
                if cell.isToday {
                    RoundedRectangle(cornerRadius: max(2, side * 0.24), style: .continuous)
                        .strokeBorder(Theme.Colors.textPrimary.opacity(0.75), lineWidth: 1.5)
                }
            }
            .accessibilityLabel(cell.date.formatted(date: .abbreviated, time: .omitted))
            .accessibilityValue(cell.value.map { metric.formatWithUnit($0) } ?? "No data")
    }

    private func fill(for cell: Cell) -> Color {
        guard let value = cell.value else {
            return cell.isFuture ? .clear : Theme.Colors.textPrimary.opacity(0.03)
        }

        let level: Double
        if let p25 = analysis.percentile25, let median = analysis.median, let p75 = analysis.percentile75 {
            switch value {
            case ..<p25: level = 0.18
            case ..<median: level = 0.38
            case ..<p75: level = 0.62
            default: level = 1.0
            }
        } else {
            level = 0.62
        }

        return metric.accentColor.opacity(level)
    }

    private func buildWeeks() -> [Week] {
        guard !analysis.samples.isEmpty else { return [] }

        var lookup: [Date: Double] = [:]
        for sample in analysis.samples {
            lookup[calendar.startOfDay(for: sample.date)] = sample.value
        }

        let today = calendar.startOfDay(for: Date())
        let lastSampleDay = calendar.startOfDay(for: analysis.samples[analysis.samples.count - 1].date)
        let anchor = max(today, lastSampleDay)

        guard let lastWeek = calendar.dateInterval(of: .weekOfYear, for: anchor) else { return [] }
        let firstSampleDay = calendar.startOfDay(for: analysis.samples[0].date)
        guard let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstSampleDay) else { return [] }

        let totalWeeks = (calendar.dateComponents([.weekOfYear], from: firstWeek.start, to: lastWeek.start).weekOfYear ?? 0) + 1
        let weekCount = min(max(totalWeeks, 1), maxWeeks)

        guard let windowStart = calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: lastWeek.start) else {
            return []
        }

        var weeks: [Week] = []
        weeks.reserveCapacity(weekCount)

        for weekIndex in 0..<weekCount {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekIndex, to: windowStart) else { continue }
            var cells: [Cell] = []
            cells.reserveCapacity(7)

            for dayIndex in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: dayIndex, to: weekStart) else { continue }
                let dayStart = calendar.startOfDay(for: day)
                cells.append(
                    Cell(
                        date: dayStart,
                        value: lookup[dayStart],
                        isToday: calendar.isDate(dayStart, inSameDayAs: today),
                        isFuture: dayStart > today
                    )
                )
            }

            weeks.append(Week(start: weekStart, cells: cells))
        }

        return weeks
    }
}
