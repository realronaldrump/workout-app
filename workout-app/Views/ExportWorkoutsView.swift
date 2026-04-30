import Foundation
import SwiftUI

// swiftlint:disable file_length

struct ExportWorkoutsView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @ObservedObject private var exerciseMetadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var exerciseRelationshipManager = ExerciseRelationshipManager.shared
    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var logStore: WorkoutLogStore
    @EnvironmentObject private var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager
    @EnvironmentObject private var intentionalBreaksManager: IntentionalBreaksManager

    private let weightUnit = "lbs"

    // Top-level navigation
    @State private var selectedCategory: ExportCategory = .workouts

    // Shared scope (workouts + health)
    @State private var selectedRange: ExportTimeRange = .all
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var didInitializeCustomRange = false
    @State private var activeSheet: ExportSheet?

    // Workouts category
    @State private var workoutMode: WorkoutExportMode = .allWorkouts
    @State private var selectedWorkoutColumns: Set<WorkoutExportColumn> = Set(WorkoutExportColumn.defaultColumns)
    @State private var includeBreakRangesInWorkoutExport = false
    @State private var includeExerciseTags = true
    @State private var selectedExerciseNames: Set<String> = []
    @State private var selectedWorkoutDateIds: Set<String> = []
    @State private var selectedMuscleTagIds: Set<String> = []

    @State private var isExportingWorkouts = false
    @State private var workoutExportStatusMessage: String?
    @State private var workoutExportFileURL: URL?

    @State private var isExportingExercises = false
    @State private var exerciseExportStatusMessage: String?
    @State private var exerciseExportFileURL: URL?

    // Health category
    @State private var healthExportMode: HealthExportMode = .dailySummary
    @State private var selectedHealthSummaryMetrics: Set<HealthMetric> = Set(HealthMetric.allCases)
    @State private var selectedHealthSampleMetrics: Set<HealthMetric> = Set(HealthMetric.allCases.filter(\.supportsSamples))
    @State private var includeHealthWorkoutLocations = false

    @State private var isExportingHealth = false
    @State private var healthExportStatusMessage: String?
    @State private var healthExportFileURL: URL?

    // Backup category
    @State private var isExportingFullBackup = false
    @State private var fullBackupStatusMessage: String?
    @State private var fullBackupFileURL: URL?

    // Errors / share
    @State private var exportErrorMessage: String?
    @State private var shareItem: ExportShareItem?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    heroHeader
                    categoryPicker

                    if dataManager.workouts.isEmpty && selectedCategory != .backup {
                        emptyState
                    } else {
                        categoryPanel
                            .id(selectedCategory)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.vertical, Theme.Spacing.xl)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(maxWidth: Theme.Layout.maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(Theme.Animation.gentleSpring, value: selectedCategory)
                .animation(Theme.Animation.smooth, value: workoutMode)
                .animation(Theme.Animation.smooth, value: healthExportMode)
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("ExportWorkouts")
        .sheet(item: $activeSheet, content: sheetView(for:))
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { newValue in
                if !newValue { exportErrorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Unknown error")
        }
        .onAppear {
            initializeDefaultRangesIfNeeded()
            pruneSelections()
        }
        .onChange(of: dataManager.workouts.count) { _, _ in
            initializeDefaultRangesIfNeeded()
            pruneSelections()
        }
        .onChange(of: selectedRange) { _, _ in
            clearAllExportState()
            pruneSelections()
        }
        .onChange(of: customStartDate) { _, _ in
            guard selectedRange == .custom else { return }
            clearAllExportState()
            pruneSelections()
        }
        .onChange(of: customEndDate) { _, _ in
            guard selectedRange == .custom else { return }
            clearAllExportState()
            pruneSelections()
        }
        .onChange(of: workoutMode) { _, _ in
            clearWorkoutExportState()
        }
        .onChange(of: healthExportMode) { _, _ in
            clearHealthExportState()
        }
        .onChange(of: includeBreakRangesInWorkoutExport) { _, _ in
            clearWorkoutExportState()
        }
        .onChange(of: includeHealthWorkoutLocations) { _, _ in
            clearHealthExportState()
        }
        .onChange(of: includeExerciseTags) { _, _ in
            exerciseExportStatusMessage = nil
            exerciseExportFileURL = nil
        }
    }
}

// MARK: - Hero / Category

private extension ExportWorkoutsView {
    var heroHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Image(systemName: "tray.and.arrow.up.fill")
                    .font(Theme.Iconography.feature)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge, style: .continuous)
                            .fill(Theme.warmGradient)
                    )
                    .shadow(color: Theme.Colors.accentSecondary.opacity(0.30), radius: 14, y: 6)
                    .shadow(color: Theme.Colors.accentSecondary.opacity(0.10), radius: 24, y: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Export & Backup")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(0.5)

                    Text("Save your data your way — workouts, health, or a complete backup.")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    var categoryPicker: some View {
        ExportCategorySegmentedPicker(
            options: ExportCategory.allCases.map { category in
                ExportCategoryOption(
                    id: category.rawValue,
                    title: category.title,
                    systemImage: category.systemImage,
                    tint: category.tint
                )
            },
            selection: $selectedCategory,
            value: { option in
                ExportCategory(rawValue: option.id) ?? .workouts
            }
        )
    }

    var emptyState: some View {
        EmptyStateCard(
            icon: "square.and.arrow.up",
            tint: Theme.Colors.accent,
            title: "No Workouts Yet",
            message: "Once you have workouts logged or imported, they'll be available to export here."
        )
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.lg)
    }

    @ViewBuilder
    var categoryPanel: some View {
        switch selectedCategory {
        case .workouts:
            workoutsPanel
        case .health:
            healthPanel
        case .backup:
            backupPanel
        }
    }
}

// MARK: - Workouts Panel

