import SwiftUI

// MARK: - Empty State

/// First run: an empty bar waiting for its first plate.
struct HomeEmptyState: View {
    var weeklyGoal: Int = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Day one.")
                    .font(Theme.Typography.displayHero)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Every session you log loads a plate on this week's bar. Start a workout, or bring in your history from Strong.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BarbellLoadView(plates: [], goal: weeklyGoal, showsDayLabels: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stands in for the hero while saved history loads: the empty bar, no numbers yet,
/// so the week never shows a partial count and then jumps.
struct TodayLoadingHero: View {
    var weeklyGoal: Int = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SkeletonRect(width: 132, height: 96, cornerRadius: Theme.CornerRadius.medium)
                Text("Loading your training history.")
                    .font(Theme.Typography.title4)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            BarbellLoadView(plates: [], goal: weeklyGoal, showsDayLabels: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading workouts")
    }
}

// MARK: - Today Hero

/// The one bold moment on Today: the week's count at poster scale over a barbell
/// loaded with this week's sessions, then the actions that load the next plate.
struct TodayHero: View {
    let sessionsThisWeek: Int
    let weeklyGoal: Int
    let streakWeeks: Int
    let plates: [LoadedPlate]
    let activeSession: ActiveWorkoutSession?
    let lastWorkout: Workout?
    let onPrimaryAction: () -> Void
    let onRepeatLast: (Workout) -> Void
    let onOpenWeek: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var goal: Int { max(weeklyGoal, 1) }

    private var statusLine: String {
        let remaining = goal - sessionsThisWeek
        if sessionsThisWeek == 0 { return "sessions this week. The bar is empty." }
        if remaining > 0 { return "sessions this week. \(Self.spelled(remaining).capitalizedFirst) to go." }
        if remaining == 0 { return "sessions this week. Goal hit." }
        return "sessions this week. \(Self.spelled(-remaining).capitalizedFirst) past your goal."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpenWeek) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(sessionsThisWeek)")
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .contentTransition(.numericText(value: Double(sessionsThisWeek)))
                            .animation(reduceMotion ? nil : Theme.Animation.spring, value: sessionsThisWeek)
                        Text("/\(goal)")
                            .foregroundStyle(Theme.Colors.decorativeSubtle)
                    }
                    .font(Theme.Typography.posterNumber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                    Text(statusLine)
                        .font(Theme.Typography.bodyLarge)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    BarbellLoadView(plates: plates, goal: goal)
                        .padding(.top, Theme.Spacing.lg)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(PressableCardButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(sessionsThisWeek) of \(goal) \(statusLine)")
            .accessibilityHint("Opens consistency details")

            streakLine
                .padding(.top, Theme.Spacing.lg)

            primaryButton
                .padding(.top, Theme.Spacing.xl)

            if activeSession == nil, let lastWorkout {
                repeatButton(lastWorkout)
                    .padding(.top, Theme.Spacing.sm)
            }
        }
    }

