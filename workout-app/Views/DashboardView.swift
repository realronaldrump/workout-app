import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @StateObject private var insightsEngine: InsightsEngine
    @State private var selectedTimeRange = TimeRange.allTime
    @State private var selectedExerciseFromInsight: String?
    @State private var stats: WorkoutStats?
    
    init(dataManager: WorkoutDataManager, iCloudManager: iCloudDocumentManager) {
        self.dataManager = dataManager
        self.iCloudManager = iCloudManager
        _insightsEngine = StateObject(wrappedValue: InsightsEngine(dataManager: dataManager))
    }
    
    enum TimeRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case threeMonths = "3 Months"
        case year = "Year"
        case allTime = "All Time"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    if dataManager.workouts.isEmpty {
                        EmptyStateView()
                            .padding(.top, 100)
                    } else {
                        // Time Range Picker
                        Picker("Time Range", selection: $selectedTimeRange) {
                            ForEach(TimeRange.allCases, id: \.self) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        if let stats = stats {
                            OverviewCardsView(stats: stats)
                            
                            // Intelligent Insights Section
                            InsightsSectionView(
                                insightsEngine: insightsEngine,
                                dataManager: dataManager
                            ) { insight in
                                if let exerciseName = insight.exerciseName {
                                    selectedExerciseFromInsight = exerciseName
                                }
                            }
                            
                            // Muscle Balance Visualization
                            MuscleHeatmapView(dataManager: dataManager)
                            
                            ConsistencyView(stats: stats, workouts: filteredWorkouts)
                            VolumeProgressChart(workouts: filteredWorkouts)
                            ExerciseBreakdownView(workouts: filteredWorkouts)
                            RecentWorkoutsView(workouts: Array(dataManager.workouts.prefix(5)))
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Summary")
            .navigationDestination(item: $selectedExerciseFromInsight) { exerciseName in
                ExerciseDetailView(exerciseName: exerciseName, dataManager: dataManager)
            }
            .onAppear {
                loadLatestWorkoutData()
            }
            .refreshable {
                loadLatestWorkoutData()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var filteredWorkouts: [Workout] {
        guard !dataManager.workouts.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimeRange {
        case .week:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            return dataManager.workouts.filter { $0.date >= weekAgo }
        case .month:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
            return dataManager.workouts.filter { $0.date >= monthAgo }
        case .threeMonths:
            let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!
            return dataManager.workouts.filter { $0.date >= threeMonthsAgo }
        case .year:
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
            return dataManager.workouts.filter { $0.date >= yearAgo }
        case .allTime:
            return dataManager.workouts
        }
    }
    
    private func loadLatestWorkoutData() {
        // Load the most recent CSV from iCloud
        let files = iCloudManager.listWorkoutFiles()
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }
        
        if let latestFile = files.first {
            do {
                let data = try Data(contentsOf: latestFile)
                let sets = try CSVParser.parseStrongWorkoutsCSV(from: data)
                Task {
                    dataManager.processWorkoutSets(sets)
                    stats = dataManager.calculateStats()
                }
            } catch {
                print("Failed to load workout data: \(error)")
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(Theme.Colors.textTertiary)
            
            VStack(spacing: Theme.Spacing.sm) {
                Text("No Workout Data")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text("Go to Settings to import your Strong workouts CSV.")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.xxl)
    }
}