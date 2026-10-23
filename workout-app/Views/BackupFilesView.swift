import SwiftUI

struct BackupFilesView: View {
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @State private var sections: [BackupFileSection] = []
    @State private var selectedFile: URL?
    @State private var showingDeleteAlert = false
    @State private var deletionErrorMessage: String?
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var loadRevision = UUID()

    var body: some View {
        ZStack {
            AdaptiveBackground()
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    if isDeleting {
                        ProgressView("Deleting file…")
                            .frame(maxWidth: .infinity)
                    }
                    if isLoading {
                        ProgressView("Loading saved files…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xxl)
                    } else if sections.isEmpty {
                        EmptyStateCard(
                            icon: "icloud.slash",
                            tint: Theme.Colors.textTertiary,
                            title: "No backup files",
                            message: "Create a backup from Settings > Export."
                        )
                        .padding(.top, 50)
                    } else {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                BackupFileSectionHeader(section: section)

                                LazyVStack(spacing: Theme.Spacing.sm) {
                                    ForEach(section.files) { file in
                                        BackupFileRow(file: file) {
                                            selectedFile = file.url
                                            showingDeleteAlert = true
                                        }
                                        .disabled(isDeleting)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
                .contentColumn()
            }
            .refreshable { await loadFiles() }
        }
        .navigationTitle("Backup files")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadFiles()
        }
        .alert("Delete file", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let file = selectedFile {
                    Task {
                        await deleteFileAndCopies(file)
                    }
                }
            }
        } message: {
            Text("Delete \(selectedFile?.lastPathComponent ?? "this file") and its local and iCloud copies? This cannot be undone. Your workouts in the app will remain.")
        }
        .alert(
            "Could not delete file",
            isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        deletionErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionErrorMessage ?? "The file could not be deleted. Try again.")
        }
    }

    @MainActor
    private func loadFiles(allowDuringDeletion: Bool = false) async {
        guard !isDeleting || allowDuringDeletion else { return }
        let revision = UUID()
        loadRevision = revision
        if sections.isEmpty { isLoading = true }
        defer {
            if loadRevision == revision { isLoading = false }
        }

        let files = await iCloudManager.exportAndBackupFiles()
        let loadedSections = await Task.detached(priority: .userInitiated) { [files] in
            return BackupFileSection.sections(from: files)
        }.value
        guard loadRevision == revision, !Task.isCancelled else { return }
        sections = loadedSections
    }

    private func removeFile(_ file: URL) {
        sections = BackupFileSection.sections(
            from: sections
                .flatMap(\.files)
                .map(\.url)
                .filter { $0.lastPathComponent != file.lastPathComponent }
        )
    }

    @MainActor
    private func deleteFileAndCopies(_ file: URL) async {
        guard !isDeleting else { return }
        isDeleting = true
        // Invalidate a refresh that captured the inventory before deletion began.
        loadRevision = UUID()
        isLoading = false
        defer { isDeleting = false }
        do {
            try await iCloudManager.deleteAllCopies(ofExportOrBackup: file)
            removeFile(file)
            selectedFile = nil
        } catch {
            // A partial failure can still remove one physical copy. Reload so the
            // inventory accurately reflects whatever remains before showing the error.
            await loadFiles(allowDuringDeletion: true)
            selectedFile = nil
            deletionErrorMessage = error.localizedDescription
        }
    }
}

struct BackupFileRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let file: BackupFileEntry
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(file.fileName)
                .font(Theme.Typography.condensed)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)

            if !file.detailText.isEmpty {
                Text(file.detailText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Theme.Spacing.md) {
                ShareLink(item: file.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(Theme.Typography.captionBold)
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                }
                .tint(Theme.Colors.accent)
                .accessibilityLabel("Share \(file.fileName)")

                Spacer(minLength: 0)

                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.error)
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(file.fileName)")
                .accessibilityHint("Opens a confirmation before deleting this file and its copies")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

struct BackupFileSectionHeader: View {
    let section: BackupFileSection

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(section.title)
                .sectionHeaderStyle()

            Spacer()

            Text(section.countText)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.Colors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.sm)
    }
}

nonisolated struct BackupFileSection: Identifiable, Equatable {
    let kind: BackupFileKind
    let files: [BackupFileEntry]

    var id: BackupFileKind { kind }
    var title: String { kind.sectionTitle }

    var countText: String {
        "\(files.count) \(files.count == 1 ? "file" : "files")"
    }

    static func sections(from urls: [URL]) -> [BackupFileSection] {
        let grouped = Dictionary(grouping: urls.map(BackupFileEntry.init(url:)), by: \.kind)

        return BackupFileKind.allCases.compactMap { kind in
            guard let files = grouped[kind]?.sorted(by: BackupFileEntry.newestFirst),
                  !files.isEmpty else {
                return nil
            }

            return BackupFileSection(kind: kind, files: files)
        }
    }
}

