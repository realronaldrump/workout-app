import SwiftUI

struct DataClearSheetRoute: Identifiable {
    let id = UUID()
}

struct SelectiveDataClearSheet: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @ObservedObject var logStore: WorkoutLogStore
    @ObservedObject var sessionManager: WorkoutSessionManager
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var intentionalBreaksManager: IntentionalBreaksManager
    @ObservedObject var annotationsManager: WorkoutAnnotationsManager
    @ObservedObject var gymProfilesManager: GymProfilesManager
    @Binding var hasSeenOnboarding: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategories = Set(AppDataClearCategory.allCases)
    @State private var showingConfirmation = false
    @State private var isClearing = false
    @State private var workoutFileCount: Int?
    @State private var exportAndBackupFileCount: Int?

    private var plan: AppDataClearPlan {
        AppDataClearPlan(requestedCategories: selectedCategories)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        header
                        quickActions
                        categoryList
                        impliedCleanupNote
                        analyticsPrivacyNote
                        clearButton
                    }
                    .padding()
                }
            }
            .task {
                await refreshFileCounts()
            }
            .navigationTitle("Clear Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .fixedSize()
                        .disabled(isClearing)
                }
            }
            .alert("Clear Selected Data?", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    clearSelectedData()
                }
            } message: {
                Text(confirmationMessage)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Choose what to remove", systemImage: "trash.fill")
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.error)

            Text("Clear everything, or keep parts like Health history, exercise setup, preferences, or backups.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.error.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(Theme.Colors.error.opacity(0.15), lineWidth: 1)
        )
    }

    private var quickActions: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button("Select All") {
                selectedCategories = Set(AppDataClearCategory.allCases)
            }
            .buttonStyle(DataClearPillButtonStyle(isActive: selectedCategories.count == AppDataClearCategory.allCases.count))

            Button("Select None") {
                selectedCategories = []
            }
            .buttonStyle(DataClearPillButtonStyle(isActive: selectedCategories.isEmpty))

            Spacer(minLength: 0)
        }
        .disabled(isClearing)
    }

    private var categoryList: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(AppDataClearCategory.allCases) { category in
                DataClearCategoryRow(
                    category: category,
                    preview: preview(for: category),
                    isSelected: selectedCategories.contains(category),
                    isImplied: plan.impliedCategories.contains(category)
                ) {
                    toggle(category)
                }
            }
        }
    }

    @ViewBuilder
    private var impliedCleanupNote: some View {
        if !plan.impliedCategories.isEmpty {
            Text("Also cleared automatically: \(categoryListText(plan.impliedCategories)).")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.xs)
        }
    }

    private var analyticsPrivacyNote: some View {
        Text("Anonymous analytics consent stays unchanged.")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.horizontal, Theme.Spacing.xs)
    }

    private var clearButton: some View {
        Button {
            showingConfirmation = true
        } label: {
            HStack {
                Spacer()
                if isClearing {
                    ProgressView()
                        .tint(.white)
                    Text("Clearing...")
                } else if isCountingFiles {
                    ProgressView()
                        .tint(.white)
                    Text("Counting Preview...")
                } else {
                    Text(clearButtonTitle)
                }
                Spacer()
            }
            .font(Theme.Typography.bodyBold)
            .foregroundStyle(.white)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(plan.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.error)
            )
        }
        .buttonStyle(.plain)
        .disabled(plan.isEmpty || isClearing || isCountingFiles)
        .opacity((plan.isEmpty || isClearing || isCountingFiles) ? 0.6 : 1)
    }

    private var clearButtonTitle: String {
        selectedCategories.count == AppDataClearCategory.allCases.count
            ? "Clear All App Data"
            : "Clear Selected Data"
    }

    private var isCountingFiles: Bool {
        workoutFileCount == nil || exportAndBackupFileCount == nil
    }

    private var confirmationMessage: String {
        let targets = categoryListText(plan.effectiveCategories)
        let total = plan.effectiveCategories.reduce(0) { result, category in
            result + (preview(for: category).count ?? 0)
        }
        return "This permanently deletes \(total) item\(total == 1 ? "" : "s") across: \(targets). This cannot be undone."
    }

    private func toggle(_ category: AppDataClearCategory) {
        guard !isClearing else { return }
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    private func clearSelectedData() {
        guard !isClearing else { return }
        isClearing = true

        Task { @MainActor in
            await AppDataClearService.clear(
                plan: plan,
                context: AppDataClearContext(
                    dataManager: dataManager,
                    iCloudManager: iCloudManager,
                    logStore: logStore,
                    sessionManager: sessionManager,
                    healthManager: healthManager,
                    intentionalBreaksManager: intentionalBreaksManager,
                    annotationsManager: annotationsManager,
                    gymProfilesManager: gymProfilesManager
                ),
                setHasSeenOnboarding: { hasSeenOnboarding = $0 }
            )
            isClearing = false
            dismiss()
        }
    }

    private func refreshFileCounts() async {
        async let workoutFiles = iCloudManager.countWorkoutFiles()
        async let exportFiles = iCloudManager.countExportAndBackupFiles()
        let counts = await (workoutFiles, exportFiles)
        workoutFileCount = counts.0
        exportAndBackupFileCount = counts.1
    }

    private func preview(for category: AppDataClearCategory) -> DataClearCategoryPreview {
        switch category {
        case .workoutHistory:
            let importedCount = dataManager.importedWorkouts.count
            let loggedCount = logStore.workouts.count
            let fileCount = workoutFileCount
            let total = importedCount + loggedCount + (fileCount ?? 0)
            let fileText = fileCount.map { "\($0) file\($0 == 1 ? "" : "s")" } ?? "counting files"
            return DataClearCategoryPreview(
                count: fileCount == nil ? nil : total,
                detail: "\(importedCount) imported, \(loggedCount) logged, \(fileText)"
            )
        case .gymProfiles:
            let count = gymProfilesManager.gyms.count
            return DataClearCategoryPreview(count: count, detail: "\(count) saved gym\(count == 1 ? "" : "s")")
        case .gymAssignments:
            let count = annotationsManager.annotations.count
            return DataClearCategoryPreview(count: count, detail: "\(count) workout tag\(count == 1 ? "" : "s")")
        case .healthData:
            let workoutCount = healthManager.healthDataStore.count
            let dailyCount = healthManager.dailyHealthStore.count
            let coverageCount = healthManager.dailyHealthCoverage.count
            return DataClearCategoryPreview(
                count: workoutCount + dailyCount + coverageCount,
                detail: "\(workoutCount) workout, \(dailyCount) daily, \(coverageCount) coverage"
            )
        case .intentionalBreaks:
            let savedCount = intentionalBreaksManager.savedBreaks.count
            let dismissedCount = intentionalBreaksManager.dismissedSuggestionRanges.count
            return DataClearCategoryPreview(
                count: savedCount + dismissedCount,
                detail: "\(savedCount) saved, \(dismissedCount) dismissed"
            )
        case .exerciseCustomization:
            let tagCount = ExerciseMetadataManager.shared.muscleTagOverrides.count
            let metricCount = ExerciseMetricManager.shared.cardioOverrides.count
            let favoriteCount = favoriteExerciseCount()
            let detail = [
                "\(tagCount) tag override\(tagCount == 1 ? "" : "s")",
                "\(metricCount) metric preference\(metricCount == 1 ? "" : "s")",
                "\(favoriteCount) favorite\(favoriteCount == 1 ? "" : "s")"
            ]
            .joined(separator: ", ")
            return DataClearCategoryPreview(
                count: tagCount + metricCount + favoriteCount,
                detail: detail
            )
        case .profileAndPreferences:
            let count = profilePreferenceCount()
            return DataClearCategoryPreview(count: count, detail: "\(count) saved setting\(count == 1 ? "" : "s")")
        case .guideProgress:
            let completedCount = FeatureGuideManager.shared.completionCount
            let onboardingCount = hasSeenOnboarding ? 1 : 0
            let dismissedCount = UserDefaults.standard.object(forKey: "dismissedUntaggedCount") == nil ? 0 : 1
            return DataClearCategoryPreview(
                count: completedCount + onboardingCount + dismissedCount,
                detail: "\(completedCount) guide\(completedCount == 1 ? "" : "s"), \(onboardingCount) onboarding flag, \(dismissedCount) dashboard dismissal"
            )
        case .activeSessionDraft:
            let count = sessionManager.activeSession == nil ? 0 : 1
            return DataClearCategoryPreview(count: count, detail: count == 1 ? "1 active draft" : "No active draft")
        case .importExportFiles:
            let count = exportAndBackupFileCount
            return DataClearCategoryPreview(
                count: count,
                detail: count.map { "\($0) CSV or backup file\($0 == 1 ? "" : "s")" } ?? "Counting files"
            )
        }
    }

    private func favoriteExerciseCount(userDefaults: UserDefaults = .standard) -> Int {
        guard let data = userDefaults.string(forKey: "favoriteExercises")?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return 0
        }
        return decoded.count
    }

    private func profilePreferenceCount(userDefaults: UserDefaults = .standard) -> Int {
        var count = 0
        let keys = [
            "profileName",
            "weightIncrement",
            "intentionalRestDays",
            "sessionsPerWeekGoal",
            "appearanceMode",
            healthManager.preferredSleepSourceKey,
            healthManager.preferredSleepSourceNameKey
        ]

        for key in keys where userDefaults.object(forKey: key) != nil {
            count += 1
        }

        if gymProfilesManager.lastUsedGymProfileId != nil {
            count += 1
        }

        return count
    }

    private func categoryListText(_ categories: Set<AppDataClearCategory>) -> String {
        AppDataClearCategory.allCases
            .filter { categories.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }
}

