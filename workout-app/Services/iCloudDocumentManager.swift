import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// swiftlint:disable:next type_name
final class iCloudDocumentManager: ObservableObject {
    @Published var isDocumentPickerPresented = false
    @Published var importedData: Data?
    // We start in local-storage mode, then flip to iCloud if the container becomes available.
    @Published var isUsingLocalFallback = true
    @Published var isInitializing = true

    private var _documentsURL: URL?

    private var documentsURL: URL? {
        _documentsURL ?? localDocumentsURL
    }

    private var localDocumentsURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    init() {
        // Use local fallback immediately for safety
        _documentsURL = localDocumentsURL
        isUsingLocalFallback = true
        // Start async iCloud check
        Task { await initializeContainer() }
    }

    private func initializeContainer() async {
        let localURL = localDocumentsURL

        // Perform iCloud check on background thread to avoid blocking main
        let iCloudURL = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents")
        }.value

        if let iCloudURL {
            await Task.detached(priority: .utility) {
                do {
                    try Self.ensureDirectoryExists(at: iCloudURL)
                    if let localURL {
                        try Self.migrateWorkoutFiles(from: localURL, to: iCloudURL)
                    }
                } catch {
                    print("Failed to prepare iCloud directory: \(error)")
                }
            }.value
        }

