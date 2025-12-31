import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var dataManager: WorkoutDataManager
    // Removed local healthData state to use source of truth
    @State private var showingSyncError = false
    @State private var syncErrorMessage = ""
    @State private var selectedExercise: ExerciseSelection?
    @State private var showingQuickStart = false
    @State private var quickStartExercise: String?
    
    var body: some View {
        ZStack {
            AdaptiveBackground()
            
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    // Workout summary card
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
                    .glassBackground(elevation: 2)
                    
                    // Health Data Section
                    if healthManager.isHealthKitAvailable() {
                        healthDataSection
                    }
                    
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
                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
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
            ExerciseDetailView(exerciseName: selection.id, dataManager: dataManager)
        }
        .sheet(isPresented: $showingQuickStart) {
            QuickStartView(exerciseName: quickStartExercise)
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
                HealthDataView(healthData: data)
                RecoveryInsightCard(healthData: data)
            } else {
                noHealthDataCard
            }
        }
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
                    .fill(LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing))
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
            
            Text("No Health Data Synced")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textSecondary)
            
            Text("Tap 'Sync' to fetch Apple Health data recorded during this workout.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .glassBackground(elevation: 2)
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
    var onViewHistory: ((String) -> Void)? = nil
    var onQuickStart: ((String) -> Void)? = nil
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation { isExpanded.toggle() }
                Haptics.selection()
            }) {
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
        .glassBackground(elevation: 2)
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

    private var insight: (title: String, message: String, tint: Color, icon: String) {
        let hrv = healthData.avgHRV ?? 0
        let resting = healthData.restingHeartRate ?? 0
        let workload = healthData.avgHeartRate ?? 0

        if resting > 70 || hrv < 35 {
            return (
                title: "Recovery Needed",
                message: "Resting HR is elevated and HRV is lower than usual. Favor mobility or low-intensity work.",
                tint: Theme.Colors.warning,
                icon: "bed.double.fill"
            )
        }

        if workload > 150 {
            return (
                title: "High-Intensity Session",
                message: "You spent most of the workout in higher zones. Prioritize sleep and hydration tonight.",
                tint: Theme.Colors.accentSecondary,
                icon: "bolt.heart"
            )
        }

        return (
            title: "Ready for More",
            message: "Recovery metrics look steady. You can push again if energy feels good.",
            tint: Theme.Colors.success,
            icon: "checkmark.seal.fill"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: insight.icon)
                    .foregroundColor(insight.tint)
                Text(insight.title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            Text(insight.message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 2)
        .onAppear {
            if insight.title == "Recovery Needed", !didTriggerHaptic {
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
