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
