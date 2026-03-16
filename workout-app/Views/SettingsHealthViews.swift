import SwiftUI

struct HealthHistorySyncView: View {
    @EnvironmentObject private var healthManager: HealthKitManager

    let workouts: [Workout]

    @State private var showingCustomRange = false
    @State private var customRange: DateInterval = {
        let end = Date()
        let start = Calendar.current.date(byAdding: .year, value: -2, to: end) ?? end
        return DateInterval(start: start, end: end)
    }()
    @State private var isAuthorizing = false
    @State private var errorMessage: String?
    @State private var syncNote: String?

    private static let allHistoryStart: Date = {
        Calendar.current.date(from: DateComponents(year: 1970, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
    }()

    private var earliestWorkoutDate: Date? {
        workouts.map(\.date).min()
    }

    private var earliestCachedDate: Date? {
        healthManager.dailyHealthStore.keys.min()
    }

    private var syncEndDate: Date {
        let now = Date()
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
    }

    private var statusLine: String {
        if healthManager.isDailySyncing {
            return "Syncing \(Int(healthManager.dailySyncProgress * 100))%"
        }

        if let syncNote {
            return syncNote
        }

        if let lastDailySyncDate = healthManager.lastDailySyncDate {
            return "Last synced \(SettingsDateFormatters.mediumDateTime.string(from: lastDailySyncDate))"
        }

        return "No manual history backfill yet"
    }

    private var coverageLine: String {
        if let earliestCachedDate {
            return "Daily cache starts \(SettingsDateFormatters.mediumDate.string(from: earliestCachedDate))"
        }

        return "Daily history cache is empty"
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Health History Sync")
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("Backfill older daily Apple Health history without rerunning onboarding. Workout-linked Health sync remains separate.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("STATUS")
                            .font(Theme.Typography.metricLabel)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .tracking(1.2)

                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(statusLine)
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Text(coverageLine)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)

                            if let earliestWorkoutDate {
                                Text("First workout in app: \(SettingsDateFormatters.mediumDate.string(from: earliestWorkoutDate))")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }

                            if healthManager.isDailySyncing {
                                ProgressView(value: healthManager.dailySyncProgress)
                                    .tint(Theme.Colors.error)
                            }
                        }
                        .padding()
                        .softCard(elevation: 1)
                    }

                    if healthManager.authorizationStatus != .authorized {
                        unauthorizedCard
                    } else {
                        presetSection

                        if let errorMessage {
                            Text(errorMessage)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.error)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .navigationTitle("Health History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCustomRange) {
            HealthCustomRangeSheet(range: $customRange) {
                Task {
                    await syncDailyHistory(range: boundedRange(customRange), label: "Custom range")
                }
            }
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
        }
    }

    private var unauthorizedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Apple Health access is required before this screen can backfill older history.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                Task {
                    await requestAuthorization()
                }
            } label: {
                HStack {
                    if isAuthorizing {
                        ProgressView()
                            .tint(.white)
                    }

                    Text("Connect Apple Health")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, Theme.Spacing.md)
                .brutalistButtonChrome(
                    fill: Theme.Colors.accent,
                    cornerRadius: Theme.CornerRadius.large
                )
            }
            .buttonStyle(.plain)
            .disabled(isAuthorizing)
        }
        .padding()
        .softCard(elevation: 1)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("BACKFILL RANGE")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(1.2)

            VStack(spacing: Theme.Spacing.sm) {
                syncOptionRow(
                    title: "Last 2 Years",
                    subtitle: "Good catch-up if onboarding only grabbed 12 months"
                ) {
                    await syncDailyHistory(
                        range: relativeRange(yearsBack: 2),
                        label: "Last 2 years"
                    )
                }

                if let earliestWorkoutDate {
                    syncOptionRow(
                        title: "Since First Workout",
                        subtitle: "Backfill from your earliest logged workout on \(SettingsDateFormatters.mediumDate.string(from: earliestWorkoutDate))"
                    ) {
                        await syncDailyHistory(
                            range: DateInterval(
                                start: Calendar.current.startOfDay(for: earliestWorkoutDate),
                                end: syncEndDate
                            ),
                            label: "Since first workout"
                        )
                    }
                }

                syncOptionRow(
                    title: "All Available Health Data",
                    subtitle: "Large sync. Reads daily Health history from the earliest supported date through today."
                ) {
                    await syncDailyHistory(
                        range: DateInterval(start: Self.allHistoryStart, end: syncEndDate),
                        label: "All available history"
                    )
                }

                Button {
                    errorMessage = nil
                    syncNote = nil
                    showingCustomRange = true
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Custom Range")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Text("Pick exact start and end dates for a targeted backfill")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "calendar")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding()
                    .softCard(elevation: 1)
                }
                .buttonStyle(.plain)
                .disabled(healthManager.isDailySyncing)
                .opacity(healthManager.isDailySyncing ? 0.7 : 1)
            }
        }
    }

    private func syncOptionRow(
        title: String,
        subtitle: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(3)
                }

                Spacer()

                if healthManager.isDailySyncing {
                    ProgressView()
                        .tint(Theme.Colors.error)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .padding()
            .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
        .disabled(healthManager.isDailySyncing)
        .opacity(healthManager.isDailySyncing ? 0.7 : 1)
    }

    private func requestAuthorization() async {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        defer { isAuthorizing = false }

        do {
            try await healthManager.requestAuthorization()
            errorMessage = nil
            syncNote = "Apple Health connected"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncDailyHistory(range: DateInterval, label: String) async {
        guard healthManager.authorizationStatus == .authorized else {
            errorMessage = "Apple Health access is required before syncing older history."
            return
        }
        guard !healthManager.isDailySyncing else { return }

        errorMessage = nil
        syncNote = "\(label) sync started"

        do {
            try await healthManager.syncDailyHealthData(range: range)
            syncNote = "\(label) synced"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func relativeRange(yearsBack: Int) -> DateInterval {
        let start = Calendar.current.date(byAdding: .year, value: -yearsBack, to: Date()) ?? Date()
        return DateInterval(start: Calendar.current.startOfDay(for: start), end: syncEndDate)
    }

    private func boundedRange(_ range: DateInterval) -> DateInterval {
        let start = Calendar.current.startOfDay(for: range.start)
        let end = min(range.end, syncEndDate)
        return DateInterval(start: start, end: end)
    }
}

private enum HealthCacheAction: String, Identifiable {
    case clearWorkoutRange
    case clearDailyRange
    case clearBothRange
    case clearWorkoutAll
    case clearDailyAll
    case clearAndResyncRange

    var id: String { rawValue }
}

struct HealthCacheManagementView: View {
    @EnvironmentObject private var healthManager: HealthKitManager

    let workouts: [Workout]

    @State private var selectedRange: DateInterval = {
        let now = Date()
        let start = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        return DateInterval(start: start, end: now)
    }()
    @State private var showingCustomRange = false
    @State private var pendingAction: HealthCacheAction?
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var isBusy: Bool {
        isWorking || healthManager.isSyncing || healthManager.isDailySyncing
    }

    private var cachedWorkoutDates: [Date] {
        healthManager.healthDataStore.values.map(\.workoutDate)
    }

    private var earliestCachedDate: Date? {
        (cachedWorkoutDates + healthManager.dailyHealthStore.keys).min()
    }

    private var syncEndDate: Date {
        let now = Date()
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
    }

    private var boundedRange: DateInterval {
        let calendar = Calendar.current
        let requestedStart = calendar.startOfDay(for: selectedRange.start)
        let earliest = earliestCachedDate.map { calendar.startOfDay(for: $0) } ?? requestedStart
        let start = max(requestedStart, earliest)
        let end = min(selectedRange.end, syncEndDate)
        if start >= end {
            let fallbackEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: start) ?? start
            return DateInterval(start: start, end: fallbackEnd)
        }
        return DateInterval(start: start, end: end)
    }

    private var cachedWorkoutEntriesInRange: Int {
        healthManager.healthDataStore.values.filter { boundedRange.contains($0.workoutDate) }.count
    }

    private var cachedDailyEntriesInRange: Int {
        healthManager.dailyHealthStore.values.filter { boundedRange.contains($0.dayStart) }.count
    }

    private var coveredDaysInRange: Int {
        healthManager.dailyHealthCoverage.filter { boundedRange.contains($0) }.count
    }

    private var workoutsInRange: [Workout] {
        workouts.filter { boundedRange.contains($0.date) }
    }

    private var workoutCacheSubtitle: String {
        let count = healthManager.healthDataStore.count
        if count == 0 {
            return "No workout-linked Health cache"
        }
        return "\(count) workout health record\(count == 1 ? "" : "s") cached"
    }

    private var dailyCacheSubtitle: String {
        let count = healthManager.dailyHealthStore.count
        if count == 0 {
            return "No daily Health history cache"
        }
        return "\(count) day\(count == 1 ? "" : "s") with Health data cached"
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Health Cache")
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("Delete only this app's cached Apple Health data, then re-sync a smaller window if needed. Your workouts and Apple Health itself stay untouched.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    statusSection
                    rangeSection
                    actionSection

                    if let statusMessage {
                        Text(statusMessage)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.success)
                            .padding()
                            .softCard(elevation: 1)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.error)
                            .padding()
                            .softCard(elevation: 1)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .navigationTitle("Health Cache")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCustomRange) {
            HealthCustomRangeSheet(
                range: $selectedRange,
                earliestSelectableDate: earliestCachedDate
            ) {
                errorMessage = nil
                statusMessage = nil
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { newValue in
                    if !newValue {
                        pendingAction = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(confirmationButtonTitle(for: pendingAction), role: .destructive) {
                    Task {
                        await performAction(pendingAction)
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("CACHE STATUS")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(1.2)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Spacing.sm)],
                spacing: Theme.Spacing.sm
            ) {
                cacheMetricCard(
                    title: "Workout Cache",
                    value: "\(healthManager.healthDataStore.count)",
                    detail: workoutCacheSubtitle,
                    tint: Theme.Colors.error
                )

                cacheMetricCard(
                    title: "Daily Entries",
                    value: "\(healthManager.dailyHealthStore.count)",
                    detail: dailyCacheSubtitle,
                    tint: Theme.Colors.accent
                )

                cacheMetricCard(
                    title: "Covered Days",
                    value: "\(healthManager.dailyHealthCoverage.count)",
                    detail: healthManager.dailyHealthCoverage.isEmpty ? "Missing days will be re-fetched" : "Scanned daily history days",
                    tint: Theme.Colors.accentSecondary
                )
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let earliestCachedDate {
                    Text("Earliest cached Health date: \(SettingsDateFormatters.mediumDate.string(from: earliestCachedDate))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Text("No Health cache on device right now.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                if isBusy {
                    ProgressView(value: healthManager.isDailySyncing ? healthManager.dailySyncProgress : healthManager.syncProgress)
                        .tint(Theme.Colors.error)
                }
            }
            .padding()
            .softCard(elevation: 1)
        }
    }

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("TARGET RANGE")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(1.2)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Spacing.sm)],
                spacing: Theme.Spacing.sm
            ) {
                rangeButton(title: "Last 90 Days") {
                    selectedRange = relativeRange(daysBack: 90)
                }

                rangeButton(title: "Last Year") {
                    selectedRange = relativeRange(yearsBack: 1)
                }

                rangeButton(title: "All Cached") {
                    selectedRange = allCachedRange()
                }

                rangeButton(title: "Custom") {
                    showingCustomRange = true
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(rangeSummaryLine)
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("This range currently includes \(cachedWorkoutEntriesInRange) workout health record\(cachedWorkoutEntriesInRange == 1 ? "" : "s"), \(cachedDailyEntriesInRange) daily entry\(cachedDailyEntriesInRange == 1 ? "" : "ies"), and \(coveredDaysInRange) scanned day\(coveredDaysInRange == 1 ? "" : "s").")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if !workoutsInRange.isEmpty {
                    Text("\(workoutsInRange.count) workout\(workoutsInRange.count == 1 ? "" : "s") in the app fall inside this range and can be re-synced.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding()
            .softCard(elevation: 1)
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("ACTIONS")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(1.2)

            VStack(spacing: Theme.Spacing.sm) {
                actionRow(
                    title: "Clear Workout Cache In Range",
                    subtitle: "Deletes workout-linked Health payloads only for the selected range.",
                    tint: Theme.Colors.error,
                    systemImage: "heart.slash"
                ) {
                    pendingAction = .clearWorkoutRange
                }

                actionRow(
                    title: "Clear Daily History In Range",
                    subtitle: "Deletes cached daily Health entries and scanned coverage days for the selected range.",
                    tint: Theme.Colors.accent,
                    systemImage: "calendar.badge.minus"
                ) {
                    pendingAction = .clearDailyRange
                }

                actionRow(
                    title: "Clear Both Caches In Range",
                    subtitle: "Best when you want to shrink the cache before a more targeted sync.",
                    tint: Theme.Colors.warning,
                    systemImage: "trash"
                ) {
                    pendingAction = .clearBothRange
                }

                actionRow(
                    title: "Clear Then Re-Sync Range",
                    subtitle: healthManager.authorizationStatus == .authorized
                        ? "Rebuilds workout-linked Health data and daily history only for the selected range."
                        : "Clears now. Re-sync requires Apple Health access first.",
                    tint: Theme.Colors.success,
                    systemImage: "arrow.clockwise"
                ) {
                    pendingAction = .clearAndResyncRange
                }

                actionRow(
                    title: "Clear All Workout Cache",
                    subtitle: "Keeps workouts, tags, and logs. Deletes all workout-linked Health sync data.",
                    tint: Theme.Colors.error,
                    systemImage: "figure.run.circle"
                ) {
                    pendingAction = .clearWorkoutAll
                }

                actionRow(
                    title: "Clear All Daily History",
                    subtitle: "Deletes all cached daily Health history and coverage tracking.",
                    tint: Theme.Colors.accentSecondary,
                    systemImage: "calendar.circle"
                ) {
                    pendingAction = .clearDailyAll
                }
            }
        }
    }

    private var confirmationTitle: String {
        guard let pendingAction else { return "Confirm Action" }
        return confirmationButtonTitle(for: pendingAction)
    }

    private var confirmationMessage: String {
        guard let pendingAction else { return "" }

        switch pendingAction {
        case .clearWorkoutRange:
            return "Remove workout-linked Health cache between \(formattedDate(boundedRange.start)) and \(formattedDate(boundedRange.end))."
        case .clearDailyRange:
            return "Remove daily Health entries and scanned coverage for the selected range so that range can be re-fetched later."
        case .clearBothRange:
            return "Remove both workout-linked and daily Health cache for the selected range. Workouts and Apple Health data will remain in place."
        case .clearWorkoutAll:
            return "Delete every cached workout-linked Health record from this app."
        case .clearDailyAll:
            return "Delete every cached daily Health entry and every scanned daily-history marker from this app."
        case .clearAndResyncRange:
            return "Delete both caches for the selected range, then sync that range again. This can take a while for ranges with many workouts."
        }
    }

    private func cacheMetricCard(
        title: String,
        value: String,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(1.0)

            Text(value)
                .font(Theme.Typography.metric)
                .foregroundStyle(tint)

            Text(detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .softCard(elevation: 1)
    }

    private func rangeButton(title: String, action: @escaping () -> Void) -> some View {
        Button {
            errorMessage = nil
            statusMessage = nil
            action()
        } label: {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.7 : 1)
    }

    private func actionRow(
        title: String,
        subtitle: String,
        tint: Color,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding()
            .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.7 : 1)
    }

    private var rangeSummaryLine: String {
        "Selected range: \(formattedDate(boundedRange.start)) to \(formattedDate(boundedRange.end))"
    }

    private func confirmationButtonTitle(for action: HealthCacheAction) -> String {
        switch action {
        case .clearWorkoutRange:
            return "Clear Workout Cache"
        case .clearDailyRange:
            return "Clear Daily History"
        case .clearBothRange:
            return "Clear Both Caches"
        case .clearWorkoutAll:
            return "Clear All Workout Cache"
        case .clearDailyAll:
            return "Clear All Daily History"
        case .clearAndResyncRange:
            return "Clear And Re-Sync"
        }
    }

    private func performAction(_ action: HealthCacheAction) async {
        guard !isBusy else { return }

        pendingAction = nil
        errorMessage = nil
        statusMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            switch action {
            case .clearWorkoutRange:
                let result = healthManager.clearCachedHealthData(
                    in: boundedRange,
                    includeWorkoutData: true,
                    includeDailyData: false
                )
                statusMessage = workoutResultMessage(from: result, scope: "selected range")

            case .clearDailyRange:
                let result = healthManager.clearCachedHealthData(
                    in: boundedRange,
                    includeWorkoutData: false,
                    includeDailyData: true
                )
                statusMessage = dailyResultMessage(from: result, scope: "selected range")

            case .clearBothRange:
                let result = healthManager.clearCachedHealthData(in: boundedRange)
                statusMessage = combinedResultMessage(from: result, scope: "selected range")

            case .clearWorkoutAll:
                let result = healthManager.clearCachedHealthData(
                    includeWorkoutData: true,
                    includeDailyData: false
                )
                statusMessage = workoutResultMessage(from: result, scope: "all cached workouts")

            case .clearDailyAll:
                let result = healthManager.clearCachedHealthData(
                    includeWorkoutData: false,
                    includeDailyData: true
                )
                statusMessage = dailyResultMessage(from: result, scope: "all cached daily history")

            case .clearAndResyncRange:
                let cleared = healthManager.clearCachedHealthData(in: boundedRange)

                guard healthManager.authorizationStatus == .authorized else {
                    statusMessage = combinedResultMessage(from: cleared, scope: "selected range") + " Apple Health access is still required before re-syncing."
                    return
                }

                let workoutsToSync = workoutsInRange
                if !workoutsToSync.isEmpty {
                    _ = try await healthManager.syncAllWorkouts(workoutsToSync)
                }
                try await healthManager.syncDailyHealthData(range: boundedRange)

                let syncedWorkoutCount = workoutsToSync.count
                let syncedDayCount = healthManager.dayCount(in: boundedRange)
                statusMessage = "Re-synced \(syncedWorkoutCount) workout\(syncedWorkoutCount == 1 ? "" : "s") and refreshed \(syncedDayCount) day\(syncedDayCount == 1 ? "" : "s") of daily Health history."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func workoutResultMessage(from result: HealthCacheClearResult, scope: String) -> String {
        if result.removedWorkoutEntries == 0 {
            return "No workout-linked Health cache found in the \(scope)."
        }
        return "Removed \(result.removedWorkoutEntries) workout-linked Health record\(result.removedWorkoutEntries == 1 ? "" : "s") from the \(scope)."
    }

    private func dailyResultMessage(from result: HealthCacheClearResult, scope: String) -> String {
        if result.removedDailyEntries == 0 && result.removedCoveredDays == 0 {
            return "No daily Health cache found in the \(scope)."
        }
        return "Removed \(result.removedDailyEntries) daily entry\(result.removedDailyEntries == 1 ? "" : "ies") and reset \(result.removedCoveredDays) scanned day\(result.removedCoveredDays == 1 ? "" : "s") in the \(scope)."
    }

    private func combinedResultMessage(from result: HealthCacheClearResult, scope: String) -> String {
        if !result.removedAnything {
            return "No Health cache found in the \(scope)."
        }
        return "Removed \(result.removedWorkoutEntries) workout record\(result.removedWorkoutEntries == 1 ? "" : "s"), \(result.removedDailyEntries) daily entr\(result.removedDailyEntries == 1 ? "y" : "ies"), and reset \(result.removedCoveredDays) scanned day\(result.removedCoveredDays == 1 ? "" : "s") in the \(scope)."
    }

    private func relativeRange(daysBack: Int? = nil, yearsBack: Int? = nil) -> DateInterval {
        let now = Date()
        let calendar = Calendar.current

        let start: Date
        if let daysBack {
            start = calendar.date(byAdding: .day, value: -daysBack, to: now) ?? now
        } else if let yearsBack {
            start = calendar.date(byAdding: .year, value: -yearsBack, to: now) ?? now
        } else {
            start = now
        }

        return DateInterval(start: calendar.startOfDay(for: start), end: syncEndDate)
    }

    private func allCachedRange() -> DateInterval {
        guard let earliestCachedDate else {
            return relativeRange(yearsBack: 1)
        }
        return DateInterval(start: Calendar.current.startOfDay(for: earliestCachedDate), end: syncEndDate)
    }

    private func formattedDate(_ date: Date) -> String {
        SettingsDateFormatters.mediumDate.string(from: date)
    }
}

struct SleepSourceSettingsView: View {
    @EnvironmentObject private var healthManager: HealthKitManager
    let workouts: [Workout]

    @AppStorage("preferredSleepSourceKey") private var preferredSleepSourceKey: String = ""
    @AppStorage("preferredSleepSourceName") private var preferredSleepSourceName: String = ""

    @State private var availableSources: [SleepSourceOption] = []
    @State private var isLoading = false
    @State private var isApplying = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Sleep Source")
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("Use one Apple Health source per night so duplicated providers do not inflate your sleep totals.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(
                            "If you pick a preferred source, the app uses it first. " +
                            "When that source misses a night or has less than 15 minutes of asleep-stage data, " +
                            "the app falls back to the strongest other Apple Health source for that night " +
                            "and labels the result in sleep details."
                        )
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding()
                    .softCard(elevation: 1)

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        sleepSourceRow(
                            title: "Auto",
                            subtitle: "Always pick the strongest available source for each night",
                            key: ""
                        )

                        ForEach(availableSources) { source in
                            sleepSourceRow(
                                title: source.name,
                                subtitle: source.bundleIdentifier ?? "Apple Health source",
                                key: source.key
                            )
                        }
                    }

                    if isLoading {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView()
                            Text("Loading sleep sources…")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.error)
                    }

                    if healthManager.authorizationStatus != .authorized {
                        Text("Connect Apple Health to discover source apps. Auto remains available even before Health access is granted.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }

                    if !preferredSleepSourceName.isEmpty {
                        Text("Current preference: \(preferredSleepSourceName). Missing nights can still fall back to another source.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .navigationTitle("Sleep Source")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSourcesIfNeeded()
        }
    }

    private func sleepSourceRow(title: String, subtitle: String, key: String) -> some View {
        Button {
            Task {
                await applySelection(key: key, name: key.isEmpty ? "" : title)
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if isSelected(key: key) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding()
            .softCard(elevation: 1)
            .opacity(isApplying ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isApplying)
    }

    private func isSelected(key: String) -> Bool {
        let normalizedSelectedKey = HealthKitManager.normalizedSleepSourceKey(preferredSleepSourceKey) ?? ""
        let normalizedRowKey = HealthKitManager.normalizedSleepSourceKey(key) ?? ""
        return normalizedSelectedKey == normalizedRowKey
    }

    private func loadSourcesIfNeeded() async {
        guard !isLoading else { return }
        guard healthManager.authorizationStatus == .authorized else {
            availableSources = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            availableSources = try await healthManager.fetchAvailableSleepSources()
            errorMessage = nil
        } catch {
            availableSources = []
            errorMessage = error.localizedDescription
        }
    }

    private func applySelection(key: String, name: String) async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        await healthManager.applySleepSourcePreference(
            key: key,
            name: name,
            workouts: workouts
        )

        preferredSleepSourceKey = key
        preferredSleepSourceName = name
    }
}
