import SwiftUI

struct ProgramHubView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var programStore: ProgramStore
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var ouraManager: OuraManager
    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager

    @State private var showingBuilder = false
    @State private var showingReplaceAlert = false

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    topBar

                    header

                    if let plan = programStore.activePlan {
                        activePlanSection(plan)
                    } else {
                        emptyState
                    }

                    if !programStore.archivedPlans.isEmpty {
                        archivedSection
                    }
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: Theme.Spacing.sm)
        }
        .sheet(isPresented: $showingBuilder) {
            NavigationStack {
                ProgramBuilderView()
            }
        }
        .alert("Replace active session?", isPresented: $showingReplaceAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                startTodayPlan(forceReplace: true)
            }
        } message: {
            Text("Starting today's planned session will discard the current in-progress session.")
        }
    }

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            AppPillButton(title: "Back", systemImage: "chevron.left", variant: .subtle) {
                dismiss()
            }

            Spacer()

            AppPillButton(title: "Build", systemImage: "wand.and.sparkles") {
                showingBuilder = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Adaptive Program Coach")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.2)

            Text("Plan your next 8 weeks, start today's targets, and auto-adjust progression from results.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func activePlanSection(_ plan: ProgramPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text(plan.name)
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Spacer()

                    Button {
                        programStore.archiveActivePlan()
                        Haptics.selection()
                    } label: {
                        Text("Archive")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.error)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 6)
                            .softCard(elevation: 1)
                    }
                    .buttonStyle(.plain)
                }

                Text("\(plan.goal.title) • \(plan.split.title) • \(plan.daysPerWeek) days/week")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if plan.dueDayCount > 0 {
                    Text(
                        "Adherence \(Int(round(plan.adherenceToDate * 100)))% • " +
                        "\(plan.completedDueDays)/\(plan.dueDayCount) due sessions"
                    )
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                } else {
                    Text("Program starts \(plan.startDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)

            momentumSection(plan)
            weeklyProgressSection(plan)

            if let today = programStore.todayPlan(
                dailyHealthStore: healthManager.dailyHealthStore,
                ouraScores: ouraManager.dailyScoreStore
            ) {
                let dayStart = Calendar.current.startOfDay(for: today.day.scheduledDate)
                let todayStart = Calendar.current.startOfDay(for: Date())
                let isOverdue = dayStart < todayStart

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today's Plan")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.8)

                            Text(today.day.focusTitle)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Text(today.day.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)

                            if isOverdue {
                                Text("Overdue")
                                    .font(Theme.Typography.microcopy)
                                    .foregroundStyle(Theme.Colors.warning)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Readiness \(Int(round(today.readiness.score)))")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(today.readiness.band.rawValue.capitalized)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            if sessionManager.activeSession != nil {
                                showingReplaceAlert = true
                            } else {
                                startTodayPlan(forceReplace: false)
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Start Session")
                                    .font(Theme.Typography.captionBold)
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.Colors.accent)
                            .cornerRadius(Theme.CornerRadius.small)
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ProgramDayDetailView(dayId: today.day.id)
                        } label: {
                            HStack {
                                Spacer()
                                Text("Open Day")
                                    .font(Theme.Typography.captionBold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, Theme.Spacing.sm)
                            .softCard(elevation: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            } else {
                pendingStateSection(plan)
            }

            if !plan.completionRecords.isEmpty {
                recentCompletionsSection(plan)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Program Weeks")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(1.0)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(plan.weeks) { week in
                        NavigationLink {
                            ProgramWeekView(weekNumber: week.weekNumber)
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Week \(week.weekNumber)")
                                        .font(Theme.Typography.headline)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(
                                        "\(week.startDate.formatted(date: .abbreviated, time: .omitted)) - " +
                                        "\(week.endDate.formatted(date: .abbreviated, time: .omitted))"
                                    )
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }

                                Spacer()

                                let completed = week.days.filter { $0.state == .completed }.count
                                Text("\(completed)/\(week.days.count)")
                                    .font(Theme.Typography.captionBold)
                                    .foregroundStyle(Theme.Colors.textPrimary)

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .padding(Theme.Spacing.lg)
                            .softCard(elevation: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func momentumSection(_ plan: ProgramPlan) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let recentStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let allDays = plan.allDays.sorted { $0.scheduledDate < $1.scheduledDate }
        let pastOrToday = allDays.filter { calendar.startOfDay(for: $0.scheduledDate) <= today }
        let recentDays = allDays.filter {
            let dayStart = calendar.startOfDay(for: $0.scheduledDate)
            return dayStart >= recentStart && dayStart <= today
        }

        var completionStreak = 0
        for day in pastOrToday.reversed() {
            if day.state == .completed {
                completionStreak += 1
            } else {
                break
            }
        }

        let recentCompleted = recentDays.filter { $0.state == .completed }.count
        let recentTotal = max(recentDays.count, 1)
        let recentPercent = Int(round((Double(recentCompleted) / Double(recentTotal)) * 100))

        let nextDay = allDays.first { day in
            let isPending = day.state == .planned || day.state == .moved
            let dayStart = calendar.startOfDay(for: day.scheduledDate)
            return isPending && dayStart >= today
        }

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Momentum")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            HStack(spacing: Theme.Spacing.md) {
                momentumMetric(
                    title: "Streak",
                    value: "\(completionStreak)",
                    subtitle: completionStreak == 1 ? "completed day" : "completed days"
                )

                momentumMetric(
                    title: "7-Day",
                    value: "\(recentPercent)%",
                    subtitle: "adherence"
                )

                momentumMetric(
                    title: "Next",
                    value: nextDay?.scheduledDate.formatted(date: .abbreviated, time: .omitted) ?? "Done",
                    subtitle: nextDay?.focusTitle ?? "No pending day"
                )
            }
        }
    }

    private func momentumMetric(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }

    private func weeklyProgressSection(_ plan: ProgramPlan) -> some View {
        let cutoffDay = Calendar.current.startOfDay(for: Date())

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Weekly Progress")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(plan.weeks) { week in
                    let dueCount = week.days.filter {
                        Calendar.current.startOfDay(for: $0.scheduledDate) <= cutoffDay
                    }.count
                    let completedCount = week.days.filter {
                        Calendar.current.startOfDay(for: $0.scheduledDate) <= cutoffDay
                            && $0.state == .completed
                    }.count
                    let ratio = dueCount > 0 ? (Double(completedCount) / Double(dueCount)) : 0

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("Week \(week.weekNumber)")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Spacer()

                            if dueCount > 0 {
                                Text("\(completedCount)/\(dueCount)")
                                    .font(Theme.Typography.microcopy)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            } else {
                                Text("Upcoming")
                                    .font(Theme.Typography.microcopy)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }

                        ProgressView(value: ratio)
                            .tint(Theme.Colors.accent)
                    }
                    .padding(Theme.Spacing.md)
                    .softCard(elevation: 1)
                }
            }
        }
    }

    private func pendingStateSection(_ plan: ProgramPlan) -> some View {
        let pendingCount = plan.allDays.filter { $0.state == .planned || $0.state == .moved }.count
        let completedAll = pendingCount == 0

        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(completedAll ? "Program Complete" : "No Day Available")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(
                completedAll
                    ? "Every programmed session is complete or resolved. Archive this plan or build the next cycle."
                    : "No eligible day was found for today. Open a week to move or reset pending sessions."
            )
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func recentCompletionsSection(_ plan: ProgramPlan) -> some View {
        let recentRecords = Array(plan.completionRecords.sorted { $0.completedAt > $1.completedAt }.prefix(5))
        let daysById = Dictionary(uniqueKeysWithValues: plan.allDays.map { ($0.id, $0) })

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Recent Completions")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(recentRecords, id: \.id) { record in
                    let day = daysById[record.dayId]
                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day?.focusTitle ?? "Planned Session")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Readiness \(Int(round(record.readinessScore)))")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("\(record.successfulExerciseCount)/\(max(record.totalExerciseCount, 1)) targets")
                                .font(Theme.Typography.microcopy)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("No active program")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Build an 8-week plan from your workout history. The app will adapt targets as you log sessions.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("Current history: \(dataManager.workouts.count) workouts")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)

            Button {
                showingBuilder = true
            } label: {
                HStack {
                    Spacer()
                    Text("Build My Program")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.accent)
                .cornerRadius(Theme.CornerRadius.large)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 2)
    }

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Archived")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(1.0)

                Spacer()

                if programStore.archivedPlans.count > 4 {
                    NavigationLink {
                        ProgramArchiveListView()
                    } label: {
                        Text("See all")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(programStore.archivedPlans.prefix(4), id: \.id) { plan in
                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Text(plan.goal.title)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(round(plan.adherenceToDate * 100)))%")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("adherence (due)")
                                .font(Theme.Typography.microcopy)
                                .foregroundStyle(Theme.Colors.textTertiary)

                            Button {
                                programStore.restoreArchivedPlan(planId: plan.id)
                                Haptics.selection()
                            } label: {
                                Text("Restore")
                                    .font(Theme.Typography.microcopy)
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
                }
            }
        }
    }

    private func startTodayPlan(forceReplace: Bool) {
        guard let today = programStore.todayPlan(
            dailyHealthStore: healthManager.dailyHealthStore,
            ouraScores: ouraManager.dailyScoreStore
        ) else { return }

        Task { @MainActor in
            if forceReplace {
                await sessionManager.discardDraft()
            }

            sessionManager.startSession(
                name: today.day.focusTitle,
                gymProfileId: gymProfilesManager.lastUsedGymProfileId,
                templateExercises: today.adjustedExercises,
                plannedProgramId: today.planId,
                plannedDayId: today.day.id,
                plannedDayDate: today.day.scheduledDate
            )
            sessionManager.isPresentingSessionUI = true
            Haptics.notify(.success)
        }
    }
}
