import SwiftUI

struct ExerciseCard: View {
    let exercise: Exercise
    var personalRecordDate: Date?
    var highlightedSetIDs: Set<UUID> = []
    var onViewHistory: ((String) -> Void)?
    var onQuickStart: ((String) -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var setBadgeSize: CGFloat = 24
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared

    private var isCardio: Bool {
        metadataManager
            .resolvedTags(for: exercise.name)
            .contains(where: { $0.builtInGroup == .cardio })
    }

    private var cardioConfig: ResolvedCardioMetricConfiguration {
        metricManager.resolvedCardioConfiguration(for: exercise.name, historySets: exercise.sets)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Button {
                    onViewHistory?(exercise.name)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                            exerciseTitle
                            if personalRecordDate != nil {
                                PRTag()
                            }
                        }
                        Text(summaryLine)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(onViewHistory == nil)
                .accessibilityHint(onViewHistory == nil ? "" : "Opens this exercise's history")

                if onViewHistory != nil || onQuickStart != nil {
                    Menu {
                        exerciseMenuItems
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("\(exercise.name) actions")
                }
            }

            if exercise.sets.isEmpty {
                Text("No sets recorded for this exercise.")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                        setRow(index: index, set: set)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small, style: .continuous)
                                    .fill(
                                        highlightedSetIDs.contains(set.id)
                                            ? Theme.Colors.plateYellow.opacity(0.18)
                                            : Color.clear
                                    )
                            )
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .softCard()
        .contextMenu { exerciseMenuItems }
    }

    @ViewBuilder
    private var exerciseMenuItems: some View {
        if let onViewHistory {
            Button("Exercise history", systemImage: "chart.xyaxis.line") {
                onViewHistory(exercise.name)
            }
        }
        if let onQuickStart {
            Button("Start a workout with this", systemImage: "play.fill") {
                onQuickStart(exercise.name)
            }
        }
    }

    private var summaryLine: String {
        let sets = SharedFormatters.count(exercise.sets.count, "set")
        if isCardio {
            let totalDistance = exercise.sets.reduce(0.0) { $0 + $1.distance }
            let totalSeconds = exercise.sets.reduce(0.0) { $0 + $1.seconds }
            var parts = [sets]
            if totalDistance > 0 { parts.append("\(WorkoutValueFormatter.distanceText(totalDistance)) distance") }
            if totalSeconds > 0 { parts.append(WorkoutValueFormatter.durationText(seconds: totalSeconds)) }
            return parts.joined(separator: ", ")
        }
        guard exercise.totalVolume > 0 else { return sets }
        return "\(sets), \(SharedFormatters.volumeWithUnit(exercise.totalVolume))"
    }

    private var exerciseTitle: some View {
        Text(exercise.name)
            .font(Theme.Typography.title3)
            .foregroundStyle(Theme.Colors.textPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func setRow(index: Int, set: WorkoutSet) -> some View {
        let isRecord = highlightedSetIDs.contains(set.id)

        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text("\(index + 1)")
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(minWidth: setBadgeSize, alignment: .leading)
                .accessibilityLabel("Set \(index + 1)")

            if isCardio {
                Text(cardioSetSummary(set))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(WorkoutValueFormatter.weightText(set.weight))
                        .font(Theme.Typography.title4Bold)
                        .monospacedDigit()
                    Text("lb")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("×")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("\(set.reps)")
                        .font(Theme.Typography.title4Bold)
                        .monospacedDigit()
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(WorkoutValueFormatter.weightText(set.weight)) pounds for \(set.reps) reps")
            }

            if isRecord {
                PRTag()
            }

            Spacer(minLength: Theme.Spacing.xs)

            if !isCardio && !dynamicTypeSize.isAccessibilitySize {
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

struct SyncPulse: View {
    var body: some View {
        ProgressView()
            .controlSize(.mini)
            .tint(Theme.Colors.textPrimary)
            .accessibilityHidden(true)
    }
}