private extension ExportWorkoutsView {
    var workoutsPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            workoutsScopeCard
            workoutsActionCard
            exerciseListCard
        }
    }

    var workoutsScopeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            cardEyebrow(text: "Step 1", title: "Time Range", systemImage: "calendar.badge.clock", tint: ExportCategory.workouts.tint)
            timeRangePills
            scopeStats
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    var workoutsActionCard: some View {
        let modeOptions: [ExportModeOption<WorkoutExportMode>] = WorkoutExportMode.allCases.map { mode in
            ExportModeOption(
                value: mode,
                title: mode.title,
                subtitle: mode.subtitle(workoutCount: workoutsInSelection.count),
                systemImage: mode.systemImage
            )
        }

        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            cardEyebrow(
                text: "Step 2",
                title: "Workout CSV",
                systemImage: "tablecells",
                tint: ExportCategory.workouts.tint
            )

            ExportFieldGroup(label: "What to export") {
                ExportModeChipPicker(
                    options: modeOptions,
                    selection: $workoutMode,
                    tint: ExportCategory.workouts.tint
                )
            }

            workoutModeDetail

            ExportFieldGroup(
                label: "CSV columns",
                trailing: "\(selectedWorkoutColumns.count) of \(WorkoutExportColumn.allCases.count)"
            ) {
                ExportSelectionButton(
                    title: "Columns",
                    summary: selectedWorkoutColumns.isEmpty ? "Choose columns" : "\(selectedWorkoutColumns.count) selected",
                    previewText: selectedWorkoutColumnPreviewText,
                    action: { openSheet(.workoutColumns) }
                )
            }

            workoutBreakRangeToggle

            VStack(spacing: Theme.Spacing.md) {
                ExportPrimaryButton(
                    title: "Export Workout CSV",
                    isRunning: isExportingWorkouts,
                    isEnabled: workoutExportButtonEnabled,
                    tint: ExportCategory.workouts.tint,
                    action: startWorkoutExport
                )

                if !workoutExportButtonEnabled, !isExportingWorkouts {
                    Text(workoutExportDisabledReason)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }

            ExportLastFileFooter(
                fileName: workoutExportFileURL?.lastPathComponent,
                statusMessage: workoutExportStatusMessage,
                url: workoutExportFileURL,
                onShare: presentShare
            )
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    @ViewBuilder
    var workoutModeDetail: some View {
        switch workoutMode {
        case .allWorkouts:
            EmptyView()
        case .byExercise:
            ExportFieldGroup(
                label: "Exercises",
                trailing: availableExerciseNames.isEmpty ? nil : "\(availableExerciseNames.count) in range"
            ) {
                ExportSelectionButton(
                    title: "Exercises",
                    summary: selectedExerciseNamesInRange.isEmpty ? "Choose exercises" : "\(selectedExerciseNamesInRange.count) selected",
                    previewText: selectedExercisePreviewText,
                    action: { openSheet(.exerciseHistory) }
                )
            }
        case .byMuscle:
            ExportFieldGroup(
                label: "Muscle groups",
                trailing: availableMuscleTags.isEmpty ? nil : "\(availableMuscleTags.count) in range"
            ) {
                ExportSelectionButton(
                    title: "Muscle groups",
                    summary: selectedMuscleTagIdsInRange.isEmpty ? "Choose muscle groups" : "\(selectedMuscleTagIdsInRange.count) selected",
                    previewText: selectedMuscleTagPreviewText,
                    action: { openSheet(.muscleGroups) }
                )
            }
        case .byDate:
            ExportFieldGroup(
                label: "Workout dates",
                trailing: workoutDateOptions.isEmpty ? nil : "\(workoutDateOptions.count) in range"
            ) {
                ExportSelectionButton(
                    title: "Workout dates",
                    summary: selectedWorkoutDateIdsInRange.isEmpty ? "Choose dates" : "\(selectedWorkoutDateIdsInRange.count) selected",
                    previewText: selectedWorkoutDatePreviewText,
                    action: { openSheet(.workoutDates) }
                )
            }
        }
    }

    @ViewBuilder
    var workoutBreakRangeToggle: some View {
        if !breakRangesInSelection.isEmpty {
            Toggle(isOn: $includeBreakRangesInWorkoutExport) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include saved break ranges")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(workoutBreakRangeSummaryText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .tint(ExportCategory.workouts.tint)
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                    .fill(Theme.Colors.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                    .strokeBorder(Theme.Colors.border.opacity(0.4), lineWidth: 1)
            )
            .accessibilityHint("Adds saved break ranges that overlap the export range as context rows in the workout CSV")
        }
    }

    var exerciseListCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            cardEyebrow(
                text: "Companion",
                title: "Exercise List",
                systemImage: "list.bullet.rectangle.portrait",
                tint: ExportCategory.workouts.tint.opacity(0.85)
            )

            Text("A simple, deduplicated list of exercises used in this range. Useful for keeping a master library or sharing your routine.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $includeExerciseTags) {
                Text("Include muscle tags")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .tint(ExportCategory.workouts.tint)

            ExportPrimaryButton(
                title: "Export Exercise List",
                isRunning: isExportingExercises,
                isEnabled: exerciseExportButtonEnabled,
                tint: ExportCategory.workouts.tint,
                action: startExerciseExport
            )

            ExportLastFileFooter(
                fileName: exerciseExportFileURL?.lastPathComponent,
                statusMessage: exerciseExportStatusMessage,
                url: exerciseExportFileURL,
                onShare: presentShare
            )
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    var workoutExportDisabledReason: String {
        if selectedWorkoutColumns.isEmpty {
            return "Select at least one CSV column to enable export."
        }
        switch workoutMode {
        case .allWorkouts:
            return "There are no workouts in the selected time range."
        case .byExercise:
            return availableExerciseNames.isEmpty
                ? "No exercises are available in this range."
                : "Choose at least one exercise to include."
        case .byMuscle:
            return availableMuscleTags.isEmpty
                ? "No muscle groups are available in this range."
                : "Choose at least one muscle group to include."
        case .byDate:
            return workoutDateOptions.isEmpty
                ? "No workout dates are available in this range."
                : "Choose at least one date to include."
        }
    }
}

// MARK: - Health Panel

private extension ExportWorkoutsView {
    @ViewBuilder
    var healthPanel: some View {
        if !healthManager.isHealthKitAvailable() {
            healthUnavailableCard
        } else if healthManager.authorizationStatus != .authorized {
            healthAccessCard
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                healthScopeCard
                healthActionCard
            }
        }
    }

    var healthScopeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            cardEyebrow(text: "Step 1", title: "Time Range", systemImage: "calendar.badge.clock", tint: ExportCategory.health.tint)
            timeRangePills
            scopeStats
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    var healthActionCard: some View {
        let modeOptions: [ExportModeOption<HealthExportMode>] = HealthExportMode.allCases.map { mode in
            ExportModeOption(
                value: mode,
                title: mode.title,
                subtitle: mode.subtitle,
                systemImage: mode.systemImage
            )
        }

        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            cardEyebrow(
                text: "Step 2",
                title: "Apple Health CSV",
                systemImage: "heart.text.square.fill",
                tint: ExportCategory.health.tint
            )

            ExportFieldGroup(label: "Export type") {
                ExportModeChipPicker(
                    options: modeOptions,
                    selection: $healthExportMode,
                    tint: ExportCategory.health.tint
                )
            }

            healthModeDetail

            VStack(spacing: Theme.Spacing.md) {
                ExportPrimaryButton(
                    title: healthExportMode.exportButtonTitle,
                    isRunning: isExportingHealth,
                    isEnabled: healthExportButtonEnabled,
                    tint: ExportCategory.health.tint,
                    action: startHealthExport
                )

                if !healthExportButtonEnabled, !isExportingHealth {
                    Text(healthExportDisabledReason)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }

            ExportLastFileFooter(
                fileName: healthExportFileURL?.lastPathComponent,
                statusMessage: healthExportStatusMessage,
                url: healthExportFileURL,
                onShare: presentShare
            )

            Text(healthExportMode.footnote)
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    @ViewBuilder
    var healthModeDetail: some View {
        switch healthExportMode {
        case .dailySummary:
            ExportFieldGroup(
                label: "Daily metrics",
                trailing: "\(selectedHealthSummaryMetrics.count) of \(availableHealthSummaryMetrics.count)"
            ) {
                ExportSelectionButton(
                    title: "Daily metrics",
                    summary: selectedHealthSummaryMetrics.isEmpty ? "Choose metrics" : "\(selectedHealthSummaryMetrics.count) selected",
                    previewText: selectedHealthSummaryPreviewText,
                    action: { openSheet(.healthDailyMetrics) }
                )
            }
        case .workoutSummary:
            ExportFieldGroup(
                label: "Workouts",
                trailing: "\(workoutsInSelection.count) in range"
            ) {
                Toggle(isOn: $includeHealthWorkoutLocations) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include location data")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Adds workout and route coordinates to the CSV.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .tint(ExportCategory.health.tint)
                .padding(Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                        .fill(Theme.Colors.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                        .strokeBorder(Theme.Colors.border.opacity(0.4), lineWidth: 1)
                )
            }
        case .metricSamples:
            ExportFieldGroup(
                label: "Sample metrics",
                trailing: "\(selectedHealthSampleMetrics.count) of \(availableHealthSampleMetrics.count)"
            ) {
                ExportSelectionButton(
                    title: "Sample metrics",
                    summary: selectedHealthSampleMetrics.isEmpty ? "Choose metrics" : "\(selectedHealthSampleMetrics.count) selected",
                    previewText: selectedHealthSamplePreviewText,
                    action: { openSheet(.healthSampleMetrics) }
                )
            }
        }
    }

    var healthExportDisabledReason: String {
        switch healthExportMode {
        case .dailySummary:
            return selectedHealthSummaryMetrics.isEmpty
                ? "Choose at least one daily metric."
                : ""
        case .workoutSummary:
            return workoutsInSelection.isEmpty
                ? "There are no workouts in the selected time range."
                : ""
        case .metricSamples:
            return selectedHealthSampleMetrics.isEmpty
                ? "Choose at least one metric to sample."
                : ""
        }
    }

    var healthUnavailableCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "heart.slash.fill")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 38, height: 38)
                    .background(Theme.Colors.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Health Unavailable")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Health exports require HealthKit access on a supported device.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Daily summaries, raw metric samples, and workout-linked health exports will appear here when Apple Health is available.")
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    var healthAccessCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "heart.text.square.fill")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(ExportCategory.health.tint)
                    .frame(width: 38, height: 38)
                    .background(ExportCategory.health.tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect Apple Health")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Grant read access to export daily summaries, raw metric samples, or workout-linked health data.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if healthManager.authorizationStatus == .denied {
                Text("Health access is currently denied. Re-enable it in the system Health permissions, then come back here to export.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ExportPrimaryButton(
                title: healthManager.authorizationStatus == .denied ? "Try Health Authorization Again" : "Connect Apple Health",
                isRunning: false,
                isEnabled: true,
                tint: ExportCategory.health.tint,
                action: requestHealthAuthorization
            )
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}

// MARK: - Backup Panel

private extension ExportWorkoutsView {
    var backupPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            backupHeroCard
            backupInventoryCard
        }
    }

    var backupHeroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "archivebox.fill")
                    .font(Theme.Iconography.feature)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                            .fill(Theme.warmGradient)
                    )
                    .shadow(color: Theme.Colors.accentSecondary.opacity(0.30), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Master Backup")
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("One native backup file you can restore on any device. Includes everything below.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ExportPrimaryButton(
                title: "Export Master Backup",
                isRunning: isExportingFullBackup,
                isEnabled: !isExportingFullBackup,
                tint: ExportCategory.backup.tint,
                action: startFullBackupExport
            )

            ExportLastFileFooter(
                fileName: fullBackupFileURL?.lastPathComponent,
                statusMessage: fullBackupStatusMessage,
                url: fullBackupFileURL,
                onShare: presentShare
            )

            Text("Creates a Big Beautiful Workout backup. It does not include previous export files or unfinished workout drafts.")
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    var backupInventoryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            cardEyebrow(text: "Included", title: "What's in this backup", systemImage: "checklist", tint: ExportCategory.backup.tint)

            VStack(spacing: 0) {
                ForEach(backupInventoryItems) { item in
                    if item.id != backupInventoryItems.first?.id {
                        Divider()
                            .background(Theme.Colors.border.opacity(0.4))
                    }
                    ExportInventoryRow(
                        icon: item.icon,
                        title: item.title,
                        value: item.value,
                        tint: ExportCategory.backup.tint
                    )
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    var backupInventoryItems: [BackupInventoryItem] {
        let workouts = dataManager.workouts.count
        let logged = logStore.workouts.count
        let gyms = gymProfilesManager.gyms.count
        let breaks = intentionalBreaksManager.savedBreaks.count
        let workoutHealth = healthManager.healthDataStore.count
        let dailyHealth = healthManager.dailyHealthStore.count
        let annotations = annotationsManager.annotations.count
        let tagOverrides = exerciseMetadataManager.muscleTagOverrides.count
        let metricPrefs = ExerciseMetricManager.shared.cardioOverrides.count
        let relationships = exerciseRelationshipManager.relationships.count

        return [
            BackupInventoryItem(id: "workouts", icon: "figure.strengthtraining.traditional", title: "Workouts", value: "\(workouts)"),
            BackupInventoryItem(id: "logged", icon: "doc.append.fill", title: "Logged sessions", value: "\(logged)"),
            BackupInventoryItem(id: "gyms", icon: "mappin.and.ellipse", title: "Gym profiles", value: "\(gyms)"),
            BackupInventoryItem(id: "breaks", icon: "pause.circle.fill", title: "Break ranges", value: "\(breaks)"),
            BackupInventoryItem(id: "workoutHealth", icon: "heart.circle.fill", title: "Workout health snapshots", value: "\(workoutHealth)"),
            BackupInventoryItem(id: "dailyHealth", icon: "calendar.badge.heart", title: "Daily health entries", value: "\(dailyHealth)"),
            BackupInventoryItem(id: "annotations", icon: "note.text", title: "Workout annotations", value: "\(annotations)"),
            BackupInventoryItem(id: "tagOverrides", icon: "tag.fill", title: "Exercise tag overrides", value: "\(tagOverrides)"),
            BackupInventoryItem(id: "relationships", icon: "rectangle.stack.fill", title: "Exercise relationships", value: "\(relationships)"),
            BackupInventoryItem(id: "metricPrefs", icon: "slider.horizontal.3", title: "Metric preferences", value: "\(metricPrefs)")
        ]
    }
}

// MARK: - Shared Scope (Range + Stats)

private extension ExportWorkoutsView {
    var timeRangePills: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TimeRangePillPicker(
                options: ExportTimeRange.allCases,
                selected: $selectedRange,
                label: { $0.title },
                isSpecialOption: { $0 == .custom },
                onCustomTap: { openSheet(.customRange) }
            )
            .accessibilityLabel("Export time range")
            .accessibilityValue(rangeAccessibilityValue)

            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "calendar")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(rangeSummaryText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Spacer()

                if selectedRange == .custom {
                    Button("Edit") {
                        openSheet(.customRange)
                    }
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var scopeStats: some View {
        let workouts = workoutsInSelection
        let resolver = exerciseRelationshipManager.resolverSnapshot()
        let totalSets = ExerciseAggregation.totalSets(for: workouts, resolver: resolver)
        let totalExercises = Set(
            workouts.flatMap { ExerciseAggregation.aggregateExercises(in: $0, resolver: resolver).map(\.name) }
        ).count

        return HStack(spacing: Theme.Spacing.md) {
            scopeStatTile(label: "Workouts", value: "\(workouts.count)")
            scopeStatTile(label: "Exercises", value: "\(totalExercises)")
            scopeStatTile(label: "Sets", value: "\(totalSets)")
        }
    }

    func scopeStatTile(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.Typography.title4Bold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .fill(Theme.Colors.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .strokeBorder(Theme.Colors.border.opacity(0.4), lineWidth: 1)
        )
    }

    var rangeSummaryText: String {
        let range = effectiveDayRange
        if Calendar.current.isDate(range.start, inSameDayAs: range.endInclusive) {
            return formatDay(range.start)
        }
        return "\(formatDay(range.start)) → \(formatDay(range.endInclusive))"
    }

    func cardEyebrow(text: String, title: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(Theme.Typography.title4)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                    .tracking(1.0)
                Text(title)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Sheets

private extension ExportWorkoutsView {
    @ViewBuilder
    func sheetView(for sheet: ExportSheet) -> some View {
        switch sheet {
        case .customRange:
            ExportCustomRangeSheet(
                startDate: customStartDate,
                endDate: customEndDate,
                earliestSelectableDate: earliestSelectableDate,
                latestSelectableDate: latestSelectableDate
            ) { start, end in
                customStartDate = start
                customEndDate = end
                selectedRange = .custom
            }
        case .workoutColumns:
            ExportWorkoutColumnSelectionSheet(
                selectedColumns: $selectedWorkoutColumns,
                availableColumns: WorkoutExportColumn.allCases
            )
        case .exerciseHistory:
            ExportExerciseSelectionSheet(
                selectedExerciseNames: $selectedExerciseNames,
                availableExerciseNames: availableExerciseNames
            )
        case .workoutDates:
            ExportWorkoutDateSelectionSheet(
                selectedDateIds: $selectedWorkoutDateIds,
                dateOptions: workoutDateOptions
            )
        case .muscleGroups:
            ExportMuscleGroupSelectionSheet(
                selectedTagIds: $selectedMuscleTagIds,
                availableTags: availableMuscleTags
            )
        case .healthDailyMetrics:
            ExportHealthMetricSelectionSheet(
                title: "Daily Health Metrics",
                selectedMetrics: $selectedHealthSummaryMetrics,
                availableMetrics: availableHealthSummaryMetrics
            )
        case .healthSampleMetrics:
            ExportHealthMetricSelectionSheet(
                title: "Raw Sample Metrics",
                selectedMetrics: $selectedHealthSampleMetrics,
                availableMetrics: availableHealthSampleMetrics
            )
        }
    }
}

// MARK: - Derived State

private extension ExportWorkoutsView {
    var workoutExportButtonEnabled: Bool {
        guard !isExportingWorkouts, !selectedWorkoutColumns.isEmpty else { return false }
        switch workoutMode {
        case .allWorkouts:
            return !workoutsInSelection.isEmpty
        case .byExercise:
            return !selectedExerciseNamesInRange.isEmpty
        case .byMuscle:
            return !selectedMuscleTagIdsInRange.isEmpty
        case .byDate:
            return !selectedWorkoutDateIdsInRange.isEmpty
        }
    }

    var exerciseExportButtonEnabled: Bool {
        !isExportingExercises && !workoutsInSelection.isEmpty
    }

    var healthExportButtonEnabled: Bool {
        guard !isExportingHealth else { return false }
        switch healthExportMode {
        case .dailySummary:
            return !selectedHealthSummaryMetrics.isEmpty
        case .workoutSummary:
            return !workoutsInSelection.isEmpty
        case .metricSamples:
            return !selectedHealthSampleMetrics.isEmpty
        }
    }

    var availableHealthSummaryMetrics: [HealthMetric] {
        HealthMetric.allCases.sorted(by: healthMetricAscending)
    }

    var availableHealthSampleMetrics: [HealthMetric] {
        HealthMetric.allCases
            .filter(\.supportsSamples)
            .sorted(by: healthMetricAscending)
    }

    var availableExerciseNames: [String] {
        let resolver = exerciseRelationshipManager.resolverSnapshot()
        let names = workoutsInSelection.reduce(into: Set<String>()) { result, workout in
            for exercise in workout.exercises {
                let rawName = ExerciseIdentityResolver.trimmedName(exercise.name)
                guard !rawName.isEmpty else { continue }
                result.insert(rawName)
                result.insert(resolver.aggregateName(for: rawName))
            }
        }
        return names.sorted(by: localizedAscending)
    }

    var orderedSelectedWorkoutColumns: [WorkoutExportColumn] {
        WorkoutExportColumn.allCases.filter { selectedWorkoutColumns.contains($0) }
    }

    var selectedExerciseNamesInRange: Set<String> {
        selectedExerciseNames.intersection(Set(availableExerciseNames))
    }

    func exerciseMatchesSelection(
        _ exercise: Exercise,
        selectedNameKeys: Set<String>,
        resolver: ExerciseIdentityResolver
    ) -> Bool {
        let rawName = ExerciseIdentityResolver.trimmedName(exercise.name)
        guard !rawName.isEmpty else { return false }
        return selectedNameKeys.contains(ExerciseIdentityResolver.normalizedName(rawName)) ||
            selectedNameKeys.contains(ExerciseIdentityResolver.normalizedName(resolver.aggregateName(for: rawName)))
    }

    var workoutDateOptions: [ExportWorkoutDateOption] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: workoutsInSelection) { workout in
            calendar.startOfDay(for: workout.date)
        }

        return grouped.keys.sorted(by: >).compactMap { day in
            guard let workouts = grouped[day] else { return nil }
            return ExportWorkoutDateOption(
                id: dayIdentifier(for: day),
                date: day,
                workoutCount: workouts.count
            )
        }
    }

    var selectedWorkoutDateIdsInRange: Set<String> {
        selectedWorkoutDateIds.intersection(Set(workoutDateOptions.map(\.id)))
    }

    var availableMuscleTags: [MuscleTag] {
        let resolver = exerciseRelationshipManager.resolverSnapshot()
        let exerciseNames = workoutsInSelection.reduce(into: Set<String>()) { result, workout in
            for exercise in workout.exercises {
                let rawName = ExerciseIdentityResolver.trimmedName(exercise.name)
                guard !rawName.isEmpty else { continue }
                result.insert(rawName)
                result.insert(resolver.aggregateName(for: rawName))
            }
        }
        var uniqueTags: [String: MuscleTag] = [:]

        for exerciseName in exerciseNames {
            for tag in exerciseMetadataManager.resolvedTags(for: exerciseName) {
                uniqueTags[tag.id] = tag
            }
        }

        let builtInOrder: [MuscleGroup: Int] = Dictionary(
            uniqueKeysWithValues: MuscleGroup.allCases.enumerated().map { ($1, $0) }
        )

        return uniqueTags.values.sorted { lhs, rhs in
            switch (lhs.builtInGroup, rhs.builtInGroup) {
            case let (left?, right?):
                let leftOrder = builtInOrder[left] ?? Int.max
                let rightOrder = builtInOrder[right] ?? Int.max
                if leftOrder != rightOrder { return leftOrder < rightOrder }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }

            return localizedAscending(lhs.displayName, rhs.displayName)
        }
    }

    var selectedMuscleTagIdsInRange: Set<String> {
        selectedMuscleTagIds.intersection(Set(availableMuscleTags.map(\.id)))
    }

    var selectedExercisePreviewText: String? {
        previewText(for: Array(selectedExerciseNamesInRange))
    }

    var selectedMuscleTagPreviewText: String? {
        let selectedTagMap = Dictionary(uniqueKeysWithValues: availableMuscleTags.map { ($0.id, $0.displayName) })
        let names = Array(selectedMuscleTagIdsInRange.compactMap { selectedTagMap[$0] })
        return previewText(for: names)
    }

    var selectedWorkoutDatePreviewText: String? {
        let selectedDateMap = Dictionary(uniqueKeysWithValues: workoutDateOptions.map { ($0.id, formatDay($0.date)) })
        let labels = Array(selectedWorkoutDateIdsInRange.compactMap { selectedDateMap[$0] })
        return previewText(for: labels)
    }

    var selectedWorkoutColumnPreviewText: String? {
        previewText(for: orderedSelectedWorkoutColumns.map(\.title))
    }

    var selectedHealthSummaryPreviewText: String? {
        previewText(for: sortedHealthMetrics(selectedHealthSummaryMetrics).map(\.title))
    }

    var selectedHealthSamplePreviewText: String? {
        previewText(for: sortedHealthMetrics(selectedHealthSampleMetrics).map(\.title))
    }

    var workoutsInSelection: [Workout] {
        guard !dataManager.workouts.isEmpty else { return [] }

        let range = effectiveDayRange
        let calendar = Calendar.current
        let endExclusive = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: range.endInclusive)
        ) ?? range.endInclusive

        let baseWorkouts: [Workout]
        if selectedRange == .lastWorkout {
            baseWorkouts = dataManager.workouts.max(by: { $0.date < $1.date }).map { [$0] } ?? []
        } else {
            baseWorkouts = dataManager.workouts
        }

        return baseWorkouts.filter { workout in
            workout.date >= range.start && workout.date < endExclusive
        }
    }

    var breakRangesInSelection: [IntentionalBreakRange] {
        let calendar = Calendar.current
        let range = effectiveDayRange
        let start = calendar.startOfDay(for: range.start)
        let endInclusive = calendar.startOfDay(for: range.endInclusive)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endInclusive) ?? endInclusive

        return intentionalBreaksManager.savedBreaks
            .filter { breakRange in
                let breakStart = calendar.startOfDay(for: breakRange.startDate)
                let breakEnd = calendar.startOfDay(for: breakRange.endDate)
                let breakEndExclusive = calendar.date(byAdding: .day, value: 1, to: breakEnd) ?? breakEnd
                return breakStart < endExclusive && breakEndExclusive > start
            }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
                return (lhs.displayName ?? "").localizedCaseInsensitiveCompare(rhs.displayName ?? "") == .orderedAscending
            }
    }

    var workoutBreakRangeSummaryText: String {
        let count = breakRangesInSelection.count
        if count == 0 {
            return "No saved break ranges overlap this range."
        }
        if count == 1 {
            return "1 saved break range overlaps this range."
        }
        return "\(count) saved break ranges overlap this range."
    }

    var effectiveDayRange: (start: Date, endInclusive: Date) {
        let calendar = Calendar.current
        let fallbackDay = calendar.startOfDay(for: Date())
        let earliest = dataManager.workouts.map(\.date).min().map { calendar.startOfDay(for: $0) }
        let latest = dataManager.workouts.map(\.date).max().map { calendar.startOfDay(for: $0) }
        let referenceDay = latest ?? fallbackDay

        switch selectedRange {
        case .lastWorkout:
            let day = latest ?? fallbackDay
            return (day, day)
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: referenceDay) ?? referenceDay
            return (calendar.startOfDay(for: start), referenceDay)
        case .fourWeeks:
            let start = calendar.date(byAdding: .day, value: -27, to: referenceDay) ?? referenceDay
            return (calendar.startOfDay(for: start), referenceDay)
        case .twelveWeeks:
            let start = calendar.date(byAdding: .day, value: -83, to: referenceDay) ?? referenceDay
            return (calendar.startOfDay(for: start), referenceDay)
        case .sixMonths:
            let start = calendar.date(byAdding: .month, value: -6, to: referenceDay) ?? referenceDay
            return (calendar.startOfDay(for: start), referenceDay)
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: referenceDay) ?? referenceDay
            return (calendar.startOfDay(for: start), referenceDay)
        case .all:
            return (earliest ?? referenceDay, latest ?? referenceDay)
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.startOfDay(for: customEndDate)
            return start <= end ? (start, end) : (end, start)
        }
    }

    var earliestSelectableDate: Date? {
        dataManager.workouts.map(\.date).min().map { Calendar.current.startOfDay(for: $0) }
    }

    var latestSelectableDate: Date {
        let latestWorkoutDate = dataManager.workouts.map(\.date).max()
        return max(Date(), latestWorkoutDate ?? Date())
    }

    var rangeAccessibilityValue: String {
        let range = effectiveDayRange
        return "\(selectedRange.accessibilityTitle), \(formatDay(range.start)) to \(formatDay(range.endInclusive))"
    }

    var healthExportDateInterval: DateInterval {
        let calendar = Calendar.current
        let range = effectiveDayRange
        let start = calendar.startOfDay(for: range.start)
        let end = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: range.endInclusive
        ) ?? range.endInclusive
        return DateInterval(start: start, end: end)
    }
}

