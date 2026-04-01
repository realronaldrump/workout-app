import CoreData
import Foundation

nonisolated final class AppDatabase: @unchecked Sendable {
    static let shared = AppDatabase()

    private enum EntityName {
        static let importedWorkout = "ImportedWorkoutRecord"
        static let loggedWorkout = "LoggedWorkoutRecord"
        static let annotation = "WorkoutAnnotationRecord"
        static let identity = "WorkoutIdentityRecord"
        static let healthWorkout = "WorkoutHealthRecord"
        static let dailyHealth = "DailyHealthRecord"
        static let dailyCoverage = "DailyHealthCoverageRecord"
        static let gymProfile = "GymProfileRecord"
    }

    private let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "WorkoutAppStore", managedObjectModel: model)

        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let storeURL = directory.appendingPathComponent("WorkoutAppStore.sqlite")
            description = NSPersistentStoreDescription(url: storeURL)
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

    // MARK: - Imported Workouts

    nonisolated func loadImportedWorkouts() throws -> [Workout] {
        try fetchDecoded(
            entityName: EntityName.importedWorkout,
            sortDescriptors: [NSSortDescriptor(key: "workoutDate", ascending: false)]
        )
    }

    nonisolated func saveImportedWorkouts(_ workouts: [Workout]) throws {
        try performWrite { context in
            try self.deleteAllObjects(entityName: EntityName.importedWorkout, in: context)
            for workout in workouts {
                let object = NSEntityDescription.insertNewObject(
                    forEntityName: EntityName.importedWorkout,
                    into: context
                )
                object.setValue(workout.id.uuidString, forKey: "workoutId")
                object.setValue(workout.date, forKey: "workoutDate")
                object.setValue(Date(), forKey: "updatedAt")
                object.setValue(try Self.makeEncoder().encode(workout), forKey: "payload")
            }
        }
    }

    nonisolated func clearImportedWorkouts() throws {
        try performWrite { context in
            try self.deleteAllObjects(entityName: EntityName.importedWorkout, in: context)
        }
    }

    // MARK: - Logged Workouts

    nonisolated func loadLoggedWorkouts() throws -> [LoggedWorkout] {
        try fetchDecoded(
            entityName: EntityName.loggedWorkout,
            sortDescriptors: [NSSortDescriptor(key: "workoutDate", ascending: false)]
        )
    }

    nonisolated func saveLoggedWorkout(_ workout: LoggedWorkout) throws {
        try performWrite { context in
            let object = try self.upsertObject(
                entityName: EntityName.loggedWorkout,
                uniqueKey: "workoutId",
                value: workout.id.uuidString,
                context: context
            )
            object.setValue(workout.id.uuidString, forKey: "workoutId")
            object.setValue(workout.startedAt, forKey: "workoutDate")
            object.setValue(workout.updatedAt, forKey: "updatedAt")
            object.setValue(try Self.makeEncoder().encode(workout), forKey: "payload")
        }
    }

    nonisolated func replaceLoggedWorkouts(_ workouts: [LoggedWorkout]) throws {
        try performWrite { context in
            try self.deleteAllObjects(entityName: EntityName.loggedWorkout, in: context)
            for workout in workouts {
                let object = NSEntityDescription.insertNewObject(
                    forEntityName: EntityName.loggedWorkout,
                    into: context
                )
                object.setValue(workout.id.uuidString, forKey: "workoutId")
                object.setValue(workout.startedAt, forKey: "workoutDate")
                object.setValue(workout.updatedAt, forKey: "updatedAt")
                object.setValue(try Self.makeEncoder().encode(workout), forKey: "payload")
            }
        }
    }

    nonisolated func deleteLoggedWorkout(id: UUID) throws {
        try performWrite { context in
            if let object = try self.fetchObject(
                entityName: EntityName.loggedWorkout,
                key: "workoutId",
                value: id.uuidString,
                context: context
            ) {
                context.delete(object)
            }
        }
    }

    nonisolated func clearLoggedWorkouts() throws {
        try performWrite { context in
            try self.deleteAllObjects(entityName: EntityName.loggedWorkout, in: context)
        }
    }

    // MARK: - Annotations

    nonisolated func loadAnnotations() throws -> [WorkoutAnnotation] {
        try performRead { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.annotation)
            let objects = try context.fetch(request)
            return objects.compactMap { object in
                guard let workoutIdString = object.value(forKey: "workoutId") as? String,
                      let workoutId = UUID(uuidString: workoutIdString) else {
                    return nil
                }
                let gymIdString = object.value(forKey: "gymProfileId") as? String
                return WorkoutAnnotation(
                    workoutId: workoutId,
                    gymProfileId: gymIdString.flatMap(UUID.init(uuidString:))
                )
            }
        }
    }

    nonisolated func replaceAnnotations(_ annotations: [WorkoutAnnotation]) throws {
        try performWrite { context in
            try self.deleteAllObjects(entityName: EntityName.annotation, in: context)
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
            try self.deleteAllObjects(entityName: EntityName.annotation, in: context)
        }
    }

    // MARK: - Workout Identities

    nonisolated func loadWorkoutIdentities() throws -> [String: UUID] {
        try performRead { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.identity)
            let objects = try context.fetch(request)
            var result: [String: UUID] = [:]
            for object in objects {
                guard let workoutKey = object.value(forKey: "workoutKey") as? String,
                      let workoutIdString = object.value(forKey: "workoutId") as? String,
                      let workoutId = UUID(uuidString: workoutIdString) else {
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
            try self.deleteAllObjects(entityName: EntityName.identity, in: context)
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
                object.setValue(Date(), forKey: "updatedAt")
                object.setValue(try Self.makeEncoder().encode(entry), forKey: "payload")
            }
        }
    }

    nonisolated func deleteWorkoutHealthData(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try performWrite { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.healthWorkout)
            request.predicate = NSPredicate(format: "workoutId IN %@", ids.map(\.uuidString))
            let objects = try context.fetch(request)
            objects.forEach(context.delete)
        }
    }

    nonisolated func clearWorkoutHealthData() throws {
        try performWrite { context in
            try self.deleteAllObjects(entityName: EntityName.healthWorkout, in: context)
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
            try self.deleteAllObjects(entityName: EntityName.dailyHealth, in: context)
            for entry in entries {
                let object = NSEntityDescription.insertNewObject(
                    forEntityName: EntityName.dailyHealth,
                    into: context
                )
                object.setValue(entry.dayStart, forKey: "dayStart")
                object.setValue(Date(), forKey: "updatedAt")
                object.setValue(try Self.makeEncoder().encode(entry), forKey: "payload")
            }
        }
    }

    nonisolated func clearDailyHealthData() throws {
        try performWrite { context in
            try self.deleteAllObjects(entityName: EntityName.dailyHealth, in: context)
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
            try self.deleteAllObjects(entityName: EntityName.dailyCoverage, in: context)
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
            try self.deleteAllObjects(entityName: EntityName.dailyCoverage, in: context)
        }
    }

    // MARK: - Gyms

    nonisolated func loadGymProfiles() throws -> [GymProfile] {
        try fetchDecoded(
            entityName: EntityName.gymProfile,
            sortDescriptors: [NSSortDescriptor(key: "updatedAt", ascending: false)]
        )
    }

    nonisolated func saveGymProfiles(_ gyms: [GymProfile]) throws {
        try performWrite { context in
            try self.deleteAllObjects(entityName: EntityName.gymProfile, in: context)
            for gym in gyms {
                let object = NSEntityDescription.insertNewObject(
                    forEntityName: EntityName.gymProfile,
                    into: context
                )
                object.setValue(gym.id.uuidString, forKey: "recordId")
                object.setValue(Date(), forKey: "updatedAt")
                object.setValue(try Self.makeEncoder().encode(gym), forKey: "payload")
            }
        }
    }

    nonisolated func clearGymProfiles() throws {
        try performWrite { context in
            try self.deleteAllObjects(entityName: EntityName.gymProfile, in: context)
        }
    }

    // MARK: - Helpers

    private nonisolated func fetchDecoded<T: Decodable>(
        entityName: String,
        sortDescriptors: [NSSortDescriptor]
    ) throws -> [T] {
        try performRead { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.sortDescriptors = sortDescriptors
            let objects = try context.fetch(request)
            return try objects.compactMap { object in
                guard let payload = object.value(forKey: "payload") as? Data else { return nil }
                return try Self.makeDecoder().decode(T.self, from: payload)
            }
        }
    }

    private nonisolated func performRead<T>(_ work: (NSManagedObjectContext) throws -> T) throws -> T {
        var result: Result<T, Error>!
        container.viewContext.performAndWait {
            result = Result { try work(container.viewContext) }
        }
        return try result.get()
    }

    private nonisolated func performWrite(_ work: (NSManagedObjectContext) throws -> Void) throws {
        try performRead { context in
            try work(context)
            if context.hasChanges {
                try context.save()
            }
        }
    }

    private nonisolated func fetchObject(
        entityName: String,
        key: String,
        value: String,
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
        value: String,
        context: NSManagedObjectContext
    ) throws -> NSManagedObject {
        if let existing = try fetchObject(entityName: entityName, key: uniqueKey, value: value, context: context) {
            return existing
        }
        return NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
    }

    private nonisolated func deleteAllObjects(entityName: String, in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let delete = NSBatchDeleteRequest(fetchRequest: request)
        delete.resultType = .resultTypeObjectIDs
        let result = try context.execute(delete) as? NSBatchDeleteResult
        if let deletedObjectIDs = result?.result as? [NSManagedObjectID] {
            let changes = [NSDeletedObjectsKey: deletedObjectIDs]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        }
    }

    private nonisolated static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            blobEntity(
                name: EntityName.importedWorkout,
                uniqueKey: "workoutId",
                keyAttributes: [.string("workoutId"), .date("workoutDate"), .date("updatedAt"), .binary("payload")]
            ),
            blobEntity(
                name: EntityName.loggedWorkout,
                uniqueKey: "workoutId",
                keyAttributes: [.string("workoutId"), .date("workoutDate"), .date("updatedAt"), .binary("payload")]
            ),
            regularEntity(
                name: EntityName.annotation,
                uniqueKey: "workoutId",
                attributes: [.string("workoutId"), .optionalString("gymProfileId"), .date("updatedAt")]
            ),
            regularEntity(
                name: EntityName.identity,
                uniqueKey: "workoutKey",
                attributes: [.string("workoutKey"), .string("workoutId"), .date("updatedAt")]
            ),
            blobEntity(
                name: EntityName.healthWorkout,
                uniqueKey: "workoutId",
                keyAttributes: [.string("workoutId"), .date("workoutDate"), .date("updatedAt"), .binary("payload")]
            ),
            blobEntity(
                name: EntityName.dailyHealth,
                uniqueKey: "dayStart",
                keyAttributes: [.dateKey("dayStart"), .date("updatedAt"), .binary("payload")]
            ),
            regularEntity(
                name: EntityName.dailyCoverage,
                uniqueKey: "dayStart",
                attributes: [.dateKey("dayStart")]
            ),
            blobEntity(
                name: EntityName.gymProfile,
                uniqueKey: "recordId",
                keyAttributes: [.string("recordId"), .date("updatedAt"), .binary("payload")]
            )
        ]
        return model
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

    private enum AttributeSpec {
        case string(String)
        case optionalString(String)
        case date(String)
        case dateKey(String)
        case binary(String)

        var indexName: String? {
            switch self {
            case .string(let name):
                return name
            case .date(let name) where name == "workoutDate" || name == "updatedAt":
                return name
            case .dateKey(let name):
                return name
            case .optionalString, .date, .binary:
                return nil
            }
        }
    }

    private nonisolated static func blobEntity(
        name: String,
        uniqueKey: String,
        keyAttributes: [AttributeSpec]
    ) -> NSEntityDescription {
        regularEntity(name: name, uniqueKey: uniqueKey, attributes: keyAttributes)
    }

    private nonisolated static func regularEntity(
        name: String,
        uniqueKey: String,
        attributes: [AttributeSpec]
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        let properties = attributes.map(Self.attribute)
        entity.properties = properties
        entity.indexes = Self.indexDescriptions(for: attributes, properties: properties)
        entity.uniquenessConstraints = [[uniqueKey]]
        return entity
    }

    private nonisolated static func attribute(_ spec: AttributeSpec) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        switch spec {
        case .string(let name):
            attribute.name = name
            attribute.attributeType = .stringAttributeType
            attribute.isOptional = false
        case .optionalString(let name):
            attribute.name = name
            attribute.attributeType = .stringAttributeType
            attribute.isOptional = true
        case .date(let name):
            attribute.name = name
            attribute.attributeType = .dateAttributeType
            attribute.isOptional = false
        case .dateKey(let name):
            attribute.name = name
            attribute.attributeType = .dateAttributeType
            attribute.isOptional = false
        case .binary(let name):
            attribute.name = name
            attribute.attributeType = .binaryDataAttributeType
            attribute.isOptional = false
            attribute.allowsExternalBinaryDataStorage = true
        }
        return attribute
    }

    private nonisolated static func indexDescriptions(
        for attributes: [AttributeSpec],
        properties: [NSPropertyDescription]
    ) -> [NSFetchIndexDescription] {
        let indexedPropertyNames = attributes.compactMap { $0.indexName }
        guard !indexedPropertyNames.isEmpty else { return [] }

        let propertiesByName = Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0) })
        return indexedPropertyNames.compactMap { propertyName -> NSFetchIndexDescription? in
            guard let property = propertiesByName[propertyName] else { return nil }
            let element = NSFetchIndexElementDescription(property: property, collationType: .binary)
            return NSFetchIndexDescription(name: "\(propertyName)Index", elements: [element])
        }
    }
}