    @ViewBuilder
    private var streakLine: some View {
        if streakWeeks > 0 {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text("\(streakWeeks)")
                    .font(Theme.Typography.sectionHeader2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(streakWeeks == 1 ? "week with a workout" : "weeks in a row with a workout")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Log a workout this week to start a streak.")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var primaryButton: some View {
        Button(action: onPrimaryAction) {
            HStack(spacing: Theme.Spacing.sm) {
                if let activeSession {
                    LivePulseDot(color: Theme.Colors.success, size: 7)
                    Text("Resume \(activeSession.name)")
                        .lineLimit(1)
                    Spacer(minLength: Theme.Spacing.sm)
                    Text(activeSession.startedAt, style: .timer)
                        .monospacedDigit()
                        .opacity(0.7)
                } else {
                    Text("Start workout")
                }
            }
            .font(Theme.Typography.title4Bold)
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.primaryControlHeight)
        }
        .buttonStyle(BrandPrimaryButtonStyle())
        .accessibilityLabel(activeSession.map { "Resume \($0.name)" } ?? "Start workout")
        .accessibilityHint(activeSession == nil ? "Begins a workout session" : "Returns to the active workout")
    }

    private func repeatButton(_ workout: Workout) -> some View {
        let parts = SharedFormatters.workoutTitleParts(workout.name)
        return Button {
            Haptics.selection()
            onRepeatLast(workout)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "arrow.counterclockwise")
                    .font(Theme.Typography.captionBold)
                    .accessibilityHidden(true)
                Text("Repeat \(parts.title)")
                    .font(Theme.Typography.headline)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                Text(workout.date.formatted(.relative(presentation: .named)))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(BrandSecondaryButtonStyle())
        .accessibilityLabel("Repeat last workout: \(workout.name)")
        .accessibilityHint("Starts this workout again")
    }

    private static func spelled(_ value: Int) -> String {
        guard value <= 10 else { return "\(value)" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

// MARK: - Week Rack

/// One week on the rack: its sessions as plates, oldest week first.
struct RackWeek: Identifiable, Hashable {
    let weekStart: Date
    let plates: [LoadedPlate]
    let isBreak: Bool

    var id: Date { weekStart }
}

/// Every recent week as a short stack of plates against the weekly goal line.
/// The selected week shows its sessions in plate colors; tap a week to select it.
struct WeekRackChart: View {
    let weeks: [RackWeek]
    let goal: Int
    let selectedWeekStart: Date?
    let onSelect: (Date) -> Void

    private let plateHeight: CGFloat = 7
    private let plateGap: CGFloat = 2
    private let columnWidth: CGFloat = 20
    private let columnGap: CGFloat = 8

    private var levels: Int {
        // Keep at least four levels so every column clears the minimum tap height.
        max(goal, weeks.map(\.plates.count).max() ?? 0, 4)
    }

    private var stackHeight: CGFloat {
        CGFloat(levels) * (plateHeight + plateGap)
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: columnGap) {
                ForEach(weeks) { week in
                    column(week)
                        .id(week.weekStart)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(alignment: .top) {
                // Sits in the gap just above the plate that meets the goal.
                goalLine
                    .padding(.top, Theme.Spacing.md + stackHeight - CGFloat(goal) * (plateHeight + plateGap) + plateGap / 2 - 0.5)
            }
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.trailing)
    }

    private var goalLine: some View {
        HorizontalRule()
            .stroke(Theme.Colors.decorativeSubtle, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func column(_ week: RackWeek) -> some View {
        let isSelected = selectedWeekStart.map { Calendar.current.isDate($0, inSameDayAs: week.weekStart) } ?? false
        let metGoal = week.plates.count >= goal
        let neutral = metGoal ? Theme.Colors.textSecondary : Theme.Colors.decorativeSubtle

        return Button {
            Haptics.selection()
            onSelect(week.weekStart)
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                VStack(spacing: plateGap) {
                    Spacer(minLength: 0)
                    if week.plates.isEmpty {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(
                                Theme.Colors.decorativeSubtle,
                                style: StrokeStyle(lineWidth: 1, dash: week.isBreak ? [2, 2] : [])
                            )
                            .frame(height: plateHeight)
                    } else {
                        ForEach(week.plates.reversed()) { plate in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(isSelected ? plate.category.color : neutral)
                                .overlay {
                                    if isSelected && plate.category == .conditioning {
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .strokeBorder(Theme.Colors.decorativeSubtle, lineWidth: 1)
                                    }
                                }
                                .frame(height: plateHeight)
                        }
                    }
                }
                .frame(width: columnWidth, height: stackHeight)

                Rectangle()
                    .fill(isSelected ? Theme.Colors.ink : Color.clear)
                    .frame(width: columnWidth, height: 3)

                Text(monthLabel(for: week) ?? " ")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize()
                    .frame(width: columnWidth, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: week))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Labels the first week of each month so the rack reads like a calendar.
    private func monthLabel(for week: RackWeek) -> String? {
        let calendar = Calendar.current
        let isFirstColumn = weeks.first?.weekStart == week.weekStart
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: week.weekStart) else { return nil }
        let startsMonth = calendar.component(.month, from: week.weekStart) != calendar.component(.month, from: weekEnd)
            || calendar.component(.day, from: week.weekStart) == 1
        guard isFirstColumn || startsMonth else { return nil }
        return weekEnd.formatted(.dateTime.month(.abbreviated))
    }

    private func accessibilityLabel(for week: RackWeek) -> String {
        let start = week.weekStart.formatted(.dateTime.month(.wide).day())
        if week.isBreak && week.plates.isEmpty { return "Week of \(start), planned break" }
        return "Week of \(start), \(SharedFormatters.count(week.plates.count, "session"))"
    }
}

/// A single horizontal line through the middle of its frame, for dashed rules.
struct HorizontalRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Week Stats

/// Four numbers for the selected week, each opening its detail.
struct WeekStatsRow: View {
    let bucket: HomeWeekBucket?
    let onMetricTap: (WorkoutMetricDetailKind) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let hasWorkouts = !(bucket?.workouts.isEmpty ?? true)
        let sessionsLabel = bucket?.workouts.count == 1 ? "session" : "sessions"
        let setsLabel = bucket?.setsValue == "1" ? "set" : "sets"
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
            : AnyLayout(StatColumns())

        layout {
            stat(bucket?.sessionsValue ?? "0", label: sessionsLabel, kind: .sessions, id: "home-summary-sessions", enabled: hasWorkouts)
            stat(bucket?.volumeValue ?? "--", label: "lbs lifted", kind: .totalVolume, id: "home-summary-totalVolume", enabled: hasWorkouts)
            stat(bucket?.setsValue ?? "--", label: setsLabel, kind: .totalSets, id: "home-summary-totalSets", enabled: hasWorkouts)
            stat(bucket?.averageDurationValue ?? "--", label: "avg length", kind: .averageDuration, id: "home-summary-averageDuration", enabled: hasWorkouts)
        }
        .padding(.vertical, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.md)
        .softCard()
    }

    private func stat(_ value: String, label: String, kind: WorkoutMetricDetailKind, id: String, enabled: Bool) -> some View {
        Button {
            Haptics.selection()
            onMetricTap(kind)
        } label: {
            DisplayStat(value: value, label: label, valueFont: Theme.Typography.number)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.xs)
                .contentShape(.rect)
        }
        .buttonStyle(PressableCardButtonStyle())
        .disabled(!enabled)
        .accessibilityIdentifier(id)
        .accessibilityHint(enabled ? "Opens details" : "")
    }
}

// MARK: - Health Status

/// One quiet line about Apple Health: a dot that is green when data is fresh.
struct SyncStatusPill: View {
    let text: String
    let isActive: Bool
    var isSyncing = false

    var body: some View {
        HStack(spacing: 6) {
            if isSyncing {
                LivePulseDot(color: Theme.Colors.success, size: 6)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(isActive ? Theme.Colors.success : Theme.Colors.decorativeSubtle)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(minHeight: Theme.Layout.minimumTapTarget)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Apple Health: \(text)")
    }
}

// MARK: - Workout Row

/// A training-log line: date in the margin, what and where, how long, and a repeat.
struct HomeWorkoutRow: View {
    let workout: Workout
    let exerciseCount: Int
    var category: PlateCategory?
    var showsRule = true
    let onRepeat: () -> Void
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let parts = SharedFormatters.workoutTitleParts(workout.name)
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Button(action: onTap) {
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    WorkoutDateBadge(date: workout.date, category: category)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(parts.title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let place = parts.place {
                            Text(place)
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: Theme.Spacing.sm)

                    if !dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(workout.duration)
                                .font(Theme.Typography.numberSmall)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            Text(SharedFormatters.count(exerciseCount, "exercise"))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(PressableCardButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(workout.name), \(workout.date.formatted(date: .abbreviated, time: .shortened)), "
                    + "\(workout.duration), \(SharedFormatters.count(exerciseCount, "exercise"))"
            )
            .accessibilityHint("Opens workout details")

            Button {
                Haptics.selection()
                onRepeat()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(Theme.Colors.rule, lineWidth: 1.5))
                    .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(AppInteractionButtonStyle())
            .accessibilityLabel("Repeat \(workout.name)")
        }
        .ledgerRow(showsRule: showsRule)
    }
}

/// The date in a log's margin: weekday above a big day number. A plate mark shows
/// what the session trained when it is known.
struct WorkoutDateBadge: View {
    let date: Date
    var tint: Color = Theme.Colors.textPrimary
    var category: PlateCategory?
    @ScaledMetric(relativeTo: .caption) private var columnWidth: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if let category {
                PlateMark(category: category, height: 30)
            }
            VStack(spacing: -2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(Theme.Typography.caption2Bold)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(date.formatted(.dateTime.day()))
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Calendar.current.isDateInToday(date) ? Theme.Colors.success : tint)
            }
            .frame(minWidth: columnWidth)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Week Bucket

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
            return "This week"
        case 1:
            return "Last week"
        default:
            return "Week of \(weekStart.formatted(Date.FormatStyle().month(.abbreviated).day()))"
        }
    }

    var rangeLabel: String {
        let start = weekStart.formatted(Date.FormatStyle().month(.abbreviated).day())
        let end = displayEnd.formatted(Date.FormatStyle().month(.abbreviated).day())
        return "\(start) – \(end)"
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

    var statusLabel: String {
        if isSavedBreakWeek {
            return "Planned break"
        }
        if stats.totalWorkouts == 0 {
            return isCurrentWeek ? "Nothing logged yet" : "No sessions"
        }
        return SharedFormatters.count(stats.totalWorkouts, "session")
    }
}

// MARK: - Destination Row

/// A place to go next, listed like an index entry.
struct ExploreRow: View {
    let title: String
    let subtitle: String
    var showsRule = true

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.cardHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Image(systemName: "chevron.right")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .ledgerRow(showsRule: showsRule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}
