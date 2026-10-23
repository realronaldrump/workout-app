import SwiftUI

struct RecentSetsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let exerciseName: String
    let sessions: [ExerciseHistorySession]
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared
    @State private var visibleCount: Int = 5
    @State private var selectedWorkout: Workout?

    private var history: [(date: Date, sets: [WorkoutSet])] {
        sessions.map { (date: $0.date, sets: $0.sets) }
    }

    private var sortedSessions: [ExerciseHistorySession] {
        sessions.sorted { $0.date > $1.date }
    }

    private var recentSessions: [ExerciseHistorySession] {
        Array(sortedSessions.prefix(visibleCount))
    }

    private var canShowMore: Bool {
        sortedSessions.count > visibleCount
    }

    private var isCardio: Bool {
        metadataManager
            .resolvedTags(for: exerciseName)
            .contains(where: { $0.builtInGroup == .cardio })
    }

    private var cardioConfig: ResolvedCardioMetricConfiguration {
        let sets = history.flatMap(\.sets)
        return metricManager.resolvedCardioConfiguration(for: exerciseName, historySets: sets)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Recent sessions")
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: 0) {
                ForEach(Array(recentSessions.enumerated()), id: \.element.workoutId) { position, session in
                    Button {
                        selectedWorkout = dataManager.workouts.first { $0.id == session.workoutId }
                    } label: {
                        sessionBlock(session)
                            .ledgerRow(showsRule: position < recentSessions.count - 1 || canShowMore)
                    }
                    .buttonStyle(PressableCardButtonStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        session.date.formatted(date: .abbreviated, time: .shortened)
                            + ", " + SharedFormatters.count(session.sets.count, "set")
                    )
                    .accessibilityHint("Opens the source workout")
                }
            }

            if canShowMore {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut) {
                        visibleCount = min(visibleCount + 5, sortedSessions.count)
                    }
                } label: {
                    Text("Show more sessions")
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .underline()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: exerciseName) { _, _ in visibleCount = 5 }
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
    }

    private func sessionBlock(_ session: ExerciseHistorySession) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                        .font(Theme.Typography.title4)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(sessionSummary(session))
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 4) {
                ForEach(Array(session.sets.enumerated()), id: \.offset) { index, set in
                    setRow(index: index, set: set)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private func sessionSummary(_ session: ExerciseHistorySession) -> String {
        var parts = [
            session.date.formatted(date: .omitted, time: .shortened),
            SharedFormatters.count(session.sets.count, "set")
        ]
        if !isCardio, !ExerciseLoad.isAssistedExercise(exerciseName) {
            let volume = session.sets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
            if volume > 0 { parts.append(SharedFormatters.volumeWithUnit(volume)) }
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func setRow(index: Int, set: WorkoutSet) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text("\(index + 1)")
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(minWidth: 24, alignment: .leading)
                .accessibilityLabel("Set \(index + 1)")

            if isCardio {
                Text(cardioSetSummary(set))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(ExerciseLoad.formatWeight(set.weight, exerciseName: exerciseName)) × \(set.reps)")
                    .font(Theme.Typography.title4Bold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            Spacer(minLength: Theme.Spacing.xs)

            if !isCardio, !dynamicTypeSize.isAccessibilitySize,
               !ExerciseLoad.isAssistedExercise(exerciseName), set.weight > 0 {
                Text(WorkoutValueFormatter.weightText(set.weight * Double(set.reps)))
                    .font(Theme.Typography.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .accessibilityLabel("\(WorkoutValueFormatter.weightText(set.weight * Double(set.reps))) pounds of volume")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func cardioSetSummary(_ set: WorkoutSet) -> String {
        var parts: [String] = []
        if set.distance > 0 {
            parts.append("\(WorkoutValueFormatter.distanceText(set.distance)) dist")
        }
        if set.seconds > 0 {
            parts.append(WorkoutValueFormatter.durationText(seconds: set.seconds))
        }
        if parts.isEmpty, set.reps > 0 {
            parts.append("\(set.reps) \(cardioConfig.countLabel)")
        }
        return parts.isEmpty ? "No data" : parts.joined(separator: ", ")
    }
}