// MARK: - Actions

private extension ExportWorkoutsView {
    func openSheet(_ sheet: ExportSheet) {
        activeSheet = sheet
        Haptics.selection()
    }

    func presentShare(_ url: URL) {
        shareItem = ExportShareItem(url: url)
    }

    func showError(_ error: Error) {
        exportErrorMessage = error.localizedDescription
        Haptics.notify(.error)
    }

    @MainActor
    func startFullBackupExport() {
        guard !isExportingFullBackup else { return }
        trackExportStarted(kind: "masterBackup")

        fullBackupStatusMessage = nil
        fullBackupFileURL = nil
        isExportingFullBackup = true

        do {
            let backup = try AppBackupService.makeBackup(
                dataManager: dataManager,
                logStore: logStore,
                healthManager: healthManager,
                annotationsManager: annotationsManager,
                gymProfilesManager: gymProfilesManager,
                intentionalBreaksManager: intentionalBreaksManager
            )
            let fileName = AppBackupService.makeBackupFileName(exportedAt: backup.exportedAt)
            let storageSnapshot = iCloudManager.storageSnapshot()
            let itemCount = backupItemCount(backup)

            Task.detached(priority: .userInitiated) {
                do {
                    guard let directory = storageSnapshot.url else {
                        throw iCloudError.containerNotAvailable
                    }

                    let fileURL = directory.appendingPathComponent(fileName)
                    try AppBackupService.exportBackup(to: fileURL, backup: backup)

                    await MainActor.run {
                        fullBackupFileURL = fileURL
                        fullBackupStatusMessage = storageSnapshot.isUsingLocalFallback
                            ? "Saved on-device (iCloud unavailable)"
                            : "Saved to iCloud Drive"
                        isExportingFullBackup = false
                        trackExportCompleted(kind: "masterBackup", itemCount: itemCount)
                        presentShare(fileURL)
                        Haptics.notify(.success)
                    }
                } catch {
                    await MainActor.run {
                        isExportingFullBackup = false
                        trackExportFailed(kind: "masterBackup", error: error)
                        showError(error)
                    }
                }
            }
        } catch {
            isExportingFullBackup = false
            trackExportFailed(kind: "masterBackup", error: error)
            showError(error)
        }
    }

