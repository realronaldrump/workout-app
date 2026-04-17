import SwiftUI

struct BackupFilesView: View {
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @State private var sections: [BackupFileSection] = []
    @State private var selectedFile: URL?
    @State private var showingDeleteAlert = false

    var body: some View {
        ZStack {
            AdaptiveBackground()
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    if sections.isEmpty {
                        EmptyStateCard(
                            icon: "icloud.slash",
                            tint: Theme.Colors.textTertiary,
                            title: "No Backup Files",
                            message: "Exported CSVs and master backups will appear here."
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
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Backup Files")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadFiles()
        }
        .alert("Delete File", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let file = selectedFile {
                    try? iCloudManager.deleteFile(at: file)
                    removeFile(file)
                }
            }
        } message: {
            Text("Are you sure you want to delete this backup file?")
        }
    }

    @MainActor
    private func loadFiles() async {
        let directoryURL = iCloudManager.storageSnapshot().url
        sections = await Task.detached(priority: .userInitiated) { [directoryURL] in
            let files = directoryURL.map { iCloudDocumentManager.listExportAndBackupFiles(in: $0) } ?? []
            return BackupFileSection.sections(from: files)
        }.value
    }

    private func removeFile(_ file: URL) {
        sections = BackupFileSection.sections(
            from: sections
                .flatMap(\.files)
                .map(\.url)
                .filter { $0 != file }
        )
    }
}

struct BackupFileRow: View {
    let file: BackupFileEntry
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.fileName)
                    .font(Theme.Typography.condensed)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !file.detailText.isEmpty {
                    Text(file.detailText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.error)
                    .padding(8)
                    .background(Theme.Colors.error.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
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

        return details.joined(separator: " | ")
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
            return "Master Backups"
        case .strongImport:
            return "Strong Imports"
        case .workoutExport:
            return "Workout Exports"
        case .exerciseList:
            return "Exercise Lists"
        case .exerciseHistory:
            return "Exercise History"
        case .muscleGroup:
            return "Muscle Groups"
        case .workoutDates:
            return "Workout Dates"
        case .healthDaily:
            return "Health Daily"
        case .healthWorkout:
            return "Health Workouts"
        case .healthMetricSamples:
            return "Health Metric Samples"
        case .otherCSV:
            return "Other CSV Files"
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
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}
