import SwiftUI

/// Visual muscle group display showing workout frequency by muscle group
/// Dark minimalist design with glassmorphism
struct MuscleHeatmapView: View {
    let dataManager: WorkoutDataManager
    
    @State private var selectedMuscleGroup: MuscleGroup?
    @State private var isAppearing = false
    
    private var muscleGroupStats: [MuscleGroup: MuscleStats] {
        calculateMuscleStats()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Header
            HStack {
                Text("Muscle Balance")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Spacer()
                
                Text("4 weeks")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            
            // Muscle group grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Theme.Spacing.md) {
                ForEach(MuscleGroup.allCases.filter { $0 != .core }, id: \.self) { group in
                    MuscleGroupTile(
                        muscleGroup: group,
                        stats: muscleGroupStats[group],
                        isSelected: selectedMuscleGroup == group
                    ) {
                        withAnimation(Theme.Animation.spring) {
                            selectedMuscleGroup = selectedMuscleGroup == group ? nil : group
                        }
                    }
                }
            }
            
            // Selected detail (drill down)
            if let selected = selectedMuscleGroup, let stats = muscleGroupStats[selected] {
                MuscleDetailView(muscleGroup: selected, stats: stats)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(cornerRadius: Theme.CornerRadius.large, elevation: 2)
        .opacity(isAppearing ? 1 : 0)
        .onAppear {
            withAnimation(Theme.Animation.spring) {
                isAppearing = true
            }
        }
    }
    
    private func calculateMuscleStats() -> [MuscleGroup: MuscleStats] {
        let calendar = Calendar.current
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        
        let recentWorkouts = dataManager.workouts.filter { $0.date >= fourWeeksAgo }
        var muscleGroupData: [MuscleGroup: (sets: Int, exercises: Set<String>, lastDate: Date?)] = [:]
        
        for group in MuscleGroup.allCases {
            muscleGroupData[group] = (sets: 0, exercises: [], lastDate: nil)
        }
        
        for workout in recentWorkouts {
            for exercise in workout.exercises {
                guard let group = ExerciseMetadataManager.shared.getMuscleGroup(for: exercise.name) else { continue }
                if var current = muscleGroupData[group] {
                    current.sets += exercise.sets.count
                    current.exercises.insert(exercise.name)
                    if current.lastDate.map({ workout.date > $0 }) ?? true { current.lastDate = workout.date }
                    muscleGroupData[group] = current
                }
            }
        }
        
        var result: [MuscleGroup: MuscleStats] = [:]
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
    let muscleGroup: MuscleGroup
    let stats: MuscleStats?
    let isSelected: Bool
    let onTap: () -> Void
    
    private var color: Color {
        muscleGroup.color
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
    let muscleGroup: MuscleGroup
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
                        .foregroundColor(muscleGroup.color)
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
                            .fill(Double(i) / 5.0 < stats.intensity ? muscleGroup.color : Theme.Colors.glass)
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
                                .background(Theme.Colors.glass)
                                .cornerRadius(Theme.CornerRadius.small)
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 2)
    }
}

extension MuscleGroup {
    var iconName: String {
        switch self {
        case .push: return "arrow.up.right"
        case .pull: return "arrow.down.left"
        case .legs: return "figure.walk"
        case .core: return "circle.hexagongrid"
        case .cardio: return "heart"
        }
    }
    
    var shortName: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .core: return "Core"
        case .cardio: return "Cardio"
        }
    }
}
