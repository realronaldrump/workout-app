import Foundation
import Combine

enum WorkoutSessionError: LocalizedError {
    case noActiveSession
    case noCompletedSets
    case completedSetMissingFields(exercise: String, setOrder: Int)
    case completedSetMissingCardioFields(exercise: String, setOrder: Int)

    var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active session."
        case .noCompletedSets:
            return "Log at least one completed set before finishing."
        case .completedSetMissingFields(let exercise, let setOrder):
            return "Set \(setOrder) in \(exercise) is marked complete but missing weight/reps."
        case .completedSetMissingCardioFields(let exercise, let setOrder):
            return "Set \(setOrder) in \(exercise) is marked complete but missing cardio metrics."
        }
    }
}

struct SetPrefill: Sendable {
    var weight: Double?
    var reps: Int?
    var distance: Double?
    var seconds: Double?

    init(weight: Double? = nil, reps: Int? = nil, distance: Double? = nil, seconds: Double? = nil) {
        self.weight = weight
        self.reps = reps
        self.distance = distance
        self.seconds = seconds
    }
}

@MainActor
final class WorkoutSessionManager: ObservableObject {
    @Published var activeSession: ActiveWorkoutSession?
    @Published var isPresentingSessionUI: Bool = false

    private let fileName = "active_session_v1.json"
    private let draftStore = ActiveSessionDraftStore()
    private var persistTask: Task<Void, Never>?

