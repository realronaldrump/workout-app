import Foundation

enum LegacyProgramCleanup {
    private static let cleanupFlagKey = "legacy_program_cleanup_v1"
    private static let legacyProgramStoreFileName = "program_store_v1.json"

    static func runIfNeeded(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard !userDefaults.bool(forKey: cleanupFlagKey) else { return }
        defer { userDefaults.set(true, forKey: cleanupFlagKey) }

        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let legacyFileURL = documentsDirectory.appendingPathComponent(legacyProgramStoreFileName)
        guard fileManager.fileExists(atPath: legacyFileURL.path) else { return }

        do {
            try fileManager.removeItem(at: legacyFileURL)
        } catch {
            print("Failed to delete legacy program store: \(error)")
        }
    }
}
