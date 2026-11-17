import Foundation
import SwiftUI

// swiftlint:disable file_length

struct ExportWorkoutsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @ObservedObject private var exerciseMetadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var exerciseRelationshipManager = ExerciseRelationshipManager.shared
    @ObservedObject private var exerciseMetricManager = ExerciseMetricManager.shared
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
    @State private var includePDFJournal = false
    @AppStorage("workoutExportFormat") private var workoutExportFormat: WorkoutExportFormat = .csv
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
    @State private var workoutCopyMessage: String?
    @State private var llmEstimate: LLMExportEstimate?
    @State private var showingLogPreview = false
    @State private var llmPreviewError: String?
    @State private var isCopyingWorkoutLog = false

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

                    if dataManager.workouts.isEmpty && selectedCategory == .workouts {
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
                .animation(reduceMotion ? nil : Theme.Animation.gentleSpring, value: selectedCategory)
                .animation(reduceMotion ? nil : Theme.Animation.smooth, value: workoutMode)
                .animation(reduceMotion ? nil : Theme.Animation.smooth, value: healthExportMode)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selectedCategory == .workouts, !dataManager.workouts.isEmpty {
                workoutActionBar
            }
        }
        .collapsingTitle("Export")
        .analyticsScreen("ExportWorkouts")
        .task(id: llmEstimateKey) {
            await refreshLLMEstimate()
        }
        .sheet(item: $activeSheet, content: sheetView(for:))
        .sheet(isPresented: $showingLogPreview) {
            if let llmEstimate {
                WorkoutLogPreviewSheet(text: llmEstimate.preview, totalLines: llmEstimate.lineCount)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { newValue in
                if !newValue { exportErrorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Something went wrong. Try exporting again.")
        }
        .onAppear {
            initializeDefaultRangesIfNeeded()
            pruneSelections()
        }
        .onChange(of: dataManager.datasetRevision) { _, _ in
            initializeDefaultRangesIfNeeded()
            pruneSelections()
            clearWorkoutExportState()
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
        .onChange(of: includePDFJournal) { _, _ in
            clearWorkoutExportState()
        }
        .onChange(of: workoutExportFormat) { _, _ in
            clearWorkoutExportState()
        }
        .onChange(of: selectedWorkoutColumns) { _, _ in
            clearWorkoutExportState()
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
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Export")
                .font(Theme.Typography.displayHeroCompact)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .pageTitleAnchor()
            Text("Save workouts, Apple Health data, or a full backup as files.")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var categoryPicker: some View {
        AppSegmentedPicker(
            title: "Export",
            selection: Binding(
                get: { selectedCategory },
                set: { newValue in
                    guard newValue != selectedCategory else { return }
                    selectedCategory = newValue
                    Haptics.toggle()
                }
            ),
            options: ExportCategory.allCases.map { (label: $0.title, value: $0) }
        )
    }

    var emptyState: some View {
        EmptyStateCard(
            icon: "square.and.arrow.up",
            tint: Theme.Colors.accent,
            title: "No workouts yet",
            message: "Log or import a workout to export it."
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
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            rangeSection { workoutScopeStats }.disabled(isExportingWorkouts)
            workoutSelectionSection.disabled(isExportingWorkouts)
            workoutFormatSection.disabled(isExportingWorkouts)
            exerciseListSection
        }
    }

    var workoutSelectionSection: some View {
        let modeOptions: [ExportModeOption<WorkoutExportMode>] = WorkoutExportMode.allCases.map { mode in
            ExportModeOption(
                value: mode,
                title: mode.title,
                subtitle: mode.subtitle(workoutCount: workoutsInSelection.count),
                systemImage: mode.systemImage
            )
        }

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(title: "Workouts")
            ExportModeChipPicker(options: modeOptions, selection: $workoutMode)
            workoutModeDetail
        }
    }

    var workoutFormatSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(title: "Format")

            ExportFormatPicker(selection: $workoutExportFormat)

            Text(workoutExportFormat.subtitle)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if workoutExportFormat == .llm {
                if let llmEstimate {
                    llmSizePanel(llmEstimate)
                    Button { showingLogPreview = true } label: {
                        TextLinkLabel(title: "Preview training log")
                    }
                    .buttonStyle(PressableCardButtonStyle())
                    .accessibilityIdentifier("workoutExportPreview")
                } else if let llmPreviewError {
                    Text(llmPreviewError)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else if workoutExportButtonEnabled {
                    ProgressView("Preparing preview…")
                        .font(Theme.Typography.subheadline)
                        .tint(Theme.Colors.textSecondary)
                }
            }

            VStack(spacing: 0) {
                if workoutExportFormat == .pdf {
                    LedgerToggleRow(
                        title: "Include every set",
                        subtitle: "Adds a full workout journal after the charts.",
                        isOn: $includePDFJournal
                    )
                    .accessibilityIdentifier("includePDFJournal")
                }

                if workoutExportFormat == .llm {
                    Label {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Complete training data")
                                .font(Theme.Typography.headline)
                            Text("Every field for the workouts you select, including muscle roles and saved breaks. Original values and set order, without sampling.")
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "checkmark.seal")
                            .foregroundStyle(Theme.Colors.success)
                    }
                    .ledgerRow()
                } else {
                    ExportSelectionButton(
                        title: "Fields",
                        summary: selectedWorkoutColumns.isEmpty
                            ? "Choose fields"
                            : "\(selectedWorkoutColumns.count) of \(WorkoutExportColumn.allCases.count)",
                        previewText: selectedWorkoutColumnPreviewText,
                        action: { openSheet(.workoutColumns) }
                    )
                    if !breakRangesInSelection.isEmpty {
                        LedgerToggleRow(
                            title: "Include saved breaks",
                            subtitle: workoutBreakRangeSummaryText,
                            isOn: $includeBreakRangesInWorkoutExport
                        )
                        .accessibilityHint("Adds saved break ranges that overlap the export range")
                    }
                }
            }

            ExportLastFileFooter(
                fileName: workoutExportFileURL?.lastPathComponent,
                statusMessage: workoutExportStatusMessage,
                url: workoutExportFileURL,
                onShare: presentShare
            )

            Button {
                selectedCategory = .backup
            } label: {
                TextLinkLabel(title: "Back up everything instead")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workoutExportBackupShortcut")
        }
    }

    var workoutActionBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let workoutCopyMessage {
                Label(workoutCopyMessage, systemImage: "checkmark")
                    .foregroundStyle(Theme.Colors.success)
                    .font(Theme.Typography.caption)
                    .accessibilityIdentifier("workoutExportCopyStatus")
            } else if !workoutExportButtonEnabled, !isExportingWorkouts {
                Text(workoutExportDisabledReason)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .font(Theme.Typography.caption)
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
            layout {
                ExportPrimaryButton(
                    title: dynamicTypeSize.isAccessibilitySize ? "Export" : "Export \(workoutExportFormat.title)",
                    isRunning: isExportingWorkouts && !isCopyingWorkoutLog,
                    isEnabled: workoutExportButtonEnabled,
                    action: startWorkoutExport
                )
                .accessibilityLabel("Export \(workoutExportFormat.fileNoun)")
                .accessibilityIdentifier("workoutExportSave")
                if workoutExportFormat == .llm {
                    Button(action: copyWorkoutLog) {
                        HStack(spacing: Theme.Spacing.sm) {
                            if isCopyingWorkoutLog { ProgressView().tint(Theme.Colors.textPrimary) }
                            else { Image(systemName: "doc.on.doc") }
                            Text(isCopyingWorkoutLog ? "Copying…" : "Copy")
                                .font(Theme.Typography.headline)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .frame(minHeight: Theme.Layout.primaryControlHeight)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .disabled(!workoutExportButtonEnabled)
                    .accessibilityLabel("Copy training log")
                    .accessibilityIdentifier("workoutExportCopy")
                }
            }
        }
        .padding(.horizontal, Theme.Layout.screenGutter)
        .padding(.vertical, Theme.Spacing.sm)
        .contentColumn()
        .background(Theme.Colors.ground)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.rule).frame(height: 1) }
    }

    /// Byte reduction is measured; token count is explicitly a model-dependent estimate.
    func llmSizePanel(_ estimate: LLMExportEstimate) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
                : AnyLayout(StatColumns())
            layout {
                DisplayStat(value: "~" + compactCount(estimate.tokens), label: "estimated tokens")
                DisplayStat(value: ByteCountFormatter.string(fromByteCount: Int64(estimate.bytes), countStyle: .file), label: "text file")
                DisplayStat(value: "\(estimate.savingsPercent)%", label: "less data than JSON", tint: Theme.Colors.success)
            }
            Text("Token counts vary by AI model. Size compares the same data in the JSON export.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    var workoutModeDetail: some View {
        switch workoutMode {
        case .allWorkouts:
            EmptyView()
        case .byExercise:
            ExportSelectionButton(
                title: "Exercises",
                summary: selectedExerciseNamesInRange.isEmpty
                    ? "Choose from \(availableExerciseNames.count)"
                    : "\(selectedExerciseNamesInRange.count) of \(availableExerciseNames.count)",
                previewText: selectedExercisePreviewText,
                action: { openSheet(.exerciseHistory) }
            )
        case .byMuscle:
            ExportSelectionButton(
                title: "Muscle groups",
                summary: selectedMuscleTagIdsInRange.isEmpty
                    ? "Choose from \(availableMuscleTags.count)"
                    : "\(selectedMuscleTagIdsInRange.count) of \(availableMuscleTags.count)",
                previewText: selectedMuscleTagPreviewText,
                action: { openSheet(.muscleGroups) }
            )
        case .byDate:
            ExportSelectionButton(
                title: "Workout dates",
                summary: selectedWorkoutDateIdsInRange.isEmpty
                    ? "Choose from \(workoutDateOptions.count)"
                    : "\(selectedWorkoutDateIdsInRange.count) of \(workoutDateOptions.count)",
                previewText: selectedWorkoutDatePreviewText,
                action: { openSheet(.workoutDates) }
            )
        }
    }

    var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(title: "Exercise list", subtitle: "Each exercise in this range, once, as a CSV.")

            LedgerToggleRow(title: "Include muscle roles", isOn: $includeExerciseTags, showsRule: false)

            ExportPrimaryButton(
                title: "Export exercise list",
                isRunning: isExportingExercises,
                isEnabled: exerciseExportButtonEnabled,
                isSecondary: true,
                action: startExerciseExport
            )

            ExportLastFileFooter(
                fileName: exerciseExportFileURL?.lastPathComponent,
                statusMessage: exerciseExportStatusMessage,
                url: exerciseExportFileURL,
                onShare: presentShare
            )
        }
    }

    var workoutExportDisabledReason: String {
        if orderedSelectedWorkoutColumns.isEmpty {
            return "Select at least one field."
        }
        switch workoutMode {
        case .allWorkouts:
            return "No workouts in this time range."
        case .byExercise:
            return availableExerciseNames.isEmpty
                ? "No exercises in this range."
                : "Choose at least one exercise."
        case .byMuscle:
            return availableMuscleTags.isEmpty
                ? "No muscle groups in this range."
                : "Choose at least one muscle group."
        case .byDate:
            return workoutDateOptions.isEmpty
                ? "No workout dates in this range."
                : "Choose at least one date."
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
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                rangeSection { healthScopeStats }
                healthActionSection
            }
        }
    }

    @ViewBuilder
    var healthScopeStats: some View {
        let range = effectiveDayRange
        let cachedDays = healthManager.dailyHealthStore.keys.filter {
            $0 >= range.start && Calendar.current.startOfDay(for: $0) <= range.endInclusive
        }.count
        let workoutCount = workoutsInSelection.count
        DisplayStat(value: cachedDays.formatted(), label: cachedDays == 1 ? "daily record" : "daily records")
        DisplayStat(value: workoutCount.formatted(), label: workoutCount == 1 ? "workout" : "workouts")
    }

    var healthActionSection: some View {
        let modeOptions: [ExportModeOption<HealthExportMode>] = HealthExportMode.allCases.map { mode in
            ExportModeOption(
                value: mode,
                title: mode.title,
                subtitle: mode.subtitle,
                systemImage: mode.systemImage
            )
        }

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(title: "Apple Health CSV", help: healthExportMode.footnote)

            VStack(spacing: 0) {
                ExportModeChipPicker(options: modeOptions, selection: $healthExportMode)
                healthModeDetail
            }

            VStack(spacing: Theme.Spacing.sm) {
                ExportPrimaryButton(
                    title: healthExportMode.exportButtonTitle,
                    isRunning: isExportingHealth,
                    isEnabled: healthExportButtonEnabled,
                    action: startHealthExport
                )

                if !healthExportButtonEnabled, !isExportingHealth {
                    Text(healthExportDisabledReason)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ExportLastFileFooter(
                fileName: healthExportFileURL?.lastPathComponent,
                statusMessage: healthExportStatusMessage,
                url: healthExportFileURL,
                onShare: presentShare
            )
        }
    }

    @ViewBuilder
    var healthModeDetail: some View {
        switch healthExportMode {
        case .dailySummary:
            ExportSelectionButton(
                title: "Daily metrics",
                summary: selectedHealthSummaryMetrics.isEmpty
                    ? "Choose metrics"
                    : "\(selectedHealthSummaryMetrics.count) of \(availableHealthSummaryMetrics.count)",
                previewText: selectedHealthSummaryPreviewText,
                action: { openSheet(.healthDailyMetrics) }
            )
        case .workoutSummary:
            LedgerToggleRow(
                title: "Include location data",
                subtitle: "Adds workout and route coordinates to the CSV.",
                isOn: $includeHealthWorkoutLocations
            )
        case .metricSamples:
            ExportSelectionButton(
                title: "Sample metrics",
                summary: selectedHealthSampleMetrics.isEmpty
                    ? "Choose metrics"
                    : "\(selectedHealthSampleMetrics.count) of \(availableHealthSampleMetrics.count)",
                previewText: selectedHealthSamplePreviewText,
                action: { openSheet(.healthSampleMetrics) }
            )
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
                ? "No workouts in this time range."
                : ""
        case .metricSamples:
            return selectedHealthSampleMetrics.isEmpty
                ? "Choose at least one metric to sample."
                : ""
        }
    }

    var healthUnavailableCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Apple Health isn't available")
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Health exports need Apple Health on a supported device.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var healthAccessCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Connect Apple Health")
                    .font(Theme.Typography.sectionHeader2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    healthManager.authorizationStatus == .denied
                        ? "Health access is off. Allow it in the Settings app, then try again."
                        : "Allow read access to export your Health data."
                )
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            ExportPrimaryButton(
                title: healthManager.authorizationStatus == .denied ? "Try Health access again" : "Connect Apple Health",
                isRunning: false,
                isEnabled: true,
                action: requestHealthAuthorization
            )
        }
    }
}