    @MainActor
    func requestHealthAuthorization() {
        AppAnalytics.shared.track(
            AnalyticsSignal.healthAuthorizationStarted,
            payload: ["Context.source": "export"]
        )
        Task {
            do {
                try await ensureHealthAuthorization()
                Haptics.notify(.success)
            } catch {
                await MainActor.run {
                    showError(error)
                }
            }
        }
    }

    @MainActor
    func startHealthExport() {
        switch healthExportMode {
        case .dailySummary:
            startHealthDailySummaryExport()
        case .workoutSummary:
            startHealthWorkoutSummaryExport()
        case .metricSamples:
            startHealthMetricSamplesExport()
        }
    }

    @MainActor
    func startHealthDailySummaryExport() {
        guard healthExportButtonEnabled else { return }
        trackExportStarted(kind: "healthDailySummary", extra: ["Export.metricCount": "\(selectedHealthSummaryMetrics.count)"])

        healthExportStatusMessage = nil
        healthExportFileURL = nil
        isExportingHealth = true

        let metrics = sortedHealthMetrics(selectedHealthSummaryMetrics)
        let range = effectiveDayRange
        let healthRange = healthExportDateInterval

        Task {
            do {
                try await ensureHealthAuthorization()
                try await healthManager.syncDailyHealthData(range: healthRange)

                let entries = Array(healthManager.dailyHealthStore.values)
                let storageSnapshot = iCloudManager.storageSnapshot()

                Task.detached(priority: .userInitiated) {
                    do {
                        guard let directory = storageSnapshot.url else {
                            throw iCloudError.containerNotAvailable
                        }

                        let data = try HealthCSVExporter.exportDailySummaryCSV(
                            entries: entries,
                            metrics: metrics,
                            startDate: range.start,
                            endDateInclusive: range.endInclusive
                        )

                        let fileName = try HealthCSVExporter.makeDailySummaryExportFileName(
                            startDate: range.start,
                            endDateInclusive: range.endInclusive,
                            metricCount: metrics.count
                        )

                        try iCloudDocumentManager.saveWorkoutFile(data: data, in: directory, fileName: fileName)
                        let fileURL = directory.appendingPathComponent(fileName)

                        await MainActor.run {
                            healthExportFileURL = fileURL
                            healthExportStatusMessage = storageSnapshot.isUsingLocalFallback
                                ? "Saved on-device (iCloud unavailable)"
                                : "Saved to iCloud Drive"
                            isExportingHealth = false
                            trackExportCompleted(
                                kind: "healthDailySummary",
                                itemCount: entries.count,
                                extra: ["Export.metricCount": "\(metrics.count)"]
                            )
                            presentShare(fileURL)
                            Haptics.notify(.success)
                        }
                    } catch {
                        await MainActor.run {
                            isExportingHealth = false
                            trackExportFailed(kind: "healthDailySummary", error: error)
                            showError(error)
                        }
                    }
                }
            } catch {
                isExportingHealth = false
                trackExportFailed(kind: "healthDailySummary", error: error)
                showError(error)
            }
        }
    }

