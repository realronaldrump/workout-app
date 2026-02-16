import SwiftUI

struct ConsistencyView: View {
    let stats: WorkoutStats
    let workouts: [Workout]
    var streakWorkouts: [Workout]?
    var timeRange: TimeRangeOption = .month
    var dateRange: DateInterval?
    var onTap: (() -> Void)?
    @AppStorage("sessionsPerWeekGoal") private var sessionsPerWeekGoal: Int = 4

    enum TimeRangeOption {
        case week, month, threeMonths, year, allTime
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private var targetSessionsPerWeek: Int {
        min(max(sessionsPerWeekGoal, 1), 14)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Consistency")
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            Group {
                if let onTap {
                    MetricTileButton(action: onTap, content: { cardContent })
                } else {
                    cardContent
                }
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(summaryText)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Each bar is one week. Orange marker shows your \(targetSessionsPerWeek)-session target.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                spacing: Theme.Spacing.sm
            ) {
                ConsistencyMetricPill(
                    label: "Avg Sessions/Wk",
                    value: String(format: "%.1f", stats.workoutsPerWeek)
                )
                ConsistencyMetricPill(
                    label: "This Week",
                    value: "\(thisWeekSessions)/\(targetSessionsPerWeek)"
                )
                ConsistencyMetricPill(
                    label: "Current Streak",
                    value: "\(stats.currentStreak)d",
                    highlight: stats.currentStreak > 0
                )
                ConsistencyMetricPill(
                    label: "Longest Streak",
                    value: "\(stats.longestStreak)d"
                )
            }

            WeeklyConsistencyGraph(
                buckets: displayedWeeklyBuckets,
                targetSessionsPerWeek: targetSessionsPerWeek,
                maxSessions: maxSessionsInDisplay
            )

            HStack(spacing: Theme.Spacing.md) {
                ConsistencyLegendItem(color: Theme.Colors.success, label: "Goal hit")
                ConsistencyLegendItem(color: Theme.Colors.accent.opacity(0.6), label: "Below goal")

                Spacer()

                if didTruncateWeeks {
                    Text("Showing last \(displayedWeeklyBuckets.count) weeks")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            // Non-interactive preview (safe inside the full-card tap target).
            LongestStreaksPreview(workouts: streakWorkouts ?? workouts, maxCount: 2)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var summaryText: String {
        guard !weeklyBuckets.isEmpty else {
            return "No sessions yet in this range."
        }
        return "\(weeksAtGoal) of \(weeklyBuckets.count) weeks hit your \(targetSessionsPerWeek)-session goal"
    }

    private var thisWeekSessions: Int {
        weeklyBuckets.last?.sessions ?? 0
    }

    private var weeksAtGoal: Int {
        weeklyBuckets.filter { $0.sessions >= targetSessionsPerWeek }.count
    }

    private var maxSessionsInDisplay: Int {
        max(targetSessionsPerWeek, displayedWeeklyBuckets.map(\.sessions).max() ?? targetSessionsPerWeek)
    }

    private var maxWeeksToDisplay: Int {
        switch timeRange {
        case .allTime:
            return 52
        default:
            return Int.max
        }
    }

    private var displayedWeeklyBuckets: [WeeklyConsistencyBucket] {
        guard weeklyBuckets.count > maxWeeksToDisplay else { return weeklyBuckets }
        return Array(weeklyBuckets.suffix(maxWeeksToDisplay))
    }

    private var didTruncateWeeks: Bool {
        displayedWeeklyBuckets.count < weeklyBuckets.count
    }

    private var weeklyBuckets: [WeeklyConsistencyBucket] {
        let bounds = normalizedRangeBounds
        let firstWeekStart = startOfWeek(for: bounds.start)
        let lastWeekStart = startOfWeek(for: bounds.end)

        let sessionsByWeek = workouts.reduce(into: [Date: Int]()) { counts, workout in
            let day = calendar.startOfDay(for: workout.date)
            guard day >= bounds.start && day <= bounds.end else { return }
            counts[startOfWeek(for: day), default: 0] += 1
        }

        var buckets: [WeeklyConsistencyBucket] = []
        var cursor = firstWeekStart
        while cursor <= lastWeekStart {
            let weekEnd = min(calendar.date(byAdding: .day, value: 6, to: cursor) ?? cursor, bounds.end)
            buckets.append(
                WeeklyConsistencyBucket(
                    weekStart: cursor,
                    weekEnd: weekEnd,
                    sessions: sessionsByWeek[cursor, default: 0]
                )
            )

            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }

        return buckets
    }

    private var resolvedDateRange: DateInterval {
        if let dateRange {
            return dateRange
        }

        let now = Date()
        switch timeRange {
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .month:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .threeMonths:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return DateInterval(start: start, end: now)
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return DateInterval(start: start, end: now)
        case .allTime:
            let oldest = workouts.map(\.date).min() ?? now
            return DateInterval(start: oldest, end: now)
        }
    }

    private var normalizedRangeBounds: (start: Date, end: Date) {
        let start = calendar.startOfDay(for: resolvedDateRange.start)
        let end = calendar.startOfDay(for: resolvedDateRange.end)
        if end < start {
            return (start: start, end: start)
        }
        return (start: start, end: end)
    }

    private func startOfWeek(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}

private struct WeeklyConsistencyBucket: Identifiable {
    let weekStart: Date
    let weekEnd: Date
    let sessions: Int

    var id: Date { weekStart }
}

private struct ConsistencyMetricPill: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            Text(value)
                .font(Theme.Typography.subheadline)
                .foregroundColor(highlight ? Theme.Colors.success : Theme.Colors.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(Theme.Colors.border.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct WeeklyConsistencyGraph: View {
    let buckets: [WeeklyConsistencyBucket]
    let targetSessionsPerWeek: Int
    let maxSessions: Int

    private let barHeight: CGFloat = 108

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Weekly Sessions")
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Spacer()

                Text("Goal \(targetSessionsPerWeek)/wk")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .monospacedDigit()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        WeeklyConsistencyBar(
                            bucket: bucket,
                            targetSessionsPerWeek: targetSessionsPerWeek,
                            maxSessions: maxSessions,
                            barHeight: barHeight,
                            label: weekLabel(for: bucket.weekStart),
                            showLabel: shouldShowLabel(index: index)
                        )
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    private var labelStep: Int {
        let count = buckets.count
        if count <= 8 { return 1 }
        if count <= 16 { return 2 }
        if count <= 32 { return 4 }
        return 8
    }

    private func shouldShowLabel(index: Int) -> Bool {
        index == 0 || index == buckets.count - 1 || index % labelStep == 0
    }

    private func weekLabel(for date: Date) -> String {
        if buckets.count <= 10 {
            return date.formatted(Date.FormatStyle().month(.abbreviated).day())
        }
        return date.formatted(Date.FormatStyle().month(.abbreviated))
    }
}

private struct WeeklyConsistencyBar: View {
    let bucket: WeeklyConsistencyBucket
    let targetSessionsPerWeek: Int
    let maxSessions: Int
    let barHeight: CGFloat
    let label: String
    let showLabel: Bool

    private var normalizedMax: CGFloat {
        CGFloat(max(maxSessions, 1))
    }

    private var fillHeight: CGFloat {
        guard bucket.sessions > 0 else { return 0 }
        return max(2, (CGFloat(bucket.sessions) / normalizedMax) * barHeight)
    }

    private var targetOffset: CGFloat {
        min(barHeight, (CGFloat(targetSessionsPerWeek) / normalizedMax) * barHeight)
    }

    private var barColor: Color {
        bucket.sessions >= targetSessionsPerWeek ? Theme.Colors.success : Theme.Colors.accent.opacity(0.6)
    }

    private var sessionTextColor: Color {
        bucket.sessions >= targetSessionsPerWeek ? Theme.Colors.success : Theme.Colors.textPrimary
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .fill(Theme.Colors.surface.opacity(0.55))
                    .frame(width: 18, height: barHeight)

                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .fill(barColor)
                    .frame(width: 18, height: fillHeight)

                Rectangle()
                    .fill(Theme.Colors.accentSecondary)
                    .frame(width: 24, height: 1)
                    .offset(y: -(targetOffset - 0.5))
            }

            Text("\(bucket.sessions)")
                .font(Theme.Typography.captionBold)
                .foregroundColor(sessionTextColor)
                .monospacedDigit()

            if showLabel {
                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .frame(height: 14)
            } else {
                Color.clear
                    .frame(height: 14)
            }
        }
        .frame(width: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let start = bucket.weekStart.formatted(Date.FormatStyle().month(.abbreviated).day())
        let end = bucket.weekEnd.formatted(Date.FormatStyle().month(.abbreviated).day().year())
        let count = bucket.sessions
        return "\(start) to \(end): \(count) session\(count == 1 ? "" : "s")"
    }
}

private struct ConsistencyLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }
}

// MARK: - Calendar Heatmap (for MetricDetailView compatibility)

struct CalendarHeatmap: View {
    let workouts: [Workout]
    var anchorDate: Date?

    private let rows = Array(repeating: GridItem(.fixed(12), spacing: 4), count: 7)
    private let weeks = 16

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Day Labels
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(dayLabel(for: index))
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(height: 12)
                }
            }
            .padding(.top, 0)

            // Heatmap Grid
            let dates = generateDateGrid()
            LazyHGrid(rows: rows, spacing: 4) {
                ForEach(dates, id: \.self) { date in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForDate(date))
                        .frame(width: 12, height: 12)
                }
            }
        }
        .frame(height: 120) // Fixed height for the horizontal container

