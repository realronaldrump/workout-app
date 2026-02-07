import SwiftUI

/// Visual muscle group display showing workout frequency by muscle group
/// Warm, vibrant design with glassmorphism
struct MuscleHeatmapView: View {
    let dataManager: WorkoutDataManager
    let dateRange: DateInterval
    var onOpen: (() -> Void)? = nil

    @State private var selectedMuscleTag: MuscleTag?
    @State private var isAppearing = false

    private var muscleGroupStats: [MuscleTag: MuscleStats] {
        calculateMuscleStats()
    }

    private var dateRangeLabel: String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: dateRange.start, to: dateRange.end).day ?? 0

        if days <= 7 {
            return "This week"
        } else if days <= 31 {
            return "This month"
        } else if days <= 93 {
            return "3 months"
        } else if days <= 366 {
            return "This year"
        } else {
            return "All time"
        }
    }

    var body: some View {
        let stats = muscleGroupStats
        let builtInTags = MuscleGroup.allCases.map { MuscleTag.builtIn($0) }
        let customTags = stats.keys
            .filter { $0.kind == .custom }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let tags = builtInTags + customTags

        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Header
            HStack {
                Text("Muscle Balance")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .tracking(1.0)

                Spacer()

                Text(dateRangeLabel)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)

                if let onOpen {
                    Button {
                        Haptics.selection()
                        onOpen()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Muscle balance details")
                }
            }

            // Muscle group grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Theme.Spacing.md) {
                ForEach(tags, id: \.id) { tag in
                    MuscleGroupTile(
                        muscleGroup: tag,
                        stats: stats[tag],
                        isSelected: selectedMuscleTag?.id == tag.id
                    ) {
                        withAnimation(Theme.Animation.spring) {
                            selectedMuscleTag = selectedMuscleTag?.id == tag.id ? nil : tag
                        }
                    }
                }
            }

            // Selected detail
            if let selected = selectedMuscleTag, let stats = stats[selected] {
                MuscleDetailView(muscleGroup: selected, stats: stats)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(cornerRadius: Theme.CornerRadius.large, elevation: 2)
        .opacity(isAppearing ? 1 : 0)
        .onAppear {
            withAnimation(Theme.Animation.spring) {
                isAppearing = true
            }
        }
    }

    private func calculateMuscleStats() -> [MuscleTag: MuscleStats] {
        let recentWorkouts = dataManager.workouts.filter { dateRange.contains($0.date) }
        var muscleGroupData: [MuscleTag: (sets: Int, exercises: Set<String>, lastDate: Date?)] = [:]

        for group in MuscleGroup.allCases {
            muscleGroupData[MuscleTag.builtIn(group)] = (sets: 0, exercises: [], lastDate: nil)
        }

        for workout in recentWorkouts {
            for exercise in workout.exercises {
                let tags = ExerciseMetadataManager.shared.resolvedTags(for: exercise.name)
                guard !tags.isEmpty else { continue }

                for tag in tags {
                    var current = muscleGroupData[tag] ?? (sets: 0, exercises: [], lastDate: nil)
                    current.sets += exercise.sets.count
                    current.exercises.insert(exercise.name)
                    if current.lastDate.map({ workout.date > $0 }) ?? true { current.lastDate = workout.date }
                    muscleGroupData[tag] = current
                }
            }
        }

        var result: [MuscleTag: MuscleStats] = [:]
        let maxSets = muscleGroupData.values.map { $0.sets }.max() ?? 1

        for (group, data) in muscleGroupData {
            let intensity = maxSets > 0 ? Double(data.sets) / Double(maxSets) : 0
            result[group] = MuscleStats(
                totalSets: data.sets,
                exerciseCount: data.exercises.count,
                exercises: Array(data.exercises),
                intensity: intensity,
                lastWorked: data.lastDate
            )
        }

        return result
    }
}

struct MuscleStats {
    let totalSets: Int
    let exerciseCount: Int
    let exercises: [String]
    let intensity: Double
    let lastWorked: Date?
}

struct MuscleGroupTile: View {
    let muscleGroup: MuscleTag
    let stats: MuscleStats?
    let isSelected: Bool
    let onTap: () -> Void

    private var color: Color {
        muscleGroup.tint
    }

    private var opacity: Double {
        guard let stats = stats, stats.totalSets > 0 else { return 0.2 }
        return 0.3 + (stats.intensity * 0.7)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Theme.Spacing.sm) {
                // Icon
                Image(systemName: muscleGroup.iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(color.opacity(opacity))

                // Name
                Text(muscleGroup.shortName)
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                // Sets count
                if let stats = stats, stats.totalSets > 0 {
                    Text("\(stats.totalSets)")
                        .font(Theme.Typography.numberSmall)
                        .foregroundColor(color)
                } else {
                    Text("—")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(color.opacity(isSelected ? 0.15 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct MuscleDetailView: View {
    let muscleGroup: MuscleTag
    let stats: MuscleStats

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Header
            HStack {
                Text(muscleGroup.displayName)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                if let lastDate = stats.lastWorked {
                    Text(lastDate.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            // Stats row
            HStack(spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stats.totalSets)")
                        .font(Theme.Typography.number)
                        .foregroundColor(muscleGroup.tint)
                    Text("sets")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stats.exerciseCount)")
                        .font(Theme.Typography.number)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("exercises")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                // Intensity indicator
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Double(i) / 5.0 < stats.intensity ? muscleGroup.tint : Theme.Colors.surface)
                            .frame(width: 8, height: 20)
                    }
                }
            }

            // Exercise list
            if !stats.exercises.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(stats.exercises.sorted(), id: \.self) { exercise in
                            Text(exercise)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(Theme.Colors.surface)
                                .cornerRadius(Theme.CornerRadius.small)
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}
