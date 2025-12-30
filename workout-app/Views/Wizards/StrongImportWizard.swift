import SwiftUI
import UniformTypeIdentifiers

struct StrongImportWizard: View {
    @Binding var isPresented: Bool
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    
    @State private var step = 0
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importStats: (workouts: Int, exercises: Int)?
    @State private var showingFileImporter = false
    
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
            .background(Theme.Colors.background)
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
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Theme.Colors.accent)
                
                Text("Processing your data...")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
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
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            
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
            
            Spacer()
            
            Button(action: { isPresented = false }) {
                Text("Done")
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.Colors.success)
                    .foregroundColor(.white)
                    .cornerRadius(Theme.CornerRadius.large)
            }
            .padding(Theme.Spacing.xl)
        }
    }
    
    // MARK: - Logic
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
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
                return
            }
            
            // Release security scope now that we have the data
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
            
            isImporting = true
            
            Task {
                do {
                    let sets = try CSVParser.parseStrongWorkoutsCSV(from: fileData)
                    
                    // Artificial delay for UX
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    
                    await MainActor.run {
                        dataManager.processWorkoutSets(sets)
                        let stats = dataManager.calculateStats()
                        importStats = (stats.totalWorkouts, stats.totalExercises)
                        
                        // Save to iCloud
                        let fileName = "strong_workouts_\(Date().timeIntervalSince1970).csv"
                        try? iCloudManager.saveToiCloud(data: fileData, fileName: fileName)
                        
                        withAnimation {
                            isImporting = false
                            step = 2
                        }
                    }
                } catch {
                    await MainActor.run {
                        importError = error.localizedDescription
                        isImporting = false
                    }
                }
            }
            
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}
