import SwiftUI

struct MuscleRecencyView: View {
    @ObservedObject var dataManager: WorkoutDataManager

    private var recencyRows: [MuscleGroupRecency] {
        let workouts = dataManager.workouts
        let exerciseNames = Set(workouts.flatMap { $0.exercises.map(\.name) })
        let tagMappings = ExerciseMetadataManager.shared.resolvedMappings(for: exerciseNames)
        let groupMappings: [String: [MuscleGroup]] = tagMappings.mapValues { tags in
            tags.compactMap { $0.builtInGroup }
        }

        return MuscleRecencySuggestionEngine.allGroupRecency(
            workouts: workouts,
            muscleGroupsByExerciseName: groupMappings
        )
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    Text("Muscle Recency")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.5)
                        .padding(.top, Theme.Spacing.md)

                    Text("See when each muscle group was last trained.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    VStack(spacing: Theme.Spacing.md) {
                        ForEach(recencyRows) { row in
                            recencyRow(row)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle("Muscle Recency")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recencyRow(_ row: MuscleGroupRecency) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(row.group.color.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: row.group.iconName)
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(row.group.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(row.group.displayName)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                if let topExercise = row.lastExercise {
                    Text(topExercise.name)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("No tagged workouts yet")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(lastWorkedLabel(for: row))
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(row.lastTrained == nil ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                Text(lastWorkedDateLabel(for: row))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.group.displayName), \(lastWorkedLabel(for: row)), \(lastWorkedDateLabel(for: row))")
    }

    private func lastWorkedLabel(for row: MuscleGroupRecency) -> String {
        guard let daysSince = row.daysSince else { return "Never worked" }
        return "Last worked \(daysSince)d ago"
    }

    private func lastWorkedDateLabel(for row: MuscleGroupRecency) -> String {
        guard let lastTrained = row.lastTrained else { return "No date available" }
        return lastTrained.formatted(date: .abbreviated, time: .omitted)
    }
}
