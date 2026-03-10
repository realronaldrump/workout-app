import SwiftUI

struct HomeEmptyState: View {
    let onStart: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.accent.opacity(0.08))
                        .frame(width: 80, height: 80)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(Theme.Iconography.hero)
                        .foregroundColor(Theme.Colors.accent)
                }

                Text("You're Ready.")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .tracking(0.8)

                Text("Start a session or import your history.\nWe'll keep it simple from there.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            VStack(spacing: Theme.Spacing.md) {
                Button(
                    action: {
                        Haptics.selection()
                        onStart()
                    },
                    label: {
                        Text("Start a Session")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.lg)
                            .frame(minHeight: 56)
                            .background(Theme.accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge))
                            .shadow(color: Theme.Colors.accent.opacity(0.25), radius: 12, x: 0, y: 6)
                    }
                )
                .buttonStyle(.plain)

                Button(
                    action: {
                        Haptics.selection()
                        onImport()
                    },
                    label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "arrow.down.to.line")
                                .font(Theme.Typography.footnoteBold)
                            Text("Import from Strong")
                                .font(Theme.Typography.bodyBold)
                        }
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .frame(minHeight: 48)
                        .softCard(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
                    }
                )
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 2)
    }
}

// MARK: - Sync Status Pill

struct SyncStatusPill: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Theme.Colors.success : Theme.Colors.textTertiary.opacity(0.5))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.metricLabel)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(isActive ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Theme.Colors.surfaceRaised)
        )
        .overlay(
            Capsule()
                .strokeBorder(Theme.Colors.border.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync status: \(text)")
    }
}

// MARK: - Compact Change Card (always-visible period-over-period delta)

struct CompactChangeCard: View {
    let metric: ChangeMetric

    private var tint: Color {
        metric.isPositive ? Theme.Colors.success : Theme.Colors.warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 5) {
                Image(systemName: metric.isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(Theme.Typography.microLabel)
                    .foregroundColor(tint)
                Text(metric.title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }

            Text(formatValue(metric))
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)

            if metric.percentChange != 0 {
                Text(String(format: "%+.0f%%", metric.percentChange))
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(tint.opacity(0.1))
                    )
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title): \(formatValue(metric)), \(metric.isPositive ? "increased" : "decreased")")
    }

    private func formatValue(_ metric: ChangeMetric) -> String {
        if metric.title.contains("Sessions") {
            return String(format: "%.0f", metric.current)
        }
        if metric.title.contains("Volume") {
            return SharedFormatters.volumePrecise(metric.current)
        }
        return String(format: "%.1f", metric.current)
    }
}

// MARK: - Home Workout Row (with repeat button)

