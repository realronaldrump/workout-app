import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

class iCloudDocumentManager: ObservableObject {
    @Published var isDocumentPickerPresented = false
    @Published var importedData: Data?
    @Published var isUsingLocalFallback = false
    
    // Lazy property to determine the best available directory
    private lazy var documentsURL: URL? = {
        // Try iCloud first
        if let url = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
            print("Using iCloud container: \(url.path)")
            return url
        }
        
        // Fallback to local documents
        print("iCloud not available, falling back to local Documents directory")
        isUsingLocalFallback = true
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }()
    
    init() {
        setupContainer()
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
        try data.write(to: fileURL)
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
            
            do {
                let data = try Data(contentsOf: url)
                parent.importedData = data
                parent.onImport?(data)
            } catch {
                print("Failed to import file: \(error)")
            }
        }
    }
}
