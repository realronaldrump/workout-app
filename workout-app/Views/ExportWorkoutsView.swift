import SwiftUI

struct ExportWorkoutsView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @ObservedObject private var exerciseMetadataManager = ExerciseMetadataManager.shared

    private let weightUnit = "lbs"

    @State private var mode: ExportMode = .basic
    @State private var selectedRange: ExportTimeRange = .all
    @State private var customStartDate: Date = Date()
    @State private var customEndDate: Date = Date()
    @State private var showingCustomRangeSheet = false
    @State private var didInitializeCustomRange = false

    @State private var isExportingWorkouts = false
    @State private var workoutExportStatusMessage: String?
    @State private var workoutExportFileURL: URL?

    @State private var includeExerciseTags = true
    @State private var isExportingExercises = false
    @State private var exerciseExportStatusMessage: String?
    @State private var exerciseExportFileURL: URL?

    @State private var exportErrorMessage: String?
    @State private var showingErrorAlert = false

    @State private var showingShareSheet = false
    @State private var shareFileURL: URL?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    header

                    if dataManager.workouts.isEmpty {
                        ContentUnavailableView(
                            "No Workouts",
                            systemImage: "square.and.arrow.up",
                            description: Text("Import workouts before exporting.")
                        )
                        .padding(.top, Theme.Spacing.xl)
                    } else {
                        modePicker
                        rangeCard
                        summaryCard
                        workoutExportCard
                        exerciseExportCard
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Failed", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Unknown error")
        }
        .onAppear {
            initializeDefaultRangesIfNeeded()
        }
        .onChange(of: dataManager.workouts.count) { _, _ in
            initializeDefaultRangesIfNeeded()
        }
        .onChange(of: selectedRange) { _, _ in
            clearExportState()
        }
        .onChange(of: customStartDate) { _, _ in
            guard selectedRange == .custom else { return }
            clearExportState()
        }
        .onChange(of: customEndDate) { _, _ in
            guard selectedRange == .custom else { return }
            clearExportState()
        }
        .sheet(isPresented: $showingCustomRangeSheet) {
            ExportCustomRangeSheet(
                startDate: $customStartDate,
                endDate: $customEndDate,
                latestSelectableDate: latestSelectableDate
            )
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 56))
                .foregroundStyle(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Theme.Colors.accentSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(Theme.Colors.shadowOpacity), radius: 0, x: 4, y: 4)

            Text("Export Workouts")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.5)

            Text("Create a CSV backup you can share or store.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Mode")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.xs)

            BrutalistSegmentedPicker(
                title: "Export Mode",
                selection: $mode,
                options: ExportMode.allCases.map { (label: $0.title, value: $0) }
            )

            if mode == .complete {
                Text("Complete export includes exercise tags and is available below.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    private var rangeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Time Range")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }

            timeRangePicker

            rangeDetails
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var timeRangePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Preset")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(ExportTimeRange.allCases) { range in
                        let isSelected = selectedRange == range
                        Button {
                            if range == .custom {
                                selectedRange = .custom
                                showingCustomRangeSheet = true
                            } else {
                                selectedRange = range
                            }
                            Haptics.selection()
                        } label: {
                            Text(range.title)
                                .font(Theme.Typography.metricLabel)
                                .textCase(.uppercase)
                                .tracking(0.8)
                                .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .frame(minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                        .fill(isSelected ? Theme.Colors.accent : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var rangeDetails: some View {
        let range = effectiveDayRange

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
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
                Button {
                    showingCustomRangeSheet = true
                    Haptics.selection()
                } label: {
                    Text("Edit Custom Range")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.elevated)
                        .cornerRadius(Theme.CornerRadius.large)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private var summaryCard: some View {
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

            summaryRow(title: "Workouts", value: "\(workouts.count)")
            summaryRow(title: "Exercises", value: "\(totalExercises)")
            summaryRow(title: "Sets", value: "\(totalSets)")
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private var workoutExportCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: "square.and.arrow.up.on.square")
                    .foregroundStyle(Theme.Colors.accentSecondary)
                Text("Export Workouts")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }

            if let message = workoutExportStatusMessage {
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if let url = workoutExportFileURL {
                Text(url.lastPathComponent)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button(action: startWorkoutExport) {
                    HStack(spacing: Theme.Spacing.sm) {
                        if isExportingWorkouts {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up.doc.fill")
                        }
                        Text(isExportingWorkouts ? "Exporting" : "Export CSV")
                    }
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(workoutExportButtonEnabled ? Theme.Colors.accent : Theme.Colors.surface)
                    .foregroundColor(workoutExportButtonEnabled ? .white : Theme.Colors.textTertiary)
                    .cornerRadius(Theme.CornerRadius.large)
                }
                .buttonStyle(.plain)
                .disabled(!workoutExportButtonEnabled)

                if let url = workoutExportFileURL {
                    Button(
                        action: {
                            shareFileURL = url
                            showingShareSheet = true
                        },
                        label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline)
                                .frame(width: 48, height: 48)
                                .background(Theme.Colors.cardBackground)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                                )
                                .cornerRadius(Theme.CornerRadius.large)
                        }
                    )
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share")
                }
            }

            Text("Basic mode exports a compact CSV (workout/exercise info shown once). Includes muscle tags; only adds Distance/Seconds if present.")
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var workoutExportButtonEnabled: Bool {
        if isExportingWorkouts { return false }
        if mode != .basic { return false }
        return !workoutsInSelection.isEmpty
    }

    private var exerciseExportCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .foregroundStyle(Theme.Colors.accentSecondary)
                Text("Export Exercises")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }

            Toggle(isOn: $includeExerciseTags) {
                Text("Include tags")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .tint(Theme.Colors.accent)

            if let message = exerciseExportStatusMessage {
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if let url = exerciseExportFileURL {
                Text(url.lastPathComponent)
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button(action: startExerciseExport) {
                    HStack(spacing: Theme.Spacing.sm) {
                        if isExportingExercises {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up.doc.fill")
                        }
                        Text(isExportingExercises ? "Exporting" : "Export CSV")
                    }
                    .font(Theme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(exerciseExportButtonEnabled ? Theme.Colors.accent : Theme.Colors.surface)
                    .foregroundColor(exerciseExportButtonEnabled ? .white : Theme.Colors.textTertiary)
                    .cornerRadius(Theme.CornerRadius.large)
                }
                .buttonStyle(.plain)
                .disabled(!exerciseExportButtonEnabled)

                if let url = exerciseExportFileURL {
                    Button(
                        action: {
                            shareFileURL = url
                            showingShareSheet = true
                        },
                        label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline)
                                .frame(width: 48, height: 48)
                                .background(Theme.Colors.cardBackground)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                                )
                                .cornerRadius(Theme.CornerRadius.large)
                        }
                    )
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share")
                }
            }

            Text("Exports a unique list of exercises within the selected time range. Tags come from your exercise tagging settings.")
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var exerciseExportButtonEnabled: Bool {
        if isExportingExercises { return false }
        return !workoutsInSelection.isEmpty
    }

    private var workoutsInSelection: [Workout] {
        guard !dataManager.workouts.isEmpty else { return [] }

        let range = effectiveDayRange
        let calendar = Calendar.current
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: range.endInclusive)) ?? range.endInclusive

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

    private var effectiveDayRange: (start: Date, endInclusive: Date) {
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
            let start = earliest ?? referenceDay
            let end = latest ?? referenceDay
            return (start, end)
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.startOfDay(for: customEndDate)
            if start <= end {
                return (start, end)
            }
            return (end, start)
        }
    }

    private var latestSelectableDate: Date {
        let latestWorkoutDate = dataManager.workouts.map(\.date).max()
        return max(Date(), latestWorkoutDate ?? Date())
    }

    private func initializeDefaultRangesIfNeeded() {
        guard !didInitializeCustomRange else { return }
        guard !dataManager.workouts.isEmpty else { return }

        let calendar = Calendar.current
        guard let earliest = dataManager.workouts.map(\.date).min(),
              let latest = dataManager.workouts.map(\.date).max() else {
            return
        }

        // Seed the custom range with the full dataset so custom starts from a useful default.
        customStartDate = calendar.startOfDay(for: earliest)
        customEndDate = calendar.startOfDay(for: latest)
        didInitializeCustomRange = true
    }

    private func formatDay(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    @MainActor
    private func startWorkoutExport() {
        guard workoutExportButtonEnabled else { return }

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

        let exerciseNames = Set(workoutsSnapshot.flatMap { $0.exercises.map(\.name) })
        var exerciseTagsByName: [String: String] = [:]
        for name in exerciseNames {
            let tags = exerciseMetadataManager.resolvedTags(for: name)
            guard !tags.isEmpty else { continue }
            exerciseTagsByName[name] = tags.map(\.displayName).joined(separator: "; ")
        }

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
                    weightUnit: unit
                )

                let fileName = try WorkoutCSVExporter.makeBasicExportFileName(
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
                    shareFileURL = fileURL
                    isExportingWorkouts = false
                    showingShareSheet = true
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    showingErrorAlert = true
                    isExportingWorkouts = false
                    Haptics.notify(.error)
                }
            }
        }
    }

    @MainActor
    private func startExerciseExport() {
        guard exerciseExportButtonEnabled else { return }

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
                    shareFileURL = fileURL
                    isExportingExercises = false
                    showingShareSheet = true
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    showingErrorAlert = true
                    isExportingExercises = false
                    Haptics.notify(.error)
                }
            }
        }
    }

    @MainActor
    private func clearExportState() {
        workoutExportStatusMessage = nil
        workoutExportFileURL = nil
        exerciseExportStatusMessage = nil
        exerciseExportFileURL = nil
    }
}