struct HomeWorkoutRow: View {
    let workout: Workout
    let onRepeat: () -> Void
    let onTap: () -> Void
    @EnvironmentObject var healthManager: HealthKitManager

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button(action: { onTap() }, label: {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(workout.name)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)

                        HStack(spacing: Theme.Spacing.md) {
                            Label(workout.duration, systemImage: "clock")
                            Label("\(workout.exercises.count) exercises", systemImage: "figure.strengthtraining.traditional")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                        if let data = healthManager.getHealthData(for: workout.id) {
                            HealthDataSummaryView(healthData: data)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption2Bold)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            })
            .buttonStyle(PlainButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(workout.name), \(workout.date.formatted(date: .abbreviated, time: .shortened))")
            .accessibilityHint("Double tap for details")

            Button {
                Haptics.selection()
                onRepeat()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(Theme.Typography.caption2Bold)
                    .foregroundColor(Theme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat \(workout.name)")
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

struct HomeWeekBucket: Identifiable {
    let weekStart: Date
    let referenceDate: Date
    let workouts: [Workout]
    let stats: WorkoutStats
    let trackedDayCount: Int
    let excludedDayCount: Int

    var id: Date { weekStart }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private var currentWeekStart: Date {
        SharedFormatters.startOfWeekSunday(for: referenceDate)
    }

    private var weekOffset: Int {
        let days = calendar.dateComponents([.day], from: weekStart, to: currentWeekStart).day ?? 0
        return max(0, days / 7)
    }

    var isCurrentWeek: Bool {
        calendar.isDate(weekStart, inSameDayAs: currentWeekStart)
    }

    var displayEnd: Date {
        let naturalEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return min(naturalEnd, referenceDate)
    }

    var title: String {
        switch weekOffset {
        case 0:
            return "Week View"
        case 1:
            return "Last Week"
        default:
            return "Week of \(weekStart.formatted(Date.FormatStyle().month(.abbreviated).day()))"
        }
    }

    var rangeLabel: String {
        let start = weekStart.formatted(Date.FormatStyle().month(.abbreviated).day())
        let end = displayEnd.formatted(Date.FormatStyle().month(.abbreviated).day())
        return "\(start) - \(end)"
    }

    var sessionsValue: String {
        "\(stats.totalWorkouts)"
    }

    var eligibleDayCount: Int {
        max(trackedDayCount - excludedDayCount, 0)
    }

    var isFullyExcused: Bool {
        eligibleDayCount == 0
    }

    var isSavedBreakWeek: Bool {
        workouts.isEmpty && isFullyExcused
    }

    var volumeValue: String {
        stats.totalWorkouts == 0 ? "--" : SharedFormatters.volumeCompact(stats.totalVolume)
    }

    var sessionHeader: String {
        if isSavedBreakWeek {
            return "Saved Break"
        }
        return isCurrentWeek ? "Sessions So Far" : "Sessions"
    }

    var emptyMessage: String {
        if isSavedBreakWeek {
            return "This week is fully covered by your saved break dates."
        }
        if isCurrentWeek {
            return "No sessions logged yet. Swipe to revisit previous weeks."
        }
        return "No sessions were logged during this week."
    }

    var statusLabel: String {
        if isSavedBreakWeek {
            return "Saved break"
        }
        if stats.totalWorkouts == 0 {
            return isCurrentWeek ? "Open week" : "No sessions"
        }
        return stats.totalWorkouts == 1 ? "1 session" : "\(stats.totalWorkouts) sessions"
    }
}

struct WeeklySummaryCarouselCard: View {
    let bucket: HomeWeekBucket
    let onMetricTap: (WorkoutMetricDetailKind) -> Void
    let onWorkoutTap: (Workout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bucket.rangeLabel)
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(bucket.title)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Text(bucket.statusLabel)
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(bucket.stats.totalWorkouts == 0 ? Theme.Colors.textTertiary : Theme.Colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                (bucket.stats.totalWorkouts == 0 ? Theme.Colors.border : Theme.Colors.accent)
                                    .opacity(0.12)
                            )
                    )
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    SummaryPill(title: "Sessions", value: bucket.sessionsValue, onTap: bucket.workouts.isEmpty ? nil : {
                        onMetricTap(.sessions)
                    })
                    SummaryPill(title: "Volume", value: bucket.volumeValue, onTap: bucket.workouts.isEmpty ? nil : {
                        onMetricTap(.totalVolume)
                    })
                }

                VStack(spacing: Theme.Spacing.sm) {
                    SummaryPill(title: "Sessions", value: bucket.sessionsValue, onTap: bucket.workouts.isEmpty ? nil : {
                        onMetricTap(.sessions)
                    })
                    SummaryPill(title: "Volume", value: bucket.volumeValue, onTap: bucket.workouts.isEmpty ? nil : {
                        onMetricTap(.totalVolume)
                    })
                }
            }

            if bucket.workouts.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(bucket.sessionHeader)
                        .font(Theme.Typography.metricLabel)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Text(bucket.emptyMessage)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .fill(Theme.Colors.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .strokeBorder(Theme.Colors.border.opacity(0.35), lineWidth: 1)
                )
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(bucket.sessionHeader)
                        .font(Theme.Typography.metricLabel)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    ForEach(bucket.workouts.prefix(3)) { workout in
                        WeeklySessionPreviewCard(workout: workout) {
                            onWorkoutTap(workout)
                        }
                    }

                    if bucket.workouts.count > 3 {
                        Text("+\(bucket.workouts.count - 3) more sessions that week")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
            }

        }
        .padding(.vertical, Theme.Spacing.sm)
    }
}

private struct WeeklySessionPreviewCard: View {
    let workout: Workout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(workout.duration)
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text("\(workout.exercises.count) exercises")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption2Bold)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                    .fill(Theme.Colors.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                    .strokeBorder(Theme.Colors.border.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workout.name), \(workout.date.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityHint("Double tap for workout details")
    }
}

// MARK: - Reusable Components

struct SecondaryChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(
            action: {
                Haptics.selection()
                action()
            },
            label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: icon)
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.accent)
                    Text(title)
                        .font(Theme.Typography.captionBold)
                        .textCase(.uppercase)
                        .tracking(0.6)
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .frame(minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .fill(Theme.Colors.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .strokeBorder(Theme.Colors.border.opacity(0.4), lineWidth: 1)
                )
            }
        )
        .buttonStyle(.plain)
    }
}

struct SummaryPill: View {
    let title: String
    let value: String
    var onTap: (() -> Void)?

    var body: some View {
        Group {
            if let onTap {
                MetricTileButton(action: onTap, content: { content })
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)

            Text(value)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(Theme.Colors.border.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }
}

struct ExploreRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(tint.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}