// MARK: - Backup Panel

private extension ExportWorkoutsView {
    var backupPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeading(
                    title: "Full backup",
                    subtitle: "Everything listed below, in one file. Restore it from Settings, then Import."
                )

                ExportPrimaryButton(
                    title: "Export full backup",
                    isRunning: isExportingFullBackup,
                    isEnabled: !isExportingFullBackup,
                    action: startFullBackupExport
                )

                ExportLastFileFooter(
                    fileName: fullBackupFileURL?.lastPathComponent,
                    statusMessage: fullBackupStatusMessage,
                    url: fullBackupFileURL,
                    onShare: presentShare
                )

                Text("Leaves out earlier export files and unfinished workout drafts.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SectionHeading(title: "What's included")
                VStack(spacing: 0) {
                    ForEach(Array(backupInventoryItems.enumerated()), id: \.element.id) { index, item in
                        ExportInventoryRow(title: item.title, value: item.value, showsRule: index > 0)
                    }
                }
            }
        }
    }

    var backupInventoryItems: [BackupInventoryItem] {
        let workouts = dataManager.workouts.count
        let logged = logStore.workouts.count
        let gyms = gymProfilesManager.gyms.count
        let breaks = intentionalBreaksManager.savedBreaks.count
        let workoutHealth = healthManager.healthDataStore.count
        let dailyHealth = healthManager.dailyHealthStore.count
        let annotations = annotationsManager.annotations.count
        let tagOverrides = exerciseMetadataManager.muscleAssignmentOverrides.count
        let metricPrefs = ExerciseMetricManager.shared.cardioOverrides.count
        let relationships = exerciseRelationshipManager.relationships.count

        return [
            BackupInventoryItem(id: "workouts", title: "Workouts", value: "\(workouts)"),
            BackupInventoryItem(id: "logged", title: "Logged sessions", value: "\(logged)"),
            BackupInventoryItem(id: "gyms", title: "Gym profiles", value: "\(gyms)"),
            BackupInventoryItem(id: "breaks", title: "Break ranges", value: "\(breaks)"),
            BackupInventoryItem(id: "workoutHealth", title: "Workout health snapshots", value: "\(workoutHealth)"),
            BackupInventoryItem(id: "dailyHealth", title: "Daily health entries", value: "\(dailyHealth)"),
            BackupInventoryItem(id: "annotations", title: "Workout annotations", value: "\(annotations)"),
            BackupInventoryItem(id: "tagOverrides", title: "Exercise muscle-role overrides", value: "\(tagOverrides)"),
            BackupInventoryItem(id: "relationships", title: "Exercise relationships", value: "\(relationships)"),
            BackupInventoryItem(id: "metricPrefs", title: "Metric preferences", value: "\(metricPrefs)")
        ]
    }
}

