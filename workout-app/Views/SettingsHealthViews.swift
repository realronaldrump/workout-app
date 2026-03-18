import SwiftUI

// MARK: - Unified Health Data Settings

private enum HealthCacheAction: String, Identifiable {
    case clearWorkoutRange
    case clearDailyRange
    case clearBothRange
    case clearWorkoutAll
    case clearDailyAll
    case clearAndResyncRange
    case clearAndResyncAll

    var id: String { rawValue }
}

struct HealthDataSettingsView: View {
    @EnvironmentObject private var healthManager: HealthKitManager
    let workouts: [Workout]

    // Sync state
    @State private var showingSyncCustomRange = false
    @State private var syncCustomRange: DateInterval = {
        let end = Date()
        let start = Calendar.current.date(byAdding: .year, value: -2, to: end) ?? end
        return DateInterval(start: start, end: end)
    }()
    @State private var isAuthorizing = false
    @State private var syncNote: String?

    // Cache state
    @State private var cacheRange: DateInterval = {
        let now = Date()
        let start = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        return DateInterval(start: start, end: now)
    }()
    @State private var showingCacheCustomRange = false
    @State private var pendingAction: HealthCacheAction?
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showAdvancedCache = false

    // MARK: - Computed Properties

    private static let allHistoryStart: Date = {
        Calendar.current.date(from: DateComponents(year: 1970, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
    }()

    private var isBusy: Bool {
        isWorking || healthManager.isSyncing || healthManager.isDailySyncing
    }

    private var earliestWorkoutDate: Date? {
        workouts.map(\.date).min()
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

    private var boundedCacheRange: DateInterval {
        let calendar = Calendar.current
        let requestedStart = calendar.startOfDay(for: cacheRange.start)
        let earliest = earliestCachedDate.map { calendar.startOfDay(for: $0) } ?? requestedStart
        let start = max(requestedStart, earliest)
        let end = min(cacheRange.end, syncEndDate)
        if start >= end {
            let fallbackEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: start) ?? start
            return DateInterval(start: start, end: fallbackEnd)
        }
        return DateInterval(start: start, end: end)
    }

    private var workoutsInRange: [Workout] {
        workouts.filter { boundedCacheRange.contains($0.date) }
    }

    private var cachedWorkoutEntriesInRange: Int {
        healthManager.healthDataStore.values.filter { boundedCacheRange.contains($0.workoutDate) }.count
    }

    private var cachedDailyEntriesInRange: Int {
        healthManager.dailyHealthStore.values.filter { boundedCacheRange.contains($0.dayStart) }.count
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    overviewSection
                    syncSection
                    manageSection
                    feedbackSection
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .navigationTitle("Health Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSyncCustomRange) {
            HealthCustomRangeSheet(range: $syncCustomRange) {
                Task {
                    await syncDailyHistory(
                        range: boundedSyncRange(syncCustomRange),
                        label: "Custom range"
                    )
                }
            }
        }
        .sheet(isPresented: $showingCacheCustomRange) {
            HealthCustomRangeSheet(
                range: $cacheRange,
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
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(confirmationButtonLabel(for: pendingAction), role: .destructive) {
                    Task { await performAction(pendingAction) }
                }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text(confirmationMessage)
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(overviewHeadline)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(overviewDetail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
            }

            if isBusy {
                ProgressView(
                    value: healthManager.isDailySyncing
                        ? healthManager.dailySyncProgress
                        : healthManager.syncProgress
                )
                .tint(Theme.Colors.accent)
            }

            HStack(spacing: Theme.Spacing.sm) {
                overviewPill(
                    label: "Workouts",
                    value: "\(healthManager.healthDataStore.count)",
                    tint: Theme.Colors.error
                )
                overviewPill(
                    label: "Daily",
                    value: "\(healthManager.dailyHealthStore.count)",
                    tint: Theme.Colors.accent
                )
                overviewPill(
                    label: "Days",
                    value: "\(healthManager.dailyHealthCoverage.count)",
                    tint: Theme.Colors.accentSecondary
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isBusy {
            ProgressView()
                .frame(width: 36, height: 36)
        } else {
            Image(systemName: healthManager.authorizationStatus == .authorized ? "heart.fill" : "heart.slash")
                .font(Theme.Iconography.title3Strong)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(healthManager.authorizationStatus == .authorized ? Theme.Colors.success : Theme.Colors.textTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
        }
    }

    private var overviewHeadline: String {
        if healthManager.isDailySyncing {
            return "Syncing… \(Int(healthManager.dailySyncProgress * 100))%"
        }
        if healthManager.isSyncing {
            return "Syncing workouts… \(Int(healthManager.syncProgress * 100))%"
        }
        if let syncNote { return syncNote }
        if healthManager.authorizationStatus != .authorized {
            return "Apple Health not connected"
        }
        if let date = healthManager.lastDailySyncDate {
            return "Last synced \(SettingsDateFormatters.mediumDateTime.string(from: date))"
        }
        return "Connected — no history synced yet"
    }

    private var overviewDetail: String {
        if let earliest = earliestCachedDate {
            return "Health data cached from \(SettingsDateFormatters.mediumDate.string(from: earliest))"
        }
        return "No cached health data on this device"
    }

    private func overviewPill(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Typography.bodyBold)
                .foregroundStyle(tint)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(tint.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Sync History", icon: "clock.arrow.trianglehead.counterclockwise.rotate.90")

            if healthManager.authorizationStatus != .authorized {
                unauthorizedCard
            } else {
                Text("Download older health data from Apple Health.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                FlowLayout(spacing: Theme.Spacing.sm) {
                    syncPill("Last 2 Years") {
                        await syncDailyHistory(range: relativeSyncRange(yearsBack: 2), label: "Last 2 years")
                    }

                    if let date = earliestWorkoutDate {
                        syncPill("Since First Workout") {
                            await syncDailyHistory(
                                range: DateInterval(start: Calendar.current.startOfDay(for: date), end: syncEndDate),
                                label: "Since first workout"
                            )
                        }
                    }

                    syncPill("All Available") {
                        await syncDailyHistory(
                            range: DateInterval(start: Self.allHistoryStart, end: syncEndDate),
                            label: "All available history"
                        )
                    }

                    Button {
                        errorMessage = nil
                        syncNote = nil
                        showingSyncCustomRange = true
                    } label: {
                        Label("Custom", systemImage: "calendar")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.Colors.accent.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .opacity(isBusy ? 0.5 : 1)
                }
            }
        }
    }

    private var unauthorizedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Connect Apple Health to sync your history.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                Task { await requestAuthorization() }
            } label: {
                HStack {
                    if isAuthorizing { ProgressView().tint(.white) }
                    Text("Connect Apple Health")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, Theme.Spacing.md)
                .brutalistButtonChrome(fill: Theme.Colors.accent, cornerRadius: Theme.CornerRadius.large)
            }
            .buttonStyle(.plain)
            .disabled(isAuthorizing)
        }
        .padding()
        .softCard(elevation: 1)
    }

    private func syncPill(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 4) {
                Text(title).font(Theme.Typography.caption)
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(Theme.Typography.caption2)
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.surface)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
    }

    // MARK: - Manage Section

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Manage Data", icon: "externaldrive.badge.minus")

            Text("Your workouts and Apple Health stay untouched — this only affects cached data in the app.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            // Primary actions
            primaryActionButton(
                title: "Refresh All Health Data",
                subtitle: healthManager.authorizationStatus == .authorized
                    ? "Clear and re-download everything"
                    : "Connect Apple Health first to re-download",
                icon: "arrow.clockwise",
                tint: Theme.Colors.accent
            ) {
                pendingAction = .clearAndResyncAll
            }

            primaryActionButton(
                title: "Clear All Cached Data",
                subtitle: "Remove all health data stored in the app",
                icon: "trash",
                tint: Theme.Colors.error
            ) {
                pendingAction = .clearBothRange
                cacheRange = allCachedRange()
            }

            // Advanced toggle
            advancedSection
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showAdvancedCache.toggle()
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Advanced Options")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Image(systemName: showAdvancedCache ? "chevron.up" : "chevron.down")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .buttonStyle(.plain)

            if showAdvancedCache {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    // Range picker
                    Text("Select a date range, then choose an action.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    FlowLayout(spacing: Theme.Spacing.sm) {
                        rangePill("Last 90 Days") { cacheRange = relativeCacheRange(daysBack: 90) }
                        rangePill("Last Year") { cacheRange = relativeCacheRange(yearsBack: 1) }
                        rangePill("All Cached") { cacheRange = allCachedRange() }

                        Button {
                            showingCacheCustomRange = true
                        } label: {
                            Label("Custom", systemImage: "calendar")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.accent)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(Theme.Colors.accent.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                        .opacity(isBusy ? 0.5 : 1)
                    }

                    // Range summary
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(formattedDate(boundedCacheRange.start)) → \(formattedDate(boundedCacheRange.end))")
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("\(cachedWorkoutEntriesInRange) workout record\(cachedWorkoutEntriesInRange == 1 ? "" : "s"), \(cachedDailyEntriesInRange) daily entr\(cachedDailyEntriesInRange == 1 ? "y" : "ies") in range")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .softCard(elevation: 1)

                    // Granular actions
                    VStack(spacing: Theme.Spacing.sm) {
                        advancedActionRow(
                            title: "Clear workout data in range",
                            icon: "heart.slash",
                            tint: Theme.Colors.error
                        ) { pendingAction = .clearWorkoutRange }

                        advancedActionRow(
                            title: "Clear daily data in range",
                            icon: "calendar.badge.minus",
                            tint: Theme.Colors.accent
                        ) { pendingAction = .clearDailyRange }

                        advancedActionRow(
                            title: "Clear & re-sync range",
                            icon: "arrow.clockwise",
                            tint: Theme.Colors.success
                        ) { pendingAction = .clearAndResyncRange }

                        advancedActionRow(
                            title: "Clear all workout data",
                            icon: "figure.run.circle",
                            tint: Theme.Colors.error
                        ) { pendingAction = .clearWorkoutAll }

                        advancedActionRow(
                            title: "Clear all daily history",
                            icon: "calendar.circle",
                            tint: Theme.Colors.accentSecondary
                        ) { pendingAction = .clearDailyAll }
                    }
                }
                .padding(Theme.Spacing.md)
                .softCard(elevation: 1)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackSection: some View {
        if let statusMessage {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
                Text(statusMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(elevation: 1)
        }

        if let errorMessage {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.error)
                Text(errorMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(elevation: 1)
        }
    }

    // MARK: - Reusable Components

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Iconography.mediumStrong)
                .foregroundStyle(Theme.Colors.accent)
            Text(title)
                .font(Theme.Typography.bodyBold)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private func primaryActionButton(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption2Bold)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.6 : 1)
    }

    private func advancedActionRow(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(Theme.Iconography.small)
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Theme.Iconography.micro)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
    }

    private func rangePill(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            errorMessage = nil
            statusMessage = nil
            action()
        } label: {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.surface)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
    }

    // MARK: - Sync Logic

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
            errorMessage = "Connect Apple Health before syncing history."
            return
        }
        guard !healthManager.isDailySyncing else { return }