        await MainActor.run {
            if let url = iCloudURL {
                _documentsURL = url
                print("Using iCloud container: \(url.path)")
                isUsingLocalFallback = false
            } else {
                print("iCloud not available, using local Documents directory")
                isUsingLocalFallback = true
            }
            setupContainer()
            isInitializing = false
        }
    }

    private func setupContainer() {
        guard let url = documentsURL else {
            print("Failed to resolve any documents directory")
            return
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                print("Created documents directory at: \(url.path)")
            } catch {
                print("Failed to create directory: \(error)")
            }
        }
    }

    func saveToiCloud(data: Data, fileName: String) throws {
        guard let containerURL = documentsURL else {
            throw iCloudError.containerNotAvailable
        }

        let fileURL = containerURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func loadFromiCloud(fileName: String) throws -> Data {
        guard let containerURL = documentsURL else {
            throw iCloudError.containerNotAvailable
        }

        let fileURL = containerURL.appendingPathComponent(fileName)
        return try Data(contentsOf: fileURL)
    }

    func listWorkoutFiles() -> [URL] {
        guard let containerURL = documentsURL else { return [] }

        return Self.listWorkoutFiles(in: containerURL)
    }

    func listBackupFiles() -> [URL] {
        guard let containerURL = documentsURL else { return [] }

        return Self.listBackupFiles(in: containerURL)
    }

    func deleteFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func deleteAllWorkoutFiles() async {
        await deleteFiles(matchingExtensions: ["csv"])
    }

    func deleteAllExportAndBackupFiles() async {
        await deleteFiles(matchingExtensions: ["csv", AppBackupService.backupFileExtension])
    }

    func countWorkoutFiles() async -> Int {
        await countFiles(matchingExtensions: ["csv"])
    }

    func countExportAndBackupFiles() async -> Int {
        await countFiles(matchingExtensions: ["csv", AppBackupService.backupFileExtension])
    }

    private func countFiles(matchingExtensions extensions: Set<String>) async -> Int {
        let directories = await storageSearchDirectories()
        guard !directories.isEmpty else { return 0 }

        let lowercasedExtensions = Set(extensions.map { $0.lowercased() })

        return await Task.detached(priority: .utility) { [directories, lowercasedExtensions] in
            var count = 0
            for containerURL in directories {
                do {
                    let files = try FileManager.default.contentsOfDirectory(
                        at: containerURL,
                        includingPropertiesForKeys: [.nameKey],
                        options: .skipsHiddenFiles
                    )
                    count += files.filter { lowercasedExtensions.contains($0.pathExtension.lowercased()) }.count
                } catch {
                    print("Failed to list files for count: \(error)")
                }
            }
            return count
        }.value
    }

    private func deleteFiles(matchingExtensions extensions: Set<String>) async {
        let directories = await storageSearchDirectories()
        guard !directories.isEmpty else { return }

        let lowercasedExtensions = Set(extensions.map { $0.lowercased() })

        await Task.detached(priority: .utility) { [directories, lowercasedExtensions] in
            for containerURL in directories {
                do {
                    let files = try FileManager.default.contentsOfDirectory(
                        at: containerURL,
                        includingPropertiesForKeys: [.nameKey],
                        options: .skipsHiddenFiles
                    )
                    for file in files where lowercasedExtensions.contains(file.pathExtension.lowercased()) {
                        do {
                            try FileManager.default.removeItem(at: file)
                            print("Deleted file: \(file.lastPathComponent)")
                        } catch {
                            print("Failed to delete file \(file.lastPathComponent): \(error)")
                        }
                    }
                } catch {
                    print("Failed to list files for deletion: \(error)")
                }
            }
        }.value

        // Also clear imported data from memory if needed
        await MainActor.run {
            importedData = nil
        }
    }

    /// Snapshot the current storage location for use from background tasks.
    /// This avoids doing file I/O on the main actor when `iCloudDocumentManager` is main-actor isolated via SwiftUI.
    @MainActor
    func storageSnapshot() -> (url: URL?, isUsingLocalFallback: Bool) {
        (documentsURL, isUsingLocalFallback)
    }

    @MainActor
    func awaitStorageInitialization() async {
        while isInitializing {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor
    func initializedStorageSnapshot() async -> (url: URL?, isUsingLocalFallback: Bool) {
        await awaitStorageInitialization()
        return storageSnapshot()
    }

    @MainActor
    func storageSearchDirectories() async -> [URL] {
        await awaitStorageInitialization()

        var results: [URL] = []
        var seen = Set<String>()

        for url in [documentsURL, localDocumentsURL].compactMap({ $0 }) {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                results.append(url)
            }
        }

        return results
    }

    nonisolated static func listWorkoutFiles(in directory: URL) -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.nameKey, .creationDateKey],
                options: .skipsHiddenFiles
            )
            return files.filter { $0.pathExtension.lowercased() == "csv" }
        } catch {
            print("Failed to list files: \(error)")
            return []
        }
    }

    nonisolated static func listBackupFiles(in directory: URL) -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.nameKey, .creationDateKey],
                options: .skipsHiddenFiles
            )
            return files.filter { $0.pathExtension.lowercased() == AppBackupService.backupFileExtension }
        } catch {
            print("Failed to list backup files: \(error)")
            return []
        }
    }

    nonisolated static func listExportAndBackupFiles(in directory: URL) -> [URL] {
        listWorkoutFiles(in: directory) + listBackupFiles(in: directory)
    }

    /// Strong imports are the canonical source the app auto-loads on launch.
    /// Exported CSVs share the same extension but may include partial ranges.
    nonisolated static func listStrongImportFiles(in directory: URL) -> [URL] {
        listWorkoutFiles(in: directory)
            .filter { $0.lastPathComponent.hasPrefix("strong_workouts_") }
    }

    nonisolated static func latestBackupFile(in directories: [URL]) -> URL? {
        for directory in directories {
            let files = listNewestFirst(listBackupFiles(in: directory))
            if let latest = files.first {
                return latest
            }
        }

        return nil
    }

    nonisolated static func saveWorkoutFile(data: Data, in directory: URL, fileName: String) throws {
        try ensureDirectoryExists(at: directory)
        let fileURL = directory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    nonisolated static func saveBackupFile(data: Data, in directory: URL, fileName: String) throws {
        try ensureDirectoryExists(at: directory)
        let fileURL = directory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    nonisolated static func ensureDirectoryExists(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    nonisolated static func migrateWorkoutFiles(from sourceDirectory: URL, to destinationDirectory: URL) throws -> Int {
        let sourcePath = sourceDirectory.standardizedFileURL.path
        let destinationPath = destinationDirectory.standardizedFileURL.path
        guard sourcePath != destinationPath else { return 0 }

        try ensureDirectoryExists(at: destinationDirectory)

        var migratedCount = 0
        for fileURL in listWorkoutFiles(in: sourceDirectory) {
            let destinationURL = destinationDirectory.appendingPathComponent(fileURL.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destinationURL.path) else { continue }

            do {
                try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                migratedCount += 1
            } catch {
                print("Failed to migrate file \(fileURL.lastPathComponent): \(error)")
            }
        }

        return migratedCount
    }

    private nonisolated static func listNewestFirst(_ files: [URL]) -> [URL] {
        files.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 > date2
        }
    }
}

// swiftlint:disable:next type_name
enum iCloudError: LocalizedError {
    case containerNotAvailable

    var errorDescription: String? {
        switch self {
        case .containerNotAvailable:
            return "Storage container is not available."
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var importedData: Data?
    var onImport: ((Data) -> Void)?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.commaSeparatedText, UTType.json, UTType.data],
            asCopy: true
        )
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            let hasAccess = url.startAccessingSecurityScopedResource()
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let data = try Data(contentsOf: url)
                    DispatchQueue.main.async {
                        self.parent.importedData = data
                        self.parent.onImport?(data)
                    }
                } catch {
                    print("Failed to import file: \(error)")
                }
            }
        }
    }
}
