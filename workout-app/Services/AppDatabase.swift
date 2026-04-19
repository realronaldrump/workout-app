import CoreData
import Foundation

nonisolated enum WorkoutStoreSource: String, Codable, Sendable {
    case imported
    case logged
}

nonisolated enum LegacyMigrationPlanStatus: Equatable, Sendable {
    case ready
    case notNeeded
    case alreadyCompleted
    case noMigratableRecords
}

nonisolated struct LegacyMigrationSummary: Equatable, Sendable {
    var importedWorkoutCount: Int
    var loggedWorkoutCount: Int
    var workoutIdentityCount: Int
    var annotationCount: Int
    var workoutHealthCount: Int
    var dailyHealthCount: Int
    var dailyCoverageCount: Int
    var gymProfileCount: Int
    var hasLegacySources: Bool
    var hasStoredV2Data: Bool
    var wasPreviouslyCompleted: Bool

    var workoutCount: Int { importedWorkoutCount + loggedWorkoutCount }

    var totalMigratableItems: Int {
        importedWorkoutCount +
        loggedWorkoutCount +
        workoutIdentityCount +
        annotationCount +
        workoutHealthCount +
        dailyHealthCount +
        dailyCoverageCount +
        gymProfileCount
    }

    var hasMigratableData: Bool {
        totalMigratableItems > 0
    }
}

nonisolated struct LegacyMigrationPlan: Equatable, Sendable {
    var status: LegacyMigrationPlanStatus
    var summary: LegacyMigrationSummary

    var shouldPresentWizard: Bool {
        switch status {
        case .ready, .noMigratableRecords:
            return true
        case .notNeeded, .alreadyCompleted:
            return false
        }
    }
}

nonisolated struct LegacyMigrationResult: Equatable, Sendable {
    var summary: LegacyMigrationSummary
    var migrated: Bool
}

nonisolated enum LegacyMigrationError: LocalizedError {
    case noMigratableRecords

    var errorDescription: String? {
        switch self {
        case .noMigratableRecords:
            return "Saved data files were found, but no records could be read from them."
        }
    }
}

