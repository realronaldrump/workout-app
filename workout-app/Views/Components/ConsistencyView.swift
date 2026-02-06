import SwiftUI

struct ConsistencyView: View {
    let stats: WorkoutStats
    let workouts: [Workout]
    var timeRange: TimeRangeOption = .month
    var onTap: (() -> Void)? = nil

    enum TimeRangeOption {
        case week, month, threeMonths, year, allTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Consistency")
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            Group {
                if let onTap {
                    MetricTileButton(action: onTap) {
                        cardContent
                    }
                } else {
                    cardContent
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var targetSessionsPerWeek: Double { 4.0 }

    private var weeksInRange: Int {
        switch timeRange {
        case .week: return 1
        case .month: return 4
        case .threeMonths: return 13
        case .year: return 52
        case .allTime:
            guard let oldest = workouts.map({ $0.date }).min() else { return 4 }
            let weeks = Calendar.current.dateComponents([.weekOfYear], from: oldest, to: Date()).weekOfYear ?? 4
            return max(weeks, 1)
        }
    }

    private var targetSessions: Int {
        Int(ceil(Double(weeksInRange) * targetSessionsPerWeek))
    }

    private var sessionCount: Int {
        workouts.count
    }

    private var progress: Double {
        guard targetSessions > 0 else { return 0 }
        return min(Double(sessionCount) / Double(targetSessions), 1.0)
    }

    private var daysInRange: Int {
        switch timeRange {
        case .week: return 7
        case .month: return 28
        case .threeMonths: return 91
        case .year: return 365
        case .allTime: return min(weeksInRange * 7, 365)
        }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(alignment: .center, spacing: Theme.Spacing.xl) {
                // Activity Ring
                ActivityRing(progress: progress, sessionCount: sessionCount, targetSessions: targetSessions)
                    .frame(width: 100, height: 100)

                // Stats Column
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    StatRow(label: "Sessions/Wk", value: String(format: "%.1f", stats.workoutsPerWeek))
                    StatRow(label: "Current", value: "\(stats.currentStreak) days", highlight: stats.currentStreak > 0)
                    StatRow(label: "Longest", value: "\(stats.longestStreak) days")
                }

                Spacer()
            }

            // Streak Bar
            StreakBar(workouts: workouts, daysToShow: daysInRange)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}

// MARK: - Activity Ring

private struct ActivityRing: View {
    let progress: Double
    let sessionCount: Int
    let targetSessions: Int

    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Theme.Colors.surface, lineWidth: 10)

            // Progress arc — flat solid stroke, squared ends
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    Theme.Colors.success,
                    style: StrokeStyle(lineWidth: 10, lineCap: .butt)
                )
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: 2) {
                Text("\(Int(animatedProgress * 100))%")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("\(sessionCount)/\(targetSessions)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .onAppear {
            withAnimation(Theme.Animation.spring.delay(0.2)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(Theme.Animation.spring) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Stat Row

private struct StatRow: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
            Spacer()
            Text(value)
                .font(Theme.Typography.subheadline)
                .foregroundColor(highlight ? Theme.Colors.success : Theme.Colors.textPrimary)
        }
    }
}

// MARK: - Streak Bar

private struct StreakBar: View {
    let workouts: [Workout]
    let daysToShow: Int

    private var workoutDays: Set<Date> {
        let calendar = Calendar.current
        return Set(workouts.map { calendar.startOfDay(for: $0.date) })
    }

    private var dates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let count = min(daysToShow, 28) // Cap at 4 weeks for visual clarity
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: -($0), to: today) }.reversed()
    }

    private var weekGroupedDates: [[Date]] {
        let calendar = Calendar.current
        var weeks: [[Date]] = []
        var currentWeek: [Date] = []
        var lastWeekOfYear: Int?

        for date in dates {
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            if let last = lastWeekOfYear, last != weekOfYear {
                if !currentWeek.isEmpty {
                    weeks.append(currentWeek)
                    currentWeek = []
                }
            }
            currentWeek.append(date)
            lastWeekOfYear = weekOfYear
        }
        if !currentWeek.isEmpty {
            weeks.append(currentWeek)
        }
        return weeks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Day labels
            HStack(spacing: 0) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Week rows
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(weekGroupedDates.indices, id: \.self) { weekIndex in
                        WeekColumn(dates: weekGroupedDates[weekIndex], workoutDays: workoutDays)
                    }
                }
            }
        }
    }
}

private struct WeekColumn: View {
    let dates: [Date]
    let workoutDays: Set<Date>

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 4) {
            ForEach(dates, id: \.self) { date in
                let isWorkout = workoutDays.contains(calendar.startOfDay(for: date))
                let isToday = calendar.isDateInToday(date)
                RoundedRectangle(cornerRadius: 2)
                    .fill(isWorkout ? Theme.Colors.success : Theme.Colors.surface.opacity(0.5))
                    .frame(width: 14, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(isToday ? Theme.Colors.accent : Color.clear, lineWidth: 2)
                    )
            }
        }
    }
}

// MARK: - Calendar Heatmap (for MetricDetailView compatibility)

struct CalendarHeatmap: View {
    let workouts: [Workout]

    private let rows = Array(repeating: GridItem(.fixed(12), spacing: 4), count: 7)
    private let weeks = 16

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Day Labels
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    if index % 2 == 1 { // Mon, Wed, Fri
                        Text(dayLabel(for: index))
                            .font(.caption2)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(height: 12)
                    } else {
                        Spacer().frame(height: 12)
                    }
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
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        return symbols[index]
    }

    private func generateDateGrid() -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        let today = Date()

        let weekday = calendar.component(.weekday, from: today)
        let daysToSaturday = 7 - weekday

        guard let endOfWeek = calendar.date(byAdding: .day, value: daysToSaturday, to: today) else { return [] }

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