private enum ExportMode: String, CaseIterable, Identifiable {
    case basic
    case complete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic:
            return "Basic"
        case .complete:
            return "Complete"
        }
    }
}

private enum ExportTimeRange: String, CaseIterable, Identifiable {
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
}

private struct ExportCustomRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var startDate: Date
    @Binding var endDate: Date
    let latestSelectableDate: Date

    @State private var draftStartDate: Date
    @State private var draftEndDate: Date

    init(startDate: Binding<Date>, endDate: Binding<Date>, latestSelectableDate: Date) {
        _startDate = startDate
        _endDate = endDate
        self.latestSelectableDate = latestSelectableDate

        _draftStartDate = State(initialValue: startDate.wrappedValue)
        _draftEndDate = State(initialValue: endDate.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Start")
                            .font(Theme.Typography.metricLabel)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.8)

                        DatePicker(
                            "Start",
                            selection: $draftStartDate,
                            in: ...latestSelectableDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(Theme.Colors.accent)
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("End")
                            .font(Theme.Typography.metricLabel)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.8)

                        DatePicker(
                            "End",
                            selection: $draftEndDate,
                            in: draftStartDate...latestSelectableDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(Theme.Colors.accent)
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)

                    Button {
                        let calendar = Calendar.current
                        startDate = calendar.startOfDay(for: draftStartDate)
                        endDate = calendar.startOfDay(for: draftEndDate)
                        Haptics.selection()
                        dismiss()
                    } label: {
                        Text("Apply Range")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.elevated)
                            .cornerRadius(Theme.CornerRadius.large)
                    }
                    .buttonStyle(.plain)
                }
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    AppPillButton(title: "Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
    }
}
