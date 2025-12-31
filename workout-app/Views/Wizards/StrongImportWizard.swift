import SwiftUI
import UniformTypeIdentifiers

struct StrongImportWizard: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @EnvironmentObject var healthManager: HealthKitManager
    
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
                    Button("Close") { isPresented = false }
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
                return "Waiting for a file..."
            case .reading:
                return "Reading CSV file..."
            case .parsing:
                return "Parsing workout data..."
            case .processing:
                return "Building workouts..."
            case .saving:
                return "Saving file..."
            case .complete:
                return "Import complete."
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
                
                Text("Bring your workout history to life. We support the standard CSV export from the Strong app.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: { 
                withAnimation { step = 1 }
            }) {
                Text("Get Started")
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.Colors.accent)
                    .foregroundColor(.white)
                    .cornerRadius(Theme.CornerRadius.large)
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
                    Button(action: { showingFileImporter = true }) {
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
                        Text("Import Complete!")
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
                        .glassBackground()
                    }
                }
                
                importDetailsCard
                healthSyncStatusCard
                
                Button(action: { isPresented = false }) {
                    Text("Done")
                        .font(Theme.Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Colors.success)
                        .foregroundColor(.white)
                        .cornerRadius(Theme.CornerRadius.large)
                }
                
                if healthManager.isSyncing {
                    Text("Health sync continues in the background. You can close this screen.")
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
        .glassBackground()
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
            
            if dataManager.workouts.count > 0 {
                statusRow(title: "Workouts", value: "\(healthManager.syncedWorkoutsCount) of \(dataManager.workouts.count)")
            }
            
            if let note = healthSyncNote {
                Text(note)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            if case .needsAuthorization = healthSyncState {
                Text("Enable Health access in Settings > Health > Data Access & Devices > workout-app.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if let lastSync = healthManager.lastSyncDate {
                statusRow(title: "Last Sync", value: formatDate(lastSync))
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground()
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
            ? "Saved on-device (iCloud unavailable)"
            : "Saved to iCloud Drive"
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
            return "Permission Needed"
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
            return "Fetching Apple Health data for your imported workouts."
        }
        switch healthSyncState {
        case .idle:
            return "Health sync will start automatically after import."
        case .unavailable:
            return "Health data is not available on this device."
        case .needsAuthorization:
            if healthManager.authorizationStatus == .denied {
                return "Health access was denied."
            }
            return "Waiting for Health permission."
        case .syncing:
            return "Fetching Apple Health data for your imported workouts."
        case .synced(let date):
            return "Health sync completed \(formatDate(date))."
        case .failed(let message):
            return "Health sync failed: \(message)"
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
    
    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
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
            importedFileName = url.lastPathComponent
            importPhase = .reading
            isImporting = true
            
            // Security: access security scoped resource
            let hasAccess = url.startAccessingSecurityScopedResource()
            
            // Read file data synchronously while we have security scope access
            // This MUST happen before any async code, as defer would release access too early
            let fileData: Data
            do {
                fileData = try Data(contentsOf: url)
            } catch {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                importError = "Could not read file: \(error.localizedDescription)"
                isImporting = false
                importPhase = .idle
                return
            }
            
            // Release security scope now that we have the data
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
            importPhase = .parsing
            
            Task.detached(priority: .userInitiated) {
                do {
                    let sets = try CSVParser.parseStrongWorkoutsCSV(from: fileData)
                    await MainActor.run {
                        importPhase = .processing
                    }
                    
                    // Artificial delay for UX
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    
                    await MainActor.run {
                        dataManager.processWorkoutSets(sets)
                        let stats = dataManager.calculateStats()
                        importStats = (stats.totalWorkouts, stats.totalExercises)
                        importPhase = .saving
                        
                        // Save to iCloud
                        let fileName = "strong_workouts_\(Date().timeIntervalSince1970).csv"
                        do {
                            try iCloudManager.saveToiCloud(data: fileData, fileName: fileName)
                            storageStatusMessage = iCloudManager.isUsingLocalFallback
                                ? "Saved on-device (iCloud unavailable)"
                                : "Saved to iCloud Drive"
                        } catch {
                            storageStatusMessage = "Save failed: \(error.localizedDescription)"
                        }
                        
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

        Task { @MainActor in
            do {
                if healthManager.authorizationStatus == .notDetermined {
                    healthSyncState = .needsAuthorization
                    try await healthManager.requestAuthorization()
                }

                guard healthManager.authorizationStatus == .authorized else {
                    healthSyncState = .needsAuthorization
                    return
                }

                healthSyncState = .syncing
                let results = try await healthManager.syncAllWorkouts(dataManager.workouts)
                let hasData = results.contains { $0.hasHealthData }
                if !hasData {
                    healthSyncNote = "No Health data was found for those workout times."
                }
                healthSyncState = .synced(Date())
            } catch {
                healthSyncState = .failed(error.localizedDescription)
            }
        }
    }
}
