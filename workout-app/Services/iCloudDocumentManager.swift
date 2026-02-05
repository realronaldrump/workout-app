import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

class iCloudDocumentManager: ObservableObject {
    @Published var isDocumentPickerPresented = false
    @Published var importedData: Data?
    // We start in local-storage mode, then flip to iCloud if the container becomes available.
    @Published var isUsingLocalFallback = true
    @Published var isInitializing = true
    
    private var _documentsURL: URL?
    
    private var documentsURL: URL? {
        return _documentsURL ?? localDocumentsURL
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
        // Perform iCloud check on background thread to avoid blocking main
        let iCloudURL = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents")
        }.value
        
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
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: [.nameKey, .creationDateKey], options: .skipsHiddenFiles)
            return files.filter { $0.pathExtension == "csv" }
        } catch {
            print("Failed to list files: \(error)")
            return []
        }
    }
    
    func deleteFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
    
    func deleteAllWorkoutFiles() async {
        guard let containerURL = documentsURL else { return }

        await Task.detached(priority: .utility) {
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: containerURL,
                    includingPropertiesForKeys: [.nameKey],
                    options: .skipsHiddenFiles
                )
                for file in files where file.pathExtension == "csv" {
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
        }.value
        
        // Also clear imported data from memory if needed
        await MainActor.run {
            self.importedData = nil
        }
    }
}

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
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.commaSeparatedText], asCopy: true)
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
