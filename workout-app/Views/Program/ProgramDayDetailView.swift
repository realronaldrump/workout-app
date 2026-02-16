import SwiftUI

struct ProgramDayDetailView: View {
    let dayId: UUID

    @EnvironmentObject private var programStore: ProgramStore
    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingMoveSheet = false
    @State private var moveDate: Date = Date()
    @State private var showingReplaceAlert = false
    @State private var selectedWorkout: Workout?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            if let plan = programStore.activePlan,
               let day = programStore.dayPlan(dayId: dayId) {
                let readiness = readinessSnapshot(for: plan)
                let adjustedTargets = ProgramAutoregulationEngine.adjustedTargets(
                    from: day.exercises,
                    readiness: readiness,
                    roundingIncrement: plan.progressionRule.weightIncrement
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        header(day: day)

                        readinessCard(readiness: readiness)

                        exercisesCard(day: day, adjustedTargets: adjustedTargets, readiness: readiness)

                        if day.state == .completed,
                           let completion = programStore.completionRecord(for: day.id) {
                            completionCard(day: day, completion: completion, plan: plan)
                        }

                        actions(day: day)
                    }
                    .padding(Theme.Spacing.xl)
                }
            } else {
                ContentUnavailableView(
                    "Plan Day Not Found",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("This day is no longer available in the active program.")
                )
                .padding(.horizontal, Theme.Spacing.xl)
            }
        }
        .navigationTitle("Program Day")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMoveSheet) {
            moveSheet
        }
        .alert("Replace active session?", isPresented: $showingReplaceAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                startSessionFromPlan(forceReplace: true)
            }
        } message: {
            Text("Starting this planned day will discard the current in-progress session.")
        }
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
        .onAppear {
            if let day = programStore.dayPlan(dayId: dayId) {
                moveDate = day.scheduledDate
            }
        }
    }

    private func header(day: ProgramDayPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(day.focusTitle)
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.2)

                    Text(day.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                statusPill(for: day)
            }

            Text("Week \(day.weekNumber) • Day \(day.dayNumber)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func readinessCard(readiness: ReadinessSnapshot) -> some View {
        let hasHealthInputs = readiness.sleepHours != nil
            || readiness.restingHeartRateDelta != nil
            || readiness.hrvDelta != nil

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Readiness")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.sm) {
                Text("Score \(Int(round(readiness.score)))")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(readiness.band.rawValue.capitalized)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(readinessColor(readiness.band))
                    .cornerRadius(Theme.CornerRadius.small)

                Spacer()

                Text("x\(String(format: "%.2f", readiness.multiplier))")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Text("Applied to today's target loads when you start this planned session.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            if hasHealthInputs {
                VStack(alignment: .leading, spacing: 4) {
                    if let sleepHours = readiness.sleepHours {
                        readinessMetricRow(
                            title: "Sleep",
                            value: "\(formatWeight(sleepHours)) h"
                        )
                    }
                    if let restingHRDelta = readiness.restingHeartRateDelta {
                        readinessMetricRow(
                            title: "Resting HR Δ",
                            value: "\(formatSigned(restingHRDelta)) bpm"
                        )
                    }
                    if let hrvDelta = readiness.hrvDelta {
                        readinessMetricRow(
                            title: "HRV Δ",
                            value: "\(formatSigned(hrvDelta)) ms"
                        )
                    }
                }
            } else {
                Text("No daily health inputs found for this date. Neutral readiness is used.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func readinessMetricRow(title: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textTertiary)

            Spacer()

            Text(value)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func exercisesCard(
        day: ProgramDayPlan,
        adjustedTargets: [PlannedExerciseTarget],
        readiness: ReadinessSnapshot
    ) -> some View {
        let adjustedByName = adjustedTargets.reduce(into: [String: PlannedExerciseTarget]()) { partial, target in
            partial[normalize(target.exerciseName)] = target
        }

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Targets")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(day.exercises) { target in
                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.exerciseName)
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Text("\(target.setCount) sets • \(target.repRange.lowerBound)-\(target.repRange.upperBound) reps")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Spacer()

                        if let adjustedWeight = adjustedByName[normalize(target.exerciseName)]?.targetWeight {
                            if let baseWeight = target.targetWeight,
                               abs(adjustedWeight - baseWeight) > 0.01 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(formatWeight(adjustedWeight)) lbs")
                                        .font(Theme.Typography.captionBold)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text("base \(formatWeight(baseWeight))")
                                        .font(Theme.Typography.microcopy)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            } else {
                                Text("\(formatWeight(adjustedWeight)) lbs")
                                    .font(Theme.Typography.captionBold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                        } else {
                            Text("Bodyweight")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .softCard(elevation: 1)
                }
            }

            let modifierPercent = Int(round((readiness.multiplier - 1.0) * 100))
            if modifierPercent != 0 {
                let prefix = modifierPercent > 0 ? "+" : ""
                Text("Today's readiness modifier: \(prefix)\(modifierPercent)% on weighted targets.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private func completionCard(day: ProgramDayPlan, completion: ProgramCompletionRecord, plan: ProgramPlan) -> some View {
        let successPercent = Int(round(completion.adherenceRatio * 100))
        let linkedWorkout = dataManager.workouts.first(where: { $0.id == completion.workoutId })

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Completed Session")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(completion.completedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("\(completion.successfulExerciseCount)/\(max(completion.totalExerciseCount, 1)) targets hit")
                        .font(Theme.Typography.microcopy)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(successPercent)%")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("adherence")
                        .font(Theme.Typography.microcopy)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            if let linkedWorkout {
                let evaluationsByExercise = day.exercises.reduce(into: [String: ExerciseProgressEvaluation]()) { partial, target in
                    let completedSets = linkedWorkout.exercises
                        .first(where: { normalize($0.name) == normalize(target.exerciseName) })?
                        .sets ?? []
                    let evaluation = ProgramAutoregulationEngine.evaluateCompletion(
                        planned: target,
                        completedSets: completedSets,
                        rule: plan.progressionRule
                    )
                    partial[normalize(target.exerciseName)] = evaluation
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Target Outcomes")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(day.exercises) { target in
                            let evaluation = evaluationsByExercise[normalize(target.exerciseName)]
                            let wasSuccessful = evaluation?.wasSuccessful == true

                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: wasSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(wasSuccessful ? Theme.Colors.success : Theme.Colors.warning)

                                Text(target.exerciseName)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(1)

                                Spacer()

                                if let nextWeight = evaluation?.nextTarget.targetWeight {
                                    Text("Next \(formatWeight(nextWeight))")
                                        .font(Theme.Typography.microcopy)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                } else {
                                    Text("Next bodyweight")
                                        .font(Theme.Typography.microcopy)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs)
                            .softCard(elevation: 1)
                        }
                    }
                }
            }

            if linkedWorkout != nil {
                Button {
                    selectedWorkout = linkedWorkout
                    Haptics.selection()
                } label: {
                    Text("View Logged Workout")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
            } else {
                Text("Linked workout is unavailable.")
                    .font(Theme.Typography.microcopy)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func actions(day: ProgramDayPlan) -> some View {
        let isCompleted = day.state == .completed
        let canResetToPlanned = day.state == .skipped || day.state == .moved

        return VStack(spacing: Theme.Spacing.sm) {
            Button {
                if sessionManager.activeSession != nil {
                    showingReplaceAlert = true
                } else {
                    startSessionFromPlan(forceReplace: false)
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Start Planned Session")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.accent)
                .cornerRadius(Theme.CornerRadius.large)
            }
            .buttonStyle(.plain)
            .disabled(isCompleted)
            .opacity(isCompleted ? 0.6 : 1)

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    programStore.skipDay(dayId: day.id)
                    Haptics.selection()
                } label: {
                    Text("Skip Day")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .softCard(elevation: 1)
                }
                .buttonStyle(.plain)
                .disabled(isCompleted)
                .opacity(isCompleted ? 0.5 : 1)

                Button {
                    showingMoveSheet = true
                } label: {
                    Text("Move Day")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .softCard(elevation: 1)
                }
                .buttonStyle(.plain)
                .disabled(isCompleted)
                .opacity(isCompleted ? 0.5 : 1)
            }

            if canResetToPlanned {
                Button {
                    programStore.resetDayToPlanned(dayId: day.id)
                    Haptics.selection()
                } label: {
                    HStack {
                        Spacer()
                        Text("Return to Planned")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                    .softCard(elevation: 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var moveSheet: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(spacing: Theme.Spacing.lg) {
                    DatePicker(
                        "Move to",
                        selection: $moveDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .padding(Theme.Spacing.md)
                    .softCard(elevation: 1)

                    Button {
                        programStore.moveDay(dayId: dayId, to: moveDate)
                        Haptics.selection()
                        showingMoveSheet = false
                    } label: {
                        HStack {
                            Spacer()
                            Text("Save New Date")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.accent)
                        .cornerRadius(Theme.CornerRadius.large)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("Move Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppPillButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                        showingMoveSheet = false
                    }
                }
            }
        }
    }

    private func startSessionFromPlan(forceReplace: Bool) {
        guard let plan = programStore.activePlan,
              let day = programStore.dayPlan(dayId: dayId) else { return }

        let adjustedTargets = ProgramAutoregulationEngine.adjustedTargets(
            from: day.exercises,
            readiness: readinessSnapshot(for: plan),
            roundingIncrement: plan.progressionRule.weightIncrement
        )

        Task { @MainActor in
            if forceReplace {
                await sessionManager.discardDraft()
            }

            let preferredGym = gymProfilesManager.lastUsedGymProfileId
            sessionManager.startSession(
                name: day.focusTitle,
                gymProfileId: preferredGym,
                templateExercises: adjustedTargets,
                plannedProgramId: plan.id,
                plannedDayId: day.id,
                plannedDayDate: day.scheduledDate
            )
            sessionManager.isPresentingSessionUI = true
            Haptics.notify(.success)
            dismiss()
        }
    }

    private func statusPill(for day: ProgramDayPlan) -> some View {
        Text(statusText(for: day))
            .font(Theme.Typography.captionBold)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .background(statusColor(for: day))
            .cornerRadius(Theme.CornerRadius.small)
    }

    private func statusText(for day: ProgramDayPlan) -> String {
        if isOverdue(day) {
            return "Overdue"
        }
        return day.state.rawValue.capitalized
    }

    private func statusColor(for day: ProgramDayPlan) -> Color {
        if isOverdue(day) {
            return Theme.Colors.warning
        }

        switch day.state {
        case .planned:
            return Theme.Colors.accent
        case .completed:
            return Theme.Colors.success
        case .skipped:
            return Theme.Colors.warning
        case .moved:
            return Theme.Colors.accentSecondary
        }
    }

    private func readinessColor(_ band: ReadinessBand) -> Color {
        switch band {
        case .low:
            return Theme.Colors.warning
        case .neutral:
            return Theme.Colors.accent
        case .high:
            return Theme.Colors.success
        }
    }

    private func isOverdue(_ day: ProgramDayPlan) -> Bool {
        guard day.state == .planned || day.state == .moved else { return false }
        let dayStart = Calendar.current.startOfDay(for: day.scheduledDate)
        let todayStart = Calendar.current.startOfDay(for: Date())
        return dayStart < todayStart
    }

    private func readinessSnapshot(for plan: ProgramPlan) -> ReadinessSnapshot {
        ProgramAutoregulationEngine.readinessSnapshot(
            dailyHealthStore: healthManager.dailyHealthStore,
            on: Date(),
            rule: plan.progressionRule
        )
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(weight))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), weight)
    }

    private func formatSigned(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(formatWeight(value))"
    }
}
