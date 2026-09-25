import SwiftUI

struct HomeEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            BrandBandLabel(text: "Day one", systemImage: "sparkles")

            Text("Let's build something big.")
                .font(Theme.Typography.displayHeroCompact)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Log your first session and this screen fills in with your week, streaks, recovery signals, and the trends that matter.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.sm) {
                emptyFeature(icon: "calendar", title: "Weekly goal", tint: Theme.Colors.accent)
                emptyFeature(icon: "flame.fill", title: "Streaks", tint: Theme.Colors.accentSecondary)
                emptyFeature(icon: "trophy.fill", title: "PRs", tint: Theme.Colors.gold)
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(elevation: 2)
    }

    private func emptyFeature(icon: String, title: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            IconTile(systemImage: icon, tint: tint, size: 30)
            Text(title)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                .fill(tint.opacity(Theme.Opacity.subtleFill))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Today Hero

/// The one bold surface on Today: weekly goal ring, a 7-day strip, streak, and the
/// primary start/resume action, all on the brand gradient.
struct TodayHeroCard: View {
    let sessionsThisWeek: Int
    let weeklyGoal: Int
    let streakWeeks: Int
    let weekStart: Date
    let trainedDays: Set<Date>
    let activeSession: ActiveWorkoutSession?
    let onPrimaryAction: () -> Void
    let onOpenWeek: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var goal: Int { max(weeklyGoal, 1) }

    private var progress: Double {
        Double(sessionsThisWeek) / Double(goal)
    }

    private var headline: String {
        if sessionsThisWeek == 0 { return "Fresh week" }
        if sessionsThisWeek < goal {
            let remaining = goal - sessionsThisWeek
            return "\(remaining) to go"
        }
        if sessionsThisWeek == goal { return "Goal hit" }
        return "Goal smashed"
    }

    private var message: String {
        if sessionsThisWeek == 0 { return "Get the first one on the board." }
        if sessionsThisWeek < goal {
            return "\(SharedFormatters.count(sessionsThisWeek, "session")) down. Keep the rhythm going."
        }
        if sessionsThisWeek == goal { return "That's a big, beautiful week." }
        return "+\(sessionsThisWeek - goal) past your goal. Nicely done."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Button(action: onOpenWeek) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    topRow
                    ringRow
                    WeekDayStrip(weekStart: weekStart, trainedDays: trainedDays)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(PressableCardButtonStyle())
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint("Opens consistency details")

            primaryButton
        }
        .padding(Theme.Spacing.lg)
        .background(HeroCardBackground(watermark: "figure.strengthtraining.traditional"))
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            BrandBandLabel(text: "This week", fill: .white, textColor: Theme.Colors.onHeroAccent)

            Spacer(minLength: Theme.Spacing.sm)

            if streakWeeks > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .symbolRenderingMode(.multicolor)
                    Text("\(streakWeeks)-week streak")
                        .lineLimit(1)
                }
                .font(Theme.Typography.captionBold)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.22)))
            }
        }
    }

    private var ringRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.lg))

        return layout {
            ZStack {
                ProgressRing(
                    progress: progress,
                    lineWidth: 10,
                    tint: .white,
                    trackTint: Color.white.opacity(0.2)
                )
                VStack(spacing: 0) {
                    Text("\(sessionsThisWeek)")
                        .font(Theme.Typography.ringNumber)
                        .contentTransition(.numericText(value: Double(sessionsThisWeek)))
                        .animation(Theme.Animation.spring, value: sessionsThisWeek)
                    Text("of \(goal)")
                        .font(Theme.Typography.caption2Bold)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .foregroundStyle(.white)
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(headline)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(.white)
                Text(message)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var primaryButton: some View {
        Button(action: onPrimaryAction) {
            HStack(spacing: Theme.Spacing.sm) {
                if let activeSession {
                    LivePulseDot(color: Theme.Colors.success, size: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Resume \(activeSession.name)")
                            .font(Theme.Typography.headline)
                            .lineLimit(1)
                        Text(activeSession.startedAt, style: .timer)
                            .font(Theme.Typography.captionBold)
                            .monospacedDigit()
                            .opacity(0.75)
                    }
                } else {
                    Image(systemName: "bolt.fill")
                        .font(Theme.Typography.title4Bold)
                    Text("Start a Session")
                        .font(Theme.Typography.headline)
                        .lineLimit(2)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: "arrow.right")
                    .font(Theme.Typography.subheadlineBold)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.Colors.onHeroAccent)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                Color.white,
                in: RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityLabel(activeSession.map { "Resume \($0.name)" } ?? "Start a Session")
        .accessibilityHint(activeSession == nil ? "Begins a workout session" : "Returns to the active workout")
    }

    private var accessibilitySummary: String {
        var parts = ["This week, \(sessionsThisWeek) of \(goal) sessions", headline]
        if streakWeeks > 0 {
            parts.append("\(streakWeeks) week streak")
        }
        return parts.joined(separator: ". ")
    }
}

/// Sunday-first strip of the current week. Trained days fill in white.
struct WeekDayStrip: View {
    let weekStart: Date
    let trainedDays: Set<Date>
    var referenceDate = Date()

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let isTrained = trainedDays.contains(dayStart)
        let isToday = calendar.isDate(day, inSameDayAs: referenceDate)
        let isFuture = dayStart > calendar.startOfDay(for: referenceDate)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let symbolIndex = calendar.component(.weekday, from: day) - 1
        let letter = symbols.indices.contains(symbolIndex) ? symbols[symbolIndex] : ""

        return VStack(spacing: 6) {
            Text(letter)
                .font(Theme.Typography.caption2Bold)
                .foregroundStyle(Color.white.opacity(isFuture ? 0.55 : 0.9))

            ZStack {
                Circle()
                    .fill(isTrained ? Color.white : Color.white.opacity(isFuture ? 0.08 : 0.16))
                if isToday && !isTrained {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                }
                if isTrained {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.Colors.onHeroAccent)
                }
            }
            .frame(width: 28, height: 28)
        }
    }
}

// MARK: - Sync Status Pill

struct SyncStatusPill: View {
    let text: String
    let isActive: Bool
    var isSyncing = false

    var body: some View {
        HStack(spacing: 6) {
            if isSyncing {
                LivePulseDot(color: Theme.Colors.accent, size: 6)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(isActive ? Theme.Colors.success : Theme.Colors.textTertiary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            Image(systemName: "heart.fill")
                .font(Theme.Typography.microLabel)
                .foregroundStyle(Theme.Colors.error)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.captionStrong)
                .foregroundStyle(isActive ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: Theme.Layout.minimumTapTarget)
        .contentShape(Capsule())
        .background(
            Capsule()
                .fill(Theme.Colors.surface.opacity(0.85))
        )
        .overlay(
            Capsule()
                .strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 1)
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
        .glassBackground(opacity: 0.1, cornerRadius: Theme.CornerRadius.large, elevation: 1)
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
    let exerciseCount: Int
    let onRepeat: () -> Void
    let onTap: () -> Void
    @EnvironmentObject var healthManager: HealthKitManager

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Button(action: { onTap() }, label: {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    WorkoutDateBadge(date: workout.date)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(workout.name)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: Theme.Spacing.md) {
                            Label(workout.duration, systemImage: "clock")
                            Label(
                                SharedFormatters.count(exerciseCount, "exercise"),
                                systemImage: "dumbbell.fill"
                            )
                        }
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .labelStyle(.titleAndIcon)

                        if let data = healthManager.getHealthData(for: workout.id) {
                            HealthDataSummaryView(healthData: data)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            })
            .buttonStyle(PressableCardButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(workout.name), \(workout.date.formatted(date: .abbreviated, time: .shortened))")
            .accessibilityHint("Double tap for details")

            Button {
                Haptics.selection()
                onRepeat()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundColor(Theme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.Colors.accentTint))
                    .overlay(Circle().strokeBorder(Theme.Colors.accent.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(AppInteractionButtonStyle())
            .accessibilityLabel("Repeat \(workout.name)")
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

/// Compact weekday + day number badge used by workout rows.
struct WorkoutDateBadge: View {
    let date: Date
    var tint: Color = Theme.Colors.accent

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(Theme.Typography.microLabel)
                .tracking(0.6)
            Text(date.formatted(.dateTime.day()))
                .font(Theme.Typography.title3)
                .monospacedDigit()
        }
        .foregroundStyle(isToday ? Color.white : tint)
        .frame(width: 46, height: 46)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                .fill(isToday ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.Colors.accentTint))
        )
        .accessibilityHidden(true)
    }
}

struct HomeWeekBucket: Identifiable {
    let weekStart: Date
    let referenceDate: Date
    let workouts: [Workout]
    let exerciseCounts: [UUID: Int]
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
            return "This Week"
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

    var setsValue: String {
        stats.totalWorkouts == 0 ? "--" : "\(stats.totalSets)"
    }

    var averageDurationValue: String {
        guard !workouts.isEmpty else { return "--" }
        let totalMinutes = workouts.reduce(0) { $0 + $1.estimatedDurationMinutes() }
        return SharedFormatters.durationMinutes(
            Double(totalMinutes) / Double(workouts.count)
        )
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
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(bucket.title)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                if bucket.stats.totalWorkouts > 0 {
                    BrandBandLabel(text: bucket.statusLabel)
                } else {
                    Text(bucket.statusLabel)
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.Colors.border.opacity(0.35)))
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.xs),
                    GridItem(.flexible(), spacing: Theme.Spacing.xs)
                ],
                spacing: Theme.Spacing.xs
            ) {
                SummaryPill(title: "Sessions", value: bucket.sessionsValue, onTap: bucket.workouts.isEmpty ? nil : {
                    onMetricTap(.sessions)
                })
                .accessibilityIdentifier("home-summary-sessions")
                SummaryPill(title: "Volume", value: bucket.volumeValue, onTap: bucket.workouts.isEmpty ? nil : {
                    onMetricTap(.totalVolume)
                })
                .accessibilityIdentifier("home-summary-totalVolume")
                SummaryPill(title: "Sets", value: bucket.setsValue, onTap: bucket.workouts.isEmpty ? nil : {
                    onMetricTap(.totalSets)
                })
                .accessibilityIdentifier("home-summary-totalSets")
                SummaryPill(title: "Avg Duration", value: bucket.averageDurationValue, onTap: bucket.workouts.isEmpty ? nil : {
                    onMetricTap(.averageDuration)
                })
                .accessibilityIdentifier("home-summary-averageDuration")
            }

            if bucket.workouts.isEmpty {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Image(systemName: bucket.isSavedBreakWeek ? "beach.umbrella.fill" : "calendar.badge.plus")
                        .font(Theme.Iconography.title3)
                        .foregroundStyle(bucket.isSavedBreakWeek ? Theme.Colors.accentTertiary : Theme.Colors.accent)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(bucket.sessionHeader)
                            .sectionHeaderStyle()
                        Text(bucket.emptyMessage)
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                        .strokeBorder(
                            Theme.Colors.border,
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(bucket.sessionHeader)
                        .font(Theme.Typography.metricLabel)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    ForEach(bucket.workouts.prefix(3)) { workout in
                        WeeklySessionPreviewCard(
                            workout: workout,
                            exerciseCount: bucket.exerciseCounts[workout.id] ?? workout.exercises.count
                        ) {
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
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }
}

private struct WeeklySessionPreviewCard: View {
    let workout: Workout
    let exerciseCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                WorkoutDateBadge(date: workout.date)

                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(workout.date.formatted(date: .omitted, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(workout.duration)
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text(SharedFormatters.count(exerciseCount, "exercise"))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption2Bold)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(elevation: 1)
        }
        .buttonStyle(PressableCardButtonStyle())
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
                HStack(spacing: Theme.Spacing.md) {
                    IconTile(systemImage: icon, tint: Theme.Colors.accent, size: 32)
                    Text(title)
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer(minLength: Theme.Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption2Bold)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: 56)
                .softCard(elevation: 1)
            }
        )
        .buttonStyle(PressableCardButtonStyle())
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
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(value)
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                .fill(Theme.Colors.surfaceRaised)
        )
        .overlay(alignment: .leading) {
            // Accent tick keeps the four tiles reading as one family.
            Capsule()
                .fill(Theme.Colors.accent.opacity(onTap == nil ? 0.25 : 0.8))
                .frame(width: 3)
                .padding(.vertical, Theme.Spacing.md)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                .strokeBorder(Theme.Colors.border.opacity(0.35), lineWidth: 1)
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
            HStack(alignment: .top) {
                IconTile(systemImage: icon, tint: tint, size: 40)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(Theme.Typography.caption2Bold)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.cardHeader)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(
            // A faint wash of the tile's color so the grid reads as distinct destinations.
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.10), tint.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}
