import SwiftUI

struct RecentSetsView: View {
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
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Recent Sessions")
                .font(Theme.Typography.sectionHeader2)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(recentSessions, id: \.workoutId) { session in
                    AnalysisTile(
                        role: .revealSource,
                        destination: "the source workout",
                        accessibilityLabel: session.date.formatted(date: .abbreviated, time: .shortened)
                            + ", " + SharedFormatters.count(session.sets.count, "set"),
                        padding: Theme.Spacing.lg,
                        action: {
                            selectedWorkout = dataManager.workouts.first {
                                $0.id == session.workoutId
                            }
                        },
                        content: {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(Theme.Typography.subheadline)
                                    .foregroundColor(Theme.Colors.textSecondary)

                                ForEach(Array(session.sets.enumerated()), id: \.offset) { index, set in
                                    HStack {
                                        Text("Set \(index + 1)")
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.textTertiary)
                                            .frame(width: 50, alignment: .leading)

                                        if isCardio {
                                            Text(cardioSetSummary(set))
                                                .font(Theme.Typography.body)

                                            Spacer()
                                        } else {
                                            Text("\(Int(set.weight)) lbs × \(set.reps)")
                                                .font(Theme.Typography.body)

                                            Spacer()

                                            Text("\(Int(set.weight * Double(set.reps))) lbs")
                                                .font(Theme.Typography.caption)
                                                .foregroundColor(Theme.Colors.textSecondary)
                                        }
                                    }
                                }
                            }
                        }
                    )
                }

                if canShowMore {
                    Button {
                        withAnimation(.easeInOut) {
                            visibleCount = min(visibleCount + 5, sortedSessions.count)
                        }
                    } label: {
                        Text("Show more")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                    }
                    .softCard(elevation: 1)
                }
            }
        }
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
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
        return parts.isEmpty ? "—" : parts.joined(separator: " | ")
    }
}
