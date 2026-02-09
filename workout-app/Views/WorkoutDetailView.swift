import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var dataManager: WorkoutDataManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    // Removed local healthData state to use source of truth
    @State private var showingSyncError = false
    @State private var syncErrorMessage = ""
    @State private var selectedExercise: ExerciseSelection?
    @State private var showingQuickStart = false
    @State private var quickStartExercise: String?
    @State private var showingSessionInsights = false
    @State private var showingWorkoutHealthInsights = false
    @State private var showingFatigueInsights = false
    @State private var showingEdit = false

    private var resolvedWorkout: Workout {
        dataManager.workouts.first(where: { $0.id == workout.id }) ?? workout
    }

    private var isLoggedWorkout: Bool {
        dataManager.loggedWorkoutIds.contains(workout.id)
    }

    private func workoutDateTimeToolbarText(for date: Date) -> String {
        // Keep this compact so it fits in the nav-bar trailing container across screens/split views.
        let calendar = Calendar.current
        let now = Date()
        let includeYear = calendar.component(.year, from: date) != calendar.component(.year, from: now)

        let datePart = includeYear
            ? date.formatted(.dateTime.year().month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day())

        let timePart = date.formatted(.dateTime.hour().minute())
        return "\(datePart) | \(timePart)"
    }

    var body: some View {
        let workout = resolvedWorkout
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    // Workout summary card
                    MetricTileButton(
                        action: {
                            showingSessionInsights = true
                        },
                        content: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Duration")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textTertiary)
                                    Text(workout.duration)
                                        .font(Theme.Typography.metric)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                }

                                Spacer()

                                VStack(alignment: .center, spacing: 4) {
                                    Text("Exercises")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textTertiary)
                                    Text("\(workout.exercises.count)")
                                        .font(Theme.Typography.metric)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Total Volume")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textTertiary)
                                    Text(formatVolume(workout.totalVolume))
                                        .font(Theme.Typography.metric)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                }
                            }
                            .padding(Theme.Spacing.lg)
                            .softCard(elevation: 2)
                        }
                    )

                    GymAssignmentCard(workout: workout)

                    // Health Data Section
                    if healthManager.isHealthKitAvailable() {
                        healthDataSection
                    }

                    WorkoutAnnotationCard(workout: workout)

                    MetricTileButton(
                        action: {
                            showingFatigueInsights = true
                        },
                        content: {
                            FatigueLensView(summary: fatigueSummary)
                        }
                    )

                    // Exercises list
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Exercises")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)

                        ForEach(workout.exercises) { exercise in
                            ExerciseCard(
                                exercise: exercise,
                                onViewHistory: { exerciseName in
                                    selectedExercise = ExerciseSelection(id: exerciseName)
                                },
                                onQuickStart: { exerciseName in
                                    quickStartExercise = exerciseName
                                    showingQuickStart = true
                                }
                            )
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Text(workoutDateTimeToolbarText(for: workout.date))
                    // Match app's brutalist typography (avoid generic system/nav-bar styling).
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
            }

            if isLoggedWorkout {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        showingEdit = true
                        Haptics.selection()
                    }
                    .font(Theme.Typography.captionBold)
                }
            }
        }
        .onAppear {
            // Health data is now observed directly from healthManager
        }
        .alert("Sync Error", isPresented: $showingSyncError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncErrorMessage)
        }
        .navigationDestination(item: $selectedExercise) { selection in
            ExerciseDetailView(
                exerciseName: selection.id,
                dataManager: dataManager,
                annotationsManager: annotationsManager,
                gymProfilesManager: gymProfilesManager
            )
        }
        .sheet(isPresented: $showingQuickStart) {
            QuickStartView(exerciseName: quickStartExercise)
        }
        .sheet(isPresented: $showingEdit) {
            WorkoutEditView(workoutId: workout.id)
        }
        .navigationDestination(isPresented: $showingSessionInsights) {
            WorkoutSessionInsightsView(workout: workout)
        }
        .navigationDestination(isPresented: $showingWorkoutHealthInsights) {
            WorkoutHealthInsightsView(workout: workout)
        }
        .navigationDestination(isPresented: $showingFatigueInsights) {
            FatigueLensDetailView(workout: workout, summary: fatigueSummary)
        }
    }

    // MARK: - Health Data Section

    @ViewBuilder
    private var healthDataSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Health Data")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                syncButton
            }

            if let data = healthManager.getHealthData(for: workout.id) {
                MetricTileButton(
                    action: {
                        showingWorkoutHealthInsights = true
                    },
                    content: {
                        HealthDataView(healthData: data)
                    }
                )
                RecoveryInsightCard(healthData: data)
            } else {
                noHealthDataCard
            }
        }
    }

    private var fatigueSummary: FatigueSummary {
        WorkoutAnalytics.fatigueSummary(for: resolvedWorkout, allWorkouts: dataManager.workouts)
    }

    private var syncButton: some View {
        let hasData = healthManager.getHealthData(for: workout.id) != nil

        return Button(action: syncHealthData) {
            HStack(spacing: 6) {
                if healthManager.isSyncing {
                    SyncPulse()
                } else {
                    Image(systemName: hasData ? "arrow.triangle.2.circlepath" : "heart.text.square")
                        .font(.system(size: 14))
                }

                Text(hasData ? "Re-sync" : "Sync")
                    .font(Theme.Typography.subheadline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                Capsule()
                    .fill(Theme.Colors.error)
            )
        }
        .disabled(healthManager.isSyncing)
        .opacity(healthManager.isSyncing ? 0.7 : 1.0)
    }

    private var noHealthDataCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("health data 0")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textSecondary)

            Text("sync required")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 2)
    }

    // MARK: - Actions

    private func syncHealthData() {
        Task {
            do {
                // Request authorization if needed
                if healthManager.authorizationStatus != .authorized {
                    try await healthManager.requestAuthorization()
                }

                _ = try await healthManager.syncHealthDataForWorkout(workout)
                Haptics.notify(.success)
            } catch {
                syncErrorMessage = error.localizedDescription
                showingSyncError = true
            }
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk lbs", volume / 1000)
        }
        return "\(Int(volume)) lbs"
    }
}