    @MainActor
    func startHealthWorkoutSummaryExport() {
        guard healthExportButtonEnabled else { return }
        trackExportStarted(
            kind: "healthWorkoutSummary",
            extra: ["Export.includeLocations": includeHealthWorkoutLocations ? "true" : "false"]
        )

        healthExportStatusMessage = nil
        healthExportFileURL = nil
        isExportingHealth = true

        let workoutsSnapshot = workoutsInSelection
        let includeLocations = includeHealthWorkoutLocations
        let range = effectiveDayRange

        Task {
            do {
                try await ensureHealthAuthorization()

                let missingWorkouts = workoutsSnapshot.filter { healthManager.getHealthData(for: $0.id) == nil }
                if !missingWorkouts.isEmpty {
                    _ = try await healthManager.syncAllWorkouts(missingWorkouts)
                }

                let healthDataByWorkoutID = Dictionary(
                    uniqueKeysWithValues: workoutsSnapshot.compactMap { workout in
                        healthManager.getHealthData(for: workout.id).map { (workout.id, $0) }
                    }
                )

                let storageSnapshot = iCloudManager.storageSnapshot()

                Task.detached(priority: .userInitiated) {
                    do {
                        guard let directory = storageSnapshot.url else {
                            throw iCloudError.containerNotAvailable
                        }

                        let data = try HealthCSVExporter.exportWorkoutHealthSummaryCSV(
                            workouts: workoutsSnapshot,
                            healthDataByWorkoutID: healthDataByWorkoutID,
                            startDate: range.start,
                            endDateInclusive: range.endInclusive,
                            includeLocationData: includeLocations
                        )

                        let fileName = try HealthCSVExporter.makeWorkoutHealthSummaryExportFileName(
                            startDate: range.start,
                            endDateInclusive: range.endInclusive
                        )

                        try iCloudDocumentManager.saveWorkoutFile(data: data, in: directory, fileName: fileName)
                        let fileURL = directory.appendingPathComponent(fileName)

                        await MainActor.run {
                            healthExportFileURL = fileURL
                            healthExportStatusMessage = storageSnapshot.isUsingLocalFallback
                                ? "Saved on-device (iCloud unavailable)"
                                : "Saved to iCloud Drive"
                            isExportingHealth = false
                            trackExportCompleted(
                                kind: "healthWorkoutSummary",
                                itemCount: workoutsSnapshot.count,
                                extra: ["Export.includeLocations": includeLocations ? "true" : "false"]
                            )
                            presentShare(fileURL)
                            Haptics.notify(.success)
                        }
                    } catch {
                        await MainActor.run {
                            isExportingHealth = false
                            trackExportFailed(kind: "healthWorkoutSummary", error: error)
                            showError(error)
                        }
                    }
                }
            } catch {
                isExportingHealth = false
                trackExportFailed(kind: "healthWorkoutSummary", error: error)
                showError(error)
            }
        }
    }

    @MainActor
    func startHealthMetricSamplesExport() {
        guard healthExportButtonEnabled else { return }
        trackExportStarted(kind: "healthMetricSamples", extra: ["Export.metricCount": "\(selectedHealthSampleMetrics.count)"])

        healthExportStatusMessage = nil
        healthExportFileURL = nil
        isExportingHealth = true

        let metrics = sortedHealthMetrics(selectedHealthSampleMetrics)
        let range = effectiveDayRange
        let healthRange = healthExportDateInterval

        Task {
            do {
                try await ensureHealthAuthorization()

                var samplesByMetric: [HealthMetric: [HealthMetricSample]] = [:]
                for metric in metrics {
                    let samples = try await healthManager.fetchMetricSamples(metric: metric, range: healthRange)
                    if !samples.isEmpty {
                        samplesByMetric[metric] = samples
                    }
                }

                let storageSnapshot = iCloudManager.storageSnapshot()

                Task.detached(priority: .userInitiated) {
                    do {
                        guard let directory = storageSnapshot.url else {
                            throw iCloudError.containerNotAvailable
                        }

                        let data = try HealthCSVExporter.exportMetricSamplesCSV(
                            samplesByMetric: samplesByMetric,
                            startDate: range.start,
                            endDateInclusive: range.endInclusive
                        )

                        let fileName = try HealthCSVExporter.makeMetricSamplesExportFileName(
                            startDate: range.start,
                            endDateInclusive: range.endInclusive,
                            metricCount: metrics.count
                        )

                        try iCloudDocumentManager.saveWorkoutFile(data: data, in: directory, fileName: fileName)
                        let fileURL = directory.appendingPathComponent(fileName)

                        await MainActor.run {
                            healthExportFileURL = fileURL
                            healthExportStatusMessage = storageSnapshot.isUsingLocalFallback
                                ? "Saved on-device (iCloud unavailable)"
                                : "Saved to iCloud Drive"
                            isExportingHealth = false
                            trackExportCompleted(
                                kind: "healthMetricSamples",
                                itemCount: samplesByMetric.values.reduce(0) { $0 + $1.count },
                                extra: ["Export.metricCount": "\(metrics.count)"]
                            )
                            presentShare(fileURL)
                            Haptics.notify(.success)
                        }
                    } catch {
                        await MainActor.run {
                            isExportingHealth = false
                            trackExportFailed(kind: "healthMetricSamples", error: error)
                            showError(error)
                        }
                    }
                }
            } catch {
                isExportingHealth = false
                trackExportFailed(kind: "healthMetricSamples", error: error)
                showError(error)
            }
        }
    }

    @MainActor
    func startWorkoutExport() {
        guard workoutExportButtonEnabled else { return }
        switch workoutMode {
        case .allWorkouts:
            performWorkoutAllExport()
        case .byExercise:
            performExerciseHistoryExport()
        case .byMuscle:
            performMuscleGroupExport()
        case .byDate:
            performWorkoutDatesExport()
        }
    }