nonisolated final class AppDatabase: @unchecked Sendable {
    static let shared = AppDatabase()

    private enum EntityName {
        static let workout = "WorkoutRecord"
        static let exercise = "WorkoutExerciseRecord"
        static let set = "WorkoutSetRecord"
        static let annotation = "WorkoutAnnotationRecord"
        static let identity = "WorkoutIdentityRecord"
        static let healthWorkout = "WorkoutHealthRecord"
        static let dailyHealth = "DailyHealthRecord"
        static let dailyCoverage = "DailyHealthCoverageRecord"
        static let gymProfile = "GymProfileRecord"
    }

    private static let storeName = "WorkoutAppStoreV2"
    private static let sqliteFileName = "WorkoutAppStoreV2.sqlite"
    private static let legacyStoreName = "WorkoutAppStore"
    private static let legacySqliteFileName = "WorkoutAppStore.sqlite"
    private static let legacyMigrationCompleteKey = "WorkoutAppStoreV2LegacyMigrationComplete.v2"
    private static let previousLegacyMigrationCompleteKey = "WorkoutAppStoreV2LegacyMigrationComplete"

    private let container: NSPersistentContainer
    private let inMemory: Bool

    init(inMemory: Bool = false) {
        self.inMemory = inMemory

        let model = Self.makeModel()
        container = NSPersistentContainer(name: Self.storeName, managedObjectModel: model)

        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else {
            let directory = Self.storeDirectory()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            description = NSPersistentStoreDescription(url: directory.appendingPathComponent(Self.sqliteFileName))
        }

        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load app database: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

    }

    // MARK: - Clean Store

    nonisolated func resetLocalStore() throws {
        try performWrite { context in
            for entityName in Self.allEntityNames {
                try self.deleteObjects(entityName: entityName, predicate: nil, in: context)
            }
        }
    }

    nonisolated static func removePersistentStoreFiles() {
        let directory = storeDirectory()
        let baseURL = directory.appendingPathComponent(sqliteFileName)
        let urls = [
            baseURL,
            URL(fileURLWithPath: baseURL.path + "-shm"),
            URL(fileURLWithPath: baseURL.path + "-wal")
        ]
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Legacy Migration

    nonisolated func legacyMigrationPlan() throws -> LegacyMigrationPlan {
        let userDefaults = UserDefaults.standard
        let snapshot = try Self.loadLegacySnapshot()
        let summary = Self.legacyMigrationSummary(
            for: snapshot,
            hasLegacySources: Self.hasLegacySources(),
            hasStoredV2Data: try hasStoredData(),
            wasPreviouslyCompleted: Self.isLegacyMigrationMarkedComplete(userDefaults: userDefaults)
        )

        if summary.wasPreviouslyCompleted {
            return LegacyMigrationPlan(status: .alreadyCompleted, summary: summary)
        }

        if summary.hasMigratableData {
            return LegacyMigrationPlan(status: .ready, summary: summary)
        }

        if summary.hasLegacySources {
            return LegacyMigrationPlan(status: .noMigratableRecords, summary: summary)
        }

        userDefaults.set(true, forKey: Self.legacyMigrationCompleteKey)
        return LegacyMigrationPlan(status: .notNeeded, summary: summary)
    }

    nonisolated func canSkipLegacyMigrationPresentation() -> Bool {
        let userDefaults = UserDefaults.standard
        if userDefaults.bool(forKey: Self.legacyMigrationCompleteKey) {
            return true
        }

        if userDefaults.bool(forKey: Self.previousLegacyMigrationCompleteKey),
           (try? hasStoredData()) == true {
            return true
        }

        return !Self.hasLegacySources()
    }

    nonisolated func performLegacyMigration() throws -> LegacyMigrationResult {
        let snapshot = try Self.loadLegacySnapshot()
        let summary = Self.legacyMigrationSummary(
            for: snapshot,
            hasLegacySources: Self.hasLegacySources(),
            hasStoredV2Data: try hasStoredData(),
            wasPreviouslyCompleted: Self.isLegacyMigrationMarkedComplete(userDefaults: .standard)
        )

        guard summary.hasMigratableData else {
            if !summary.hasLegacySources {
                UserDefaults.standard.set(true, forKey: Self.legacyMigrationCompleteKey)
                return LegacyMigrationResult(summary: summary, migrated: false)
            }
            throw LegacyMigrationError.noMigratableRecords
        }

        try importLegacySnapshot(snapshot)
        Self.removeLegacyFileStores()
        UserDefaults.standard.set(true, forKey: Self.legacyMigrationCompleteKey)

        return LegacyMigrationResult(summary: summary, migrated: true)
    }

    private nonisolated static func isLegacyMigrationMarkedComplete(userDefaults: UserDefaults) -> Bool {
        userDefaults.bool(forKey: legacyMigrationCompleteKey) ||
        userDefaults.bool(forKey: previousLegacyMigrationCompleteKey)
    }

    nonisolated func hasStoredData() throws -> Bool {
        try performRead { context in
            for entityName in Self.allEntityNames {
                let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                request.fetchLimit = 1
                if try context.count(for: request) > 0 {
                    return true
                }
            }
            return false
        }
    }

    private nonisolated func importLegacySnapshot(_ snapshot: LegacySnapshot) throws {
        if !snapshot.importedWorkouts.isEmpty {
            let merged = Self.mergeByID(
                current: try loadImportedWorkouts(),
                incoming: snapshot.importedWorkouts
            )
            .sorted { $0.date > $1.date }
            try saveImportedWorkouts(merged)
        }

        if !snapshot.loggedWorkouts.isEmpty {
            let merged = Self.mergeByID(
                current: try loadLoggedWorkouts(),
                incoming: snapshot.loggedWorkouts
            )
            .sorted { $0.startedAt > $1.startedAt }
            try replaceLoggedWorkouts(merged)
        }

        if !snapshot.workoutIdentities.isEmpty {
            var merged = snapshot.workoutIdentities
            merged.merge(try loadWorkoutIdentities()) { _, current in current }
            try mergeWorkoutIdentities(merged)
        }

        if !snapshot.annotations.isEmpty {
            let merged = Self.mergeAnnotations(
                current: try loadAnnotations(),
                incoming: snapshot.annotations
            )
            try replaceAnnotations(merged)
        }

        if !snapshot.workoutHealthData.isEmpty {
            let merged = Self.mergeWorkoutHealthData(
                current: try loadWorkoutHealthData(),
                incoming: snapshot.workoutHealthData
            )
            try saveWorkoutHealthData(merged)
        }

        if !snapshot.dailyHealthData.isEmpty {
            let merged = Self.mergeDailyHealthData(
                current: try loadDailyHealthData(),
                incoming: snapshot.dailyHealthData
            )
            try saveDailyHealthData(merged)
        }

        if !snapshot.dailyHealthCoverage.isEmpty {
            try saveDailyHealthCoverage(try loadDailyHealthCoverage().union(snapshot.dailyHealthCoverage))
        }

        if !snapshot.gymProfiles.isEmpty {
            let merged = Self.mergeByID(
                current: try loadGymProfiles(),
                incoming: snapshot.gymProfiles
            )
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            try saveGymProfiles(merged)
        }
    }

    // MARK: - Imported Workouts

    nonisolated func loadImportedWorkouts() throws -> [Workout] {
        try loadWorkouts(source: .imported)
    }

    nonisolated func saveImportedWorkouts(_ workouts: [Workout]) throws {
        try replaceWorkouts(source: .imported) { context in
            for workout in workouts {
                try self.insertWorkout(workout, source: .imported, in: context)
            }
        }
    }

    nonisolated func clearImportedWorkouts() throws {
        try clearWorkouts(source: .imported)
    }

    // MARK: - Logged Workouts

    nonisolated func loadLoggedWorkouts() throws -> [LoggedWorkout] {
        try performRead { context in
            let snapshots = try self.loadWorkoutSnapshots(source: .logged, in: context)
            return snapshots.compactMap(Self.loggedWorkout(from:))
        }
    }

    nonisolated func loadWorkouts(containingExerciseNamed exerciseName: String, range: DateInterval? = nil) throws -> [Workout] {
        let normalizedName = Self.normalizedName(exerciseName)
        guard !normalizedName.isEmpty else { return [] }

        return try performRead { context in
            let exerciseRequest = NSFetchRequest<NSDictionary>(entityName: EntityName.exercise)
            exerciseRequest.resultType = .dictionaryResultType
            exerciseRequest.propertiesToFetch = ["workoutId"]
            exerciseRequest.returnsDistinctResults = true
            exerciseRequest.predicate = NSPredicate(format: "normalizedName == %@", normalizedName)
            exerciseRequest.fetchBatchSize = 256

            let workoutIds = Set(try context.fetch(exerciseRequest).compactMap { row in
                row["workoutId"] as? String
            })
            guard !workoutIds.isEmpty else { return [] }

            let snapshots = try self.loadWorkoutSnapshots(
                workoutIds: Array(workoutIds),
                range: range,
                in: context
            )
            return snapshots.compactMap(Self.workout(from:))
        }
    }

    nonisolated func saveLoggedWorkout(_ workout: LoggedWorkout) throws {
        try performWrite { context in
            try self.deleteWorkout(id: workout.id, source: .logged, in: context)
            try self.insertLoggedWorkout(workout, in: context)
        }
    }

    nonisolated func replaceLoggedWorkouts(_ workouts: [LoggedWorkout]) throws {
        try replaceWorkouts(source: .logged) { context in
            for workout in workouts {
                try self.insertLoggedWorkout(workout, in: context)
            }
        }
    }

    nonisolated func deleteLoggedWorkout(id: UUID) throws {
        try performWrite { context in
            try self.deleteWorkout(id: id, source: .logged, in: context)
        }
    }

    nonisolated func clearLoggedWorkouts() throws {
        try clearWorkouts(source: .logged)
    }

    // MARK: - Annotations

    nonisolated func loadAnnotations() throws -> [WorkoutAnnotation] {
        try performRead { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.annotation)
            let objects = try context.fetch(request)
            return objects.compactMap { object in
                guard let workoutId = Self.uuidValue(object, "workoutId") else { return nil }
                return WorkoutAnnotation(
                    workoutId: workoutId,
                    gymProfileId: Self.uuidValue(object, "gymProfileId")
                )
            }
        }
    }

    nonisolated func replaceAnnotations(_ annotations: [WorkoutAnnotation]) throws {
        try performWrite { context in
            try self.deleteObjects(entityName: EntityName.annotation, predicate: nil, in: context)
            for annotation in annotations {
                let object = NSEntityDescription.insertNewObject(
                    forEntityName: EntityName.annotation,
                    into: context
                )
                object.setValue(annotation.workoutId.uuidString, forKey: "workoutId")
                object.setValue(annotation.gymProfileId?.uuidString, forKey: "gymProfileId")
                object.setValue(Date(), forKey: "updatedAt")
            }
        }
    }

    nonisolated func clearAnnotations() throws {
        try performWrite { context in
            try self.deleteObjects(entityName: EntityName.annotation, predicate: nil, in: context)
        }
    }

    // MARK: - Workout Identities

    nonisolated func loadWorkoutIdentities() throws -> [String: UUID] {
        try performRead { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.identity)
            let objects = try context.fetch(request)
            var result: [String: UUID] = [:]
            result.reserveCapacity(objects.count)
            for object in objects {
                guard let workoutKey = object.value(forKey: "workoutKey") as? String,
                      let workoutId = Self.uuidValue(object, "workoutId") else {
                    continue
                }
                result[workoutKey] = workoutId
            }
            return result
        }
    }

    nonisolated func mergeWorkoutIdentities(_ entries: [String: UUID]) throws {
        guard !entries.isEmpty else { return }
        try performWrite { context in
            for (workoutKey, workoutId) in entries {
                let object = try self.upsertObject(
                    entityName: EntityName.identity,
                    uniqueKey: "workoutKey",
                    value: workoutKey,
                    context: context
                )
                object.setValue(workoutKey, forKey: "workoutKey")
                object.setValue(workoutId.uuidString, forKey: "workoutId")
                object.setValue(Date(), forKey: "updatedAt")
            }
        }
    }

    nonisolated func clearWorkoutIdentities() throws {
        try performWrite { context in
            try self.deleteObjects(entityName: EntityName.identity, predicate: nil, in: context)
        }
    }

    // MARK: - Workout Health

    nonisolated func loadWorkoutHealthData() throws -> [WorkoutHealthData] {
        try fetchDecoded(
            entityName: EntityName.healthWorkout,
            sortDescriptors: [NSSortDescriptor(key: "workoutDate", ascending: false)]
        )
    }

    nonisolated func saveWorkoutHealthData(_ entries: [WorkoutHealthData]) throws {
        guard !entries.isEmpty else { return }
        try performWrite { context in
            for entry in entries {
                let object = try self.upsertObject(
                    entityName: EntityName.healthWorkout,
                    uniqueKey: "workoutId",
                    value: entry.workoutId.uuidString,
                    context: context
                )
                object.setValue(entry.workoutId.uuidString, forKey: "workoutId")
                object.setValue(entry.workoutDate, forKey: "workoutDate")
                object.setValue(entry.workoutStartTime, forKey: "workoutStartTime")
                object.setValue(entry.workoutEndTime, forKey: "workoutEndTime")
                object.setValue(Date(), forKey: "updatedAt")
                object.setValue(try Self.makeEncoder().encode(entry), forKey: "payload")
            }
        }
    }

    nonisolated func deleteWorkoutHealthData(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try performWrite { context in
            let predicate = NSPredicate(format: "workoutId IN %@", ids.map(\.uuidString))
            try self.deleteObjects(entityName: EntityName.healthWorkout, predicate: predicate, in: context)
        }
    }

    nonisolated func clearWorkoutHealthData() throws {
        try performWrite { context in
            try self.deleteObjects(entityName: EntityName.healthWorkout, predicate: nil, in: context)
        }
    }

    // MARK: - Daily Health

    nonisolated func loadDailyHealthData() throws -> [DailyHealthData] {
        try fetchDecoded(
            entityName: EntityName.dailyHealth,
            sortDescriptors: [NSSortDescriptor(key: "dayStart", ascending: true)]
        )
    }

    nonisolated func saveDailyHealthData(_ entries: [DailyHealthData]) throws {
        try performWrite { context in
            let incomingDays = Set(entries.map(\.dayStart))
            if incomingDays.isEmpty {
                try self.deleteObjects(entityName: EntityName.dailyHealth, predicate: nil, in: context)
                return
            }

            let existingRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.dailyHealth)
            let existingObjects = try context.fetch(existingRequest)
            for object in existingObjects {
                guard let dayStart = object.value(forKey: "dayStart") as? Date else { continue }
                if !incomingDays.contains(dayStart) {
                    context.delete(object)
                }
            }

            for entry in entries {
                let object = try self.upsertObject(
                    entityName: EntityName.dailyHealth,
                    uniqueKey: "dayStart",
                    value: entry.dayStart as NSDate,
                    context: context
                )
                object.setValue(entry.dayStart, forKey: "dayStart")
                object.setValue(Date(), forKey: "updatedAt")
                object.setValue(try Self.makeEncoder().encode(entry), forKey: "payload")
            }
        }
    }

    nonisolated func clearDailyHealthData() throws {
        try performWrite { context in
            try self.deleteObjects(entityName: EntityName.dailyHealth, predicate: nil, in: context)
        }
    }

    // MARK: - Daily Coverage

    nonisolated func loadDailyHealthCoverage() throws -> Set<Date> {
        try performRead { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.dailyCoverage)
            let objects = try context.fetch(request)
            return Set(objects.compactMap { $0.value(forKey: "dayStart") as? Date })
        }
    }

    nonisolated func saveDailyHealthCoverage(_ coveredDays: Set<Date>) throws {
        try performWrite { context in
            try self.deleteObjects(entityName: EntityName.dailyCoverage, predicate: nil, in: context)
            for day in coveredDays {
                let object = NSEntityDescription.insertNewObject(
                    forEntityName: EntityName.dailyCoverage,
                    into: context
                )
                object.setValue(day, forKey: "dayStart")
            }
        }
    }

    nonisolated func clearDailyHealthCoverage() throws {
        try performWrite { context in
            try self.deleteObjects(entityName: EntityName.dailyCoverage, predicate: nil, in: context)
        }
    }

    // MARK: - Gyms

    nonisolated func loadGymProfiles() throws -> [GymProfile] {
        try performRead { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.gymProfile)
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            let objects = try context.fetch(request)
            return objects.compactMap(Self.gymProfile(from:))
        }
    }

    nonisolated func saveGymProfiles(_ gyms: [GymProfile]) throws {
        try performWrite { context in
            let incomingIds = Set(gyms.map { $0.id.uuidString })
            if incomingIds.isEmpty {
                try self.deleteObjects(entityName: EntityName.gymProfile, predicate: nil, in: context)
                return
            }

            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.gymProfile)
            let objects = try context.fetch(request)
            for object in objects {
                guard let recordId = object.value(forKey: "recordId") as? String else { continue }
                if !incomingIds.contains(recordId) {
                    context.delete(object)
                }
            }

            for gym in gyms {
                let object = try self.upsertObject(
                    entityName: EntityName.gymProfile,
                    uniqueKey: "recordId",
                    value: gym.id.uuidString,
                    context: context
                )
                object.setValue(gym.id.uuidString, forKey: "recordId")
                object.setValue(gym.name, forKey: "name")
                object.setValue(gym.address, forKey: "address")
                object.setValue(gym.latitude.map(NSNumber.init(value:)), forKey: "latitude")
                object.setValue(gym.longitude.map(NSNumber.init(value:)), forKey: "longitude")
                object.setValue(gym.createdAt, forKey: "createdAt")
                object.setValue(gym.updatedAt, forKey: "updatedAt")
            }
        }
    }

    nonisolated func clearGymProfiles() throws {
        try performWrite { context in
            try self.deleteObjects(entityName: EntityName.gymProfile, predicate: nil, in: context)
        }
    }

    // MARK: - Workout Normalization

    private nonisolated func loadWorkouts(source: WorkoutStoreSource) throws -> [Workout] {
        try performRead { context in
            let snapshots = try self.loadWorkoutSnapshots(source: source, in: context)
            return snapshots.compactMap(Self.workout(from:))
        }
    }

    private nonisolated func replaceWorkouts(
        source: WorkoutStoreSource,
        insert: (NSManagedObjectContext) throws -> Void
    ) throws {
        try performWrite { context in
            try self.clearWorkouts(source: source, in: context)
            try insert(context)
        }
    }

    private nonisolated func clearWorkouts(source: WorkoutStoreSource) throws {
        try performWrite { context in
            try self.clearWorkouts(source: source, in: context)
        }
    }

    private nonisolated func clearWorkouts(
        source: WorkoutStoreSource,
        in context: NSManagedObjectContext
    ) throws {
        let sourcePredicate = NSPredicate(format: "source == %@", source.rawValue)
        try deleteObjects(entityName: EntityName.set, predicate: sourcePredicate, in: context)
        try deleteObjects(entityName: EntityName.exercise, predicate: sourcePredicate, in: context)
        try deleteObjects(entityName: EntityName.workout, predicate: sourcePredicate, in: context)
    }

    private nonisolated func deleteWorkout(
        id: UUID,
        source: WorkoutStoreSource,
        in context: NSManagedObjectContext
    ) throws {
        let predicate = NSPredicate(format: "workoutId == %@ AND source == %@", id.uuidString, source.rawValue)
        try deleteObjects(entityName: EntityName.set, predicate: predicate, in: context)
        try deleteObjects(entityName: EntityName.exercise, predicate: predicate, in: context)
        try deleteObjects(entityName: EntityName.workout, predicate: predicate, in: context)
    }

    private nonisolated func insertWorkout(
        _ workout: Workout,
        source: WorkoutStoreSource,
        in context: NSManagedObjectContext
    ) throws {
        let workoutObject = NSEntityDescription.insertNewObject(forEntityName: EntityName.workout, into: context)
        workoutObject.setValue(workout.id.uuidString, forKey: "workoutId")
        workoutObject.setValue(source.rawValue, forKey: "source")
        workoutObject.setValue(workout.date, forKey: "workoutDate")
        workoutObject.setValue(workout.name, forKey: "workoutName")
        workoutObject.setValue(workout.duration, forKey: "duration")
        workoutObject.setValue(Date(), forKey: "updatedAt")
        workoutObject.setValue(1, forKey: "schemaVersion")

        try insertExercises(workout.exercises, workout: workout, source: source, in: context)
    }

    private nonisolated func insertLoggedWorkout(
        _ workout: LoggedWorkout,
        in context: NSManagedObjectContext
    ) throws {
        let duration = Self.formatDuration(start: workout.startedAt, end: workout.endedAt)
        let workoutObject = NSEntityDescription.insertNewObject(forEntityName: EntityName.workout, into: context)
        workoutObject.setValue(workout.id.uuidString, forKey: "workoutId")
        workoutObject.setValue(WorkoutStoreSource.logged.rawValue, forKey: "source")
        workoutObject.setValue(workout.startedAt, forKey: "workoutDate")
        workoutObject.setValue(workout.name, forKey: "workoutName")
        workoutObject.setValue(duration, forKey: "duration")
        workoutObject.setValue(workout.endedAt, forKey: "endedAt")
        workoutObject.setValue(workout.gymProfileId?.uuidString, forKey: "gymProfileId")
        workoutObject.setValue(workout.createdAt, forKey: "createdAt")
        workoutObject.setValue(workout.updatedAt, forKey: "updatedAt")
        workoutObject.setValue(workout.schemaVersion, forKey: "schemaVersion")

        for (exerciseIndex, exercise) in workout.exercises.enumerated() {
            try insertExercise(
                exerciseId: exercise.id,
                workoutId: workout.id,
                source: .logged,
                name: exercise.name,
                order: exerciseIndex,
                in: context
            )

            for set in exercise.sets {
                insertSet(
                    SetStorageValues(
                        setId: set.id,
                        workoutId: workout.id,
                        exerciseId: exercise.id,
                        source: .logged,
                        date: workout.startedAt,
                        workoutName: workout.name,
                        duration: duration,
                        exerciseName: exercise.name,
                        setOrder: set.order,
                        weight: set.weight,
                        reps: set.reps,
                        distance: set.distance,
                        seconds: set.seconds
                    ),
                    in: context
                )
            }
        }
    }

    private nonisolated func insertExercises(
        _ exercises: [Exercise],
        workout: Workout,
        source: WorkoutStoreSource,
        in context: NSManagedObjectContext
    ) throws {
        for (exerciseIndex, exercise) in exercises.enumerated() {
            try insertExercise(
                exerciseId: exercise.id,
                workoutId: workout.id,
                source: source,
                name: exercise.name,
                order: exerciseIndex,
                in: context
            )

            for set in exercise.sets {
                insertSet(
                    SetStorageValues(
                        setId: set.id,
                        workoutId: workout.id,
                        exerciseId: exercise.id,
                        source: source,
                        date: set.date,
                        workoutName: set.workoutName,
                        duration: set.duration,
                        exerciseName: set.exerciseName,
                        setOrder: set.setOrder,
                        weight: set.weight,
                        reps: set.reps,
                        distance: set.distance,
                        seconds: set.seconds
                    ),
                    in: context
                )
            }
        }
    }

    private nonisolated func insertExercise(
        exerciseId: UUID,
        workoutId: UUID,
        source: WorkoutStoreSource,
        name: String,
        order: Int,
        in context: NSManagedObjectContext
    ) throws {
        let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.exercise, into: context)
        object.setValue(Self.exerciseRecordId(workoutId: workoutId, exerciseId: exerciseId), forKey: "exerciseRecordId")
        object.setValue(workoutId.uuidString, forKey: "workoutId")
        object.setValue(source.rawValue, forKey: "source")
        object.setValue(exerciseId.uuidString, forKey: "exerciseId")
        object.setValue(name, forKey: "exerciseName")
        object.setValue(Self.normalizedName(name), forKey: "normalizedName")
        object.setValue(order, forKey: "exerciseOrder")
    }

    private nonisolated func insertSet(_ values: SetStorageValues, in context: NSManagedObjectContext) {
        let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.set, into: context)
        object.setValue(
            Self.setRecordId(workoutId: values.workoutId, exerciseId: values.exerciseId, setId: values.setId),
            forKey: "setRecordId"
        )
        object.setValue(values.workoutId.uuidString, forKey: "workoutId")
        object.setValue(values.exerciseId.uuidString, forKey: "exerciseId")
        object.setValue(values.setId.uuidString, forKey: "setId")
        object.setValue(values.source.rawValue, forKey: "source")
        object.setValue(values.date, forKey: "setDate")
        object.setValue(values.workoutName, forKey: "workoutName")
        object.setValue(values.duration, forKey: "duration")
        object.setValue(values.exerciseName, forKey: "exerciseName")
        object.setValue(Self.normalizedName(values.exerciseName), forKey: "normalizedName")
        object.setValue(values.setOrder, forKey: "setOrder")
        object.setValue(values.weight, forKey: "weight")
        object.setValue(values.reps, forKey: "reps")
        object.setValue(values.distance.map(NSNumber.init(value:)), forKey: "distance")
        object.setValue(values.seconds.map(NSNumber.init(value:)), forKey: "seconds")
        object.setValue(values.weight * Double(values.reps), forKey: "volume")
    }

    private nonisolated func loadWorkoutSnapshots(
        source: WorkoutStoreSource,
        in context: NSManagedObjectContext
    ) throws -> [WorkoutSnapshot] {
        try loadWorkoutSnapshots(
            workoutPredicate: NSPredicate(format: "source == %@", source.rawValue),
            childPredicates: [NSPredicate(format: "source == %@", source.rawValue)],
            in: context
        )
    }

    private nonisolated func loadWorkoutSnapshots(
        workoutIds: [String],
        range: DateInterval?,
        in context: NSManagedObjectContext
    ) throws -> [WorkoutSnapshot] {
        guard !workoutIds.isEmpty else { return [] }

        var predicates = [NSPredicate(format: "workoutId IN %@", workoutIds)]
        if let range {
            predicates.append(
                NSPredicate(
                    format: "workoutDate >= %@ AND workoutDate < %@",
                    range.start as NSDate,
                    range.end as NSDate
                )
            )
        }

        return try loadWorkoutSnapshots(
            workoutPredicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
            childPredicates: [NSPredicate(format: "workoutId IN %@", workoutIds)],
            in: context
        )
    }

    private nonisolated func loadWorkoutSnapshots(
        workoutPredicate: NSPredicate,
        childPredicates: [NSPredicate],
        in context: NSManagedObjectContext
    ) throws -> [WorkoutSnapshot] {
        let workoutRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.workout)
        workoutRequest.predicate = workoutPredicate
        workoutRequest.sortDescriptors = [NSSortDescriptor(key: "workoutDate", ascending: false)]
        workoutRequest.fetchBatchSize = 128

        let workoutObjects = try context.fetch(workoutRequest)
        let workoutIds = workoutObjects.compactMap { $0.value(forKey: "workoutId") as? String }
        guard !workoutIds.isEmpty else { return [] }
        let childPredicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: childPredicates + [
                NSPredicate(format: "workoutId IN %@", workoutIds)
            ]
        )

        let exerciseRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.exercise)
        exerciseRequest.predicate = childPredicate
        exerciseRequest.sortDescriptors = [
            NSSortDescriptor(key: "workoutId", ascending: true),
            NSSortDescriptor(key: "exerciseOrder", ascending: true)
        ]
        exerciseRequest.fetchBatchSize = 512

        let setRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.set)
        setRequest.predicate = childPredicate
        setRequest.sortDescriptors = [
            NSSortDescriptor(key: "workoutId", ascending: true),
            NSSortDescriptor(key: "exerciseId", ascending: true),
            NSSortDescriptor(key: "setOrder", ascending: true),
            NSSortDescriptor(key: "setDate", ascending: true)
        ]
        setRequest.fetchBatchSize = 1024

        let exerciseObjects = try context.fetch(exerciseRequest)
        let setObjects = try context.fetch(setRequest)

        let exercisesByWorkout = Dictionary(grouping: exerciseObjects) {
            ($0.value(forKey: "workoutId") as? String) ?? ""
        }
        let setsByExerciseRecord = Dictionary(grouping: setObjects) { object in
            let workoutId = (object.value(forKey: "workoutId") as? String) ?? ""
            let exerciseId = (object.value(forKey: "exerciseId") as? String) ?? ""
            return "\(workoutId)|\(exerciseId)"
        }

        return workoutObjects.compactMap { workoutObject in
            guard let workoutIdString = workoutObject.value(forKey: "workoutId") as? String,
                  let workoutId = UUID(uuidString: workoutIdString),
                  let sourceRawValue = workoutObject.value(forKey: "source") as? String,
                  let source = WorkoutStoreSource(rawValue: sourceRawValue) else {
                return nil
            }

            let exercises = (exercisesByWorkout[workoutIdString] ?? []).compactMap { exerciseObject -> ExerciseSnapshot? in
                guard let exerciseIdString = exerciseObject.value(forKey: "exerciseId") as? String,
                      let exerciseId = UUID(uuidString: exerciseIdString),
                      let exerciseName = exerciseObject.value(forKey: "exerciseName") as? String else {
                    return nil
                }

                let setKey = "\(workoutIdString)|\(exerciseIdString)"
                let sets = (setsByExerciseRecord[setKey] ?? []).compactMap(Self.setSnapshot(from:))
                return ExerciseSnapshot(
                    id: exerciseId,
                    name: exerciseName,
                    order: Self.intValue(exerciseObject, "exerciseOrder"),
                    sets: sets
                )
            }

            return WorkoutSnapshot(
                id: workoutId,
                source: source,
                date: (workoutObject.value(forKey: "workoutDate") as? Date) ?? .distantPast,
                name: (workoutObject.value(forKey: "workoutName") as? String) ?? "Workout",
                duration: (workoutObject.value(forKey: "duration") as? String) ?? "",
                endedAt: workoutObject.value(forKey: "endedAt") as? Date,
                gymProfileId: Self.uuidValue(workoutObject, "gymProfileId"),
                createdAt: workoutObject.value(forKey: "createdAt") as? Date,
                updatedAt: (workoutObject.value(forKey: "updatedAt") as? Date) ?? Date(),
                schemaVersion: Self.intValue(workoutObject, "schemaVersion"),
                exercises: exercises.sorted { $0.order < $1.order }
            )
        }
    }

    private nonisolated static func workout(from snapshot: WorkoutSnapshot) -> Workout {
        Workout(
            id: snapshot.id,
            date: snapshot.date,
            name: snapshot.name,
            duration: snapshot.duration,
            exercises: snapshot.exercises.map { exercise in
                Exercise(
                    id: exercise.id,
                    name: exercise.name,
                    sets: exercise.sets.map { set in
                        var workoutSet = WorkoutSet(
                            date: set.date,
                            workoutName: set.workoutName,
                            duration: set.duration,
                            exerciseName: set.exerciseName,
                            setOrder: set.order,
                            weight: set.weight,
                            reps: set.reps,
                            distance: set.distance ?? 0,
                            seconds: set.seconds ?? 0
                        )
                        workoutSet.id = set.id
                        return workoutSet
                    }
                )
            }
        )
    }

    private nonisolated static func loggedWorkout(from snapshot: WorkoutSnapshot) -> LoggedWorkout? {
        guard snapshot.source == .logged else { return nil }
        return LoggedWorkout(
            id: snapshot.id,
            startedAt: snapshot.date,
            endedAt: snapshot.endedAt ?? snapshot.date,
            name: snapshot.name,
            gymProfileId: snapshot.gymProfileId,
            exercises: snapshot.exercises.map { exercise in
                LoggedExercise(
                    id: exercise.id,
                    name: exercise.name,
                    sets: exercise.sets.map { set in
                        LoggedSet(
                            id: set.id,
                            order: set.order,
                            weight: set.weight,
                            reps: set.reps,
                            distance: set.distance,
                            seconds: set.seconds
                        )
                    }
                )
            },
            createdAt: snapshot.createdAt ?? snapshot.updatedAt,
            updatedAt: snapshot.updatedAt,
            schemaVersion: snapshot.schemaVersion
        )
    }

    private nonisolated static func setSnapshot(from object: NSManagedObject) -> SetSnapshot? {
        guard let setId = uuidValue(object, "setId"),
              let date = object.value(forKey: "setDate") as? Date,
              let workoutName = object.value(forKey: "workoutName") as? String,
              let duration = object.value(forKey: "duration") as? String,
              let exerciseName = object.value(forKey: "exerciseName") as? String else {
            return nil
        }

        return SetSnapshot(
            id: setId,
            date: date,
            workoutName: workoutName,
            duration: duration,
            exerciseName: exerciseName,
            order: intValue(object, "setOrder"),
            weight: doubleValue(object, "weight"),
            reps: intValue(object, "reps"),
            distance: optionalDoubleValue(object, "distance"),
            seconds: optionalDoubleValue(object, "seconds")
        )
    }

    // MARK: - Helpers

    private nonisolated func fetchDecoded<T: Decodable>(
        entityName: String,
        sortDescriptors: [NSSortDescriptor]
    ) throws -> [T] {
        try performRead { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.sortDescriptors = sortDescriptors
            request.fetchBatchSize = 256
            let objects = try context.fetch(request)
            return try objects.compactMap { object in
                guard let payload = object.value(forKey: "payload") as? Data else { return nil }
                return try Self.makeDecoder().decode(T.self, from: payload)
            }
        }
    }

    private nonisolated func performRead<T>(_ work: (NSManagedObjectContext) throws -> T) throws -> T {
        let context = makeBackgroundContext()
        var result: Result<T, Error>!
        context.performAndWait {
            result = Result { try work(context) }
        }
        return try result.get()
    }

    private nonisolated func performWrite(_ work: (NSManagedObjectContext) throws -> Void) throws {
        let context = makeBackgroundContext()
        var result: Result<Void, Error>!
        context.performAndWait {
            result = Result {
                try work(context)
                if context.hasChanges {
                    try context.save()
                }
            }
        }
        return try result.get()
    }

    private nonisolated func makeBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        return context
    }

    private nonisolated func fetchObject(
        entityName: String,
        key: String,
        value: CVarArg,
        context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "%K == %@", key, value)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private nonisolated func upsertObject(
        entityName: String,
        uniqueKey: String,
        value: CVarArg,
        context: NSManagedObjectContext
    ) throws -> NSManagedObject {
        if let existing = try fetchObject(entityName: entityName, key: uniqueKey, value: value, context: context) {
            return existing
        }
        return NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
    }

    private nonisolated func deleteObjects(
        entityName: String,
        predicate: NSPredicate?,
        in context: NSManagedObjectContext
    ) throws {
        if inMemory {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = predicate
            request.includesPropertyValues = false
            let objects = try context.fetch(request)
            objects.forEach(context.delete)
            return
        }

        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.predicate = predicate
        let delete = NSBatchDeleteRequest(fetchRequest: request)
        delete.resultType = .resultTypeObjectIDs
        let result = try context.execute(delete) as? NSBatchDeleteResult
        if let deletedObjectIDs = result?.result as? [NSManagedObjectID], !deletedObjectIDs.isEmpty {
            let changes = [NSDeletedObjectsKey: deletedObjectIDs]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context, container.viewContext])
        }
    }

    private nonisolated static func gymProfile(from object: NSManagedObject) -> GymProfile? {
        guard let id = uuidValue(object, "recordId"),
              let name = object.value(forKey: "name") as? String,
              let createdAt = object.value(forKey: "createdAt") as? Date,
              let updatedAt = object.value(forKey: "updatedAt") as? Date else {
            return nil
        }

        return GymProfile(
            id: id,
            name: name,
            address: object.value(forKey: "address") as? String,
            latitude: optionalDoubleValue(object, "latitude"),
            longitude: optionalDoubleValue(object, "longitude"),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private nonisolated static func uuidValue(_ object: NSManagedObject, _ key: String) -> UUID? {
        guard let value = object.value(forKey: key) as? String else { return nil }
        return UUID(uuidString: value)
    }

    private nonisolated static func intValue(_ object: NSManagedObject, _ key: String) -> Int {
        if let value = object.value(forKey: key) as? Int {
            return value
        }
        if let value = object.value(forKey: key) as? NSNumber {
            return value.intValue
        }
        return 0
    }

    private nonisolated static func doubleValue(_ object: NSManagedObject, _ key: String) -> Double {
        if let value = object.value(forKey: key) as? Double {
            return value
        }
        if let value = object.value(forKey: key) as? NSNumber {
            return value.doubleValue
        }
        return 0
    }

    private nonisolated static func optionalDoubleValue(_ object: NSManagedObject, _ key: String) -> Double? {
        if let value = object.value(forKey: key) as? Double {
            return value
        }
        if let value = object.value(forKey: key) as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    private nonisolated static func exerciseRecordId(workoutId: UUID, exerciseId: UUID) -> String {
        "\(workoutId.uuidString)|\(exerciseId.uuidString)"
    }

    private nonisolated static func setRecordId(workoutId: UUID, exerciseId: UUID, setId: UUID) -> String {
        "\(workoutId.uuidString)|\(exerciseId.uuidString)|\(setId.uuidString)"
    }

    private nonisolated static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private nonisolated static func formatDuration(start: Date, end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        let minutes = Int(ceil(seconds / 60.0))
        if minutes >= 60 {
            let hours = minutes / 60
            let minutesRemainder = minutes % 60
            return minutesRemainder == 0 ? "\(hours)h" : "\(hours)h \(minutesRemainder)m"
        }
        return "\(minutes)m"
    }

    private nonisolated static func storeDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private nonisolated static var allEntityNames: [String] {
        [
            EntityName.set,
            EntityName.exercise,
            EntityName.workout,
            EntityName.annotation,
            EntityName.identity,
            EntityName.healthWorkout,
            EntityName.dailyHealth,
            EntityName.dailyCoverage,
            EntityName.gymProfile
        ]
    }

    private nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension AppDatabase {
    struct WorkoutSnapshot {
        let id: UUID
        let source: WorkoutStoreSource
        let date: Date
        let name: String
        let duration: String
        let endedAt: Date?
        let gymProfileId: UUID?
        let createdAt: Date?
        let updatedAt: Date
        let schemaVersion: Int
        let exercises: [ExerciseSnapshot]
    }

    struct ExerciseSnapshot {
        let id: UUID
        let name: String
        let order: Int
        let sets: [SetSnapshot]
    }

    struct SetSnapshot {
        let id: UUID
        let date: Date
        let workoutName: String
        let duration: String
        let exerciseName: String
        let order: Int
        let weight: Double
        let reps: Int
        let distance: Double?
        let seconds: Double?
    }

    struct SetStorageValues {
        let setId: UUID
        let workoutId: UUID
        let exerciseId: UUID
        let source: WorkoutStoreSource
        let date: Date
        let workoutName: String
        let duration: String
        let exerciseName: String
        let setOrder: Int
        let weight: Double
        let reps: Int
        let distance: Double?
        let seconds: Double?
    }

    nonisolated struct LegacySnapshot {
        var importedWorkouts: [Workout] = []
        var loggedWorkouts: [LoggedWorkout] = []
        var workoutIdentities: [String: UUID] = [:]
        var annotations: [WorkoutAnnotation] = []
        var workoutHealthData: [WorkoutHealthData] = []
        var dailyHealthData: [DailyHealthData] = []
        var dailyHealthCoverage: Set<Date> = []
        var gymProfiles: [GymProfile] = []

        nonisolated var isEmpty: Bool {
            importedWorkouts.isEmpty &&
            loggedWorkouts.isEmpty &&
            workoutIdentities.isEmpty &&
            annotations.isEmpty &&
            workoutHealthData.isEmpty &&
            dailyHealthData.isEmpty &&
            dailyHealthCoverage.isEmpty &&
            gymProfiles.isEmpty
        }

        nonisolated mutating func merge(_ other: LegacySnapshot) {
            importedWorkouts = AppDatabase.mergeByID(current: importedWorkouts, incoming: other.importedWorkouts)
            loggedWorkouts = AppDatabase.mergeByID(current: loggedWorkouts, incoming: other.loggedWorkouts)
            workoutIdentities.merge(other.workoutIdentities) { current, _ in current }
            annotations = AppDatabase.mergeAnnotations(current: annotations, incoming: other.annotations)
            workoutHealthData = AppDatabase.mergeWorkoutHealthData(
                current: workoutHealthData,
                incoming: other.workoutHealthData
            )
            dailyHealthData = AppDatabase.mergeDailyHealthData(
                current: dailyHealthData,
                incoming: other.dailyHealthData
            )
            dailyHealthCoverage.formUnion(other.dailyHealthCoverage)
            gymProfiles = AppDatabase.mergeByID(current: gymProfiles, incoming: other.gymProfiles)
        }
    }
}

// MARK: - Legacy Data Loading

private extension AppDatabase {
    nonisolated static func loadLegacySnapshot() throws -> LegacySnapshot {
        var snapshot = try loadLegacyDatabaseSnapshot()
        snapshot.merge(loadLegacyFileSnapshot())
        return snapshot
    }

    nonisolated static func legacyMigrationSummary(
        for snapshot: LegacySnapshot,
        hasLegacySources: Bool,
        hasStoredV2Data: Bool,
        wasPreviouslyCompleted: Bool
    ) -> LegacyMigrationSummary {
        LegacyMigrationSummary(
            importedWorkoutCount: snapshot.importedWorkouts.count,
            loggedWorkoutCount: snapshot.loggedWorkouts.count,
            workoutIdentityCount: snapshot.workoutIdentities.count,
            annotationCount: snapshot.annotations.count,
            workoutHealthCount: snapshot.workoutHealthData.count,
            dailyHealthCount: snapshot.dailyHealthData.count,
            dailyCoverageCount: snapshot.dailyHealthCoverage.count,
            gymProfileCount: snapshot.gymProfiles.count,
            hasLegacySources: hasLegacySources,
            hasStoredV2Data: hasStoredV2Data,
            wasPreviouslyCompleted: wasPreviouslyCompleted
        )
    }

    nonisolated static func loadLegacyDatabaseSnapshot() throws -> LegacySnapshot {
        let storeURL = storeDirectory().appendingPathComponent(legacySqliteFileName)
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return LegacySnapshot()
        }

        let legacyContainer = NSPersistentContainer(
            name: legacyStoreName,
            managedObjectModel: makeLegacyModel()
        )
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldAddStoreAsynchronously = false
        legacyContainer.persistentStoreDescriptions = [description]

        var loadError: Error?
        legacyContainer.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        let context = legacyContainer.newBackgroundContext()
        context.undoManager = nil
        var result: Result<LegacySnapshot, Error>!
        context.performAndWait {
            result = Result {
                LegacySnapshot(
                    importedWorkouts: try fetchLegacyDecoded(
                        Workout.self,
                        entityName: "ImportedWorkoutRecord",
                        sortDescriptors: [NSSortDescriptor(key: "workoutDate", ascending: false)],
                        in: context
                    ),
                    loggedWorkouts: try fetchLegacyDecoded(
                        LoggedWorkout.self,
                        entityName: "LoggedWorkoutRecord",
                        sortDescriptors: [NSSortDescriptor(key: "workoutDate", ascending: false)],
                        in: context
                    ),
                    workoutIdentities: try fetchLegacyWorkoutIdentities(in: context),
                    annotations: try fetchLegacyAnnotations(in: context),
                    workoutHealthData: try fetchLegacyDecoded(
                        WorkoutHealthData.self,
                        entityName: EntityName.healthWorkout,
                        sortDescriptors: [NSSortDescriptor(key: "workoutDate", ascending: false)],
                        in: context
                    ),
                    dailyHealthData: try fetchLegacyDecoded(
                        DailyHealthData.self,
                        entityName: EntityName.dailyHealth,
                        sortDescriptors: [NSSortDescriptor(key: "dayStart", ascending: true)],
                        in: context
                    ),
                    dailyHealthCoverage: try fetchLegacyDailyHealthCoverage(in: context),
                    gymProfiles: try fetchLegacyDecoded(
                        GymProfile.self,
                        entityName: EntityName.gymProfile,
                        sortDescriptors: [NSSortDescriptor(key: "updatedAt", ascending: false)],
                        in: context
                    )
                )
            }
        }
        return try result.get()
    }

    nonisolated static func loadLegacyFileSnapshot() -> LegacySnapshot {
        let documents = documentDirectory()
        var snapshot = LegacySnapshot()

        let isoDecoder = makeDecoder()
        let defaultDecoder = JSONDecoder()

        let loggedURL = documents.appendingPathComponent("logged_workouts_v1.json")
        let loggedWorkouts: [LoggedWorkout]? = decodeLegacyFile(loggedURL, decoder: isoDecoder)
        snapshot.loggedWorkouts = loggedWorkouts ?? []

        let gymsURL = documents.appendingPathComponent("gym_profiles.json")
        let gyms: [GymProfile]? = decodeLegacyFile(gymsURL, decoder: isoDecoder)
        snapshot.gymProfiles = gyms ?? []

        let annotationsURL = documents.appendingPathComponent("workout_annotations.json")
        let annotations: [WorkoutAnnotation]? = decodeLegacyFile(annotationsURL, decoder: defaultDecoder)
        snapshot.annotations = annotations?.filter { $0.gymProfileId != nil } ?? []

        let identitiesURL = documents.appendingPathComponent("workout_identity_map.json")
        let identityStrings: [String: String]? = decodeLegacyFile(identitiesURL, decoder: defaultDecoder)
        snapshot.workoutIdentities = identityStrings?.compactMapValues(UUID.init(uuidString:)) ?? [:]

        let workoutHealthURL = documents.appendingPathComponent("health_data_store.json")
        let workoutHealthData: [WorkoutHealthData]? = decodeLegacyFile(workoutHealthURL, decoder: defaultDecoder)
        snapshot.workoutHealthData = workoutHealthData ?? []

        let workoutHealthDirectory = documents.appendingPathComponent("health_data_store", isDirectory: true)
        snapshot.workoutHealthData = mergeWorkoutHealthData(
            current: snapshot.workoutHealthData,
            incoming: loadLegacyWorkoutHealthDirectory(workoutHealthDirectory, decoder: defaultDecoder)
        )

        let dailyHealthURL = documents.appendingPathComponent("daily_health_store.json")
        let dailyHealthData: [DailyHealthData]? = decodeLegacyFile(dailyHealthURL, decoder: defaultDecoder)
        snapshot.dailyHealthData = dailyHealthData ?? []

        let dailyCoverageURL = documents.appendingPathComponent("daily_health_coverage.json")
        let dailyCoverage: [Date]? = decodeLegacyFile(dailyCoverageURL, decoder: defaultDecoder)
        snapshot.dailyHealthCoverage = Set(dailyCoverage ?? [])

        return snapshot
    }

    nonisolated static func fetchLegacyDecoded<T: Decodable>(
        _ type: T.Type,
        entityName: String,
        sortDescriptors: [NSSortDescriptor],
        in context: NSManagedObjectContext
    ) throws -> [T] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.sortDescriptors = sortDescriptors
        request.fetchBatchSize = 256
        let objects = try context.fetch(request)
        return try objects.compactMap { object in
            guard let payload = object.value(forKey: "payload") as? Data else { return nil }
            return try makeDecoder().decode(type, from: payload)
        }
    }

    nonisolated static func fetchLegacyAnnotations(in context: NSManagedObjectContext) throws -> [WorkoutAnnotation] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.annotation)
        let objects = try context.fetch(request)
        return objects.compactMap { object in
            guard let workoutId = uuidValue(object, "workoutId") else { return nil }
            return WorkoutAnnotation(workoutId: workoutId, gymProfileId: uuidValue(object, "gymProfileId"))
        }
    }

    nonisolated static func fetchLegacyWorkoutIdentities(
        in context: NSManagedObjectContext
    ) throws -> [String: UUID] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.identity)
        let objects = try context.fetch(request)
        var result: [String: UUID] = [:]
        result.reserveCapacity(objects.count)
        for object in objects {
            guard let workoutKey = object.value(forKey: "workoutKey") as? String,
                  let workoutId = uuidValue(object, "workoutId") else {
                continue
            }
            result[workoutKey] = workoutId
        }
        return result
    }

    nonisolated static func fetchLegacyDailyHealthCoverage(in context: NSManagedObjectContext) throws -> Set<Date> {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.dailyCoverage)
        let objects = try context.fetch(request)
        return Set(objects.compactMap { $0.value(forKey: "dayStart") as? Date })
    }

    nonisolated static func decodeLegacyFile<T: Decodable>(_ url: URL, decoder: JSONDecoder) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Failed to decode legacy file \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    nonisolated static func loadLegacyWorkoutHealthDirectory(
        _ directory: URL,
        decoder: JSONDecoder
    ) -> [WorkoutHealthData] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
                .filter { $0.pathExtension == "json" }

            return fileURLs.compactMap { fileURL in
                decodeLegacyFile(fileURL, decoder: decoder)
            }
        } catch {
            print("Failed to list legacy health data directory: \(error)")
            return []
        }
    }

    nonisolated static func removeLegacyFileStores() {
        let documents = documentDirectory()
        let urls = [
            documents.appendingPathComponent("logged_workouts_v1.json"),
            documents.appendingPathComponent("gym_profiles.json"),
            documents.appendingPathComponent("workout_annotations.json"),
            documents.appendingPathComponent("workout_identity_map.json"),
            documents.appendingPathComponent("health_data_store.json"),
            documents.appendingPathComponent("daily_health_store.json"),
            documents.appendingPathComponent("daily_health_coverage.json")
        ]
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        let workoutHealthDirectory = documents.appendingPathComponent("health_data_store", isDirectory: true)
        if FileManager.default.fileExists(atPath: workoutHealthDirectory.path) {
            try? FileManager.default.removeItem(at: workoutHealthDirectory)
        }
    }

    nonisolated static func hasLegacySources() -> Bool {
        let storeURL = storeDirectory().appendingPathComponent(legacySqliteFileName)
        if FileManager.default.fileExists(atPath: storeURL.path) {
            return true
        }

        let documents = documentDirectory()
        let urls = [
            documents.appendingPathComponent("logged_workouts_v1.json"),
            documents.appendingPathComponent("gym_profiles.json"),
            documents.appendingPathComponent("workout_annotations.json"),
            documents.appendingPathComponent("workout_identity_map.json"),
            documents.appendingPathComponent("health_data_store.json"),
            documents.appendingPathComponent("daily_health_store.json"),
            documents.appendingPathComponent("daily_health_coverage.json"),
            documents.appendingPathComponent("health_data_store", isDirectory: true)
        ]
        return urls.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    nonisolated static func documentDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - Merge Helpers

private extension AppDatabase {
    nonisolated static func mergeByID<T: Identifiable>(current: [T], incoming: [T]) -> [T] where T.ID == UUID {
        var resultByID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        for item in current {
            resultByID[item.id] = item
        }
        return Array(resultByID.values)
    }

    nonisolated static func mergeAnnotations(
        current: [WorkoutAnnotation],
        incoming: [WorkoutAnnotation]
    ) -> [WorkoutAnnotation] {
        var resultByWorkoutID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.workoutId, $0) })
        for annotation in current {
            resultByWorkoutID[annotation.workoutId] = annotation
        }
        return Array(resultByWorkoutID.values)
    }

    nonisolated static func mergeWorkoutHealthData(
        current: [WorkoutHealthData],
        incoming: [WorkoutHealthData]
    ) -> [WorkoutHealthData] {
        var resultByWorkoutID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.workoutId, $0) })
        for entry in current {
            resultByWorkoutID[entry.workoutId] = entry
        }
        return Array(resultByWorkoutID.values).sorted { $0.workoutDate > $1.workoutDate }
    }

    nonisolated static func mergeDailyHealthData(
        current: [DailyHealthData],
        incoming: [DailyHealthData]
    ) -> [DailyHealthData] {
        var resultByDay = Dictionary(uniqueKeysWithValues: incoming.map { ($0.dayStart, $0) })
        for entry in current {
            resultByDay[entry.dayStart] = entry
        }
        return Array(resultByDay.values).sorted { $0.dayStart < $1.dayStart }
    }
}

