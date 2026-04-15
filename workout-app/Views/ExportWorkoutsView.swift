import Foundation
import SwiftUI

// swiftlint:disable file_length

struct ExportWorkoutsView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @ObservedObject private var exerciseMetadataManager = ExerciseMetadataManager.shared
    @EnvironmentObject private var healthManager: HealthKitManager
    @EnvironmentObject private var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager

    private let weightUnit = "lbs"
    private let maxContentWidth: CGFloat = 820

    @State private var selectedRange: ExportTimeRange = .all
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var didInitializeCustomRange = false
    @State private var isFilteredExportsExpanded = false
    @State private var activeSheet: ExportSheet?

    @State private var isExportingWorkouts = false
    @State private var workoutExportStatusMessage: String?
    @State private var workoutExportFileURL: URL?
    @State private var selectedWorkoutColumns: Set<WorkoutExportColumn> = Set(WorkoutExportColumn.defaultColumns)

    @State private var includeExerciseTags = true
    @State private var isExportingExercises = false
    @State private var exerciseExportStatusMessage: String?
    @State private var exerciseExportFileURL: URL?

    @State private var selectedExerciseNames: Set<String> = []
    @State private var isExportingExerciseHistory = false
    @State private var exerciseHistoryExportStatusMessage: String?
    @State private var exerciseHistoryExportFileURL: URL?

    @State private var selectedWorkoutDateIds: Set<String> = []
    @State private var isExportingWorkoutDates = false
    @State private var workoutDatesExportStatusMessage: String?
    @State private var workoutDatesExportFileURL: URL?

    @State private var selectedMuscleTagIds: Set<String> = []
    @State private var isExportingMuscleGroups = false
    @State private var muscleGroupExportStatusMessage: String?
    @State private var muscleGroupExportFileURL: URL?

    @State private var exportErrorMessage: String?
    @State private var shareItem: ExportShareItem?

    @State private var selectedHealthSummaryMetrics: Set<HealthMetric> = Set(HealthMetric.allCases)
    @State private var selectedHealthSampleMetrics: Set<HealthMetric> = Set(HealthMetric.allCases.filter(\.supportsSamples))
    @State private var includeHealthWorkoutLocations = false

    @State private var isExportingHealthDailySummary = false
    @State private var healthDailySummaryStatusMessage: String?
    @State private var healthDailySummaryFileURL: URL?

    @State private var isExportingHealthWorkoutSummary = false
    @State private var healthWorkoutSummaryStatusMessage: String?
    @State private var healthWorkoutSummaryFileURL: URL?

    @State private var isExportingHealthMetricSamples = false
    @State private var healthMetricSamplesStatusMessage: String?
    @State private var healthMetricSamplesFileURL: URL?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    if dataManager.workouts.isEmpty {
                        emptyState
                    } else {
                        overviewSection
                        quickExportsSection
                        appleHealthSection
                        filteredExportsSection
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("ExportWorkouts")
        .sheet(item: $activeSheet) { sheet in
            sheetView(for: sheet)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    exportErrorMessage = nil
                }
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
            clearExportState()
            pruneSelections()
        }
        .onChange(of: customStartDate) { _, _ in
            guard selectedRange == .custom else { return }
            clearExportState()
            pruneSelections()
        }
        .onChange(of: customEndDate) { _, _ in
            guard selectedRange == .custom else { return }
            clearExportState()
            pruneSelections()
        }
    }
}

// MARK: - Layout

private extension ExportWorkoutsView {
    var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Image(systemName: "square.and.arrow.up")
                    .font(Theme.Iconography.display)
                    .foregroundStyle(.white)
                    .padding()
                    .background(
                        Circle()
                            .fill(Theme.warmGradient)
                    )
                    .shadow(color: Theme.Colors.accentSecondary.opacity(0.25), radius: 12, y: 4)
                    .shadow(color: Theme.Colors.accentSecondary.opacity(0.10), radius: 24, y: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Export Workouts")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.5)

                    Text("Create CSV backups for your full history or just the slices you need.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    var emptyState: some View {
        EmptyStateCard(
            icon: "square.and.arrow.up",
            tint: Theme.Colors.accent,
            title: "No Workouts",
            message: "Import workouts before exporting."
        )
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    var overviewSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ExportSectionHeader(
                eyebrow: "Shared Range",
                title: "Export Scope",
                subtitle: "Choose the time window that every export starts from."
            )

            rangeCard
            summaryCard
            workoutColumnSelectionCard
        }
    }