    @MainActor
    func performWorkoutAllExport() {
        let selectedColumns = orderedSelectedWorkoutColumns
        let includeBreakRanges = includeBreakRangesInWorkoutExport
        let breakRanges = includeBreakRanges ? breakRangesInSelection : []
        let analyticsPayload = workoutColumnAnalyticsPayload(for: selectedColumns)
            .merging(
                workoutBreakAnalyticsPayload(
                    includeBreakRanges: includeBreakRanges,
                    breakRanges: breakRanges
                )
            ) { _, new in new }
        trackExportStarted(kind: "workouts", extra: analyticsPayload)

        workoutExportStatusMessage = nil
        workoutExportFileURL = nil
        isExportingWorkouts = true

        let range = effectiveDayRange
        let start = range.start
        let end = range.endInclusive

        let workoutsSnapshot: [Workout]
        if selectedRange == .lastWorkout {
            workoutsSnapshot = dataManager.workouts.max(by: { $0.date < $1.date }).map { [$0] } ?? []
        } else {
            workoutsSnapshot = dataManager.workouts
        }

        let exerciseTagsByName = exerciseTagsByName(for: workoutsSnapshot)
        let gymNamesByWorkoutID = gymNamesByWorkoutID(for: workoutsSnapshot)
        let storageSnapshot = iCloudManager.storageSnapshot()
        let unit = weightUnit
        let resolver = exerciseRelationshipManager.resolverSnapshot()

        Task.detached(priority: .userInitiated) {
            do {
                guard let directory = storageSnapshot.url else {
                    throw iCloudError.containerNotAvailable
                }

                let fileName = try WorkoutCSVExporter.makeWorkoutExportFileName(
                    startDate: start,
                    endDateInclusive: end
                )
                let fileURL = directory.appendingPathComponent(fileName)

                try WorkoutCSVExporter.exportWorkoutHistoryCSV(
                    to: fileURL,
                    workouts: workoutsSnapshot,
                    startDate: start,
                    endDateInclusive: end,
                    exerciseTagsByName: exerciseTagsByName,
                    gymNamesByWorkoutID: gymNamesByWorkoutID,
                    selectedColumns: selectedColumns,
                    intentionalBreaks: breakRanges,
                    includeIntentionalBreaks: includeBreakRanges,
                    weightUnit: unit,
                    resolver: resolver
                )

                await MainActor.run {
                    workoutExportFileURL = fileURL
                    workoutExportStatusMessage = storageSnapshot.isUsingLocalFallback
                        ? "Saved on-device (iCloud unavailable)"
                        : "Saved to iCloud Drive"
                    isExportingWorkouts = false
                    trackExportCompleted(
                        kind: "workouts",
                        itemCount: workoutsSnapshot.count,
                        extra: analyticsPayload
                    )
                    presentShare(fileURL)
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    isExportingWorkouts = false
                    trackExportFailed(kind: "workouts", error: error)
                    showError(error)
                }
            }
        }
    }

    @MainActor
    func startExerciseExport() {
        guard exerciseExportButtonEnabled else { return }
        trackExportStarted(
            kind: "exerciseList",
            extra: ["Export.includeTags": includeExerciseTags ? "true" : "false"]
        )

        exerciseExportStatusMessage = nil
        exerciseExportFileURL = nil
        isExportingExercises = true

        let range = effectiveDayRange
        let start = range.start
        let end = range.endInclusive

        let workoutsSnapshot: [Workout]
        if selectedRange == .lastWorkout {
            workoutsSnapshot = dataManager.workouts.max(by: { $0.date < $1.date }).map { [$0] } ?? []
        } else {
            workoutsSnapshot = dataManager.workouts
        }

        let includeTags = includeExerciseTags
        let resolver = exerciseRelationshipManager.resolverSnapshot()
        let exerciseNames = Set(workoutsSnapshot.flatMap { $0.exercises.map(\.name) })
        let exerciseTagsByName: [String: String]
        if includeTags {
            var mapping: [String: String] = [:]
            for name in exerciseNames {
                let tags = exerciseMetadataManager.resolvedTags(for: name)
                mapping[name] = tags.isEmpty ? "" : tags.map(\.displayName).joined(separator: "; ")
            }
            exerciseTagsByName = mapping
        } else {
            exerciseTagsByName = [:]
        }

        let storageSnapshot = iCloudManager.storageSnapshot()

        Task.detached(priority: .userInitiated) {
            do {
                guard let directory = storageSnapshot.url else {
                    throw iCloudError.containerNotAvailable
                }

                let fileName = try WorkoutCSVExporter.makeExerciseListExportFileName(
                    startDate: start,
                    endDateInclusive: end,
                    includeTags: includeTags
                )
                let fileURL = directory.appendingPathComponent(fileName)

                try WorkoutCSVExporter.exportExerciseListCSV(
                    to: fileURL,
                    workouts: workoutsSnapshot,
                    startDate: start,
                    endDateInclusive: end,
                    includeTags: includeTags,
                    exerciseTagsByName: exerciseTagsByName,
                    resolver: resolver
                )

                await MainActor.run {
                    exerciseExportFileURL = fileURL
                    exerciseExportStatusMessage = storageSnapshot.isUsingLocalFallback
                        ? "Saved on-device (iCloud unavailable)"
                        : "Saved to iCloud Drive"
                    isExportingExercises = false
                    trackExportCompleted(
                        kind: "exerciseList",
                        itemCount: exerciseNames.count,
                        extra: ["Export.includeTags": includeTags ? "true" : "false"]
                    )
                    presentShare(fileURL)
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    isExportingExercises = false
                    trackExportFailed(kind: "exerciseList", error: error)
                    showError(error)
                }
            }
        }
    }

    @MainActor
    func performExerciseHistoryExport() {
        let selectedNames = selectedExerciseNamesInRange
        let selectedColumns = orderedSelectedWorkoutColumns
        let includeBreakRanges = includeBreakRangesInWorkoutExport
        let breakRanges = includeBreakRanges ? breakRangesInSelection : []
        let resolver = exerciseRelationshipManager.resolverSnapshot()
        let selectedNameKeys = Set(selectedNames.map(ExerciseIdentityResolver.normalizedName))
        let analyticsPayload = workoutColumnAnalyticsPayload(for: selectedColumns)
            .merging(["Export.selectionCount": "\(selectedNames.count)"]) { _, new in new }
            .merging(
                workoutBreakAnalyticsPayload(
                    includeBreakRanges: includeBreakRanges,
                    breakRanges: breakRanges
                )
            ) { _, new in new }
        trackExportStarted(kind: "exerciseHistory", extra: analyticsPayload)

        workoutExportStatusMessage = nil
        workoutExportFileURL = nil
        isExportingWorkouts = true

        let workoutsSnapshot = workoutsInSelection.compactMap { workout -> Workout? in
            let filteredExercises = workout.exercises.filter {
                exerciseMatchesSelection($0, selectedNameKeys: selectedNameKeys, resolver: resolver)
            }
            guard !filteredExercises.isEmpty else { return nil }
            return Workout(
                id: workout.id,
                date: workout.date,
                name: workout.name,
                duration: workout.duration,
                exercises: filteredExercises
            )
        }

        guard let bounds = dayBounds(for: workoutsSnapshot) else {
            isExportingWorkouts = false
            showError(WorkoutExportError.noWorkoutsInRange)
            return
        }

        let exerciseTagsByName = exerciseTagsByName(for: workoutsSnapshot)
        let gymNamesByWorkoutID = gymNamesByWorkoutID(for: workoutsSnapshot)
        let storageSnapshot = iCloudManager.storageSnapshot()
        let unit = weightUnit
        let selectedExerciseCount = selectedNames.count

        Task.detached(priority: .userInitiated) {
            do {
                guard let directory = storageSnapshot.url else {
                    throw iCloudError.containerNotAvailable
                }

                let fileName = try WorkoutCSVExporter.makeExerciseHistoryExportFileName(
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    selectedExerciseCount: selectedExerciseCount
                )
                let fileURL = directory.appendingPathComponent(fileName)

                try WorkoutCSVExporter.exportWorkoutHistoryCSV(
                    to: fileURL,
                    workouts: workoutsSnapshot,
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    exerciseTagsByName: exerciseTagsByName,
                    gymNamesByWorkoutID: gymNamesByWorkoutID,
                    selectedColumns: selectedColumns,
                    intentionalBreaks: breakRanges,
                    includeIntentionalBreaks: includeBreakRanges,
                    weightUnit: unit,
                    resolver: resolver
                )

                await MainActor.run {
                    workoutExportFileURL = fileURL
                    workoutExportStatusMessage = storageSnapshot.isUsingLocalFallback
                        ? "Saved on-device (iCloud unavailable)"
                        : "Saved to iCloud Drive"
                    isExportingWorkouts = false
                    trackExportCompleted(
                        kind: "exerciseHistory",
                        itemCount: workoutsSnapshot.count,
                        extra: analyticsPayload
                    )
                    presentShare(fileURL)
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    isExportingWorkouts = false
                    trackExportFailed(kind: "exerciseHistory", error: error)
                    showError(error)
                }
            }
        }
    }