struct ExerciseCard: View {
    let exercise: Exercise
    var onViewHistory: ((String) -> Void)?
    var onQuickStart: ((String) -> Void)?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(
                action: {
                    withAnimation { isExpanded.toggle() }
                    Haptics.selection()
                },
                label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(Theme.Typography.condensed)
                                .tracking(-0.2)
                                .foregroundColor(Theme.Colors.textPrimary)

                            HStack(spacing: 16) {
                                Label("\(exercise.sets.count) sets", systemImage: "number")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)

                                Label(formatVolume(exercise.totalVolume), systemImage: "scalemass")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
            )
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                        HStack {
                            Text("Set \(index + 1)")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .frame(width: 50, alignment: .leading)

                            Text("\(Int(set.weight)) lbs × \(set.reps)")
                                .font(Theme.Typography.body)
                                .monospacedDigit()

                            Spacer()

                            Text("\(Int(set.weight * Double(set.reps))) lbs")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        .padding(.horizontal)

                        if index < exercise.sets.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
        .contextMenu {
            Button("View History") {
                onViewHistory?(exercise.name)
            }
            Button("Compare Progress") {
                onViewHistory?(exercise.name)
            }
            Button("Quick Start") {
                onQuickStart?(exercise.name)
            }
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
}

struct RecoveryInsightCard: View {
    let healthData: WorkoutHealthData
    @State private var didTriggerHaptic = false

    private enum RecoveryGrade: String {
        case gradeA = "A"
        case b = "B"
        case gradeC = "C"

        var statusLabel: String {
            switch self {
            case .gradeA: return "Ready"
            case .b: return "Caution"
            case .gradeC: return "Needs recovery"
            }
        }

        var explanation: String {
            switch self {
            case .gradeA:
                return "A = steady recovery signals for this workout."
            case .b:
                return "B = some fatigue signal; consider a lighter next session."
            case .gradeC:
                return "C = elevated fatigue signal (high resting HR or low HRV)."
            }
        }
    }

    private struct RecoveryInsightSnapshot {
        let grade: RecoveryGrade
        let message: String
        let tint: Color
        let icon: String
    }

    private var insight: RecoveryInsightSnapshot {
        let hrv = Int(healthData.avgHRV ?? 0)
        let resting = Int(healthData.restingHeartRate ?? 0)
        let workload = Int(healthData.avgHeartRate ?? 0)
        let message = "hrv \(hrv) ms | rhr \(resting) bpm | avgHR \(workload) bpm"

        if resting > 70 || hrv < 35 {
            return RecoveryInsightSnapshot(
                grade: .gradeC,
                message: message,
                tint: Theme.Colors.warning,
                icon: "bed.double.fill"
            )
        }

        if workload > 150 {
            return RecoveryInsightSnapshot(
                grade: .b,
                message: message,
                tint: Theme.Colors.accentSecondary,
                icon: "bolt.heart"
            )
        }

        return RecoveryInsightSnapshot(
            grade: .gradeA,
            message: message,
            tint: Theme.Colors.success,
            icon: "checkmark.seal.fill"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: insight.icon)
                    .foregroundColor(insight.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recovery Grade")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(insight.grade.statusLabel)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                Text(insight.grade.rawValue)
                    .font(Theme.Typography.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(insight.tint)
                    )
            }

            Text(insight.message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            Text(insight.grade.explanation)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
        .onAppear {
            if insight.grade == .gradeC, !didTriggerHaptic {
                Haptics.notify(.warning)
                didTriggerHaptic = true
            }
        }
    }
}

struct SyncPulse: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.4 : 0.8)
            .opacity(isPulsing ? 0.6 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
