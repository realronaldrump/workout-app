import SwiftUI
import UniformTypeIdentifiers
// swiftlint:disable type_body_length

struct StrongImportWizard: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    let source: String
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var logStore: WorkoutLogStore
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @EnvironmentObject var intentionalBreaksManager: IntentionalBreaksManager

    @State private var step = 0
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importStats: (workouts: Int, exercises: Int)?
    @State private var showingFileImporter = false
    @State private var importPhase: ImportPhase = .idle
    @State private var importedFileName: String?
    @State private var importCompletedAt: Date?
    @State private var storageStatusMessage: String?
    @State private var healthSyncState: HealthSyncState = .idle
    @State private var healthSyncNote: String?
    @State private var syncTargetCount: Int?
    @State private var autoGymTagState: AutoGymTagState = .idle
    @State private var autoGymTagProgress: Double = 0
    @State private var autoGymTagReport: AutoGymTaggingReport?
    @State private var autoGymTagErrorMessage: String?
    @State private var autoGymTagRoutePermissionUnavailable = false
    @State private var showingAutoGymTagReport = false

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(spacing: 0) {
                    topBar

                    Divider()
                        .overlay(Theme.Colors.border.opacity(0.35))

                    progressIndicator
                        .padding(.top, Theme.Spacing.lg)

                    TabView(selection: $step) {
                        welcomeStep.tag(0)
                        importStep.tag(1)
                        successStep.tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.spring(), value: step)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
        .analyticsScreen("ImportWizard", source: source)
        .onAppear {
            AppAnalytics.shared.track(
                AnalyticsSignal.importWizardViewed,
                payload: ["Context.source": source]
            )
            AppAnalytics.shared.track(
                AnalyticsSignal.importWizardStepViewed,
                payload: [
                    "Context.source": source,
                    "Import.step": "\(step)"
                ]
            )
        }
        .onChange(of: step) { _, newValue in
            AppAnalytics.shared.track(
                AnalyticsSignal.importWizardStepViewed,
                payload: [
                    "Context.source": source,
                    "Import.step": "\(newValue)"
                ]
            )
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.json, UTType.data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingAutoGymTagReport) {
            if let report = autoGymTagReport {
                AutoGymTaggingReportView(report: report)
            }
        }
    }

    private var topBar: some View {
        ZStack {
            HStack {
                AppToolbarButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                    isPresented = false
                }
                Spacer()
            }

            Text("Import Data")
                .font(Theme.Typography.cardHeader)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index <= step ? Theme.Colors.accent : Theme.Colors.surface)
                    .frame(height: 4)
                    .animation(.spring(), value: step)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "square.and.arrow.down.on.square")
                .font(Theme.Iconography.wizardHero)
                .foregroundStyle(Theme.Colors.accent)
                .padding()
                .background(
                    Circle()
                        .fill(Theme.Colors.accent.opacity(0.1))
                        .frame(width: 160, height: 160)
                )

            VStack(spacing: Theme.Spacing.md) {
                    Text("Import Data")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)

                Text("Strong CSV or Big Beautiful Workout backup")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            primaryActionButton(title: "Next", fill: Theme.Colors.accent) {
                withAnimation { step = 1 }
            }
            .padding(Theme.Spacing.xl)
        }
    }

    private var importStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            if isImporting {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView(value: importPhase.rawValue)
                        .progressViewStyle(.linear)
                        .tint(Theme.Colors.accent)
                        .frame(maxWidth: 220)

                    Text(importPhase.message)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)

                    if let fileName = importedFileName {
                        Text(fileName)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(spacing: Theme.Spacing.lg) {
                    Button(
                        action: { showingFileImporter = true },
                        label: {
                            VStack(spacing: Theme.Spacing.md) {
                                Image(systemName: "doc.text.fill")
                                    .font(Theme.Iconography.largeTitle)
                                Text("Select Import File")
                                    .font(Theme.Typography.headline)
                            }
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(Theme.Spacing.xxl)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [10]))
                                    .fill(Theme.Colors.accent.opacity(0.5))
                            )
                        }
                    )
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))

                    if let error = importError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.error)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
    }

    private var successStep: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Theme.Iconography.wizardHero)
                    .foregroundStyle(Theme.Colors.success)
                    .symbolEffect(.bounce, value: step)

                if let stats = importStats {
                    VStack(spacing: Theme.Spacing.md) {
                            Text("Import Complete")
                                .font(Theme.Typography.title)

                        HStack(spacing: Theme.Spacing.xl) {
                            VStack {
                                Text("\(stats.workouts)")
                                    .font(Theme.Typography.title2)
                                    .foregroundStyle(Theme.Colors.accent)
                                Text("Workouts")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }

                            Divider()
                                .frame(height: 40)

                            VStack {
                                Text("\(stats.exercises)")
                                    .font(Theme.Typography.title2)
                                    .foregroundStyle(Theme.Colors.accent)
                                Text("Exercises")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        .padding()
                        .softCard()
                    }
                }

                importDetailsCard
                healthSyncStatusCard
                autoGymTagStatusCard

                primaryActionButton(title: "Done", fill: Theme.Colors.success) {
                    isPresented = false
                }

                if healthManager.isSyncing {
                    Text("Health sync continues in the background.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(Theme.Spacing.xl)
        }
    }

    private var importDetailsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Import Details")
                    .font(Theme.Typography.headline)
            }

            statusRow(title: "File", value: importedFileName ?? "CSV file")
            statusRow(title: "Storage", value: storageStatusText, valueColor: storageStatusColor)
            if let completedAt = importCompletedAt {
                statusRow(title: "Completed", value: formatDate(completedAt))
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }

    private var autoGymTagStatusCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Gym Tags")
                    .font(Theme.Typography.headline)
            }

            statusRow(title: "Status", value: autoGymTagStatusText, valueColor: autoGymTagStatusColor)

            Text(autoGymTagStatusDetail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if autoGymTagState == .tagging {
                ProgressView(value: autoGymTagProgress)
                    .progressViewStyle(.linear)
                    .tint(Theme.Colors.accent)
            }

            if let report = autoGymTagReport, report.attempted > 0 {
                statusRow(title: "Tagged", value: "\(report.assigned) of \(report.attempted)")
            }

            if autoGymTagNeedsReviewCount > 0 {
                statusRow(title: "Needs Review", value: "\(autoGymTagNeedsReviewCount)", valueColor: Theme.Colors.warning)
            }

            if autoGymTagRoutePermissionUnavailable {
                Text("Workout route location permission was unavailable, so any misses were left for manual review.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .needsAuthorization = autoGymTagState {
                Text("Settings > Health > Data Access > workout-app")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if shouldShowAutoGymTagActions {
                HStack(spacing: Theme.Spacing.md) {
                    if let report = autoGymTagReport, !report.items.isEmpty {
                        Button("View Results") {
                            showingAutoGymTagReport = true
                        }
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.accent)
                        .buttonStyle(.plain)
                    }

                    NavigationLink(destination: gymReviewDestination) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(gymReviewLinkTitle)
                            Image(systemName: "chevron.right")
                        }
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }

    private var healthSyncStatusCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.Colors.error)
                Text("Apple Health Sync")
                    .font(Theme.Typography.headline)
            }

            statusRow(title: "Status", value: healthSyncStatusText, valueColor: healthSyncStatusColor)

            Text(healthSyncStatusDetail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if healthManager.isSyncing {
                ProgressView(value: healthManager.syncProgress)
                    .progressViewStyle(.linear)
                    .tint(Theme.Colors.error)
            }

            let syncTotal = healthSyncTotalCount
            if syncTotal > 0 {
                statusRow(title: "Workouts", value: "\(healthManager.syncedWorkoutsCount) of \(syncTotal)")
            }

            if let note = healthSyncNote {
                Text(note)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if case .needsAuthorization = healthSyncState {
                Text("Settings > Health > Data Access > workout-app")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let lastSync = healthManager.lastSyncDate {
                statusRow(title: "Last Sync", value: formatDate(lastSync))
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }

    private func statusRow(title: String, value: String, valueColor: Color = Theme.Colors.textPrimary) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private var storageStatusText: String {
        if let message = storageStatusMessage {
            return message
        }
        return iCloudManager.isUsingLocalFallback
            ? "local"
            : "iCloud"
    }

    private var storageStatusColor: Color {
        if let message = storageStatusMessage, message.hasPrefix("Save failed") {
            return Theme.Colors.error
        }
        if iCloudManager.isUsingLocalFallback {
            return Theme.Colors.warning
        }
        return Theme.Colors.textPrimary
    }

    private var healthSyncStatusText: String {
        if healthManager.isSyncing {
            return "Syncing"
        }
        switch healthSyncState {
        case .idle:
            return "Pending"
        case .unavailable:
            return "Unavailable"
        case .needsAuthorization:
            return "Authorization Needed"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Complete"
        case .failed:
            return "Failed"
        }
    }

    private var healthSyncStatusDetail: String {
        if healthManager.isSyncing {
            return "Syncing recent workout health data."
        }
        switch healthSyncState {
        case .idle:
            return "Waiting to start automatic recent sync."
        case .unavailable:
            return "Apple Health is unavailable on this device."
        case .needsAuthorization:
            if healthManager.authorizationStatus == .denied {
                return "Apple Health access is denied. Enable access in Settings."
            }
            return "Authorization is required to sync health data."
        case .syncing:
            return "Syncing recent workout health data."
        case .synced(let date):
            return "Completed \(formatDate(date))"
        case .failed(let message):
            return "Sync failed: \(message)"
        }
    }

    private var healthSyncStatusColor: Color {
        if healthManager.isSyncing {
            return Theme.Colors.warning
        }
        switch healthSyncState {
        case .idle:
            return Theme.Colors.textTertiary
        case .unavailable:
            return Theme.Colors.warning
        case .needsAuthorization:
            return Theme.Colors.warning
        case .syncing:
            return Theme.Colors.warning
        case .synced:
            return Theme.Colors.success
        case .failed:
            return Theme.Colors.error
        }
    }

    private var healthSyncTotalCount: Int {
        syncTargetCount ?? dataManager.workouts.count
    }

    private var importedWorkoutStartDate: Date? {
        dataManager.importedWorkouts.map(\.date).min()
    }

    private var importedWorkoutEndDate: Date? {
        dataManager.importedWorkouts.map(\.date).max()
    }

    private var autoGymTagNeedsReviewCount: Int {
        autoGymTagReport?.items.reduce(into: 0) { count, item in
            if case .skipped = item.status {
                count += 1
            }
        } ?? 0
    }

    private var shouldShowAutoGymTagActions: Bool {
        switch autoGymTagState {
        case .idle, .tagging:
            return false
        case .unavailable, .needsAuthorization, .complete, .failed:
            return true
        }
    }

    private var gymReviewDestination: some View {
        GymBulkAssignView(
            autoStartAutoTagging: autoGymTagState != .complete,
            initialStartDate: importedWorkoutStartDate,
            initialEndDate: importedWorkoutEndDate,
            initialShowUnassignedOnly: true
        )
    }

    private var gymReviewLinkTitle: String {
        if autoGymTagNeedsReviewCount > 0 {
            return "Review Misses"
        }
        switch autoGymTagState {
        case .failed, .needsAuthorization, .unavailable:
            return "Open Gym Review"
        default:
            return "Review Gym Tags"
        }
    }

    private var autoGymTagStatusText: String {
        switch autoGymTagState {
        case .idle:
            return "Pending"
        case .unavailable:
            return "Unavailable"
        case .needsAuthorization:
            return "Authorization Needed"
        case .tagging:
            return "Detecting"
        case .complete:
            return "Complete"
        case .failed:
            return "Failed"
        }
    }

    private var autoGymTagStatusDetail: String {
        switch autoGymTagState {
        case .idle:
            return "Imported workouts will be checked for matching gym tags."
        case .unavailable:
            return "Apple Health is unavailable on this device, so gym auto-detect can’t run."
        case .needsAuthorization:
            if healthManager.authorizationStatus == .denied {
                return "Apple Health access is denied. Enable access in Settings to auto-detect gyms."
            }
            return "Health access is required to match imported workouts to Apple workouts."
        case .tagging:
            return "Auto-detecting gym tags for imported workouts."
        case .complete:
            guard let report = autoGymTagReport else {
                return "Gym tag detection finished."
            }
            if report.attempted == 0 {
                return "All imported workouts already had gym tags."
            }
            if autoGymTagNeedsReviewCount > 0 {
                return "Tagged \(report.assigned) workout\(report.assigned == 1 ? "" : "s") automatically. \(autoGymTagNeedsReviewCount) still need review."
            }
            return "Tagged \(report.assigned) workout\(report.assigned == 1 ? "" : "s") automatically."
        case .failed:
            return autoGymTagErrorMessage.map { "Auto-detect failed: \($0)" } ?? "Auto-detect failed."
        }
    }

    private var autoGymTagStatusColor: Color {
        switch autoGymTagState {
        case .idle:
            return Theme.Colors.textTertiary
        case .unavailable, .needsAuthorization:
            return Theme.Colors.warning
        case .tagging:
            return Theme.Colors.warning
        case .complete:
            return autoGymTagNeedsReviewCount > 0 ? Theme.Colors.warning : Theme.Colors.success
        case .failed:
            return Theme.Colors.error
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func primaryActionButton(title: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .brutalistButtonChrome(
                    fill: fill,
                    cornerRadius: Theme.CornerRadius.large
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            AppAnalytics.shared.track(
                AnalyticsSignal.importFileSelectionStarted,
                payload: [
                    "Context.source": source,
                    "Import.fileExtension": url.pathExtension.lowercased()
                ]
            )

            importError = nil
            importStats = nil
            importCompletedAt = nil
            storageStatusMessage = nil
            healthSyncState = .idle
            healthSyncNote = nil
            syncTargetCount = nil
            autoGymTagState = .idle
            autoGymTagProgress = 0
            autoGymTagReport = nil
            autoGymTagErrorMessage = nil
            autoGymTagRoutePermissionUnavailable = false
            showingAutoGymTagReport = false
            let selectedFileName = url.lastPathComponent
            importedFileName = selectedFileName
            importPhase = .reading
            isImporting = true

            // Security: access security scoped resource
            let hasAccess = url.startAccessingSecurityScopedResource()

            // Read file data off the main thread while we hold security scope access.
            DispatchQueue.global(qos: .userInitiated).async {
                let fileData: Data
                do {
                    fileData = try Data(contentsOf: url)
                } catch {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                    Task { @MainActor in
                        importError = "Could not read file: \(error.localizedDescription)"
                        isImporting = false
                        importPhase = .idle
                    }
                    return
                }

                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }

                Task { @MainActor in
                    importPhase = .parsing

                    let storageSnapshot = await iCloudManager.initializedStorageSnapshot()
                    let directoryURL = storageSnapshot.url
                    let isUsingLocalFallback = storageSnapshot.isUsingLocalFallback

                    Task.detached(priority: .userInitiated) { [fileData, selectedFileName, directoryURL, isUsingLocalFallback] in
                        do {
                            let importKind = try AppBackupService.classifyImport(
                                data: fileData,
                                fileName: selectedFileName
                            )

                            let shouldRunPostImportAutomation: Bool
                            switch importKind {
                            case .strongCSV(let data, _):
                                try await importStrongCSV(
                                    data: data,
                                    directoryURL: directoryURL,
                                    isUsingLocalFallback: isUsingLocalFallback
                                )
                                shouldRunPostImportAutomation = true
                            case .nativeBackup(let backup, _):
                                try await importNativeBackup(
                                    backup,
                                    directoryURL: directoryURL,
                                    isUsingLocalFallback: isUsingLocalFallback
                                )
                                shouldRunPostImportAutomation = false
                            }

                            await MainActor.run {
                                importPhase = .complete
                                importCompletedAt = Date()

                                withAnimation {
                                    isImporting = false
                                    step = 2
                                }
                                Haptics.notify(.success)

                                if shouldRunPostImportAutomation {
                                    startAutoHealthSyncIfNeeded()
                                    startAutoGymTaggingIfNeeded()
                                }
                            }
                        } catch {
                            await MainActor.run {
                                storageStatusMessage = nil
                                importError = "Import failed to save: \(error.localizedDescription)"
                                isImporting = false
                                importPhase = .idle
                                AppAnalytics.shared.track(
                                    AnalyticsSignal.importFailed,
                                    payload: [
                                        "Context.source": source,
                                        "Import.errorDomain": String(describing: type(of: error))
                                    ]
                                )
                            }
                        }
                    }
                }
            }

        case .failure(let error):
            importError = error.localizedDescription
            AppAnalytics.shared.track(
                AnalyticsSignal.importFailed,
                payload: [
                    "Context.source": source,
                    "Import.errorDomain": String(describing: type(of: error))
                ]
            )
        }
    }

    @MainActor
    private func importStrongCSV(
        data: Data,
        directoryURL: URL?,
        isUsingLocalFallback: Bool
    ) async throws {
        let sets = try await Task.detached(priority: .userInitiated) {
            try CSVParser.parseStrongWorkoutsCSV(from: data)
        }.value

        importPhase = .saving
        try await Task.sleep(nanoseconds: 1_000_000_000)

        guard let directory = directoryURL else {
            throw iCloudError.containerNotAvailable
        }

        let fileName = "strong_workouts_\(Date().timeIntervalSince1970).csv"
        try await Task.detached(priority: .utility) {
            try iCloudDocumentManager.saveWorkoutFile(data: data, in: directory, fileName: fileName)
        }.value

        storageStatusMessage = isUsingLocalFallback
            ? "Saved on-device only (iCloud unavailable)"
            : "Saved to iCloud Drive"
        importPhase = .processing

        let healthIdentitySnapshot = healthManager.healthDataStore.values.map {
            WorkoutHealthIdentitySnapshot(
                workoutId: $0.workoutId,
                workoutDate: $0.workoutDate
            )
        }
        let requestID = dataManager.beginImportedWorkoutRequest()

        await dataManager.processImportedWorkoutSets(
            sets,
            healthIdentitySnapshot: healthIdentitySnapshot,
            requestID: requestID
        )

        let stats = dataManager.calculateStats()
        importStats = (stats.totalWorkouts, stats.totalExercises)
        AppAnalytics.shared.track(
            AnalyticsSignal.importCompleted,
            payload: [
                "Context.source": source,
                "Import.kind": "strongCSV",
                "Import.workoutCount": "\(stats.totalWorkouts)",
                "Import.exerciseCount": "\(stats.totalExercises)"
            ]
        )
    }

    @MainActor
    private func importNativeBackup(
        _ backup: BigBeautifulWorkoutBackup,
        directoryURL: URL?,
        isUsingLocalFallback: Bool
    ) async throws {
        importPhase = .saving
        try await Task.sleep(nanoseconds: 350_000_000)

        guard let directory = directoryURL else {
            throw iCloudError.containerNotAvailable
        }

        let backupData = try AppBackupService.exportBackup(backup)
        let fileName = AppBackupService.makeBackupFileName()
        try await Task.detached(priority: .utility) {
            try iCloudDocumentManager.saveBackupFile(data: backupData, in: directory, fileName: fileName)
        }.value
        let savedURL = directory.appendingPathComponent(fileName)
        AppBackupService.persistNativeBackupSourceSignature(
            AppBackupService.importSourceSignature(for: savedURL)
        )

        storageStatusMessage = isUsingLocalFallback
            ? "Saved on-device only (iCloud unavailable)"
            : "Saved to iCloud Drive"
        importPhase = .processing

        let result = try AppBackupImporter.importBackup(
            backup,
            dataManager: dataManager,
            logStore: logStore,
            healthManager: healthManager,
            annotationsManager: annotationsManager,
            gymProfilesManager: gymProfilesManager,
            intentionalBreaksManager: intentionalBreaksManager
        )

        healthSyncState = .synced(Date())
        healthSyncNote = "Cached health data restored from backup. No Apple Health write was attempted."
        autoGymTagState = .complete
        autoGymTagReport = AutoGymTaggingReport(
            attempted: 0,
            assigned: 0,
            skippedNoMatchingWorkout: 0,
            skippedNoRoute: 0,
            skippedNoGymMatch: 0,
            skippedGymsMissingLocation: 0,
            items: []
        )

        let stats = dataManager.calculateStats()
        importStats = (stats.totalWorkouts, stats.totalExercises)
        AppAnalytics.shared.track(
            AnalyticsSignal.importCompleted,
            payload: [
                "Context.source": source,
                "Import.kind": "nativeBackup",
                "Import.workoutCount": "\(stats.totalWorkouts)",
                "Import.exerciseCount": "\(stats.totalExercises)",
                "Import.insertedCount": "\(result.insertedTotal)"
            ]
        )
    }

    @MainActor
    private func startAutoHealthSyncIfNeeded() {
        healthSyncNote = nil

        guard !dataManager.workouts.isEmpty else {
            healthSyncState = .idle
            return
        }
        guard healthManager.isHealthKitAvailable() else {
            healthSyncState = .unavailable
            return
        }
        if healthManager.authorizationStatus == .denied {
            healthSyncState = .needsAuthorization
            return
        }
        guard !healthManager.isSyncing else {
            healthSyncState = .syncing
            return
        }

        let missing = dataManager.workouts.filter { healthManager.getHealthData(for: $0.id) == nil }
        guard !missing.isEmpty else {
            syncTargetCount = 0
            healthSyncState = .synced(Date())
            healthSyncNote = "No new workouts to sync"
            return
        }

        let plannedTargets = healthManager.recommendedInitialWorkoutSyncTargets(from: dataManager.workouts)
        syncTargetCount = plannedTargets.count

        guard !plannedTargets.isEmpty else {
            healthSyncState = .synced(Date())
            healthSyncNote =
                "Skipped \(missing.count) older unsynced workout\(missing.count == 1 ? "" : "s") " +
                "to keep import fast. Use Health Cache later to backfill them."
            return
        }

        Task { @MainActor in
            do {
                if healthManager.authorizationStatus == .notDetermined {
                    healthSyncState = .needsAuthorization
                    // Avoid triggering Health authorization UI during view transitions.
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    try await healthManager.requestAuthorization()
                }

                guard healthManager.authorizationStatus == .authorized else {
                    healthSyncState = .needsAuthorization
                    return
                }

                healthSyncState = .syncing
                let results = try await healthManager.syncAllWorkouts(plannedTargets)
                let hasData = results.contains { $0.hasHealthData }
                let skippedCount = max(0, missing.count - plannedTargets.count)
                if !hasData {
                    if skippedCount > 0 {
                        healthSyncNote =
                            "No matching recent Health samples were found. "
                            + "\(skippedCount) older workout\(skippedCount == 1 ? " was" : "s were") "
                            + "skipped to keep import fast."
                    } else {
                        healthSyncNote = "No matching recent Health samples were found for imported workouts."
                    }
                } else if skippedCount > 0 {
                    healthSyncNote =
                        "Synced \(plannedTargets.count) recent workout\(plannedTargets.count == 1 ? "" : "s"). "
                        + "\(skippedCount) older workout\(skippedCount == 1 ? " was" : "s were") "
                        + "skipped to keep import fast."
                }
                healthSyncState = .synced(Date())
            } catch {
                healthSyncState = .failed(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func startAutoGymTaggingIfNeeded() {
        autoGymTagProgress = 0
        autoGymTagReport = nil
        autoGymTagErrorMessage = nil
        autoGymTagRoutePermissionUnavailable = false

        let importedWorkouts = dataManager.importedWorkouts
        guard !importedWorkouts.isEmpty else {
            autoGymTagState = .idle
            return
        }
        guard healthManager.isHealthKitAvailable() else {
            autoGymTagState = .unavailable
            return
        }
        if healthManager.authorizationStatus == .denied {
            autoGymTagState = .needsAuthorization
            return
        }

        let targets = AutoGymTaggingRunner.workoutsNeedingGymTag(
            in: importedWorkouts,
            annotationsManager: annotationsManager,
            gymProfilesManager: gymProfilesManager
        )
        guard !targets.isEmpty else {
            autoGymTagState = .complete
            autoGymTagReport = AutoGymTaggingReport(
                attempted: 0,
                assigned: 0,
                skippedNoMatchingWorkout: 0,
                skippedNoRoute: 0,
                skippedNoGymMatch: 0,
                skippedGymsMissingLocation: 0,
                items: []
            )
            return
        }

        autoGymTagState = .tagging

        Task { @MainActor in
            do {
                let result = try await AutoGymTaggingRunner.run(
                    for: importedWorkouts,
                    annotationsManager: annotationsManager,
                    gymProfilesManager: gymProfilesManager,
                    healthManager: healthManager
                ) { progress in
                    autoGymTagProgress = progress
                }
                autoGymTagReport = result.report
                autoGymTagRoutePermissionUnavailable = result.routePermissionUnavailable
                autoGymTagState = .complete
            } catch {
                if healthManager.authorizationStatus == .denied {
                    autoGymTagState = .needsAuthorization
                    autoGymTagErrorMessage = nil
                    return
                }

                if let healthError = error as? HealthKitError, case .notAvailable = healthError {
                    autoGymTagState = .unavailable
                    autoGymTagErrorMessage = nil
                    return
                }

                autoGymTagErrorMessage = error.localizedDescription
                autoGymTagState = .failed
            }
        }
    }
}
// swiftlint:enable type_body_length
