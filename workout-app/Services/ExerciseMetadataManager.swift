import Foundation
import Combine

class ExerciseMetadataManager: ObservableObject {
    static let shared = ExerciseMetadataManager()
    
    @Published var muscleGroupMappings: [String: MuscleGroup] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let metadataKey = "ExerciseMetadata"
    
    private let defaultMappings: [String: MuscleGroup] = [
        // Chest
        "Chest Press (Machine)": .chest,
        "Bench Press (Barbell)": .chest,
        "Incline Bench Press (Barbell)": .chest,
        "Dumbbell Press": .chest,
        "Chest Fly": .chest,
        "Push Ups": .chest,
        
        // Back
        "Lat Pulldown (Machine)": .back,
        "Seated Row (Machine)": .back,
        "MTS Row": .back,
        "Pull Up": .back,
        "Chin Up": .back,
        "Barbell Row": .back,
        "Deadlift (Barbell)": .back,
        "Reverse Fly (Machine)": .back,
        
        // Shoulders
        "Shoulder Press (Machine)": .shoulders,
        "Overhead Press (Barbell)": .shoulders,
        "Lateral Raise (Machine)": .shoulders,
        
        // Biceps
        "Bicep Curl (Machine)": .biceps,
        "Preacher Curl (Machine)": .biceps,
        
        // Triceps
        "Triceps Press Machine": .triceps,
        "Triceps Extension (Machine)": .triceps,
        
        // Quads
        "Leg Extension (Machine)": .quads,
        "Seated Leg Press (Machine)": .quads,
        "Squat (Barbell)": .quads,
        "Leg Press": .quads,
        "Lunges": .quads,
        
        // Hamstrings
        "Seated Leg Curl (Machine)": .hamstrings,
        "Lying Leg Curl (Machine)": .hamstrings,
        
        // Glutes
        "Hip Adductor (Machine)": .glutes,
        "Hip Abductor (Machine)": .glutes,
        "Glute Kickback (Machine)": .glutes,
        
        // Calves
        "Calf Extension Machine": .calves,
        
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