private struct DataClearCategoryRow: View {
    let category: AppDataClearCategory
    let preview: DataClearCategoryPreview
    let isSelected: Bool
    let isImplied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: category.iconName)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(category.tintColor)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(category.title)
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        if isImplied {
                            Text("Included")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.error)
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Theme.Colors.error.opacity(0.10))
                                )
                        }
                    }

                    Text(preview.displayText)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.error)

                    Text(category.subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(isSelected ? Theme.Colors.error : Theme.Colors.textTertiary)
            }
            .padding()
            .softCard(elevation: isSelected || isImplied ? 2 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder((isSelected || isImplied) ? Theme.Colors.error.opacity(0.25) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title). \(isSelected || isImplied ? "Selected" : "Not selected")")
    }
}

private struct DataClearCategoryPreview {
    let count: Int?
    let detail: String

    var displayText: String {
        guard let count else { return detail }
        return "\(count) item\(count == 1 ? "" : "s") • \(detail)"
    }
}

private struct DataClearPillButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.captionBold)
            .foregroundStyle(isActive ? .white : Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .fill(isActive ? Theme.Colors.error : Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .strokeBorder(Theme.Colors.border.opacity(isActive ? 0 : 0.7), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private extension AppDataClearCategory {
    var iconName: String {
        switch self {
        case .workoutHistory:
            return "figure.strengthtraining.traditional"
        case .gymProfiles:
            return "mappin.and.ellipse"
        case .gymAssignments:
            return "tag.fill"
        case .healthData:
            return "heart.fill"
        case .intentionalBreaks:
            return "calendar.badge.minus"
        case .exerciseCustomization:
            return "slider.horizontal.3"
        case .profileAndPreferences:
            return "person.crop.circle.fill"
        case .guideProgress:
            return "book.fill"
        case .activeSessionDraft:
            return "bolt.fill"
        case .importExportFiles:
            return "folder.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .workoutHistory:
            return Theme.Colors.accent
        case .gymProfiles:
            return Theme.Colors.accentSecondary
        case .gymAssignments:
            return Theme.Colors.accentTertiary
        case .healthData:
            return Theme.Colors.error
        case .intentionalBreaks:
            return Theme.Colors.warning
        case .exerciseCustomization:
            return Theme.Colors.success
        case .profileAndPreferences:
            return Theme.Colors.cardio
        case .guideProgress:
            return Theme.Colors.gold
        case .activeSessionDraft:
            return Theme.Colors.accent
        case .importExportFiles:
            return Theme.Colors.textSecondary
        }
    }
}
