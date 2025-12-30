import Foundation
import Combine

class ExerciseMetadataManager: ObservableObject {
    static let shared = ExerciseMetadataManager()
    
    @Published var muscleGroupMappings: [String: MuscleGroup] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let metadataKey = "ExerciseMetadata"
    
    private let defaultMappings: [String: MuscleGroup] = [
        // Push
        "Chest Press (Machine)": .push,
        "Shoulder Press (Machine)": .push,
        "Triceps Press Machine": .push,
        "Triceps Extension (Machine)": .push,
        "Chest Fly": .push,
        "Lateral Raise (Machine)": .push,
        "Bench Press (Barbell)": .push,
        "Overhead Press (Barbell)": .push,
        "Incline Bench Press (Barbell)": .push,
        "Dumbbell Press": .push,
        "Push Ups": .push,
        
        // Pull
        "Lat Pulldown (Machine)": .pull,
        "Seated Row (Machine)": .pull,
        "MTS Row": .pull,
        "Bicep Curl (Machine)": .pull,
        "Preacher Curl (Machine)": .pull,
        "Reverse Fly (Machine)": .pull,
        "Pull Up": .pull,
        "Chin Up": .pull,
        "Barbell Row": .pull,
        "Deadlift (Barbell)": .pull,
        
        // Legs
        "Leg Extension (Machine)": .legs,
        "Seated Leg Curl (Machine)": .legs,
        "Lying Leg Curl (Machine)": .legs,
        "Seated Leg Press (Machine)": .legs,
        "Calf Extension Machine": .legs,
        "Hip Adductor (Machine)": .legs,
        "Hip Abductor (Machine)": .legs,
        "Glute Kickback (Machine)": .legs,
        "Squat (Barbell)": .legs,
        "Leg Press": .legs,
        "Lunges": .legs,
        
        // Cardio
        "Running (Treadmill)": .cardio,
        "Stair stepper": .cardio,
        "Cycling": .cardio,
        "Elliptical": .cardio
    ]
    
    init() {
        loadMappings()
    }
    
    func getMuscleGroup(for exerciseName: String) -> MuscleGroup? {
        return muscleGroupMappings[exerciseName] ?? defaultMappings[exerciseName]
    }
    
    func setMuscleGroup(for exerciseName: String, to group: MuscleGroup?) {
        if let group = group {
            muscleGroupMappings[exerciseName] = group
        } else {
            muscleGroupMappings.removeValue(forKey: exerciseName)
        }
        saveMappings()
    }
    
    // MARK: - Persistence
    
    private func loadMappings() {
        if let data = userDefaults.data(forKey: metadataKey),
           let savedMappings = try? JSONDecoder().decode([String: MuscleGroup].self, from: data) {
            self.muscleGroupMappings = savedMappings
        }
    }
    
    private func saveMappings() {
        if let data = try? JSONEncoder().encode(muscleGroupMappings) {
            userDefaults.set(data, forKey: metadataKey)
        }
    }
}
