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
                Section(header: Text("Assign Muscle Tags")) {
                    if filteredExercises.isEmpty {
                        Text("0")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(filteredExercises, id: \.self) { (exercise: String) in
                        NavigationLink(destination: ExerciseTagEditorView(exerciseName: exercise)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise)
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Colors.textPrimary)

                                let tags = metadataManager.resolvedTags(for: exercise)
                                Text(tags.isEmpty ? "Untagged" : tags.map(\.displayName).joined(separator: ", "))
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(tags.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
                                    .lineLimit(2)
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
}