        errorMessage = nil
        statusMessage = nil
        syncNote = "\(label) sync started…"

        do {
            try await healthManager.syncDailyHealthData(range: range)
            syncNote = nil
            statusMessage = "\(label) synced successfully."
        } catch {
            syncNote = nil
            errorMessage = error.localizedDescription
        }
    }

    private func relativeSyncRange(yearsBack: Int) -> DateInterval {
        let start = Calendar.current.date(byAdding: .year, value: -yearsBack, to: Date()) ?? Date()
        return DateInterval(start: Calendar.current.startOfDay(for: start), end: syncEndDate)
    }

    private func boundedSyncRange(_ range: DateInterval) -> DateInterval {
        let start = Calendar.current.startOfDay(for: range.start)
        let end = min(range.end, syncEndDate)
        return DateInterval(start: start, end: end)
    }

    // MARK: - Cache Logic

    private func relativeCacheRange(daysBack: Int? = nil, yearsBack: Int? = nil) -> DateInterval {
        let calendar = Calendar.current
        let now = Date()
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
        guard let earliestCachedDate else { return relativeCacheRange(yearsBack: 1) }
        return DateInterval(start: Calendar.current.startOfDay(for: earliestCachedDate), end: syncEndDate)
    }

    private func formattedDate(_ date: Date) -> String {
        SettingsDateFormatters.mediumDate.string(from: date)
    }

    // MARK: - Confirmation Dialogs

    private var confirmationTitle: String {
        guard let pendingAction else { return "Confirm" }
        return confirmationButtonLabel(for: pendingAction)
    }

    private var confirmationMessage: String {
        guard let pendingAction else { return "" }
        switch pendingAction {
        case .clearWorkoutRange:
            return "Remove workout health data between \(formattedDate(boundedCacheRange.start)) and \(formattedDate(boundedCacheRange.end)). Your workouts themselves stay."
        case .clearDailyRange:
            return "Remove daily health entries for the selected range. They'll be re-downloaded next time you sync."
        case .clearBothRange:
            return "Remove all cached health data for the selected range. Your workouts and Apple Health data are untouched."
        case .clearWorkoutAll:
            return "Remove all cached workout health data from this app. Your workouts themselves stay."
        case .clearDailyAll:
            return "Remove all cached daily health history from this app."
        case .clearAndResyncRange:
            return "Clear and re-download health data for the selected range. This may take a moment."
        case .clearAndResyncAll:
            return "Clear all cached health data and re-download everything. This may take a few minutes."
        }
    }

    private func confirmationButtonLabel(for action: HealthCacheAction) -> String {
        switch action {
        case .clearWorkoutRange: return "Clear Workout Data"
        case .clearDailyRange: return "Clear Daily Data"
        case .clearBothRange: return "Clear All Data"
        case .clearWorkoutAll: return "Clear All Workout Data"
        case .clearDailyAll: return "Clear All Daily Data"
        case .clearAndResyncRange: return "Clear & Re-Sync"
        case .clearAndResyncAll: return "Refresh Everything"
        }
    }

    // MARK: - Perform Actions

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
                    in: boundedCacheRange,
                    includeWorkoutData: true,
                    includeDailyData: false
                )
                statusMessage = workoutResultMessage(from: result, scope: "selected range")

            case .clearDailyRange:
                let result = healthManager.clearCachedHealthData(
                    in: boundedCacheRange,
                    includeWorkoutData: false,
                    includeDailyData: true
                )
                statusMessage = dailyResultMessage(from: result, scope: "selected range")

            case .clearBothRange:
                let result = healthManager.clearCachedHealthData(in: boundedCacheRange)
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
                let cleared = healthManager.clearCachedHealthData(in: boundedCacheRange)
                guard healthManager.authorizationStatus == .authorized else {
                    statusMessage = combinedResultMessage(from: cleared, scope: "selected range") + " Connect Apple Health to re-sync."
                    return
                }
                let toSync = workoutsInRange
                if !toSync.isEmpty { _ = try await healthManager.syncAllWorkouts(toSync) }
                try await healthManager.syncDailyHealthData(range: boundedCacheRange)
                let count = toSync.count
                let days = healthManager.dayCount(in: boundedCacheRange)
                statusMessage = "Re-synced \(count) workout\(count == 1 ? "" : "s") and \(days) day\(days == 1 ? "" : "s")."

            case .clearAndResyncAll:
                _ = healthManager.clearCachedHealthData()
                guard healthManager.authorizationStatus == .authorized else {
                    statusMessage = "All cached data cleared. Connect Apple Health to re-sync."
                    return
                }
                if !workouts.isEmpty { _ = try await healthManager.syncAllWorkouts(workouts) }
                let fullRange = DateInterval(start: Self.allHistoryStart, end: syncEndDate)
                try await healthManager.syncDailyHealthData(range: fullRange)
                statusMessage = "All health data refreshed."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Result Messages

    private func workoutResultMessage(from result: HealthCacheClearResult, scope: String) -> String {
        if result.removedWorkoutEntries == 0 {
            return "No cached workout data found in the \(scope)."
        }
        return "Removed \(result.removedWorkoutEntries) workout record\(result.removedWorkoutEntries == 1 ? "" : "s") from the \(scope)."
    }

    private func dailyResultMessage(from result: HealthCacheClearResult, scope: String) -> String {
        if result.removedDailyEntries == 0 && result.removedCoveredDays == 0 {
            return "No cached daily data found in the \(scope)."
        }
        return "Removed \(result.removedDailyEntries) daily entr\(result.removedDailyEntries == 1 ? "y" : "ies") and \(result.removedCoveredDays) scanned day\(result.removedCoveredDays == 1 ? "" : "s") from the \(scope)."
    }

    private func combinedResultMessage(from result: HealthCacheClearResult, scope: String) -> String {
        if !result.removedAnything {
            return "No cached data found in the \(scope)."
        }
        return "Cleared \(result.removedWorkoutEntries) workout record\(result.removedWorkoutEntries == 1 ? "" : "s") and \(result.removedDailyEntries) daily entr\(result.removedDailyEntries == 1 ? "y" : "ies") from the \(scope)."
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Legacy Aliases (preserve compilation)

typealias HealthHistorySyncView = HealthDataSettingsView
typealias HealthCacheManagementView = HealthDataSettingsView

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
