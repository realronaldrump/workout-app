import SwiftUI

struct ExerciseTaggingView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var metadataManager = ExerciseMetadataManager.shared
    @State private var searchText = ""
    
    var uniqueExercises: [String] {
        let allExercises = dataManager.workouts.flatMap { $0.exercises.map { $0.name } }
        let unique = Set(allExercises)
        return Array(unique).sorted()
    }
    
    var filteredExercises: [String] {
        if searchText.isEmpty {
            return uniqueExercises
        } else {
            return uniqueExercises.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        ZStack {
            AdaptiveBackground()
            Form {
                Section(header: Text("Assign Muscle Groups")) {
                    if filteredExercises.isEmpty {
                        Text("0")
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(filteredExercises, id: \.self) { (exercise: String) in
                        HStack {
                            Text(exercise)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Spacer()
                            
                            Menu {
                                ForEach(MuscleGroup.allCases, id: \.self) { group in
                                    Button {
                                        metadataManager.setMuscleGroup(for: exercise, to: group)
                                    } label: {
                                        Label(group.displayName, systemImage: getIcon(for: group))
                                    }
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    metadataManager.setMuscleGroup(for: exercise, to: nil)
                                } label: {
                                    Label("None", systemImage: "xmark.circle")
                                }
                            } label: {
                                HStack {
                                    if let group = metadataManager.getMuscleGroup(for: exercise) {
                                        Text(group.displayName)
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                        Image(systemName: getIcon(for: group))
                                            .foregroundStyle(Theme.Colors.accent)
                                    } else {
                                        Text("Untagged")
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.Colors.surface.opacity(0.6))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Exercise Tags")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    }
    
    func getIcon(for group: MuscleGroup) -> String {
        switch group {
        case .chest: return "heart.fill"
        case .back: return "arrow.left.and.right"
        case .shoulders: return "figure.arms.open"
        case .biceps: return "figure.strengthtraining.functional"
        case .triceps: return "arrow.up.right"
        case .quads: return "figure.walk"
        case .hamstrings: return "figure.run"
        case .glutes: return "figure.cooldown"
        case .calves: return "shoeprints.fill"
        case .core: return "circle.hexagongrid"
        case .cardio: return "heart.text.square"
        }
    }
}