    func restoreDraft() async {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(ActiveWorkoutSession.self, from: data)
            activeSession = decoded
        } catch {
            print("Failed to restore active session draft: \(error)")
        }
    }

    func startSession(
        name: String,
        gymProfileId: UUID?,
        preselectedExercise: String? = nil
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preselected = preselectedExercise?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = !trimmedName.isEmpty ? trimmedName
            : ((preselected?.isEmpty == false) ? (preselected ?? "Workout") : "Workout")

        var session = ActiveWorkoutSession(
            startedAt: Date(),
            name: sessionName,
            gymProfileId: gymProfileId
        )

        if let exercise = preselectedExercise?.trimmingCharacters(in: .whitespacesAndNewlines),
           !exercise.isEmpty {
            session.exercises = [
                ActiveExercise(name: exercise, sets: [ActiveSet(order: 1)])
            ]
        }

        activeSession = session
        schedulePersistDraft()
    }

    func updateSessionName(_ name: String) {
        guard var session = activeSession else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        session.name = trimmed
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func setGymProfileId(_ gymProfileId: UUID?) {
        guard var session = activeSession else { return }
        session.gymProfileId = gymProfileId
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func addExercise(name: String) {
        guard var session = activeSession else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = normalizedExerciseName(trimmed)
        let exists = session.exercises.contains { normalizedExerciseName($0.name) == normalized }
        guard !exists else { return }

        session.exercises.append(ActiveExercise(name: trimmed, sets: [ActiveSet(order: 1)]))
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func removeExercise(id: UUID) {
        guard var session = activeSession else { return }
        session.exercises.removeAll { $0.id == id }
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func addSet(exerciseId: UUID) {
        addSet(exerciseId: exerciseId, prefill: SetPrefill())
    }

    func addSet(exerciseId: UUID, prefill: SetPrefill) {
        guard var session = activeSession else { return }
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }

        let nextOrder = (session.exercises[exerciseIndex].sets.map(\.order).max() ?? 0) + 1
        let newSet = ActiveSet(
            order: nextOrder,
            weight: prefill.weight,
            reps: prefill.reps,
            distance: prefill.distance,
            seconds: prefill.seconds
        )
        session.exercises[exerciseIndex].sets.append(newSet)

        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func updateSet(exerciseId: UUID, setId: UUID, prefill: SetPrefill) {
        guard var session = activeSession else { return }
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        guard let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else { return }

        session.exercises[exerciseIndex].sets[setIndex].weight = prefill.weight
        session.exercises[exerciseIndex].sets[setIndex].reps = prefill.reps
        session.exercises[exerciseIndex].sets[setIndex].distance = prefill.distance
        session.exercises[exerciseIndex].sets[setIndex].seconds = prefill.seconds

        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func deleteSet(exerciseId: UUID, setId: UUID) {
        guard var session = activeSession else { return }
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        session.exercises[exerciseIndex].sets.removeAll { $0.id == setId }
        renumberSets(&session.exercises[exerciseIndex])
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func toggleSetComplete(exerciseId: UUID, setId: UUID) {
        guard var session = activeSession else { return }
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        guard let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else { return }

        var set = session.exercises[exerciseIndex].sets[setIndex]
        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? Date() : nil
        session.exercises[exerciseIndex].sets[setIndex] = set

        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func dismissMuscleGroupSuggestion(_ group: MuscleGroup) {
        guard var session = activeSession else { return }
        if !session.dismissedMuscleGroupSuggestions.contains(group.rawValue) {
            session.dismissedMuscleGroupSuggestions.append(group.rawValue)
            touch(&session)
            activeSession = session
            schedulePersistDraft()
        }
    }

    func clearAllMuscleGroupSuggestionDismissals() {
        guard var session = activeSession else { return }
        session.dismissedMuscleGroupSuggestions.removeAll()
        touch(&session)
        activeSession = session
        schedulePersistDraft()
    }

    func finish() async throws -> LoggedWorkout {
        guard let session = activeSession else { throw WorkoutSessionError.noActiveSession }

        var totalLoggedSets = 0
        var loggedExercises: [LoggedExercise] = []

        for exercise in session.exercises {
            let completedSets = exercise.sets
                .sorted { $0.order < $1.order }
                .filter { $0.isCompleted }

            let isCardio = isCardioExercise(exercise.name)
            var loggedSets: [LoggedSet] = []
            loggedSets.reserveCapacity(completedSets.count)

            // Validate + map completed sets.
            for set in completedSets {
                if isCardio {
                    let reps = max(set.reps ?? 0, 0)
                    let distance = max(set.distance ?? 0, 0)
                    let seconds = max(set.seconds ?? 0, 0)

                    let hasAnyMetric = reps > 0 || distance > 0 || seconds > 0
                    guard hasAnyMetric else {
                        throw WorkoutSessionError.completedSetMissingCardioFields(exercise: exercise.name, setOrder: set.order)
                    }

                    let weight = max(set.weight ?? 0, 0)
                    loggedSets.append(
                        LoggedSet(
                            order: set.order,
                            weight: weight,
                            reps: reps,
                            distance: distance > 0 ? distance : nil,
                            seconds: seconds > 0 ? seconds : nil
                        )
                    )
                } else {
                    guard let weight = set.weight,
                          let reps = set.reps,
                          weight >= 0,
                          reps > 0 else {
                        throw WorkoutSessionError.completedSetMissingFields(exercise: exercise.name, setOrder: set.order)
                    }
                    loggedSets.append(LoggedSet(order: set.order, weight: weight, reps: reps))
                }
            }

            if !loggedSets.isEmpty {
                totalLoggedSets += loggedSets.count
                loggedExercises.append(LoggedExercise(name: exercise.name, sets: loggedSets))
            }
        }

        guard totalLoggedSets > 0 else { throw WorkoutSessionError.noCompletedSets }

        let endedAt = Date()
        let workout = LoggedWorkout(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: endedAt,
            name: session.name,
            gymProfileId: session.gymProfileId,
            exercises: loggedExercises,
            createdAt: endedAt,
            updatedAt: endedAt
        )

        activeSession = nil
        isPresentingSessionUI = false
        await deleteDraftFile()
        return workout
    }

    func discardDraft() async {
        activeSession = nil
        isPresentingSessionUI = false
        await deleteDraftFile()
    }

    /// Forces an immediate draft write for lifecycle edges (e.g. app moving to background).
    /// This avoids data loss if the process is suspended before the debounce delay elapses.
    func saveImmediately() {
        persistTask?.cancel()
        persistTask = nil
        persistDraftSynchronously()
    }

    // MARK: - Draft Persistence

    private func schedulePersistDraft() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch {
                // Cancelled (or otherwise interrupted) debounced persist.
                return
            }
            guard let self else { return }
            guard !Task.isCancelled else { return }
            await self.persistDraft()
        }
    }

    private func persistDraft() async {
        guard let data = encodedDraftData() else { return }
        let url = fileURL()
        await draftStore.write(data, to: url)
    }

    private func persistDraftSynchronously() {
        guard let data = encodedDraftData() else { return }
        let url = fileURL()

        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            print("Failed to persist active session draft immediately: \(error)")
        }
    }

    private func encodedDraftData() -> Data? {
        guard let session = activeSession else { return nil }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            // Encode on MainActor to avoid Swift 6 actor-isolation violations.
            return try encoder.encode(session)
        } catch {
            print("Failed to encode active session draft: \(error)")
            return nil
        }
    }

    private func deleteDraftFile() async {
        persistTask?.cancel()
        persistTask = nil

        let url = fileURL()
        await draftStore.delete(at: url)
    }

    private func fileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }

    private func touch(_ session: inout ActiveWorkoutSession) {
        session.lastModifiedAt = Date()
    }

    private func renumberSets(_ exercise: inout ActiveExercise) {
        // Keep order stable and continuous after deletes.
        let sorted = exercise.sets.sorted { $0.order < $1.order }
        var updated: [ActiveSet] = []
        updated.reserveCapacity(sorted.count)
        for (index, set) in sorted.enumerated() {
            var copy = set
            copy.order = index + 1
            updated.append(copy)
        }
        exercise.sets = updated
    }

    private func normalizedExerciseName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isCardioExercise(_ name: String) -> Bool {
        ExerciseMetadataManager.shared
            .resolvedTags(for: name)
            .contains(where: { $0.builtInGroup == .cardio })
    }
}

private actor ActiveSessionDraftStore {
    func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            print("Failed to persist active session draft: \(error)")
        }
    }

    func delete(at url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("Failed to delete active session draft: \(error)")
        }
    }
}