// MARK: - Shared Scope (Range + Stats)

private extension ExportWorkoutsView {
    /// The range picker with what that range holds, shown as a stat strip.
    func rangeSection<Stats: View>(@ViewBuilder stats: () -> Stats) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
            : AnyLayout(StatColumns())

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(title: "Range", subtitle: rangeSummaryText) {
                if selectedRange == .custom {
                    Button {
                        openSheet(.customRange)
                    } label: {
                        TextLinkLabel(title: "Edit", showsChevron: false)
                    }
                    .buttonStyle(.plain)
                }
            }

            TimeRangePillPicker(
                options: ExportTimeRange.allCases,
                selected: $selectedRange,
                label: { $0.title },
                isSpecialOption: { $0 == .custom },
                onCustomTap: { openSheet(.customRange) }
            )
            .accessibilityLabel("Export time range")
            .accessibilityValue(rangeAccessibilityValue)

            layout {
                stats()
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard()
        }
    }

    @ViewBuilder
    var workoutScopeStats: some View {
        let workouts = workoutsInSelection
        let totalSets = workouts.reduce(0) { $0 + $1.totalSets }
        let totalExercises = Set(workouts.flatMap { $0.exercises.map(\.name) }).count

        DisplayStat(value: workouts.count.formatted(), label: workouts.count == 1 ? "workout" : "workouts")
        DisplayStat(value: totalExercises.formatted(), label: totalExercises == 1 ? "exercise" : "exercises")
        DisplayStat(value: totalSets.formatted(), label: totalSets == 1 ? "set" : "sets")
    }

    var rangeSummaryText: String {
        let range = effectiveDayRange
        if Calendar.current.isDate(range.start, inSameDayAs: range.endInclusive) {
            return formatDay(range.start)
        }
        return "\(formatDay(range.start)) to \(formatDay(range.endInclusive))"
    }

    func compactCount(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1...2)))
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
                title: "Daily health metrics",
                selectedMetrics: $selectedHealthSummaryMetrics,
                availableMetrics: availableHealthSummaryMetrics
            )
        case .healthSampleMetrics:
            ExportHealthMetricSelectionSheet(
                title: "Raw sample metrics",
                selectedMetrics: $selectedHealthSampleMetrics,
                availableMetrics: availableHealthSampleMetrics
            )
        }
    }
}

