import SwiftUI
import UniformTypeIdentifiers

struct StrongImportWizard: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager

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

    var body: some View {
        NavigationStack {
            VStack {
                // Progress Indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Capsule()
                            .fill(index <= step ? Theme.Colors.accent : Theme.Colors.surface)
                            .frame(height: 4)
                            .animation(.spring(), value: step)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.lg)

                TabView(selection: $step) {
                    welcomeStep.tag(0)
                    importStep.tag(1)
                    successStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(), value: step)
            }
            .background(AdaptiveBackground())
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppPillButton(title: "Close", systemImage: "xmark", variant: .subtle) {
                        isPresented = false
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private enum ImportPhase: Double {
        case idle = 0
        case reading = 0.2
        case parsing = 0.4
        case processing = 0.6
        case saving = 0.8
        case complete = 1.0

        var message: String {
            switch self {
            case .idle:
                return "Awaiting file"
            case .reading:
                return "Reading CSV"
            case .parsing:
                return "Parsing"
            case .processing:
                return "Processing"
            case .saving:
                return "Saving"
            case .complete:
                return "Complete"
            }
        }
    }

    private enum HealthSyncState {
        case idle
        case unavailable
        case needsAuthorization
        case syncing
        case synced(Date)
        case failed(String)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 80))
                .foregroundStyle(Theme.Colors.accent)
                .padding()
                .background(
                    Circle()
                        .fill(Theme.Colors.accent.opacity(0.1))
                        .frame(width: 160, height: 160)
                )

            VStack(spacing: Theme.Spacing.md) {
                Text("Import from Strong")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("CSV export (Strong)")
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
                                    .font(.largeTitle)
                                Text("Select CSV File")
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
                    .font(.system(size: 80))
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

                NavigationLink(destination: GymBulkAssignView(autoStartAutoTagging: true)) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.Colors.accent)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-Detect Gym Tags")
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("Run gym auto-tag first, then fix misses with map search.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
                }
                .buttonStyle(PlainButtonStyle())

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
            return "Syncing workout health data."
        }
        switch healthSyncState {
        case .idle:
            return "Waiting to start automatic sync."
        case .unavailable:
            return "Apple Health is unavailable on this device."
        case .needsAuthorization:
            if healthManager.authorizationStatus == .denied {
                return "Apple Health access is denied. Enable access in Settings."
            }
            return "Authorization is required to sync health data."
        case .syncing:
            return "Syncing workout health data."
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

            importError = nil
            importStats = nil
            importCompletedAt = nil
            storageStatusMessage = nil
            healthSyncState = .idle
            healthSyncNote = nil
            syncTargetCount = nil
            importedFileName = url.lastPathComponent
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

                    let storageSnapshot = iCloudManager.storageSnapshot()
                    let directoryURL = storageSnapshot.url
                    let isUsingLocalFallback = storageSnapshot.isUsingLocalFallback

                    Task.detached(priority: .userInitiated) { [fileData, directoryURL, isUsingLocalFallback] in
                        do {
                            // Parse off the main thread to avoid UI hitches on large exports.
                            let sets = try CSVParser.parseStrongWorkoutsCSV(from: fileData)
                            await MainActor.run {
                                importPhase = .processing
                            }

                            // Artificial delay for UX
                            try await Task.sleep(nanoseconds: 1_000_000_000)

                            let healthSnapshot = await MainActor.run {
                                Array(healthManager.healthDataStore.values)
                            }

                            // Process workout sets (nonisolated async)
                            await dataManager.processImportedWorkoutSets(sets, healthDataSnapshot: healthSnapshot)

                            await MainActor.run {
                                let stats = dataManager.calculateStats()
                                importStats = (stats.totalWorkouts, stats.totalExercises)
                                importPhase = .saving
                            }

                            // Save the original file data off the main thread.
                            let fileName = "strong_workouts_\(Date().timeIntervalSince1970).csv"
                            let storageMessage: String
                            do {
                                guard let directory = directoryURL else {
                                    throw iCloudError.containerNotAvailable
                                }
                                try iCloudDocumentManager.saveWorkoutFile(data: fileData, in: directory, fileName: fileName)
                                storageMessage = isUsingLocalFallback
                                    ? "Saved on-device (iCloud unavailable)"
                                    : "Saved to iCloud Drive"
                            } catch {
                                storageMessage = "Save failed: \(error.localizedDescription)"
                            }

                            await MainActor.run {
                                storageStatusMessage = storageMessage
                                importPhase = .complete
                                importCompletedAt = Date()

                                withAnimation {
                                    isImporting = false
                                    step = 2
                                }
                                Haptics.notify(.success)

                                startAutoHealthSyncIfNeeded()
                            }
                        } catch {
                            await MainActor.run {
                                importError = error.localizedDescription
                                isImporting = false
                                importPhase = .idle
                            }
                        }
                    }
                }
            }

        case .failure(let error):
            importError = error.localizedDescription
        }
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
        syncTargetCount = missing.count
        guard !missing.isEmpty else {
            healthSyncState = .synced(Date())
            healthSyncNote = "No new workouts to sync"
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
                let results = try await healthManager.syncAllWorkouts(missing)
                let hasData = results.contains { $0.hasHealthData }
                if !hasData {
                    healthSyncNote = "No matching health samples were found for imported workouts."
                }
                healthSyncState = .synced(Date())
            } catch {
                healthSyncState = .failed(error.localizedDescription)
            }
        }
    }
}
