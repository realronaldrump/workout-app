import SwiftUI

struct BackupFilesView: View {
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @State private var files: [URL] = []
    @State private var selectedFile: URL?
    @State private var showingDeleteAlert = false
    
    var body: some View {
        ZStack {
            AdaptiveBackground()
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    if files.isEmpty {
                        ContentUnavailableView(
                            "No Backups",
                            systemImage: "icloud.slash",
                            description: Text("No backup files found in iCloud.")
                        )
                        .padding(.top, 50)
                    } else {
                        ForEach(files, id: \.self) { file in
                            BackupFileRow(file: file) {
                                selectedFile = file
                                showingDeleteAlert = true
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Backup Files")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            files = iCloudManager.listWorkoutFiles()
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        .alert("Delete File", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let file = selectedFile {
                    try? iCloudManager.deleteFile(at: file)
                    files.removeAll { $0 == file }
                }
            }
        } message: {
            Text("Are you sure you want to delete this backup file?")
        }
    }
}

struct BackupFileRow: View {
    let file: URL
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.lastPathComponent)
                    .font(Theme.Typography.condensed)
                    .tracking(-0.2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                   let fileSize = attributes[.size] as? Int,
                   let creationDate = attributes[.creationDate] as? Date {
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
                        Text("·")
                        Text(creationDate.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 2)
    }
}
