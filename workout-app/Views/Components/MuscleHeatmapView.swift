import SwiftUI

/// Visual muscle group display showing workout frequency by muscle group
/// Warm, vibrant design with glassmorphism
struct MuscleHeatmapView: View {
    let dataManager: WorkoutDataManager
    let dateRange: DateInterval
    var rangeLabel: String?
    var onOpen: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedMuscleTag: MuscleTag?
    @State private var isAppearing = false

    private var muscleGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md)
        ]
    }

    private var muscleGroupStats: [MuscleTag: MuscleStats] {
        calculateMuscleStats()
    }

    private var dateRangeLabel: String {
        if let rangeLabel {
            return rangeLabel
        }

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
            ViewThatFits(in: .horizontal) {
                HStack {
                    muscleBalanceTitle
                    Spacer()
                    dateRangeText
                    detailsButton
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        muscleBalanceTitle
                        Spacer()
                        detailsButton
                    }
                    dateRangeText
                }
            }

            // Muscle group grid
            LazyVGrid(columns: muscleGridColumns, spacing: Theme.Spacing.md) {
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

    private var muscleBalanceTitle: some View {
        Text("Effective Sets")
            .font(Theme.Typography.sectionHeader2)
            .foregroundColor(Theme.Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private var dateRangeText: some View {
        Text(dateRangeLabel)
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Colors.textTertiary)
    }

    @ViewBuilder
    private var detailsButton: some View {
        if let onOpen {
            Button {
                Haptics.selection()
                onOpen()
            } label: {
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.captionStrong)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Muscle balance details")
        }
    }

    private func calculateMuscleStats() -> [MuscleTag: MuscleStats] {
        let recentWorkouts = dataManager.workouts.filter { dateRange.contains($0.date) }
        let resolver = ExerciseIdentityResolver.current
        // swiftlint:disable:next large_tuple
        var muscleGroupData: [MuscleTag: (sets: Double, exercises: Set<String>, lastDate: Date?)] = [:]

        for group in MuscleGroup.allCases {
            muscleGroupData[MuscleTag.builtIn(group)] = (sets: 0, exercises: [], lastDate: nil)
        }

        for workout in recentWorkouts {
            for exercise in ExerciseAggregation.aggregateExercises(in: workout, resolver: resolver) {
                let assignments = ExerciseMetadataManager.shared.resolvedAssignments(for: exercise.name)
                guard !assignments.isEmpty else { continue }

                for assignment in assignments {
                    let tag = assignment.tag
                    var current = muscleGroupData[tag] ?? (sets: 0, exercises: [], lastDate: nil)
                    current.sets += MuscleContributionPolicy.effectiveSets(
                        setCount: exercise.sets.count,
                        assignment: assignment
                    )
                    current.exercises.insert(exercise.name)
                    if current.lastDate.map({ workout.date > $0 }) ?? true { current.lastDate = workout.date }
                    muscleGroupData[tag] = current
                }
            }
        }

        var result: [MuscleTag: MuscleStats] = [:]
        let maxSets = muscleGroupData.values.map { $0.sets }.max() ?? 1

        for (group, data) in muscleGroupData {
            let intensity = maxSets > 0 ? data.sets / maxSets : 0
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
    let totalSets: Double
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var color: Color {
        muscleGroup.tint
    }

    /// Share of the busiest muscle's work. Magnitude reads on one hue (the brand
    /// accent) so the grid works as a heatmap; the muscle's own color is identity only.
    private var intensity: Double {
        guard let stats, stats.totalSets > 0 else { return 0 }
        return min(max(stats.intensity, 0), 1)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(muscleGroup.shortName)
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.8)
                }

                if let stats = stats, stats.totalSets > 0 {
                    Text(MuscleContributionPolicy.formattedEffectiveSets(stats.totalSets))
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("0")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Colors.border.opacity(0.35))
                        Capsule()
                            .fill(Theme.Colors.accent)
                            .frame(width: intensity > 0 ? max(proxy.size.width * CGFloat(intensity), 4) : 0)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                    .fill(Theme.Colors.accent.opacity(0.03 + intensity * 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Colors.accent : Theme.Colors.border.opacity(0.45),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(muscleGroup.displayName)
        .accessibilityValue(
            stats.map {
                "\(MuscleContributionPolicy.formattedEffectiveSets($0.totalSets)) effective sets across \($0.exerciseCount) exercises"
            } ?? "No effective sets"
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct MuscleDetailView: View {
    let muscleGroup: MuscleTag
    let stats: MuscleStats
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Header
            ViewThatFits(in: .horizontal) {
                HStack {
                    muscleDetailTitle
                    Spacer()
                    lastWorkedText
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    muscleDetailTitle
                    lastWorkedText
                }
            }

            // Stats row
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xl) {
                    detailStats
                    Spacer()
                    intensityIndicator
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    detailStats
                    intensityIndicator
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

    private var muscleDetailTitle: some View {
        Text(muscleGroup.displayName)
            .font(Theme.Typography.headline)
            .foregroundColor(Theme.Colors.textPrimary)
    }

    @ViewBuilder
    private var lastWorkedText: some View {
        if let lastDate = stats.lastWorked {
            Text("Last worked \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    private var detailStats: some View {
        HStack(spacing: dynamicTypeSize.isAccessibilitySize ? Theme.Spacing.lg : Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MuscleContributionPolicy.formattedEffectiveSets(stats.totalSets))
                    .font(Theme.Typography.number)
                    .foregroundColor(muscleGroup.tint)
                Text("effective sets")
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
        }
    }

    private var intensityIndicator: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Double(index) / 5.0 < stats.intensity ? muscleGroup.tint : Theme.Colors.surface)
                    .frame(width: 8, height: 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Relative training intensity")
        .accessibilityValue("\(Int(round(stats.intensity * 100))) percent")
    }
}
