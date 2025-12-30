import SwiftUI

struct ExerciseListView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @State private var searchText = ""
    @State private var sortOrder = SortOrder.alphabetical
    
    enum SortOrder: String, CaseIterable {
        case alphabetical = "Name"
        case volume = "Volume"
        case frequency = "Frequency"
        case recent = "Recent"
    }
    
    var exercises: [(name: String, stats: ExerciseStats)] {
        let allExercises = dataManager.workouts.flatMap { $0.exercises }
        let grouped = Dictionary(grouping: allExercises) { $0.name }
        
        let exerciseStats = grouped.map { (name: String, exercises: [Exercise]) -> (String, ExerciseStats) in
            let totalVolume = exercises.reduce(0) { $0 + $1.totalVolume }
            let maxWeight = exercises.map { $0.maxWeight }.max() ?? 0
            let frequency = exercises.count
            
            let workoutDates = exercises.compactMap { exercise in
                dataManager.workouts.first { workout in
                    workout.exercises.contains { $0.id == exercise.id }
                }?.date
            }
            let lastPerformed = workoutDates.max()
            
            let stats = ExerciseStats(
                totalVolume: totalVolume,
                maxWeight: maxWeight,
                frequency: frequency,
                lastPerformed: lastPerformed,
                oneRepMax: exercises.map { $0.oneRepMax }.max() ?? 0
            )
            
            return (name, stats)
        }
        
        let filtered = exerciseStats.filter { exercise in
            searchText.isEmpty || exercise.0.localizedCaseInsensitiveContains(searchText)
        }
        
        switch sortOrder {
        case .alphabetical:
            return filtered.sorted { $0.0 < $1.0 }
        case .volume:
            return filtered.sorted { $0.1.totalVolume > $1.1.totalVolume }
        case .frequency:
            return filtered.sorted { $0.1.frequency > $1.1.frequency }
        case .recent:
            return filtered.sorted { ($0.1.lastPerformed ?? .distantPast) > ($1.1.lastPerformed ?? .distantPast) }
        }
    }
    
    var body: some View {
        List {
            ForEach(exercises, id: \.name) { exercise in
                NavigationLink(destination: ExerciseDetailView(exerciseName: exercise.name, dataManager: dataManager)) {
                    ExerciseRowView(name: exercise.name, stats: exercise.stats)
                }
            }
        }
        .navigationTitle("All Exercises")
        .searchable(text: $searchText, prompt: "Search exercises")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort Order", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Label(order.rawValue, systemImage: sortIcon(for: order))
                                .tag(order)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }
    
    private func sortIcon(for order: SortOrder) -> String {
        switch order {
        case .alphabetical:
            return "textformat"
        case .volume:
            return "scalemass"
        case .frequency:
            return "calendar"
        case .recent:
            return "clock"
        }
    }
}

struct ExerciseStats {
    let totalVolume: Double
    let maxWeight: Double
    let frequency: Int
    let lastPerformed: Date?
    let oneRepMax: Double
}

struct ExerciseRowView: View {
    let name: String
    let stats: ExerciseStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)
            
            HStack(spacing: 16) {
                Label("\(stats.frequency)x", systemImage: "repeat")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Label(formatWeight(stats.maxWeight), systemImage: "scalemass")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let lastDate = stats.lastPerformed {
                    Label(relativeDateString(for: lastDate), systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatWeight(_ weight: Double) -> String {
        return "\(Int(weight)) lbs"
    }
    
    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}