    @MainActor
    func performMuscleGroupExport() {
        let selectedTagIds = selectedMuscleTagIdsInRange
        let selectedColumns = orderedSelectedWorkoutColumns
        let includeBreakRanges = includeBreakRangesInWorkoutExport
        let breakRanges = includeBreakRanges ? breakRangesInSelection : []
        let analyticsPayload = workoutColumnAnalyticsPayload(for: selectedColumns)
            .merging(["Export.selectionCount": "\(selectedTagIds.count)"]) { _, new in new }
            .merging(
                workoutBreakAnalyticsPayload(
                    includeBreakRanges: includeBreakRanges,
                    breakRanges: breakRanges
                )
            ) { _, new in new }
        trackExportStarted(kind: "muscleGroup", extra: analyticsPayload)

        workoutExportStatusMessage = nil
        workoutExportFileURL = nil
        isExportingWorkouts = true

        let workoutsSnapshot = workoutsInSelection.compactMap { workout -> Workout? in
            let filteredExercises = workout.exercises.filter { exercise in
                let resolvedTagIds = Set(exerciseMetadataManager.resolvedTags(for: exercise.name).map(\.id))
                return !resolvedTagIds.isDisjoint(with: selectedTagIds)
            }

            guard !filteredExercises.isEmpty else { return nil }
            return Workout(
                id: workout.id,
                date: workout.date,
                name: workout.name,
                duration: workout.duration,
                exercises: filteredExercises
            )
        }

        guard let bounds = dayBounds(for: workoutsSnapshot) else {
            isExportingWorkouts = false
            showError(WorkoutExportError.noWorkoutsInRange)
            return
        }

        let exerciseTagsByName = exerciseTagsByName(for: workoutsSnapshot)
        let gymNamesByWorkoutID = gymNamesByWorkoutID(for: workoutsSnapshot)
        let storageSnapshot = iCloudManager.storageSnapshot()
        let unit = weightUnit
        let selectedGroupCount = selectedTagIds.count
        let resolver = exerciseRelationshipManager.resolverSnapshot()

        Task.detached(priority: .userInitiated) {
            do {
                guard let directory = storageSnapshot.url else {
                    throw iCloudError.containerNotAvailable
                }

                let fileName = try WorkoutCSVExporter.makeMuscleGroupExportFileName(
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    selectedGroupCount: selectedGroupCount
                )
                let fileURL = directory.appendingPathComponent(fileName)

                try WorkoutCSVExporter.exportWorkoutHistoryCSV(
                    to: fileURL,
                    workouts: workoutsSnapshot,
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    exerciseTagsByName: exerciseTagsByName,
                    gymNamesByWorkoutID: gymNamesByWorkoutID,
                    selectedColumns: selectedColumns,
                    intentionalBreaks: breakRanges,
                    includeIntentionalBreaks: includeBreakRanges,
                    weightUnit: unit,
                    resolver: resolver
                )

                await MainActor.run {
                    workoutExportFileURL = fileURL
                    workoutExportStatusMessage = storageSnapshot.isUsingLocalFallback
                        ? "Saved on-device (iCloud unavailable)"
                        : "Saved to iCloud Drive"
                    isExportingWorkouts = false
                    trackExportCompleted(
                        kind: "muscleGroup",
                        itemCount: workoutsSnapshot.count,
                        extra: analyticsPayload
                    )
                    presentShare(fileURL)
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    isExportingWorkouts = false
                    trackExportFailed(kind: "muscleGroup", error: error)
                    showError(error)
                }
            }
        }
    }

    @MainActor
    func performWorkoutDatesExport() {
        let selectedIds = selectedWorkoutDateIdsInRange
        let selectedColumns = orderedSelectedWorkoutColumns
        let includeBreakRanges = includeBreakRangesInWorkoutExport
        let breakRanges = includeBreakRanges ? breakRangesInSelection : []
        let analyticsPayload = workoutColumnAnalyticsPayload(for: selectedColumns)
            .merging(["Export.selectionCount": "\(selectedIds.count)"]) { _, new in new }
            .merging(
                workoutBreakAnalyticsPayload(
                    includeBreakRanges: includeBreakRanges,
                    breakRanges: breakRanges
                )
            ) { _, new in new }
        trackExportStarted(kind: "workoutDates", extra: analyticsPayload)

        workoutExportStatusMessage = nil
        workoutExportFileURL = nil
        isExportingWorkouts = true

        let workoutsSnapshot = workoutsInSelection.filter { workout in
            selectedIds.contains(dayIdentifier(for: workout.date))
        }

        guard let bounds = dayBounds(for: workoutsSnapshot) else {
            isExportingWorkouts = false
            showError(WorkoutExportError.noWorkoutsInRange)
            return
        }

        let exerciseTagsByName = exerciseTagsByName(for: workoutsSnapshot)
        let gymNamesByWorkoutID = gymNamesByWorkoutID(for: workoutsSnapshot)
        let storageSnapshot = iCloudManager.storageSnapshot()
        let unit = weightUnit
        let selectedDateCount = selectedIds.count
        let resolver = exerciseRelationshipManager.resolverSnapshot()

        Task.detached(priority: .userInitiated) {
            do {
                guard let directory = storageSnapshot.url else {
                    throw iCloudError.containerNotAvailable
                }

                let fileName = try WorkoutCSVExporter.makeWorkoutDatesExportFileName(
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    selectedDateCount: selectedDateCount
                )
                let fileURL = directory.appendingPathComponent(fileName)

                try WorkoutCSVExporter.exportWorkoutHistoryCSV(
                    to: fileURL,
                    workouts: workoutsSnapshot,
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    exerciseTagsByName: exerciseTagsByName,
                    gymNamesByWorkoutID: gymNamesByWorkoutID,
                    selectedColumns: selectedColumns,
                    intentionalBreaks: breakRanges,
                    includeIntentionalBreaks: includeBreakRanges,
                    weightUnit: unit,
                    resolver: resolver
                )

                await MainActor.run {
                    workoutExportFileURL = fileURL
                    workoutExportStatusMessage = storageSnapshot.isUsingLocalFallback
                        ? "Saved on-device (iCloud unavailable)"
                        : "Saved to iCloud Drive"
                    isExportingWorkouts = false
                    trackExportCompleted(
                        kind: "workoutDates",
                        itemCount: workoutsSnapshot.count,
                        extra: analyticsPayload
                    )
                    presentShare(fileURL)
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    isExportingWorkouts = false
                    trackExportFailed(kind: "workoutDates", error: error)
                    showError(error)
                }
            }
        }
    }
}

// MARK: - Helpers

private extension ExportWorkoutsView {
    func initializeDefaultRangesIfNeeded() {
        guard !didInitializeCustomRange else { return }
        guard !dataManager.workouts.isEmpty else { return }

        let calendar = Calendar.current
        guard let earliest = dataManager.workouts.map(\.date).min(),
              let latest = dataManager.workouts.map(\.date).max() else {
            return
        }

        customStartDate = calendar.startOfDay(for: earliest)
        customEndDate = calendar.startOfDay(for: latest)
        didInitializeCustomRange = true
    }

    func pruneSelections() {
        selectedExerciseNames = selectedExerciseNames.intersection(Set(availableExerciseNames))
        selectedWorkoutDateIds = selectedWorkoutDateIds.intersection(Set(workoutDateOptions.map(\.id)))
        selectedMuscleTagIds = selectedMuscleTagIds.intersection(Set(availableMuscleTags.map(\.id)))
    }

    func clearAllExportState() {
        clearWorkoutExportState()
        clearHealthExportState()
        exerciseExportStatusMessage = nil
        exerciseExportFileURL = nil
    }

    func clearWorkoutExportState() {
        workoutExportStatusMessage = nil
        workoutExportFileURL = nil
    }

    func clearHealthExportState() {
        healthExportStatusMessage = nil
        healthExportFileURL = nil
    }

    func previewText(for items: [String]) -> String? {
        let sorted = items.sorted(by: localizedAscending)
        guard !sorted.isEmpty else { return nil }

        if sorted.count <= 3 {
            return sorted.joined(separator: ", ")
        }

        let prefix = sorted.prefix(3).joined(separator: ", ")
        return "\(prefix), +\(sorted.count - 3) more"
    }

    func localizedAscending(_ lhs: String, _ rhs: String) -> Bool {
        let insensitive = lhs.localizedCaseInsensitiveCompare(rhs)
        if insensitive != .orderedSame {
            return insensitive == .orderedAscending
        }
        return lhs.localizedCompare(rhs) == .orderedAscending
    }