// MARK: - Derived State

private extension ExportWorkoutsView {
    var workoutExportButtonEnabled: Bool {
        guard !isExportingWorkouts, !orderedSelectedWorkoutColumns.isEmpty else { return false }
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
        workoutExportFormat == .llm ? WorkoutExportColumn.allCases
            : WorkoutExportColumn.allCases.filter { selectedWorkoutColumns.contains($0) }
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
        let workoutDates = dataManager.workouts.map(\.date)
        let healthStart = selectedCategory == .health ? healthManager.allTimeDailyHealthStartDate : nil
        let earliest = (workoutDates + [healthStart].compactMap { $0 }).min()
            .map { calendar.startOfDay(for: $0) }
        let latestWorkoutDay = workoutDates.max().map { calendar.startOfDay(for: $0) }
        let latest = selectedCategory == .health ? max(latestWorkoutDay ?? fallbackDay, fallbackDay) : latestWorkoutDay
        let referenceDay = latest ?? fallbackDay

        switch selectedRange {
        case .lastWorkout:
            let day = latestWorkoutDay ?? fallbackDay
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
        let healthStart = selectedCategory == .health ? healthManager.allTimeDailyHealthStartDate : nil
        return (dataManager.workouts.map(\.date) + [healthStart].compactMap { $0 }).min()
            .map { Calendar.current.startOfDay(for: $0) }
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

        Task { @MainActor in
            var writer: HealthCSVExporter.MetricSamplesStreamWriter?
            do {
                try await ensureHealthAuthorization()
                let storageSnapshot = iCloudManager.storageSnapshot()
                guard let directory = storageSnapshot.url else {
                    throw iCloudError.containerNotAvailable
                }

                let fileName = try HealthCSVExporter.makeMetricSamplesExportFileName(
                    startDate: range.start,
                    endDateInclusive: range.endInclusive,
                    metricCount: metrics.count
                )
                let fileURL = directory.appendingPathComponent(fileName)
                let streamWriter = try HealthCSVExporter.MetricSamplesStreamWriter(fileURL: fileURL)
                writer = streamWriter
                let calendar = Calendar.current

                for metric in metrics {
                    var chunkStart = healthRange.start
                    while chunkStart < healthRange.end {
                        try Task.checkCancellation()
                        let proposedEnd = calendar.date(byAdding: .day, value: 31, to: chunkStart)
                            ?? healthRange.end
                        let chunkEnd = min(proposedEnd, healthRange.end)
                        guard chunkEnd > chunkStart else { break }
                        let samples = try await healthManager.fetchMetricSamples(
                            metric: metric,
                            range: DateInterval(start: chunkStart, end: chunkEnd)
                        )
                        try Task.checkCancellation()
                        try await streamWriter.append(metric: metric, samples: samples)
                        chunkStart = chunkEnd
                    }
                }

                let exportedCount = try await streamWriter.finish()
                writer = nil
                healthExportFileURL = fileURL
                healthExportStatusMessage = storageSnapshot.isUsingLocalFallback
                    ? "Saved on-device (iCloud unavailable)"
                    : "Saved to iCloud Drive"
                isExportingHealth = false
                trackExportCompleted(
                    kind: "healthMetricSamples",
                    itemCount: exportedCount,
                    extra: ["Export.metricCount": "\(metrics.count)"]
                )
                presentShare(fileURL)
                Haptics.notify(.success)
            } catch {
                await writer?.discard()
                isExportingHealth = false
                trackExportFailed(kind: "healthMetricSamples", error: error)
                showError(error)
            }
        }
    }

    @MainActor
    /// Everything one workout export needs, captured on the main actor so the
    /// document can be built off it. Export, copy, and the size estimate share it.
    func makeWorkoutExportRequest() -> WorkoutExportRequest? {
        let resolver = exerciseRelationshipManager.resolverSnapshot()
        let inRange = workoutsInSelection
        let kind: WorkoutExportRequest.Kind
        let workouts: [Workout]
        var selectionCount: Int?

        func keeping(_ workout: Workout, where matches: (Exercise) -> Bool) -> Workout? {
            let exercises = workout.exercises.filter(matches)
            guard !exercises.isEmpty else { return nil }
            return Workout(
                id: workout.id, date: workout.date, name: workout.name,
                duration: workout.duration, exercises: exercises
            )
        }

        switch workoutMode {
        case .allWorkouts:
            kind = .workouts
            workouts = inRange
        case .byExercise:
            kind = .exerciseHistory
            let names = selectedExerciseNamesInRange
            let keys = Set(names.map(ExerciseIdentityResolver.normalizedName))
            selectionCount = names.count
            workouts = inRange.compactMap { workout in
                keeping(workout) { exerciseMatchesSelection($0, selectedNameKeys: keys, resolver: resolver) }
            }
        case .byMuscle:
            kind = .muscleGroup
            let tagIds = selectedMuscleTagIdsInRange
            selectionCount = tagIds.count
            workouts = inRange.compactMap { workout in
                keeping(workout) { exercise in
                    let resolved = Set(exerciseMetadataManager.resolvedTags(for: exercise.name).map(\.id))
                    return !resolved.isDisjoint(with: tagIds)
                }
            }
        case .byDate:
            kind = .workoutDates
            let dayIds = selectedWorkoutDateIdsInRange
            selectionCount = dayIds.count
            workouts = inRange.filter { dayIds.contains(dayIdentifier(for: $0.date)) }
        }

        guard !workouts.isEmpty else { return nil }
        let bounds = effectiveDayRange
        let includesBreaks = workoutExportFormat == .llm || includeBreakRangesInWorkoutExport
        let workoutIDs = Set(workouts.map(\.id))
        return WorkoutExportRequest(
            kind: kind,
            workouts: workouts,
            start: bounds.start,
            endInclusive: bounds.endInclusive,
            selectionCount: selectionCount,
            columns: orderedSelectedWorkoutColumns,
            breaks: includesBreaks ? breakRangesInSelection : [],
            includesBreaks: includesBreaks,
            exerciseTagsByName: exerciseTagsByName(for: workouts),
            exerciseMusclesByName: exerciseMusclesByName(for: workouts),
            gymNamesByWorkoutID: gymNamesByWorkoutID(for: workouts),
            weightUnit: weightUnit,
            resolver: resolver,
            calendar: Calendar.current,
            nativeWorkouts: workoutExportFormat == .llm
                ? logStore.workouts.filter { workoutIDs.contains($0.id) } : [],
            exerciseCountLabelsByName: exerciseMetricManager.exportCountLabels(for: Set(workouts.flatMap { $0.exercises.map(\.name) }))
        )
    }

    func workoutExportAnalyticsPayload(for request: WorkoutExportRequest) -> [String: String] {
        var payload = workoutColumnAnalyticsPayload(for: request.columns)
            .merging(
                workoutBreakAnalyticsPayload(includeBreakRanges: request.includesBreaks, breakRanges: request.breaks)
            ) { _, new in new }
        if let selectionCount = request.selectionCount {
            payload["Export.selectionCount"] = "\(selectionCount)"
        }
        return payload
    }

    @MainActor
    func startWorkoutExport() {
        guard workoutExportButtonEnabled else { return }
        guard let request = makeWorkoutExportRequest() else {
            showError(WorkoutExportError.noWorkoutsInRange)
            return
        }
        let format = workoutExportFormat
        let includeJournal = includePDFJournal
        let kind = request.kind.rawValue
        let analyticsPayload = workoutExportAnalyticsPayload(for: request)
        trackExportStarted(kind: kind, extra: analyticsPayload)

        clearWorkoutExportState()
        isExportingWorkouts = true
        let storageSnapshot = iCloudManager.storageSnapshot()

        Task.detached(priority: .userInitiated) {
            do {
                guard let directory = storageSnapshot.url else {
                    throw iCloudError.containerNotAvailable
                }
                let fileURL = directory.appendingPathComponent(format.fileName(from: try request.fileName()))
                try request.makeDocument().write(to: fileURL, format: format, includePDFJournal: includeJournal)

                await MainActor.run {
                    workoutExportFileURL = fileURL
                    workoutExportStatusMessage = storageSnapshot.isUsingLocalFallback
                        ? "Saved on this iPhone. iCloud Drive is unavailable."
                        : "Saved to iCloud Drive."
                    isExportingWorkouts = false
                    trackExportCompleted(kind: kind, itemCount: request.workouts.count, extra: analyticsPayload)
                    presentShare(fileURL)
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    isExportingWorkouts = false
                    isCopyingWorkoutLog = false
                    trackExportFailed(kind: kind, error: error)
                    showError(error)
                }
            }
        }
    }

    /// Puts the LLM log on the clipboard so it can be pasted straight into a chat.
    @MainActor
    func copyWorkoutLog() {
        guard workoutExportButtonEnabled else { return }
        guard let request = makeWorkoutExportRequest() else {
            showError(WorkoutExportError.noWorkoutsInRange)
            return
        }
        let analyticsPayload = workoutExportAnalyticsPayload(for: request)
            .merging(["Export.destination": "clipboard"]) { _, new in new }
        let kind = request.kind.rawValue
        trackExportStarted(kind: kind, extra: analyticsPayload)
        workoutCopyMessage = nil
        isCopyingWorkoutLog = true
        isExportingWorkouts = true

        Task.detached(priority: .userInitiated) {
            do {
                let text = WorkoutCompactLogRenderer.render(try request.makeDocument())
                let tokens = WorkoutCompactLogRenderer.estimatedTokenCount(characters: text.count)
                await MainActor.run {
                    UIPasteboard.general.string = text
                    isExportingWorkouts = false
                    isCopyingWorkoutLog = false
                    workoutCopyMessage = "Copied. About \(compactCount(tokens)) tokens, ready to paste."
                    trackExportCompleted(kind: kind, itemCount: request.workouts.count, extra: analyticsPayload)
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    isExportingWorkouts = false
                    isCopyingWorkoutLog = false
                    trackExportFailed(kind: kind, error: error)
                    showError(error)
                }
            }
        }
    }

    /// Changes whenever the LLM log's contents would. Nil while another format is selected.
    var llmEstimateKey: Int? {
        guard selectedCategory == .workouts, workoutExportFormat == .llm else { return nil }
        var hasher = Hasher()
        let range = effectiveDayRange
        hasher.combine(range.start)
        hasher.combine(range.endInclusive)
        hasher.combine(selectedRange)
        hasher.combine(workoutMode)
        hasher.combine(selectedWorkoutColumns)
        hasher.combine(selectedExerciseNames)
        hasher.combine(selectedWorkoutDateIds)
        hasher.combine(selectedMuscleTagIds)
        hasher.combine(includeBreakRangesInWorkoutExport)
        hasher.combine(dataManager.datasetRevision)
        hasher.combine(exerciseMetadataManager.muscleAssignmentOverrides)
        hasher.combine(exerciseRelationshipManager.relationships)
        hasher.combine(exerciseMetricManager.cardioOverrides)
        hasher.combine(annotationsManager.annotations.mapValues(\.gymProfileId))
        hasher.combine(gymProfilesManager.gyms)
        hasher.combine(intentionalBreaksManager.savedBreaks)
        return hasher.finalize()
    }

    @MainActor
    func refreshLLMEstimate() async {
        guard llmEstimateKey != nil, !orderedSelectedWorkoutColumns.isEmpty,
              let request = makeWorkoutExportRequest() else {
            llmEstimate = nil
            return
        }
        llmEstimate = nil
        llmPreviewError = nil
        // Let a burst of selection changes settle before measuring.
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }

        let estimate = await Task.detached(priority: .utility) { () -> LLMExportEstimate? in
            guard let document = try? request.makeDocument() else { return nil }
            let text = WorkoutCompactLogRenderer.render(document)
            let lines = text.components(separatedBy: "\n")
            return LLMExportEstimate(
                tokens: WorkoutCompactLogRenderer.estimatedTokenCount(characters: text.count),
                bytes: text.utf8.count,
                jsonBytes: (try? document.jsonData().count) ?? 0,
                preview: lines.prefix(60).joined(separator: "\n"),
                lineCount: lines.count
            )
        }.value
        guard !Task.isCancelled else { return }
        llmEstimate = estimate
        llmPreviewError = estimate == nil ? "No logged sets to preview in this selection." : nil
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
                let assignments = exerciseMetadataManager.resolvedAssignments(for: name)
                mapping[name] = MuscleContributionPolicy.exportDescription(assignments)
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
        workoutCopyMessage = nil
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

    func exerciseMusclesByName(for workouts: [Workout]) -> [String: [WorkoutExportMuscle]] {
        let names = Set(workouts.flatMap { $0.exercises.map(\.name) })
        return Dictionary(uniqueKeysWithValues: names.map { name in
            (name, exerciseMetadataManager.resolvedAssignments(for: name).map {
                WorkoutExportMuscle(name: $0.tag.displayName, role: $0.role.rawValue)
            })
        })
    }

    func exerciseTagsByName(for workouts: [Workout]) -> [String: String] {
        let exerciseNames = Set(workouts.flatMap { $0.exercises.map(\.name) })
        var mapping: [String: String] = [:]

        for name in exerciseNames {
            let assignments = exerciseMetadataManager.resolvedAssignments(for: name)
            guard !assignments.isEmpty else { continue }
            mapping[name] = MuscleContributionPolicy.exportDescription(assignments)
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
            "Export.format": workoutExportFormat.rawValue,
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
        max(
            backup.payload.exerciseMuscleAssignmentOverrides.count,
            backup.payload.exerciseTagOverrides.count
        ) +
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

    /// Every export category shares the ink accent; color isn't carrying meaning here.
    var tint: Color { Theme.Colors.accent }
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
            if workoutCount == 1 { return "1 workout" }
            return "\(workoutCount) workouts"
        case .byExercise:
            return "Selected exercises"
        case .byMuscle:
            return "Selected muscle groups"
        case .byDate:
            return "Selected dates"
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
        case .dailySummary: return "Export daily summary"
        case .workoutSummary: return "Export workout snapshot"
        case .metricSamples: return "Export raw samples"
        }
    }

    var footnote: String {
        switch self {
        case .dailySummary:
            return "Refreshes the selected range from Apple Health, then exports one row per day for your chosen metrics."
        case .workoutSummary:
            return "Exports Health data linked to workouts in this range. Missing entries are synced first when available."
        case .metricSamples:
            return "Exports raw Health samples in time order. Only metrics with sample data are listed."
        }
    }
}

/// A snapshot of one workout export, safe to hand to a background task.
private nonisolated struct WorkoutExportRequest: Sendable {
    enum Kind: String, Sendable {
        case workouts
        case exerciseHistory
        case muscleGroup
        case workoutDates

        var analysisScope: String {
            switch self {
            case .workouts: return "all workouts in the selected date range"
            case .exerciseHistory: return "selected exercises only; other exercises are excluded"
            case .muscleGroup: return "selected muscle groups only; other exercises are excluded"
            case .workoutDates: return "selected workout dates only; other dates are excluded"
            }
        }
    }

    let kind: Kind
    let workouts: [Workout]
    let start: Date
    let endInclusive: Date
    let selectionCount: Int?
    let columns: [WorkoutExportColumn]
    let breaks: [IntentionalBreakRange]
    let includesBreaks: Bool
    let exerciseTagsByName: [String: String]
    let exerciseMusclesByName: [String: [WorkoutExportMuscle]]
    let gymNamesByWorkoutID: [UUID: String]
    let weightUnit: String
    let resolver: ExerciseIdentityResolver
    let calendar: Calendar
    let nativeWorkouts: [LoggedWorkout]
    let exerciseCountLabelsByName: [String: String]

    func makeDocument() throws -> WorkoutExportDocument {
        try WorkoutExportDocument(
            workouts: workouts,
            startDate: start,
            endDateInclusive: endInclusive,
            exerciseTagsByName: exerciseTagsByName,
            exerciseMusclesByName: exerciseMusclesByName,
            gymNamesByWorkoutID: gymNamesByWorkoutID,
            selectedColumns: columns,
            intentionalBreaks: breaks,
            includeIntentionalBreaks: includesBreaks,
            weightUnit: weightUnit,
            resolver: resolver,
            calendar: calendar,
            nativeWorkouts: nativeWorkouts,
            exerciseCountLabelsByName: exerciseCountLabelsByName,
            selectionScope: kind.analysisScope
        )
    }

    /// The CSV-style name for this export; the chosen format swaps the extension.
    func fileName() throws -> String {
        switch kind {
        case .workouts:
            return try WorkoutCSVExporter.makeWorkoutExportFileName(
                startDate: start, endDateInclusive: endInclusive, calendar: calendar
            )
        case .exerciseHistory:
            return try WorkoutCSVExporter.makeExerciseHistoryExportFileName(
                startDate: start, endDateInclusive: endInclusive,
                selectedExerciseCount: selectionCount ?? 0, calendar: calendar
            )
        case .muscleGroup:
            return try WorkoutCSVExporter.makeMuscleGroupExportFileName(
                startDate: start, endDateInclusive: endInclusive,
                selectedGroupCount: selectionCount ?? 0, calendar: calendar
            )
        case .workoutDates:
            return try WorkoutCSVExporter.makeWorkoutDatesExportFileName(
                startDate: start, endDateInclusive: endInclusive,
                selectedDateCount: selectionCount ?? 0, calendar: calendar
            )
        }
    }
}

private nonisolated struct LLMExportEstimate: Equatable, Sendable {
    let tokens: Int
    let bytes: Int
    let jsonBytes: Int
    let preview: String
    let lineCount: Int

    var savingsPercent: Int {
        guard jsonBytes > 0 else { return 0 }
        return max(0, Int((100 * (1 - Double(bytes) / Double(jsonBytes))).rounded()))
    }
}

private struct BackupInventoryItem: Identifiable {
    let id: String
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

                        AppPrimaryButton(title: "Apply range", action: applyRange)
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationTitle("Custom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
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