nonisolated struct BackupFileEntry: Identifiable, Equatable {
    let url: URL
    let kind: BackupFileKind
    let createdAt: Date?
    let modifiedAt: Date?
    let fileSize: Int64?
    let sortDate: Date

    var id: URL { url }
    var fileName: String { url.lastPathComponent }

    var detailText: String {
        var details: [String] = []

        if let fileSize {
            details.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }

        if sortDate > .distantPast {
            details.append("Saved \(sortDate.formatted(date: .abbreviated, time: .shortened))")
        }

        return details.joined(separator: ". ")
    }

    init(url: URL) {
        self.url = url
        self.kind = BackupFileKind(fileName: url.lastPathComponent)

        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
        let size = values?.fileSize.map(Int64.init)
        let embeddedDate = BackupFileDateParser.embeddedDate(fileName: url.lastPathComponent, kind: kind)
        let fallbackDate = values?.contentModificationDate ?? values?.creationDate ?? .distantPast

        self.createdAt = values?.creationDate
        self.modifiedAt = values?.contentModificationDate
        self.fileSize = size
        self.sortDate = embeddedDate ?? fallbackDate
    }

    static func newestFirst(_ lhs: BackupFileEntry, _ rhs: BackupFileEntry) -> Bool {
        if lhs.sortDate != rhs.sortDate {
            return lhs.sortDate > rhs.sortDate
        }

        return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
    }
}

nonisolated enum BackupFileKind: Int, CaseIterable {
    case fullBackup
    case strongImport
    case workoutExport
    case exerciseList
    case exerciseHistory
    case muscleGroup
    case workoutDates
    case healthDaily
    case healthWorkout
    case healthMetricSamples
    case otherCSV

    init(fileName: String) {
        let lowercased = fileName.lowercased()

        if lowercased.hasSuffix(".\(AppBackupService.backupFileExtension)") {
            self = .fullBackup
        } else if lowercased.hasPrefix("strong_workouts") {
            self = .strongImport
        } else if lowercased.hasPrefix("workout_export_") {
            self = .workoutExport
        } else if lowercased.hasPrefix("exercise_export_") {
            self = .exerciseList
        } else if lowercased.hasPrefix("exercise_history_") {
            self = .exerciseHistory
        } else if lowercased.hasPrefix("muscle_group_export_") {
            self = .muscleGroup
        } else if lowercased.hasPrefix("workout_dates_") {
            self = .workoutDates
        } else if lowercased.hasPrefix("health_daily_") {
            self = .healthDaily
        } else if lowercased.hasPrefix("health_workout_summary_") {
            self = .healthWorkout
        } else if lowercased.hasPrefix("health_metric_samples_") {
            self = .healthMetricSamples
        } else {
            self = .otherCSV
        }
    }

    var sectionTitle: String {
        switch self {
        case .fullBackup:
            return "Full backups"
        case .strongImport:
            return "Strong imports"
        case .workoutExport:
            return "Workout exports"
        case .exerciseList:
            return "Exercise lists"
        case .exerciseHistory:
            return "Exercise history"
        case .muscleGroup:
            return "Muscle groups"
        case .workoutDates:
            return "Workout dates"
        case .healthDaily:
            return "Health daily"
        case .healthWorkout:
            return "Health workouts"
        case .healthMetricSamples:
            return "Health metric samples"
        case .otherCSV:
            return "Other CSV files"
        }
    }
}

nonisolated enum BackupFileDateParser {
    static func embeddedDate(fileName: String, kind: BackupFileKind) -> Date? {
        switch kind {
        case .fullBackup:
            return fullBackupDate(fileName: fileName)
        case .strongImport:
            return trailingEpochDate(fileName: fileName)
        case .workoutExport,
             .exerciseList,
             .exerciseHistory,
             .muscleGroup,
             .workoutDates,
             .healthDaily,
             .healthWorkout,
             .healthMetricSamples,
             .otherCSV:
            return trailingEpochDate(fileName: fileName)
        }
    }

    private static func fullBackupDate(fileName: String) -> Date? {
        let prefix = "bbworkout_backup_"
        let stem = fileName.deletingPathExtension
        guard stem.hasPrefix(prefix) else { return nil }

        let stamp = String(stem.dropFirst(prefix.count))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: stamp)
    }

    private static func trailingEpochDate(fileName: String) -> Date? {
        let stem = fileName.deletingPathExtension
        guard let lastComponent = stem.split(separator: "_").last,
              let timestamp = TimeInterval(lastComponent) else {
            return nil
        }

        return Date(timeIntervalSince1970: timestamp)
    }
}

private extension String {
    nonisolated var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}