        // Legend
        HStack(spacing: 8) {
            Text("0")
                .font(.caption2)
                .foregroundColor(Theme.Colors.textTertiary)

            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.success.opacity(intensity))
                    .frame(width: 12, height: 12)
            }

            Text(formatVolume(maxVolume))
                .font(.caption2)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.top, 8)
    }

    private func dayLabel(for index: Int) -> String {
        let symbols = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        return symbols[index]
    }

    private func generateDateGrid() -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        let referenceDate = anchorDate ?? Date()

        let weekday = calendar.component(.weekday, from: referenceDate)
        let daysToSaturday = 7 - weekday

        guard let endOfWeek = calendar.date(byAdding: .day, value: daysToSaturday, to: referenceDate) else { return [] }

        let totalDays = weeks * 7

        for i in 0..<totalDays {
            let daysBack = (totalDays - 1) - i
            if let date = calendar.date(byAdding: .day, value: -daysBack, to: endOfWeek) {
                dates.append(date)
            }
        }

        return dates
    }

    private func colorForDate(_ date: Date) -> Color {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let volume = dailyVolume[day, default: 0]
        guard volume > 0, maxVolume > 0 else {
            return Theme.Colors.surface.opacity(0.3)
        }
        let intensity = min(max(volume / maxVolume, 0.1), 1)
        return Theme.Colors.success.opacity(0.15 + intensity * 0.85)
    }

    private var dailyVolume: [Date: Double] {
        let calendar = Calendar.current
        return workouts.reduce(into: [Date: Double]()) { totals, workout in
            let day = calendar.startOfDay(for: workout.date)
            totals[day, default: 0] += workout.totalVolume
        }
    }

    private var maxVolume: Double {
        dailyVolume.values.max() ?? 0
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000000 {
            return String(format: "%.1fM", volume / 1000000)
        } else if volume >= 1000 {
            return String(format: "%.0fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }
}
