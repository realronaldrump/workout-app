import SwiftUI

/// Expandable list of longest streak runs (workout-day runs allowing a configurable rest window).
struct LongestStreaksSection: View {
    let workouts: [Workout]
    var collapsedCount: Int = 3
    var maxExpandedCount: Int = 12
    var title: String = "Longest Streaks"

    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            if runs.isEmpty {
                Text("No streaks yet")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(displayRuns.enumerated()), id: \.element.id) { index, run in
                        LongestStreakRow(
                            rank: index + 1,
                            run: run,
                            dateLabel: dateLabel(for: run)
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        let canExpand = runs.count > collapsedCount

        return HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.cardHeader)
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            if canExpand {
                Button {
                    withAnimation(Theme.Animation.spring) {
                        isExpanded.toggle()
                    }
                    Haptics.selection()
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(isExpanded ? "Less" : "More")
                            .font(Theme.Typography.metricLabel)
                            .foregroundColor(Theme.Colors.accent)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundColor(Theme.Colors.accent)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var runs: [StreakRun] {
        WorkoutAnalytics
            .streakRuns(for: workouts, intentionalRestDays: intentionalRestDays)
            .sorted {
                if $0.workoutDayCount != $1.workoutDayCount {
                    return $0.workoutDayCount > $1.workoutDayCount
                }
                return $0.end > $1.end
            }
    }

    private var displayRuns: [StreakRun] {
        guard runs.count > collapsedCount else { return runs }
        if isExpanded {
            return Array(runs.prefix(maxExpandedCount))
        }
        return Array(runs.prefix(collapsedCount))
    }

    private func dateLabel(for run: StreakRun) -> String {
        let calendar = Calendar.current
        let start = run.start
        let end = run.end

        if calendar.isDate(start, equalTo: end, toGranularity: .day) {
            return start.formatted(date: .abbreviated, time: .omitted)
        }

        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)

        if startYear == endYear {
            let startStr = start.formatted(Date.FormatStyle().month(.abbreviated).day())
            let endStr = end.formatted(Date.FormatStyle().month(.abbreviated).day().year())
            return "\(startStr) - \(endStr)"
        }

        let startStr = start.formatted(Date.FormatStyle().month(.abbreviated).day().year())
        let endStr = end.formatted(Date.FormatStyle().month(.abbreviated).day().year())
        return "\(startStr) - \(endStr)"
    }
}

private struct LongestStreakRow: View {
    let rank: Int
    let run: StreakRun
    let dateLabel: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("\(rank)")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textTertiary)
                .monospacedDigit()
                .frame(width: 18, alignment: .leading)

            Text("\(run.workoutDayCount) day\(run.workoutDayCount == 1 ? "" : "s")")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textPrimary)
                .monospacedDigit()

            Spacer()

            Text(dateLabel)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surface.opacity(0.55))
        )
    }
}

/// Non-interactive compact preview (safe inside full-card buttons like `MetricTileButton`).
struct LongestStreaksPreview: View {
    let workouts: [Workout]
    var maxCount: Int = 2

    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1

    var body: some View {
        let runs = WorkoutAnalytics
            .streakRuns(for: workouts, intentionalRestDays: intentionalRestDays)
            .sorted {
                if $0.workoutDayCount != $1.workoutDayCount {
                    return $0.workoutDayCount > $1.workoutDayCount
                }
                return $0.end > $1.end
            }

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Top Streaks")
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            if runs.isEmpty {
                Text("No streaks yet")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(runs.prefix(maxCount).enumerated()), id: \.element.id) { index, run in
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("#\(index + 1)")
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .monospacedDigit()

                            Text("\(run.workoutDayCount)d")
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .monospacedDigit()

                            Spacer()

                            Text(shortDateLabel(for: run))
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func shortDateLabel(for run: StreakRun) -> String {
        let calendar = Calendar.current
        if calendar.isDate(run.start, equalTo: run.end, toGranularity: .day) {
            return run.start.formatted(Date.FormatStyle().month(.abbreviated).day())
        }
        let startStr = run.start.formatted(Date.FormatStyle().month(.abbreviated).day())
        let endStr = run.end.formatted(Date.FormatStyle().month(.abbreviated).day())
        return "\(startStr) - \(endStr)"
    }
}
