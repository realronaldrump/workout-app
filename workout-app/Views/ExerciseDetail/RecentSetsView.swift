import SwiftUI

struct RecentSetsView: View {
    let exerciseName: String
    let history: [(date: Date, sets: [WorkoutSet])]
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared
    @State private var visibleCount: Int = 5

    private var sortedSessions: [(date: Date, sets: [WorkoutSet])] {
        history.sorted { $0.date > $1.date }
    }

    private var recentSessions: [(date: Date, sets: [WorkoutSet])] {
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
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(recentSessions, id: \.date) { session in
                    VStack(alignment: .leading, spacing: 8) {
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
                                        .monospacedDigit()

                                    Spacer()
                                } else {
                                    Text("\(Int(set.weight)) lbs × \(set.reps)")
                                        .font(Theme.Typography.body)
                                        .monospacedDigit()

                                    Spacer()

                                    Text("\(Int(set.weight * Double(set.reps))) lbs")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
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
