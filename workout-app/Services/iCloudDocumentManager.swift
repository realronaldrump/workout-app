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
                        try Self.migrateExportAndBackupFiles(from: localURL, to: iCloudURL)
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

    /// Deletes every physical copy represented by a single logical inventory row.
    /// Migration can leave the same filename in iCloud and local Documents; removing
    /// only the displayed (preferred) URL would allow the hidden copy to reappear.
    func deleteAllCopies(ofExportOrBackup url: URL) async throws {
        let directories = await storageSearchDirectories()
        guard !directories.isEmpty else { return }

        let fileName = url.lastPathComponent
        try await Task.detached(priority: .utility) { [directories, fileName] in
            _ = try Self.deleteExportAndBackupFileCopies(
                named: fileName,
                in: directories
            )
        }.value

        if fileName.hasPrefix("strong_workouts_") {
            importedData = nil
        }
    }

    func deleteAllWorkoutFiles() async throws {
        try await deleteAllStrongImportFiles()
    }

    /// Deletes only Strong source imports. Generated exports and native backups are preserved.
    func deleteAllStrongImportFiles() async throws {
        let directories = await storageSearchDirectories()
        guard !directories.isEmpty else { return }

        try await Task.detached(priority: .utility) { [directories] in
            _ = try Self.deleteStrongImportFiles(in: directories)
        }.value

        importedData = nil
    }

    func deleteAllExportAndBackupFiles() async throws {
        try await deleteFiles(matchingExtensions: ["csv", AppBackupService.backupFileExtension])
    }

    func countWorkoutFiles() async -> Int {
        await countStrongImportFiles()
    }

    /// Counts logical Strong imports once even when migration left a copy in both storage locations.
    func countStrongImportFiles() async -> Int {
        let directories = await storageSearchDirectories()
        guard !directories.isEmpty else { return 0 }

        return await Task.detached(priority: .utility) { [directories] in
            Self.countStrongImportFiles(in: directories)
        }.value
    }

    func countExportAndBackupFiles() async -> Int {
        await exportAndBackupFiles().count
    }

    /// Returns a unified inventory across the active and fallback storage directories.
    /// Files copied during migration are represented by the active-directory copy only.
    func exportAndBackupFiles() async -> [URL] {
        let directories = await storageSearchDirectories()
        guard !directories.isEmpty else { return [] }

        return await Task.detached(priority: .utility) { [directories] in
            Self.listExportAndBackupFiles(in: directories)
        }.value
    }

    private func deleteFiles(matchingExtensions extensions: Set<String>) async throws {
        let directories = await storageSearchDirectories()
        guard !directories.isEmpty else { return }

        let lowercasedExtensions = Set(extensions.map { $0.lowercased() })

        try await Task.detached(priority: .utility) { [directories, lowercasedExtensions] in
            var failures: [String] = []
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
                            failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                } catch {
                    failures.append("\(containerURL.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if !failures.isEmpty {
                throw ICloudFileDeletionError(failures: failures)
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

    /// Combines storage directories in priority order and collapses migrated copies by filename.
    nonisolated static func listExportAndBackupFiles(in directories: [URL]) -> [URL] {
        deduplicatedFiles(
            from: directories.flatMap { listExportAndBackupFiles(in: $0) }
        )
    }

    /// Strong imports are the canonical source the app auto-loads on launch.
    /// Exported CSVs share the same extension but may include partial ranges.
    nonisolated static func listStrongImportFiles(in directory: URL) -> [URL] {
        listWorkoutFiles(in: directory)
            .filter { $0.lastPathComponent.hasPrefix("strong_workouts_") }
    }

    nonisolated static func listStrongImportFiles(in directories: [URL]) -> [URL] {
        deduplicatedFiles(
            from: directories.flatMap { listStrongImportFiles(in: $0) }
        )
    }

    nonisolated static func countStrongImportFiles(in directories: [URL]) -> Int {
        listStrongImportFiles(in: directories).count
    }

    /// Deletes all physical copies of one logical export/backup inventory item.
    @discardableResult
    nonisolated static func deleteExportAndBackupFileCopies(
        named fileName: String,
        in directories: [URL]
    ) throws -> Int {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let allowedExtensions = ["csv", AppBackupService.backupFileExtension]
        guard allowedExtensions.contains(fileExtension) else { return 0 }

        var deletedCount = 0
        var failures: [String] = []

        for directory in directories {
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.nameKey],
                    options: .skipsHiddenFiles
                )
                for file in files where file.lastPathComponent == fileName {
                    do {
                        try FileManager.default.removeItem(at: file)
                        deletedCount += 1
                        print("Deleted file: \(file.lastPathComponent)")
                    } catch {
                        failures.append("\(file.path): \(error.localizedDescription)")
                    }
                }
            } catch {
                failures.append("\(directory.path): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            throw ICloudFileDeletionError(failures: failures)
        }
        return deletedCount
    }

    /// Deletes every physical Strong-import copy so a fallback copy cannot reappear later.
    @discardableResult
    nonisolated static func deleteStrongImportFiles(in directories: [URL]) throws -> Int {
        var deletedCount = 0
        var failures: [String] = []

        for directory in directories {
            for file in listStrongImportFiles(in: directory) {
                do {
                    try FileManager.default.removeItem(at: file)
                    deletedCount += 1
                    print("Deleted file: \(file.lastPathComponent)")
                } catch {
                    failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        if !failures.isEmpty {
            throw ICloudFileDeletionError(failures: failures)
        }
        return deletedCount
    }

    nonisolated static func latestBackupFile(in directories: [URL]) -> URL? {
        let files = deduplicatedFiles(
            from: directories.flatMap { listBackupFiles(in: $0) }
        )
        return listNewestFirst(files).first
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

    nonisolated static func writeFileAtomically(
        to fileURL: URL,
        protection: FileProtectionType = .complete,
        writer: (FileHandle) throws -> Void
    ) throws {
        try ensureDirectoryExists(at: fileURL.deletingLastPathComponent())

        let tempURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")

        let created = FileManager.default.createFile(
            atPath: tempURL.path,
            contents: nil,
            attributes: [.protectionKey: protection]
        )
        guard created else {
            throw CocoaError(.fileWriteUnknown)
        }

        let handle = try FileHandle(forWritingTo: tempURL)
        do {
            try writer(handle)
            try handle.close()

            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
            }

            try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: fileURL.path)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    nonisolated static func ensureDirectoryExists(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    nonisolated static func migrateWorkoutFiles(from sourceDirectory: URL, to destinationDirectory: URL) throws -> Int {
        try migrateFiles(
            listWorkoutFiles(in: sourceDirectory),
            from: sourceDirectory,
            to: destinationDirectory
        )
    }

    /// Migrates both CSV exports/imports and native backups when iCloud becomes available.
    @discardableResult
    nonisolated static func migrateExportAndBackupFiles(
        from sourceDirectory: URL,
        to destinationDirectory: URL
    ) throws -> Int {
        try migrateFiles(
            listExportAndBackupFiles(in: sourceDirectory),
            from: sourceDirectory,
            to: destinationDirectory
        )
    }

    private nonisolated static func migrateFiles(
        _ files: [URL],
        from sourceDirectory: URL,
        to destinationDirectory: URL
    ) throws -> Int {
        let sourcePath = sourceDirectory.standardizedFileURL.path
        let destinationPath = destinationDirectory.standardizedFileURL.path
        guard sourcePath != destinationPath else { return 0 }

        try ensureDirectoryExists(at: destinationDirectory)

        var migratedCount = 0
        for fileURL in files {
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
            let date1 = fileSortDate(url1)
            let date2 = fileSortDate(url2)
            if date1 != date2 {
                return date1 > date2
            }
            return url1.lastPathComponent.localizedStandardCompare(url2.lastPathComponent) == .orderedAscending
        }
    }

    private nonisolated static func deduplicatedFiles(from files: [URL]) -> [URL] {
        var seenFileNames = Set<String>()
        return files.filter { seenFileNames.insert($0.lastPathComponent).inserted }
    }

    private nonisolated static func fileSortDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate ?? values?.creationDate ?? .distantPast
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

nonisolated struct ICloudFileDeletionError: LocalizedError, Sendable {
    let failures: [String]

    var errorDescription: String? {
        let detail = failures.prefix(3).joined(separator: "\n")
        let remaining = max(failures.count - 3, 0)
        if remaining > 0 {
            return "Some files could not be deleted:\n\(detail)\n…and \(remaining) more."
        }
        return "Some files could not be deleted:\n\(detail)"
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
