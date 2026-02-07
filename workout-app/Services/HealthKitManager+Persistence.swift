import Foundation

extension HealthKitManager {
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    private var dataFileURL: URL {
        getDocumentsDirectory().appendingPathComponent("health_data_store.json")
    }

    private var dailyDataFileURL: URL {
        getDocumentsDirectory().appendingPathComponent("daily_health_store.json")
    }

    func persistData() {
        let entries = Array(healthDataStore.values)
        let url = dataFileURL
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(entries)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                print("Failed to persist health data: \(error)")
            }
        }
    }

    func persistDailyHealthData() {
        let entries = Array(dailyHealthStore.values)
        let url = dailyDataFileURL
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(entries)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                print("Failed to persist daily health data: \(error)")
            }
        }
    }

    func loadPersistedData() {
        cleanupLegacyUserDefaults()
        do {
            guard FileManager.default.fileExists(atPath: dataFileURL.path) else { return }
            let data = try Data(contentsOf: dataFileURL)
            let healthDataArray = try JSONDecoder().decode([WorkoutHealthData].self, from: data)
            healthDataStore = Dictionary(uniqueKeysWithValues: healthDataArray.map { ($0.workoutId, $0) })
            print("Loaded \(healthDataStore.count) health records")
        } catch {
            print("Failed to load persisted health data: \(error)")
        }

        lastSyncDate = userDefaults.object(forKey: lastSyncKey) as? Date
    }

    func loadPersistedDailyHealthData() {
        cleanupLegacyUserDefaults()
        let storedVersion = userDefaults.integer(forKey: dailyHealthStoreVersionKey)
        if storedVersion < currentDailyHealthStoreVersion {
            // Daily sleep aggregation logic changed; discard old cached daily store to avoid showing inflated sleep.
            dailyHealthStore.removeAll()
            lastDailySyncDate = nil
            userDefaults.removeObject(forKey: lastDailySyncKey)

            do {
                if FileManager.default.fileExists(atPath: dailyDataFileURL.path) {
                    try FileManager.default.removeItem(at: dailyDataFileURL)
                    print("Deleted daily health data store file (version bump)")
                }
            } catch {
                print("Failed to delete daily health data file during version bump: \(error)")
            }

            userDefaults.set(currentDailyHealthStoreVersion, forKey: dailyHealthStoreVersionKey)
            return
        }

        do {
            guard FileManager.default.fileExists(atPath: dailyDataFileURL.path) else { return }
            let data = try Data(contentsOf: dailyDataFileURL)
            let dailyArray = try JSONDecoder().decode([DailyHealthData].self, from: data)
            dailyHealthStore = Dictionary(uniqueKeysWithValues: dailyArray.map { ($0.dayStart, $0) })
            print("Loaded \(dailyHealthStore.count) daily health records")
        } catch {
            print("Failed to load persisted daily health data: \(error)")
        }

        lastDailySyncDate = userDefaults.object(forKey: lastDailySyncKey) as? Date
    }

    /// Clears all health data from memory and disk
    func clearAllData() {
        // Clear memory
        healthDataStore.removeAll()
        lastSyncDate = nil
        syncProgress = 0
        syncedWorkoutsCount = 0
        syncError = nil
        dailyHealthStore.removeAll()
        lastDailySyncDate = nil
        dailySyncProgress = 0
        isDailySyncing = false

        // Clear persistence
        cleanupLegacyUserDefaults()
        userDefaults.removeObject(forKey: lastSyncKey)
        userDefaults.removeObject(forKey: lastDailySyncKey)

        do {
            if FileManager.default.fileExists(atPath: dataFileURL.path) {
                try FileManager.default.removeItem(at: dataFileURL)
                print("Deleted health data store file")
            }
            if FileManager.default.fileExists(atPath: dailyDataFileURL.path) {
                try FileManager.default.removeItem(at: dailyDataFileURL)
                print("Deleted daily health data store file")
            }
        } catch {
            print("Failed to delete health data file: \(error)")
        }
    }

    func cleanupLegacyUserDefaults() {
        if userDefaults.data(forKey: healthDataKey) != nil {
            userDefaults.removeObject(forKey: healthDataKey)
        }
        if userDefaults.data(forKey: dailyHealthDataKey) != nil {
            userDefaults.removeObject(forKey: dailyHealthDataKey)
        }
    }
}