    var quickExportsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ExportSectionHeader(
                eyebrow: "Workout Exports",
                title: "Quick Exports",
                subtitle: "Use these when you want the broadest backup or a clean exercise inventory."
            )

            workoutExportCard
            exerciseExportCard
        }
    }

    var appleHealthSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ExportSectionHeader(
                eyebrow: "Health Exports",
                title: "Apple Health",
                subtitle: "Export daily summaries, workout-linked health data, or raw Health samples to CSV."
            )

            if !healthManager.isHealthKitAvailable() {
                healthUnavailableCard
            } else if healthManager.authorizationStatus != .authorized {
                healthAccessCard
            } else {
                healthDailySummaryCard
                healthWorkoutSummaryCard
                healthMetricSamplesCard
            }
        }
    }

    var filteredExportsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ExportSectionHeader(
                eyebrow: "Targeted Exports",
                title: "Filtered Workout Exports",
                subtitle: "Targeted workout CSVs for specific exercises, muscle groups, or dates."
            )

            CollapsibleSection(
                title: "Filtered Exports",
                subtitle: "Targeted CSVs for specific exercises, muscle groups, or workout dates.",
                isExpanded: $isFilteredExportsExpanded
            ) {
                VStack(spacing: Theme.Spacing.md) {
                    exerciseHistoryExportCard
                    muscleGroupExportCard
                    workoutDatesExportCard
                }
            }
        }
    }

    var rangeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Time Range")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }

            Text("Preset")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            TimeRangePillPicker(
                options: ExportTimeRange.allCases,
                selected: $selectedRange,
                label: { $0.title },
                isSpecialOption: { $0 == .custom },
                onCustomTap: {
                    openSheet(.customRange)
                }
            )
            .accessibilityLabel("Export time range")
            .accessibilityValue(rangeAccessibilityValue)

            rangeDetails
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    var rangeDetails: some View {
        let range = effectiveDayRange

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Current range")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Spacer()

                Text(selectedRange.accessibilityTitle)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            HStack {
                Text("Start")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(formatDay(range.start))
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            HStack {
                Text("End")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(formatDay(range.endInclusive))
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            if selectedRange == .custom {
                Button("Edit Custom Range") {
                    openSheet(.customRange)
                }
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
                .buttonStyle(.plain)
                .accessibilityHint("Adjust the custom export dates")
            }
        }
        .padding(.top, Theme.Spacing.xs)
    }

    var summaryCard: some View {
        let workouts = workoutsInSelection
        let totalSets = workouts.reduce(0) { $0 + $1.totalSets }
        let totalExercises = Set(workouts.flatMap { $0.exercises.map(\.name) }).count

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Summary")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    ExportSummaryMetricTile(title: "Workouts", value: "\(workouts.count)")
                    ExportSummaryMetricTile(title: "Exercises", value: "\(totalExercises)")
                    ExportSummaryMetricTile(title: "Sets", value: "\(totalSets)")
                }

                VStack(spacing: Theme.Spacing.sm) {
                    ExportSummaryMetricTile(title: "Workouts", value: "\(workouts.count)")
                    HStack(spacing: Theme.Spacing.md) {
                        ExportSummaryMetricTile(title: "Exercises", value: "\(totalExercises)")
                        ExportSummaryMetricTile(title: "Sets", value: "\(totalSets)")
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    var workoutColumnSelectionCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "tablecells")
                    .font(Theme.Typography.title4)
                    .foregroundStyle(Theme.Colors.accentSecondary)
                    .frame(width: 34, height: 34)
                    .background(Theme.Colors.accentSecondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Workout CSV Columns")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Choose the fields included in workout, exercise history, muscle group, and date CSVs.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            ExportSelectionButton(
                title: "Columns",
                summary: selectedWorkoutColumns.isEmpty ? "Choose columns" : "\(selectedWorkoutColumns.count) selected",
                previewText: selectedWorkoutColumnPreviewText,
                action: {
                    openSheet(.workoutColumns)
                }
            )
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    var workoutExportCard: some View {
        ExportActionCard(
            descriptor: ExportCardDescriptor(
                title: "Export Workouts",
                subtitle: "A full CSV of every workout in the selected time range.",
                systemImage: "square.and.arrow.up.on.square"
            ),
            statusMessage: workoutExportStatusMessage,
            fileName: workoutExportFileURL?.lastPathComponent,
            footnote: "Exports a compact CSV with workout and exercise details shown once per session. Selected columns control which fields appear.",
            isRunning: isExportingWorkouts,
            isEnabled: workoutExportButtonEnabled,
            shareURL: workoutExportFileURL,
            onAction: startWorkoutExport,
            onShare: presentShare
        )
    }

    var exerciseExportCard: some View {
        ExportActionCard(
            descriptor: ExportCardDescriptor(
                title: "Export Exercises",
                subtitle: "A deduplicated list of exercises used in the current time range.",
                systemImage: "list.bullet.rectangle.portrait"
            ),
            statusMessage: exerciseExportStatusMessage,
            fileName: exerciseExportFileURL?.lastPathComponent,
            footnote: "Exports a unique list of exercises within the selected time range. Tags come from your exercise tagging settings.",
            isRunning: isExportingExercises,
            isEnabled: exerciseExportButtonEnabled,
            shareURL: exerciseExportFileURL,
            onAction: startExerciseExport,
            onShare: presentShare
        ) {
            Toggle(isOn: $includeExerciseTags) {
                Text("Include tags")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .tint(Theme.Colors.accent)
            .accessibilityHint("Controls whether exercise tag columns are included in the CSV")
        }
    }

    var exerciseHistoryExportCard: some View {
        ExportActionCard(
            descriptor: ExportCardDescriptor(
                title: "Export Exercise History",
                subtitle: "Set-level history for only the exercises you choose.",
                systemImage: "chart.line.uptrend.xyaxis"
            ),
            statusMessage: exerciseHistoryExportStatusMessage,
            fileName: exerciseHistoryExportFileURL?.lastPathComponent,
            footnote: "Exports selected workout CSV columns, but only for the exercises you choose.",
            isRunning: isExportingExerciseHistory,
            isEnabled: exerciseHistoryExportButtonEnabled,
            shareURL: exerciseHistoryExportFileURL,
            onAction: startExerciseHistoryExport,
            onShare: presentShare
        ) {
            ExportSelectionButton(
                title: "Exercises",
                summary: selectedExerciseNamesInRange.isEmpty ? "Choose exercises" : "\(selectedExerciseNamesInRange.count) selected",
                previewText: selectedExercisePreviewText,
                action: {
                    isFilteredExportsExpanded = true
                    openSheet(.exerciseHistory)
                }
            )
        }
    }

    var muscleGroupExportCard: some View {
        ExportActionCard(
            descriptor: ExportCardDescriptor(
                title: "Export by Muscle Group",
                subtitle: "Only workouts containing exercises tagged to the groups you select.",
                systemImage: "figure.strengthtraining.functional"
            ),
            statusMessage: muscleGroupExportStatusMessage,
            fileName: muscleGroupExportFileURL?.lastPathComponent,
            footnote: "Choose one or more muscle groups to export selected workout CSV columns for matching exercises.",
            isRunning: isExportingMuscleGroups,
            isEnabled: muscleGroupExportButtonEnabled,
            shareURL: muscleGroupExportFileURL,
            onAction: startMuscleGroupExport,
            onShare: presentShare
        ) {
            ExportSelectionButton(
                title: "Muscle groups",
                summary: selectedMuscleTagIdsInRange.isEmpty ? "Choose muscle groups" : "\(selectedMuscleTagIdsInRange.count) selected",
                previewText: selectedMuscleTagPreviewText,
                action: {
                    isFilteredExportsExpanded = true
                    openSheet(.muscleGroups)
                }
            )
        }
    }

    var workoutDatesExportCard: some View {
        ExportActionCard(
            descriptor: ExportCardDescriptor(
                title: "Export Workout Dates",
                subtitle: "Only the workout sessions that happened on specific days.",
                systemImage: "calendar.badge.plus"
            ),
            statusMessage: workoutDatesExportStatusMessage,
            fileName: workoutDatesExportFileURL?.lastPathComponent,
            footnote: "Choose one or more dates to export selected workout CSV columns for those sessions.",
            isRunning: isExportingWorkoutDates,
            isEnabled: workoutDatesExportButtonEnabled,
            shareURL: workoutDatesExportFileURL,
            onAction: startWorkoutDatesExport,
            onShare: presentShare
        ) {
            ExportSelectionButton(
                title: "Workout dates",
                summary: selectedWorkoutDateIdsInRange.isEmpty ? "Choose dates" : "\(selectedWorkoutDateIdsInRange.count) selected",
                previewText: selectedWorkoutDatePreviewText,
                action: {
                    isFilteredExportsExpanded = true
                    openSheet(.workoutDates)
                }
            )
        }
    }

    var healthUnavailableCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "heart.slash.fill")
                    .font(Theme.Typography.title4)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 34, height: 34)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Health Unavailable")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Health exports require HealthKit access on a supported device.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Text("Daily health summaries, raw metric samples, and workout-linked health exports will appear here when Apple Health is available.")
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    var healthAccessCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "heart.text.square.fill")
                    .font(Theme.Typography.title4)
                    .foregroundStyle(Theme.Colors.error)
                    .frame(width: 34, height: 34)
                    .background(Theme.Colors.error.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect Apple Health")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Grant read access before exporting daily summaries, raw metric samples, or workout-linked health data.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            if healthManager.authorizationStatus == .denied {
                Text("Health access is currently denied. Re-enable it in the system Health permissions, then come back here to export.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Button(action: requestHealthAuthorization) {
                Text(healthManager.authorizationStatus == .denied ? "Try Health Authorization Again" : "Connect Apple Health")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.error)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    var healthDailySummaryCard: some View {
        ExportActionCard(
            descriptor: ExportCardDescriptor(
                title: "Export Daily Health Summary",
                subtitle: "One row per day across the current range, using your Apple Health aggregates.",
                systemImage: "calendar.badge.heart",
                iconTint: Theme.Colors.error
            ),
            statusMessage: healthDailySummaryStatusMessage,
            fileName: healthDailySummaryFileURL?.lastPathComponent,
            footnote: "Refreshes the selected range from Apple Health before exporting. Choose which daily metrics to include, including sleep.",
            isRunning: isExportingHealthDailySummary,
            isEnabled: healthDailySummaryExportButtonEnabled,
            shareURL: healthDailySummaryFileURL,
            onAction: startHealthDailySummaryExport,
            onShare: presentShare
        ) {
            ExportSelectionButton(
                title: "Daily metrics",
                summary: selectedHealthSummaryMetrics.isEmpty ? "Choose metrics" : "\(selectedHealthSummaryMetrics.count) selected",
                previewText: selectedHealthSummaryPreviewText,
                action: {
                    openSheet(.healthDailyMetrics)
                }
            )
        }
    }

    var healthWorkoutSummaryCard: some View {
        ExportActionCard(
            descriptor: ExportCardDescriptor(
                title: "Export Workout Health Summary",
                subtitle: "One row per workout, including synced Apple Health stats around each session.",
                systemImage: "heart.circle.fill",
                iconTint: Theme.Colors.error
            ),
            statusMessage: healthWorkoutSummaryStatusMessage,
            fileName: healthWorkoutSummaryFileURL?.lastPathComponent,
            footnote: """
            Exports the workout-linked Apple Health snapshot for workouts in the current range. \
            Missing workout health entries are synced first when possible.
            """,
            isRunning: isExportingHealthWorkoutSummary,
            isEnabled: healthWorkoutSummaryExportButtonEnabled,
            shareURL: healthWorkoutSummaryFileURL,
            onAction: startHealthWorkoutSummaryExport,
            onShare: presentShare
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
            .tint(Theme.Colors.accent)
        }
    }

    var healthMetricSamplesCard: some View {
        ExportActionCard(
            descriptor: ExportCardDescriptor(
                title: "Export Health Metric Samples",
                subtitle: "Timestamped raw samples for selected Apple Health metrics.",
                systemImage: "waveform.path.ecg",
                iconTint: Theme.Colors.error
            ),
            statusMessage: healthMetricSamplesStatusMessage,
            fileName: healthMetricSamplesFileURL?.lastPathComponent,
            footnote: "Exports raw Health samples in timestamp order. Only metrics that support sample-level export are available here.",
            isRunning: isExportingHealthMetricSamples,
            isEnabled: healthMetricSamplesExportButtonEnabled,
            shareURL: healthMetricSamplesFileURL,
            onAction: startHealthMetricSamplesExport,
            onShare: presentShare
        ) {
            ExportSelectionButton(
                title: "Sample metrics",
                summary: selectedHealthSampleMetrics.isEmpty ? "Choose metrics" : "\(selectedHealthSampleMetrics.count) selected",
                previewText: selectedHealthSamplePreviewText,
                action: {
                    openSheet(.healthSampleMetrics)
                }
            )
        }
    }

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
        !isExportingWorkouts && !workoutsInSelection.isEmpty && !selectedWorkoutColumns.isEmpty
    }

    var exerciseExportButtonEnabled: Bool {
        !isExportingExercises && !workoutsInSelection.isEmpty
    }

    var exerciseHistoryExportButtonEnabled: Bool {
        !isExportingExerciseHistory && !selectedExerciseNamesInRange.isEmpty && !selectedWorkoutColumns.isEmpty
    }

    var muscleGroupExportButtonEnabled: Bool {
        !isExportingMuscleGroups && !selectedMuscleTagIdsInRange.isEmpty && !selectedWorkoutColumns.isEmpty
    }

    var workoutDatesExportButtonEnabled: Bool {
        !isExportingWorkoutDates && !selectedWorkoutDateIdsInRange.isEmpty && !selectedWorkoutColumns.isEmpty
    }

    var healthDailySummaryExportButtonEnabled: Bool {
        !isExportingHealthDailySummary && !selectedHealthSummaryMetrics.isEmpty
    }

    var healthWorkoutSummaryExportButtonEnabled: Bool {
        !isExportingHealthWorkoutSummary && !workoutsInSelection.isEmpty
    }

    var healthMetricSamplesExportButtonEnabled: Bool {
        !isExportingHealthMetricSamples && !selectedHealthSampleMetrics.isEmpty
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
        let names = Set(workoutsInSelection.flatMap { $0.exercises.map(\.name) })
        return names.sorted(by: localizedAscending)
    }

    var orderedSelectedWorkoutColumns: [WorkoutExportColumn] {
        WorkoutExportColumn.allCases.filter { selectedWorkoutColumns.contains($0) }
    }

    var selectedExerciseNamesInRange: Set<String> {
        selectedExerciseNames.intersection(Set(availableExerciseNames))
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
        let exerciseNames = Set(workoutsInSelection.flatMap { $0.exercises.map(\.name) })
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
        previewText(for: Array(selectedExerciseNamesInRange), itemMap: nil)
    }

    var selectedMuscleTagPreviewText: String? {
        let selectedTagMap = Dictionary(uniqueKeysWithValues: availableMuscleTags.map { ($0.id, $0.displayName) })
        let names = Array(selectedMuscleTagIdsInRange.compactMap { selectedTagMap[$0] })
        return previewText(for: names, itemMap: nil)
    }

    var selectedWorkoutDatePreviewText: String? {
        let selectedDateMap = Dictionary(uniqueKeysWithValues: workoutDateOptions.map { ($0.id, formatDay($0.date)) })
        let labels = Array(selectedWorkoutDateIdsInRange.compactMap { selectedDateMap[$0] })
        return previewText(for: labels, itemMap: nil)
    }

    var selectedWorkoutColumnPreviewText: String? {
        previewText(for: orderedSelectedWorkoutColumns.map(\.title), itemMap: nil)
    }

    var selectedHealthSummaryPreviewText: String? {
        previewText(
            for: sortedHealthMetrics(selectedHealthSummaryMetrics).map(\.title),
            itemMap: nil
        )
    }

    var selectedHealthSamplePreviewText: String? {
        previewText(
            for: sortedHealthMetrics(selectedHealthSampleMetrics).map(\.title),
            itemMap: nil
        )
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
    func startHealthDailySummaryExport() {
        guard healthDailySummaryExportButtonEnabled else { return }
        trackExportStarted(kind: "healthDailySummary", extra: ["Export.metricCount": "\(selectedHealthSummaryMetrics.count)"])

        healthDailySummaryStatusMessage = nil
        healthDailySummaryFileURL = nil
        isExportingHealthDailySummary = true

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
                            healthDailySummaryFileURL = fileURL
                            healthDailySummaryStatusMessage = storageSnapshot.isUsingLocalFallback
                                ? "Saved on-device (iCloud unavailable)"
                                : "Saved to iCloud Drive"
                            isExportingHealthDailySummary = false
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
                            isExportingHealthDailySummary = false
                            trackExportFailed(kind: "healthDailySummary", error: error)
                            showError(error)
                        }
                    }
                }
            } catch {
                isExportingHealthDailySummary = false
                trackExportFailed(kind: "healthDailySummary", error: error)
                showError(error)
            }
        }
    }

    @MainActor
    func startHealthWorkoutSummaryExport() {
        guard healthWorkoutSummaryExportButtonEnabled else { return }
        trackExportStarted(
            kind: "healthWorkoutSummary",
            extra: ["Export.includeLocations": includeHealthWorkoutLocations ? "true" : "false"]
        )

        healthWorkoutSummaryStatusMessage = nil
        healthWorkoutSummaryFileURL = nil
        isExportingHealthWorkoutSummary = true

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
                            healthWorkoutSummaryFileURL = fileURL
                            healthWorkoutSummaryStatusMessage = storageSnapshot.isUsingLocalFallback
                                ? "Saved on-device (iCloud unavailable)"
                                : "Saved to iCloud Drive"
                            isExportingHealthWorkoutSummary = false
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
                            isExportingHealthWorkoutSummary = false
                            trackExportFailed(kind: "healthWorkoutSummary", error: error)
                            showError(error)
                        }
                    }
                }
            } catch {
                isExportingHealthWorkoutSummary = false
                trackExportFailed(kind: "healthWorkoutSummary", error: error)
                showError(error)
            }
        }
    }

    @MainActor
    func startHealthMetricSamplesExport() {
        guard healthMetricSamplesExportButtonEnabled else { return }
        trackExportStarted(kind: "healthMetricSamples", extra: ["Export.metricCount": "\(selectedHealthSampleMetrics.count)"])

        healthMetricSamplesStatusMessage = nil
        healthMetricSamplesFileURL = nil
        isExportingHealthMetricSamples = true

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
                            healthMetricSamplesFileURL = fileURL
                            healthMetricSamplesStatusMessage = storageSnapshot.isUsingLocalFallback
                                ? "Saved on-device (iCloud unavailable)"
                                : "Saved to iCloud Drive"
                            isExportingHealthMetricSamples = false
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
                            isExportingHealthMetricSamples = false
                            trackExportFailed(kind: "healthMetricSamples", error: error)
                            showError(error)
                        }
                    }
                }
            } catch {
                isExportingHealthMetricSamples = false
                trackExportFailed(kind: "healthMetricSamples", error: error)
                showError(error)
            }
        }
    }

    @MainActor
    func startWorkoutExport() {
        guard workoutExportButtonEnabled else { return }
        let selectedColumns = orderedSelectedWorkoutColumns
        trackExportStarted(kind: "workouts", extra: workoutColumnAnalyticsPayload(for: selectedColumns))

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

        Task.detached(priority: .userInitiated) {
            do {
                guard let directory = storageSnapshot.url else {
                    throw iCloudError.containerNotAvailable
                }

                let data = try WorkoutCSVExporter.exportWorkoutHistoryCSV(
                    workouts: workoutsSnapshot,
                    startDate: start,
                    endDateInclusive: end,
                    exerciseTagsByName: exerciseTagsByName,
                    gymNamesByWorkoutID: gymNamesByWorkoutID,
                    selectedColumns: selectedColumns,
                    weightUnit: unit
                )

                let fileName = try WorkoutCSVExporter.makeWorkoutExportFileName(
                    startDate: start,
                    endDateInclusive: end
                )

                try iCloudDocumentManager.saveWorkoutFile(data: data, in: directory, fileName: fileName)
                let fileURL = directory.appendingPathComponent(fileName)

                await MainActor.run {
                    workoutExportFileURL = fileURL
                    workoutExportStatusMessage = storageSnapshot.isUsingLocalFallback
                        ? "Saved on-device (iCloud unavailable)"
                        : "Saved to iCloud Drive"
                    isExportingWorkouts = false
                    trackExportCompleted(
                        kind: "workouts",
                        itemCount: workoutsSnapshot.count,
                        extra: workoutColumnAnalyticsPayload(for: selectedColumns)
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

                let data = try WorkoutCSVExporter.exportExerciseListCSV(
                    workouts: workoutsSnapshot,
                    startDate: start,
                    endDateInclusive: end,
                    includeTags: includeTags,
                    exerciseTagsByName: exerciseTagsByName
                )

                let fileName = try WorkoutCSVExporter.makeExerciseListExportFileName(
                    startDate: start,
                    endDateInclusive: end,
                    includeTags: includeTags
                )

                try iCloudDocumentManager.saveWorkoutFile(data: data, in: directory, fileName: fileName)
                let fileURL = directory.appendingPathComponent(fileName)

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
    func startExerciseHistoryExport() {
        guard exerciseHistoryExportButtonEnabled else { return }
        let selectedNames = selectedExerciseNamesInRange
        let selectedColumns = orderedSelectedWorkoutColumns
        trackExportStarted(
            kind: "exerciseHistory",
            extra: workoutColumnAnalyticsPayload(for: selectedColumns)
                .merging(["Export.selectionCount": "\(selectedNames.count)"]) { _, new in new }
        )

        exerciseHistoryExportStatusMessage = nil
        exerciseHistoryExportFileURL = nil
        isExportingExerciseHistory = true

        let workoutsSnapshot = workoutsInSelection.compactMap { workout -> Workout? in
            let filteredExercises = workout.exercises.filter { selectedNames.contains($0.name) }
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
            isExportingExerciseHistory = false
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

                let data = try WorkoutCSVExporter.exportWorkoutHistoryCSV(
                    workouts: workoutsSnapshot,
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    exerciseTagsByName: exerciseTagsByName,
                    gymNamesByWorkoutID: gymNamesByWorkoutID,
                    selectedColumns: selectedColumns,
                    weightUnit: unit
                )

                let fileName = try WorkoutCSVExporter.makeExerciseHistoryExportFileName(
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    selectedExerciseCount: selectedExerciseCount
                )

                try iCloudDocumentManager.saveWorkoutFile(data: data, in: directory, fileName: fileName)
                let fileURL = directory.appendingPathComponent(fileName)

                await MainActor.run {
                    exerciseHistoryExportFileURL = fileURL
                    exerciseHistoryExportStatusMessage = storageSnapshot.isUsingLocalFallback
                        ? "Saved on-device (iCloud unavailable)"
                        : "Saved to iCloud Drive"
                    isExportingExerciseHistory = false
                    isFilteredExportsExpanded = true
                    trackExportCompleted(
                        kind: "exerciseHistory",
                        itemCount: workoutsSnapshot.count,
                        extra: workoutColumnAnalyticsPayload(for: selectedColumns)
                            .merging(["Export.selectionCount": "\(selectedExerciseCount)"]) { _, new in new }
                    )
                    presentShare(fileURL)
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    isExportingExerciseHistory = false
                    trackExportFailed(kind: "exerciseHistory", error: error)
                    showError(error)
                }
            }
        }
    }

    @MainActor
    func startMuscleGroupExport() {
        guard muscleGroupExportButtonEnabled else { return }
        let selectedTagIds = selectedMuscleTagIdsInRange
        let selectedColumns = orderedSelectedWorkoutColumns
        trackExportStarted(
            kind: "muscleGroup",
            extra: workoutColumnAnalyticsPayload(for: selectedColumns)
                .merging(["Export.selectionCount": "\(selectedTagIds.count)"]) { _, new in new }
        )

        muscleGroupExportStatusMessage = nil
        muscleGroupExportFileURL = nil
        isExportingMuscleGroups = true

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
            isExportingMuscleGroups = false
            showError(WorkoutExportError.noWorkoutsInRange)
            return
        }

        let exerciseTagsByName = exerciseTagsByName(for: workoutsSnapshot)
        let gymNamesByWorkoutID = gymNamesByWorkoutID(for: workoutsSnapshot)
        let storageSnapshot = iCloudManager.storageSnapshot()
        let unit = weightUnit
        let selectedGroupCount = selectedTagIds.count

        Task.detached(priority: .userInitiated) {
            do {
                guard let directory = storageSnapshot.url else {
                    throw iCloudError.containerNotAvailable
                }

                let data = try WorkoutCSVExporter.exportWorkoutHistoryCSV(
                    workouts: workoutsSnapshot,
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    exerciseTagsByName: exerciseTagsByName,
                    gymNamesByWorkoutID: gymNamesByWorkoutID,
                    selectedColumns: selectedColumns,
                    weightUnit: unit
                )

                let fileName = try WorkoutCSVExporter.makeMuscleGroupExportFileName(
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    selectedGroupCount: selectedGroupCount
                )

                try iCloudDocumentManager.saveWorkoutFile(data: data, in: directory, fileName: fileName)
                let fileURL = directory.appendingPathComponent(fileName)

                await MainActor.run {
                    muscleGroupExportFileURL = fileURL
                    muscleGroupExportStatusMessage = storageSnapshot.isUsingLocalFallback
                        ? "Saved on-device (iCloud unavailable)"
                        : "Saved to iCloud Drive"
                    isExportingMuscleGroups = false
                    isFilteredExportsExpanded = true
                    trackExportCompleted(
                        kind: "muscleGroup",
                        itemCount: workoutsSnapshot.count,
                        extra: workoutColumnAnalyticsPayload(for: selectedColumns)
                            .merging(["Export.selectionCount": "\(selectedGroupCount)"]) { _, new in new }
                    )
                    presentShare(fileURL)
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    isExportingMuscleGroups = false
                    trackExportFailed(kind: "muscleGroup", error: error)
                    showError(error)
                }
            }
        }
    }

    @MainActor
    func startWorkoutDatesExport() {
        guard workoutDatesExportButtonEnabled else { return }
        let selectedIds = selectedWorkoutDateIdsInRange
        let selectedColumns = orderedSelectedWorkoutColumns
        trackExportStarted(
            kind: "workoutDates",
            extra: workoutColumnAnalyticsPayload(for: selectedColumns)
                .merging(["Export.selectionCount": "\(selectedIds.count)"]) { _, new in new }
        )

        workoutDatesExportStatusMessage = nil
        workoutDatesExportFileURL = nil
        isExportingWorkoutDates = true

        let workoutsSnapshot = workoutsInSelection.filter { workout in
            selectedIds.contains(dayIdentifier(for: workout.date))
        }

        guard let bounds = dayBounds(for: workoutsSnapshot) else {
            isExportingWorkoutDates = false
            showError(WorkoutExportError.noWorkoutsInRange)
            return
        }

        let exerciseTagsByName = exerciseTagsByName(for: workoutsSnapshot)
        let gymNamesByWorkoutID = gymNamesByWorkoutID(for: workoutsSnapshot)
        let storageSnapshot = iCloudManager.storageSnapshot()
        let unit = weightUnit
        let selectedDateCount = selectedIds.count

        Task.detached(priority: .userInitiated) {
            do {
                guard let directory = storageSnapshot.url else {
                    throw iCloudError.containerNotAvailable
                }

                let data = try WorkoutCSVExporter.exportWorkoutHistoryCSV(
                    workouts: workoutsSnapshot,
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    exerciseTagsByName: exerciseTagsByName,
                    gymNamesByWorkoutID: gymNamesByWorkoutID,
                    selectedColumns: selectedColumns,
                    weightUnit: unit
                )

                let fileName = try WorkoutCSVExporter.makeWorkoutDatesExportFileName(
                    startDate: bounds.start,
                    endDateInclusive: bounds.endInclusive,
                    selectedDateCount: selectedDateCount
                )

                try iCloudDocumentManager.saveWorkoutFile(data: data, in: directory, fileName: fileName)
                let fileURL = directory.appendingPathComponent(fileName)

                await MainActor.run {
                    workoutDatesExportFileURL = fileURL
                    workoutDatesExportStatusMessage = storageSnapshot.isUsingLocalFallback
                        ? "Saved on-device (iCloud unavailable)"
                        : "Saved to iCloud Drive"
                    isExportingWorkoutDates = false
                    isFilteredExportsExpanded = true
                    trackExportCompleted(
                        kind: "workoutDates",
                        itemCount: workoutsSnapshot.count,
                        extra: workoutColumnAnalyticsPayload(for: selectedColumns)
                            .merging(["Export.selectionCount": "\(selectedDateCount)"]) { _, new in new }
                    )
                    presentShare(fileURL)
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    isExportingWorkoutDates = false
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

    func clearExportState() {
        workoutExportStatusMessage = nil
        workoutExportFileURL = nil
        exerciseExportStatusMessage = nil
        exerciseExportFileURL = nil
        exerciseHistoryExportStatusMessage = nil
        exerciseHistoryExportFileURL = nil
        workoutDatesExportStatusMessage = nil
        workoutDatesExportFileURL = nil
        muscleGroupExportStatusMessage = nil
        muscleGroupExportFileURL = nil
        healthDailySummaryStatusMessage = nil
        healthDailySummaryFileURL = nil
        healthWorkoutSummaryStatusMessage = nil
        healthWorkoutSummaryFileURL = nil
        healthMetricSamplesStatusMessage = nil
        healthMetricSamplesFileURL = nil
    }

    func previewText(for items: [String], itemMap: [String: String]?) -> String? {
        let resolvedItems: [String]
        if let itemMap {
            resolvedItems = items.compactMap { itemMap[$0] }
        } else {
            resolvedItems = items
        }

        let sorted = resolvedItems.sorted(by: localizedAscending)
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
        case .lastWorkout:
            return "Last workout"
        case .week:
            return "One week"
        case .fourWeeks:
            return "Four weeks"
        case .twelveWeeks:
            return "Twelve weeks"
        case .sixMonths:
            return "Six months"
        case .year:
            return "One year"
        case .all:
            return "All time"
        case .custom:
            return "Custom range"
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
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(Theme.Spacing.md)
                                .background(Theme.Colors.elevated)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
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