    func healthMetricAscending(_ lhs: HealthMetric, _ rhs: HealthMetric) -> Bool {
        let categoryComparison = lhs.category.title.localizedCaseInsensitiveCompare(rhs.category.title)
        if categoryComparison != .orderedSame {
            return categoryComparison == .orderedAscending
        }
        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }
        return lhs.rawValue < rhs.rawValue
    }

    func sortedHealthMetrics(_ metrics: Set<HealthMetric>) -> [HealthMetric] {
        metrics.sorted(by: healthMetricAscending)
    }

    @MainActor
    func ensureHealthAuthorization() async throws {
        guard healthManager.isHealthKitAvailable() else {
            throw HealthKitError.notAvailable
        }

        if healthManager.authorizationStatus != .authorized {
            try await healthManager.requestAuthorization()
        }

        guard healthManager.authorizationStatus == .authorized else {
            throw HealthKitError.authorizationFailed("Health access is not authorized.")
        }
    }

    func dayIdentifier(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: date))
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    func dayBounds(for workouts: [Workout]) -> (start: Date, endInclusive: Date)? {
        let calendar = Calendar.current
        guard let earliest = workouts.map(\.date).min(),
              let latest = workouts.map(\.date).max() else {
            return nil
        }
        return (
            start: calendar.startOfDay(for: earliest),
            endInclusive: calendar.startOfDay(for: latest)
        )
    }

    func exerciseTagsByName(for workouts: [Workout]) -> [String: String] {
        let exerciseNames = Set(workouts.flatMap { $0.exercises.map(\.name) })
        var mapping: [String: String] = [:]

        for name in exerciseNames {
            let tags = exerciseMetadataManager.resolvedTags(for: name)
            guard !tags.isEmpty else { continue }
            mapping[name] = tags.map(\.displayName).joined(separator: "; ")
        }

        return mapping
    }

    func gymNamesByWorkoutID(for workouts: [Workout]) -> [UUID: String] {
        let annotations = annotationsManager.annotations
        let gymNames = gymProfilesManager.gymNameSnapshot()
        var mapping: [UUID: String] = [:]

        for workout in workouts {
            guard let gymId = annotations[workout.id]?.gymProfileId,
                  let gymName = gymNames[gymId] else {
                continue
            }
            mapping[workout.id] = gymName
        }

        return mapping
    }

    func workoutColumnAnalyticsPayload(for columns: [WorkoutExportColumn]) -> [String: String] {
        [
            "Export.columnCount": "\(columns.count)",
            "Export.includesGym": columns.contains(.gymName) ? "true" : "false"
        ]
    }

    func workoutBreakAnalyticsPayload(
        includeBreakRanges: Bool,
        breakRanges: [IntentionalBreakRange]
    ) -> [String: String] {
        [
            "Export.includesBreaks": includeBreakRanges ? "true" : "false",
            "Export.breakCount": "\(breakRanges.count)"
        ]
    }

    func backupItemCount(_ backup: BigBeautifulWorkoutBackup) -> Int {
        backup.payload.importedWorkouts.count +
        backup.payload.loggedWorkouts.count +
        backup.payload.gymProfiles.count +
        backup.payload.workoutAnnotations.count +
        backup.payload.workoutHealthData.count +
        backup.payload.dailyHealthData.count +
        backup.payload.exerciseTagOverrides.count +
        backup.payload.exerciseMetricPreferences.count +
        backup.payload.exerciseRelationships.count +
        backup.payload.intentionalBreakRanges.count
    }

    func formatDay(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    func trackExportStarted(kind: String, extra: [String: String] = [:]) {
        AppAnalytics.shared.track(
            AnalyticsSignal.exportStarted,
            payload: baseExportPayload(kind: kind).merging(extra) { _, new in new }
        )
    }

    func trackExportCompleted(kind: String, itemCount: Int, extra: [String: String] = [:]) {
        AppAnalytics.shared.track(
            AnalyticsSignal.exportCompleted,
            payload: baseExportPayload(kind: kind)
                .merging(["Export.itemCount": "\(itemCount)"]) { _, new in new }
                .merging(extra) { _, new in new }
        )
    }

    func trackExportFailed(kind: String, error: Error) {
        AppAnalytics.shared.track(
            AnalyticsSignal.exportFailed,
            payload: baseExportPayload(kind: kind).merging([
                "Export.errorDomain": String(describing: type(of: error))
            ]) { _, new in new }
        )
    }

    func baseExportPayload(kind: String) -> [String: String] {
        [
            "Export.kind": kind,
            "Export.range": selectedRange.accessibilityTitle,
            "Export.workoutCount": "\(workoutsInSelection.count)"
        ]
    }
}

// MARK: - Categories & Modes

private enum ExportCategory: String, CaseIterable, Hashable, Identifiable {
    case workouts
    case health
    case backup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workouts: return "Workouts"
        case .health: return "Apple Health"
        case .backup: return "Backup"
        }
    }

    var systemImage: String {
        switch self {
        case .workouts: return "figure.strengthtraining.traditional"
        case .health: return "heart.text.square.fill"
        case .backup: return "archivebox.fill"
        }
    }

    var tint: Color {
        switch self {
        case .workouts: return Theme.Colors.accent
        case .health: return Theme.Colors.error
        case .backup: return Theme.Colors.accentSecondary
        }
    }
}

private enum WorkoutExportMode: String, CaseIterable, Hashable, Identifiable {
    case allWorkouts
    case byExercise
    case byMuscle
    case byDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allWorkouts: return "All workouts"
        case .byExercise: return "By exercise"
        case .byMuscle: return "By muscle group"
        case .byDate: return "By date"
        }
    }

    func subtitle(workoutCount: Int) -> String {
        switch self {
        case .allWorkouts:
            if workoutCount == 1 { return "Every set from 1 workout in range." }
            return "Every set from \(workoutCount) workouts in range."
        case .byExercise:
            return "Only the exercises you choose."
        case .byMuscle:
            return "Only exercises tagged to chosen muscle groups."
        case .byDate:
            return "Only sessions on chosen dates."
        }
    }

    var systemImage: String {
        switch self {
        case .allWorkouts: return "list.bullet.rectangle.fill"
        case .byExercise: return "chart.line.uptrend.xyaxis"
        case .byMuscle: return "figure.strengthtraining.functional"
        case .byDate: return "calendar.badge.plus"
        }
    }
}

private enum HealthExportMode: String, CaseIterable, Hashable, Identifiable {
    case dailySummary
    case workoutSummary
    case metricSamples

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailySummary: return "Daily summary"
        case .workoutSummary: return "Workout snapshot"
        case .metricSamples: return "Raw samples"
        }
    }

    var subtitle: String {
        switch self {
        case .dailySummary: return "One row per day across the range."
        case .workoutSummary: return "Health stats around each workout."
        case .metricSamples: return "Timestamped samples per metric."
        }
    }

    var systemImage: String {
        switch self {
        case .dailySummary: return "calendar.badge.heart"
        case .workoutSummary: return "heart.circle.fill"
        case .metricSamples: return "waveform.path.ecg"
        }
    }

    var exportButtonTitle: String {
        switch self {
        case .dailySummary: return "Export Daily Summary"
        case .workoutSummary: return "Export Workout Snapshot"
        case .metricSamples: return "Export Raw Samples"
        }
    }

    var footnote: String {
        switch self {
        case .dailySummary:
            return "Refreshes the selected range from Apple Health before exporting. Choose which daily metrics to include, including sleep."
        case .workoutSummary:
            return "Exports the workout-linked Apple Health snapshot for workouts in the current range. Missing entries are synced first when possible."
        case .metricSamples:
            return "Exports raw Health samples in timestamp order. Only metrics that support sample-level export are available."
        }
    }
}

private struct BackupInventoryItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let value: String
}

// MARK: - Time Range

private enum ExportTimeRange: String, CaseIterable, Hashable, Identifiable {
    case lastWorkout = "Last"
    case week = "1w"
    case fourWeeks = "4w"
    case twelveWeeks = "12w"
    case sixMonths = "6m"
    case year = "1y"
    case all = "All"
    case custom = "Custom"

    var id: String { rawValue }
    var title: String { rawValue }

    var accessibilityTitle: String {
        switch self {
        case .lastWorkout: return "Last workout"
        case .week: return "One week"
        case .fourWeeks: return "Four weeks"
        case .twelveWeeks: return "Twelve weeks"
        case .sixMonths: return "Six months"
        case .year: return "One year"
        case .all: return "All time"
        case .custom: return "Custom range"
        }
    }
}

private enum ExportSheet: String, Identifiable {
    case customRange
    case workoutColumns
    case exerciseHistory
    case workoutDates
    case muscleGroups
    case healthDailyMetrics
    case healthSampleMetrics

    var id: String { rawValue }
}

private struct ExportShareItem: Identifiable {
    let url: URL

    var id: String { url.path }
}

// MARK: - Custom Range Sheet

private struct ExportCustomRangeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let earliestSelectableDate: Date?
    let latestSelectableDate: Date
    let onApply: (Date, Date) -> Void

    @State private var draftStartDate: Date
    @State private var draftEndDate: Date

    init(
        startDate: Date,
        endDate: Date,
        earliestSelectableDate: Date?,
        latestSelectableDate: Date,
        onApply: @escaping (Date, Date) -> Void
    ) {
        self.earliestSelectableDate = earliestSelectableDate
        self.latestSelectableDate = latestSelectableDate
        self.onApply = onApply
        _draftStartDate = State(initialValue: startDate)
        _draftEndDate = State(initialValue: endDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        dateCard(
                            title: "Start",
                            selection: $draftStartDate,
                            range: (earliestSelectableDate ?? Date.distantPast)...latestSelectableDate
                        )

                        dateCard(
                            title: "End",
                            selection: $draftEndDate,
                            range: draftStartDate...latestSelectableDate
                        )

                        Button(action: applyRange) {
                            Text("Apply Range")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(Theme.Spacing.md)
                                .background(Theme.Colors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Cancel", systemImage: "xmark", variant: .subtle) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func dateCard(
        title: String,
        selection: Binding<Date>,
        range: ClosedRange<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            DatePicker(
                title,
                selection: selection,
                in: range,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func applyRange() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: draftStartDate)
        let end = calendar.startOfDay(for: draftEndDate)
        onApply(start, end)
        Haptics.selection()
        dismiss()
    }
}

// swiftlint:enable file_length