// MARK: - Programmatic Core Data Model

private extension AppDatabase {
    enum AttributeSpec {
        case string(String)
        case optionalString(String)
        case date(String)
        case optionalDate(String)
        case int64(String)
        case double(String)
        case optionalDouble(String)
        case binary(String)

        nonisolated var name: String {
            switch self {
            case .string(let name),
                 .optionalString(let name),
                 .date(let name),
                 .optionalDate(let name),
                 .int64(let name),
                 .double(let name),
                 .optionalDouble(let name),
                 .binary(let name):
                return name
            }
        }
    }

    nonisolated static func makeLegacyModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            regularEntity(
                name: "ImportedWorkoutRecord",
                uniqueKey: "workoutId",
                attributes: [.string("workoutId"), .date("workoutDate"), .date("updatedAt"), .binary("payload")],
                indexes: ["workoutId", "workoutDate", "updatedAt"]
            ),
            regularEntity(
                name: "LoggedWorkoutRecord",
                uniqueKey: "workoutId",
                attributes: [.string("workoutId"), .date("workoutDate"), .date("updatedAt"), .binary("payload")],
                indexes: ["workoutId", "workoutDate", "updatedAt"]
            ),
            regularEntity(
                name: EntityName.annotation,
                uniqueKey: "workoutId",
                attributes: [.string("workoutId"), .optionalString("gymProfileId"), .date("updatedAt")],
                indexes: ["workoutId", "updatedAt"]
            ),
            regularEntity(
                name: EntityName.identity,
                uniqueKey: "workoutKey",
                attributes: [.string("workoutKey"), .string("workoutId"), .date("updatedAt")],
                indexes: ["workoutKey", "workoutId", "updatedAt"]
            ),
            regularEntity(
                name: EntityName.healthWorkout,
                uniqueKey: "workoutId",
                attributes: [.string("workoutId"), .date("workoutDate"), .date("updatedAt"), .binary("payload")],
                indexes: ["workoutId", "workoutDate", "updatedAt"]
            ),
            regularEntity(
                name: EntityName.dailyHealth,
                uniqueKey: "dayStart",
                attributes: [.date("dayStart"), .date("updatedAt"), .binary("payload")],
                indexes: ["dayStart", "updatedAt"]
            ),
            regularEntity(
                name: EntityName.dailyCoverage,
                uniqueKey: "dayStart",
                attributes: [.date("dayStart")],
                indexes: ["dayStart"]
            ),
            regularEntity(
                name: EntityName.gymProfile,
                uniqueKey: "recordId",
                attributes: [.string("recordId"), .date("updatedAt"), .binary("payload")],
                indexes: ["recordId", "updatedAt"]
            )
        ]
        return model
    }

    nonisolated static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            regularEntity(
                name: EntityName.workout,
                uniqueKey: "workoutId",
                attributes: [
                    .string("workoutId"),
                    .string("source"),
                    .date("workoutDate"),
                    .string("workoutName"),
                    .string("duration"),
                    .optionalDate("endedAt"),
                    .optionalString("gymProfileId"),
                    .optionalDate("createdAt"),
                    .date("updatedAt"),
                    .int64("schemaVersion")
                ],
                indexes: ["workoutId", "source", "workoutDate", "workoutName"]
            ),
            regularEntity(
                name: EntityName.exercise,
                uniqueKey: "exerciseRecordId",
                attributes: [
                    .string("exerciseRecordId"),
                    .string("workoutId"),
                    .string("source"),
                    .string("exerciseId"),
                    .string("exerciseName"),
                    .string("normalizedName"),
                    .int64("exerciseOrder")
                ],
                indexes: ["workoutId", "source", "exerciseId", "normalizedName", "exerciseOrder"]
            ),
            regularEntity(
                name: EntityName.set,
                uniqueKey: "setRecordId",
                attributes: [
                    .string("setRecordId"),
                    .string("workoutId"),
                    .string("exerciseId"),
                    .string("setId"),
                    .string("source"),
                    .date("setDate"),
                    .string("workoutName"),
                    .string("duration"),
                    .string("exerciseName"),
                    .string("normalizedName"),
                    .int64("setOrder"),
                    .double("weight"),
                    .int64("reps"),
                    .optionalDouble("distance"),
                    .optionalDouble("seconds"),
                    .double("volume")
                ],
                indexes: ["workoutId", "exerciseId", "setId", "source", "setDate", "normalizedName", "setOrder"]
            ),
            regularEntity(
                name: EntityName.annotation,
                uniqueKey: "workoutId",
                attributes: [.string("workoutId"), .optionalString("gymProfileId"), .date("updatedAt")],
                indexes: ["workoutId", "gymProfileId"]
            ),
            regularEntity(
                name: EntityName.identity,
                uniqueKey: "workoutKey",
                attributes: [.string("workoutKey"), .string("workoutId"), .date("updatedAt")],
                indexes: ["workoutKey", "workoutId"]
            ),
            regularEntity(
                name: EntityName.healthWorkout,
                uniqueKey: "workoutId",
                attributes: [
                    .string("workoutId"),
                    .date("workoutDate"),
                    .date("workoutStartTime"),
                    .date("workoutEndTime"),
                    .date("updatedAt"),
                    .binary("payload")
                ],
                indexes: ["workoutId", "workoutDate", "workoutStartTime", "workoutEndTime"]
            ),
            regularEntity(
                name: EntityName.dailyHealth,
                uniqueKey: "dayStart",
                attributes: [.date("dayStart"), .date("updatedAt"), .binary("payload")],
                indexes: ["dayStart"]
            ),
            regularEntity(
                name: EntityName.dailyCoverage,
                uniqueKey: "dayStart",
                attributes: [.date("dayStart")],
                indexes: ["dayStart"]
            ),
            regularEntity(
                name: EntityName.gymProfile,
                uniqueKey: "recordId",
                attributes: [
                    .string("recordId"),
                    .string("name"),
                    .optionalString("address"),
                    .optionalDouble("latitude"),
                    .optionalDouble("longitude"),
                    .date("createdAt"),
                    .date("updatedAt")
                ],
                indexes: ["recordId", "name", "updatedAt"]
            )
        ]
        return model
    }

    nonisolated static func regularEntity(
        name: String,
        uniqueKey: String,
        attributes: [AttributeSpec],
        indexes: [String]
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        let properties = attributes.map(attribute)
        entity.properties = properties
        entity.uniquenessConstraints = [[uniqueKey]]
        entity.indexes = indexDescriptions(for: indexes, properties: properties)
        return entity
    }

    nonisolated static func attribute(_ spec: AttributeSpec) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = spec.name

        switch spec {
        case .string:
            attribute.attributeType = .stringAttributeType
            attribute.isOptional = false
        case .optionalString:
            attribute.attributeType = .stringAttributeType
            attribute.isOptional = true
        case .date:
            attribute.attributeType = .dateAttributeType
            attribute.isOptional = false
        case .optionalDate:
            attribute.attributeType = .dateAttributeType
            attribute.isOptional = true
        case .int64:
            attribute.attributeType = .integer64AttributeType
            attribute.isOptional = false
            attribute.defaultValue = 0
        case .double:
            attribute.attributeType = .doubleAttributeType
            attribute.isOptional = false
            attribute.defaultValue = 0
        case .optionalDouble:
            attribute.attributeType = .doubleAttributeType
            attribute.isOptional = true
        case .binary:
            attribute.attributeType = .binaryDataAttributeType
            attribute.isOptional = false
            attribute.allowsExternalBinaryDataStorage = true
        }

        return attribute
    }

    nonisolated static func indexDescriptions(
        for names: [String],
        properties: [NSPropertyDescription]
    ) -> [NSFetchIndexDescription] {
        let propertiesByName = Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0) })
        return names.compactMap { propertyName in
            guard let property = propertiesByName[propertyName] else { return nil }
            let element = NSFetchIndexElementDescription(property: property, collationType: .binary)
            return NSFetchIndexDescription(name: "\(propertyName)Index", elements: [element])
        }
    }
}
