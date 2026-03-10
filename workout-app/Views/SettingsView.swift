import SwiftUI

struct SettingsView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @Binding var selectedTab: AppTab
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var logStore: WorkoutLogStore
    @EnvironmentObject var sessionManager: WorkoutSessionManager
    @EnvironmentObject var intentionalBreaksManager: IntentionalBreaksManager

    @State private var showingImportWizard = false
    @State private var showingHealthWizard = false
    @State private var showingDeleteAlert = false

    @AppStorage("weightIncrement") private var weightIncrement: Double = 2.5
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1
    @AppStorage("sessionsPerWeekGoal") private var sessionsPerWeekGoal: Int = 4
    @AppStorage("preferredSleepSourceName") private var preferredSleepSourceName: String = ""

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(spacing: Theme.Spacing.xxl) {
                // Header
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "gearshape.fill")
                        .font(Theme.Iconography.featureLarge)
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(
                            Circle()
                                .fill(Theme.accentGradient)
                        )
                        .shadow(color: Theme.Colors.accent.opacity(0.25), radius: 12, y: 4)
                        .shadow(color: Theme.Colors.accent.opacity(0.10), radius: 24, y: 8)

                    Text("Settings")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
                .animateOnAppear()

                // Data Management Section
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SettingsSectionLabel("DATA & SYNC")

                    VStack(spacing: 1) {
                        SettingsRow(
                            icon: "square.and.arrow.down",
                            color: Theme.Colors.accent,
                            title: "Import Data",
                            subtitle: "Import CSV"
                        ) {
                            showingImportWizard = true
                        }

                        Divider().padding(.leading, 50)

                        NavigationLink(destination: ExportWorkoutsView(dataManager: dataManager, iCloudManager: iCloudManager)) {
                            SettingsInlineRow(
                                icon: "square.and.arrow.up",
                                color: Theme.Colors.accentSecondary,
                                title: "Export Data",
                                subtitle: "CSV backup"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 50)

                        SettingsRow(
                            icon: "heart.fill",
                            color: Theme.Colors.error,
                            title: "Apple Health",
                            subtitle: healthManager.authorizationStatus == .authorized ? "Connected" : "Health off",
                            value: healthManager.authorizationStatus == .authorized ? "On" : "Off"
                        ) {
                            if healthManager.authorizationStatus == .authorized {
                                selectedTab = .health
                            } else {
                                showingHealthWizard = true
                            }
                        }

                        Divider().padding(.leading, 50)

                        NavigationLink(destination: HealthHistorySyncView(workouts: dataManager.workouts)) {
                            SettingsInlineRow(
                                icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                                color: Theme.Colors.error,
                                title: "Health History Sync",
                                subtitle: healthHistorySubtitle
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 50)

                        NavigationLink(destination: SleepSourceSettingsView(workouts: dataManager.workouts)) {
                            SettingsInlineRow(
                                icon: "moon.zzz.fill",
                                color: Theme.Colors.accentSecondary,
                                title: "Sleep Source",
                                subtitle: sleepSourceSubtitle
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 50)

                        NavigationLink(destination: BackupFilesView(iCloudManager: iCloudManager)) {
                            SettingsInlineRow(
                                icon: "icloud.fill",
                                color: Theme.Colors.cardio,
                                title: "Backups",
                                subtitle: "iCloud"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Preferences Section
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SettingsSectionLabel("PREFERENCES")

                    VStack(spacing: 1) {
                        // Weight increment
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "ruler.fill")
                                .font(Theme.Typography.subheadlineStrong)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.accentSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                            Text("Weight Increment")
                                .font(Theme.Typography.body)

                            Spacer()

                            Picker("", selection: $weightIncrement) {
                                ForEach(incrementOptions, id: \.self) { option in
                                    Text(incrementLabel(option)).tag(option)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding()
                        .softCard(elevation: 1)

                        Divider().padding(.leading, 50)

                        // Intentional rest window (used for streak/consistency calculations)
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "bed.double.fill")
                                .font(Theme.Typography.subheadlineStrong)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Intentional Rest")
                                    .font(Theme.Typography.body)
                                Text("Allow up to \(intentionalRestDays) day\(intentionalRestDays == 1 ? "" : "s") off without breaking streaks")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            Picker("", selection: $intentionalRestDays) {
                                ForEach(0...30, id: \.self) { days in
                                    Text("\(days) day\(days == 1 ? "" : "s")").tag(days)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding()
                        .softCard(elevation: 1)

                        Divider().padding(.leading, 50)

                        NavigationLink(destination: IntentionalBreaksView(dataManager: dataManager)) {
                            SettingsInlineRow(
                                icon: "calendar.badge.plus",
                                color: Theme.Colors.warning,
                                title: "Intentional Break Dates",
                                subtitle: intentionalBreaksSubtitle
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 50)

                        // Sessions per week goal (used by consistency visualization)
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "target")
                                .font(Theme.Typography.subheadlineStrong)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.success)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sessions / Week Goal")
                                    .font(Theme.Typography.body)
                                Text("Used by consistency goal markers")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            Picker("", selection: $sessionsPerWeekGoal) {
                                ForEach(1...14, id: \.self) { sessions in
                                    Text("\(sessions)/wk").tag(sessions)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding()
                        .softCard(elevation: 1)

                        Divider().padding(.leading, 50)

                        NavigationLink(destination: GymProfilesView()) {
                            SettingsInlineRow(
                                icon: "mappin.and.ellipse",
                                color: Theme.Colors.accent,
                                title: "Gym Profiles",
                                subtitle: "Tag workouts by location"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 50)

                        NavigationLink(destination: ExerciseTaggingView(dataManager: dataManager)) {
                            SettingsInlineRow(
                                icon: "tag.fill",
                                color: Theme.Colors.accentTertiary,
                                title: "Exercise Tags",
                                subtitle: "Assign muscle groups"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Danger Zone
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SettingsSectionLabel("DANGER ZONE")

                    Button(
                        action: { showingDeleteAlert = true },
                        label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "trash.fill")
                                    .font(Theme.Typography.subheadlineStrong)
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Theme.Colors.error)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                                Text("Clear All Data")
                                    .font(Theme.Typography.bodyBold)
                                    .foregroundStyle(Theme.Colors.error)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(Theme.Typography.captionBold)
                                    .foregroundStyle(Theme.Colors.error.opacity(0.5))
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
                    )
                    .buttonStyle(AppInteractionButtonStyle())
                }

                VStack(spacing: Theme.Spacing.xs) {
                    Text("Davis's Big Beautiful Workout App")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textTertiary)

                    Text("Version 1.0.0")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.top, Theme.Spacing.md)
                }
                .padding()
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingImportWizard) {
            StrongImportWizard(
                isPresented: $showingImportWizard,
                dataManager: dataManager,
                iCloudManager: iCloudManager
            )
        }
        .sheet(isPresented: $showingHealthWizard) {
            HealthSyncWizard(
                isPresented: $showingHealthWizard,
                workouts: dataManager.workouts
            )
        }
        .alert("Clear All Data", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await iCloudManager.deleteAllWorkoutFiles()
                    await logStore.clearAll()
                    await sessionManager.discardDraft()
                    await MainActor.run {
                        healthManager.clearAllData()
                        intentionalBreaksManager.clearAll()
                        dataManager.clearAllData()
                    }
                }
            }
        } message: {
            Text(
                "WARNING: This will permanently delete all imported CSV files, logged workouts, " +
                "intentional break dates, active session drafts, and health data from your device. This action cannot be undone."
            )
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            normalizeIncrementIfNeeded()
            normalizeSessionsGoalIfNeeded()
        }
    }

    private var incrementOptions: [Double] {
        [1.25, 2.5, 5.0]
    }

    private func incrementLabel(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func normalizeIncrementIfNeeded() {
        if !incrementOptions.contains(where: { abs($0 - weightIncrement) < 0.0001 }) {
            weightIncrement = 2.5
        }
        if weightIncrement <= 0 {
            weightIncrement = 2.5
        }
    }

    private func normalizeSessionsGoalIfNeeded() {
        if sessionsPerWeekGoal < 1 {
            sessionsPerWeekGoal = 1
        } else if sessionsPerWeekGoal > 14 {
            sessionsPerWeekGoal = 14
        }
    }

    private var intentionalBreaksSubtitle: String {
        let suggestionCount = intentionalBreaksManager
            .suggestions(for: dataManager.workouts, intentionalRestDays: intentionalRestDays)
            .count
        let savedCount = intentionalBreaksManager.savedBreaks.count

        switch (savedCount, suggestionCount) {
        case (0, 0):
            return "Auto-detect workout gaps"
        case (_, 0):
            return "\(savedCount) saved range\(savedCount == 1 ? "" : "s")"
        case (0, _):
            return "\(suggestionCount) suggested gap\(suggestionCount == 1 ? "" : "s")"
        default:
            return "\(savedCount) saved · \(suggestionCount) suggested"
        }
    }

    private var sleepSourceSubtitle: String {
        if preferredSleepSourceName.isEmpty {
            return "Auto-select the strongest sleep source"
        }
        return "\(preferredSleepSourceName) preferred, fallback enabled"
    }

    private var healthHistorySubtitle: String {
        guard healthManager.authorizationStatus == .authorized else {
            return "Connect Health to backfill older history"
        }

        if let earliest = healthManager.dailyHealthStore.keys.min() {
            return "Cached from \(SettingsDateFormatters.mediumDate.string(from: earliest))"
        }

        return "Backfill daily Health history"
    }
}

// MARK: - Settings Helper Views

private struct HealthHistorySyncView: View {
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
                            range: DateInterval(start: Calendar.current.startOfDay(for: earliestWorkoutDate), end: syncEndDate),
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

private struct SleepSourceSettingsView: View {
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

private struct SettingsSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.Typography.metricLabel)
            .foregroundStyle(Theme.Colors.textTertiary)
            .tracking(1.2)
            .padding(.horizontal)
    }
}

private struct SettingsInlineRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
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
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding()
        .softCard(elevation: 1)
    }
}

struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(color)
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

                if let value = value {
                    Text(value)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding()
            .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
    }
}

private enum SettingsDateFormatters {
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let mediumDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
