import SwiftUI

/// Non-interactive compact preview (safe inside full-card buttons like `MetricTileButton`).
struct LongestStreaksPreview: View {
    let workouts: [Workout]
    var maxCount: Int = 2

    @EnvironmentObject private var intentionalBreaksManager: IntentionalBreaksManager
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1

    var body: some View {
        let runs = WorkoutAnalytics
            .streakRuns(
                for: workouts,
                intentionalRestDays: intentionalRestDays,
                intentionalBreakRanges: intentionalBreaksManager.savedBreaks
            )
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

                            Text("\(run.workoutDayCount)d")
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(Theme.Colors.textPrimary)

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
