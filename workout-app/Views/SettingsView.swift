import Combine
import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @Binding var selectedTab: AppTab
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var logStore: WorkoutLogStore
    @EnvironmentObject var sessionManager: WorkoutSessionManager
    @EnvironmentObject var intentionalBreaksManager: IntentionalBreaksManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var showingImportWizard = false
    @State private var showingHealthWizard = false
    @State private var dataClearSheet: DataClearSheetRoute?

    @AppStorage("weightIncrement") private var weightIncrement: Double = 2.5
    @AppStorage(RestTimerState.durationPreferenceKey) private var restTimerDuration: Int = RestTimerState.defaultDuration
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1
    @AppStorage("sessionsPerWeekGoal") private var sessionsPerWeekGoal: Int = 4
    @AppStorage("preferredSleepSourceName") private var preferredSleepSourceName: String = ""
    @AppStorage("appearanceMode") private var appearanceMode: Int = AppearanceMode.system.rawValue
    @AppStorage(AppAnalytics.collectionEnabledKey) private var analyticsCollectionEnabled = true
    @AppStorage(Haptics.preferenceKey) private var hapticsEnabled = true
    @State private var cachedIntentionalBreaksSubtitle = "Auto-detect workout gaps"

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    trainingSection
                    healthSection
                    dataSection
                    appSection
                    removalSection

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Davis's Big Beautiful Workout App")
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(appVersionDisplay)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xxl)
                .contentColumn()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingImportWizard) {
            StrongImportWizard(
                isPresented: $showingImportWizard,
                dataManager: dataManager,
                iCloudManager: iCloudManager,
                source: "settings"
            )
        }
        .sheet(isPresented: $showingHealthWizard) {
            HealthSyncWizard(
                isPresented: $showingHealthWizard,
                workouts: dataManager.workouts,
                source: "settings"
            )
        }
        .sheet(item: $dataClearSheet) { _ in
            SelectiveDataClearSheet(
                dataManager: dataManager,
                iCloudManager: iCloudManager,
                logStore: logStore,
                sessionManager: sessionManager,
                healthManager: healthManager,
                intentionalBreaksManager: intentionalBreaksManager,
                annotationsManager: annotationsManager,
                gymProfilesManager: gymProfilesManager,
                hasSeenOnboarding: $hasSeenOnboarding
            )
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            normalizeIncrementIfNeeded()
            normalizeSessionsGoalIfNeeded()
            refreshIntentionalBreaksSubtitle()
            AppAnalytics.shared.configureIfNeeded()
        }
        .onChange(of: analyticsCollectionEnabled) { _, newValue in
            AppAnalytics.shared.setCollectionEnabled(newValue)
        }
        .onChange(of: intentionalRestDays) { _, _ in
            refreshIntentionalBreaksSubtitle()
        }
        .onReceive(dataManager.$workouts.dropFirst()) { _ in
            refreshIntentionalBreaksSubtitle()
        }
        .onReceive(intentionalBreaksManager.$savedBreaks.dropFirst()) { _ in
            refreshIntentionalBreaksSubtitle()
        }
        .analyticsScreen("Settings")
    }


    // MARK: - Sections

    private var trainingSection: some View {
        SettingsGroup(title: "Training") {
            SettingsPickerRow(title: "Weekly goal", subtitle: "Sessions that fill the bar each week", showsRule: false) {
                Picker("Sessions per week goal", selection: $sessionsPerWeekGoal) {
                    ForEach(1...14, id: \.self) { sessions in
                        Text("\(sessions) per week").tag(sessions)
                    }
                }
            }

            SettingsPickerRow(title: "Weight increment", subtitle: "Step size when you adjust a weight") {
                Picker("Weight increment", selection: $weightIncrement) {
                    ForEach(incrementOptions, id: \.self) { option in
                        Text(incrementLabel(option)).tag(option)
                    }
                }
            }

            SettingsPickerRow(title: "Rest timer", subtitle: "Starts after each completed set") {
                Picker("Rest timer", selection: $restTimerDuration) {
                    ForEach(restTimerOptions, id: \.self) { seconds in
                        Text(restTimerLabel(seconds)).tag(seconds)
                    }
                }
            }

            SettingsPickerRow(
                title: "Rest days",
                subtitle: "Days off allowed before a streak breaks"
            ) {
                Picker("Rest days", selection: $intentionalRestDays) {
                    ForEach(0...30, id: \.self) { days in
                        Text("\(days) day\(days == 1 ? "" : "s")").tag(days)
                    }
                }
            }

            NavigationLink(destination: IntentionalBreaksView(dataManager: dataManager)) {
                SettingsLinkRow(title: "Planned breaks", subtitle: intentionalBreaksSubtitle)
            }
            .buttonStyle(PressableCardButtonStyle())

            NavigationLink(destination: GymProfilesView()) {
                SettingsLinkRow(title: "Gyms", subtitle: "Tag workouts by location")
            }
            .buttonStyle(PressableCardButtonStyle())

            NavigationLink(destination: ExerciseTaggingView(dataManager: dataManager)) {
                SettingsLinkRow(title: "Muscle roles", subtitle: "Primary and secondary muscles for each exercise")
            }
            .buttonStyle(PressableCardButtonStyle())
        }
    }

    private var healthSection: some View {
        SettingsGroup(title: "Apple Health") {
            Button {
                if healthManager.authorizationStatus == .authorized {
                    selectedTab = .health
                } else {
                    showingHealthWizard = true
                }
            } label: {
                SettingsLinkRow(
                    title: "Apple Health",
                    subtitle: healthManager.authorizationStatus == .authorized ? "Connected" : "Not connected",
                    value: healthManager.authorizationStatus == .authorized ? "On" : "Off",
                    showsRule: false
                )
            }
            .buttonStyle(PressableCardButtonStyle())

            if healthManager.authorizationStatus == .denied {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                } label: {
                    TextLinkLabel(title: "Open Settings to grant Health access")
                        .ledgerRow()
                }
                .buttonStyle(.plain)
            }

            NavigationLink(destination: HealthPermissionAuditView()) {
                SettingsLinkRow(title: "Permissions", subtitle: healthPermissionsSubtitle)
            }
            .buttonStyle(PressableCardButtonStyle())

            NavigationLink(destination: HealthDataSettingsView(workouts: dataManager.workouts)) {
                SettingsLinkRow(title: "Health data", subtitle: healthDataSubtitle)
            }
            .buttonStyle(PressableCardButtonStyle())

            NavigationLink(destination: SleepSourceSettingsView(workouts: dataManager.workouts)) {
                SettingsLinkRow(title: "Sleep source", subtitle: sleepSourceSubtitle)
            }
            .buttonStyle(PressableCardButtonStyle())
        }
    }

    private var dataSection: some View {
        SettingsGroup(title: "Data") {
            Button {
                showingImportWizard = true
            } label: {
                SettingsLinkRow(title: "Import", subtitle: "Strong CSV or an app backup", showsRule: false)
            }
            .buttonStyle(PressableCardButtonStyle())

            NavigationLink(destination: ExportWorkoutsView(dataManager: dataManager, iCloudManager: iCloudManager)) {
                SettingsLinkRow(title: "Export", subtitle: "Backups, CSV, and PDF reports")
            }
            .buttonStyle(PressableCardButtonStyle())

            NavigationLink(destination: BackupFilesView(iCloudManager: iCloudManager)) {
                SettingsLinkRow(title: "Backups", subtitle: "Saved backups and exports")
            }
            .buttonStyle(PressableCardButtonStyle())
        }
    }

    private var appSection: some View {
        SettingsGroup(title: "App") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Appearance")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                AppSegmentedPicker(
                    title: "Appearance",
                    selection: $appearanceMode,
                    options: AppearanceMode.allCases.map { (label: $0.label, value: $0.rawValue) }
                )
            }
            .ledgerRow(showsRule: false)

            SettingsToggleRow(title: "Haptic feedback", subtitle: "Taps and clicks as you log", isOn: $hapticsEnabled)

            SettingsToggleRow(title: "Anonymous analytics", subtitle: analyticsSubtitle, isOn: $analyticsCollectionEnabled)
        }
    }

    private var removalSection: some View {
        SettingsGroup(title: "Remove data") {
            Button {
                dataClearSheet = DataClearSheetRoute()
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear app data")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.error)
                        Text("Choose what to delete and review it first")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.error)
                        .accessibilityHidden(true)
                }
                .ledgerRow(showsRule: false)
            }
            .buttonStyle(PressableCardButtonStyle())
        }
    }

    private var incrementOptions: [Double] {
        [1.25, 2.5, 5.0]
    }

    private func incrementLabel(_ value: Double) -> String {
        // "1.25 lbs", "2.5 lbs", "5 lbs"
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) lbs"
    }

    private var restTimerOptions: [Int] {
        let presets = [30, 45, 60, 90, 120, 150, 180, 240, 300]
        return Array(Set(presets + [restTimerDuration])).sorted()
    }

    private func restTimerLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes == 0 { return "\(remainder) sec" }
        return remainder == 0 ? "\(minutes) min" : "\(minutes):\(String(format: "%02d", remainder))"
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
        cachedIntentionalBreaksSubtitle
    }

    private func refreshIntentionalBreaksSubtitle() {
        let suggestionCount = intentionalBreaksManager
            .suggestions(for: dataManager.workouts, intentionalRestDays: intentionalRestDays)
            .count
        let savedCount = intentionalBreaksManager.savedBreaks.count

        switch (savedCount, suggestionCount) {
        case (0, 0):
            cachedIntentionalBreaksSubtitle = "Auto-detect workout gaps"
        case (_, 0):
            cachedIntentionalBreaksSubtitle = "\(savedCount) saved range\(savedCount == 1 ? "" : "s")"
        case (0, _):
            cachedIntentionalBreaksSubtitle = "\(suggestionCount) suggested gap\(suggestionCount == 1 ? "" : "s")"
        default:
            cachedIntentionalBreaksSubtitle = "\(savedCount) saved, \(suggestionCount) suggested"
        }
    }

    private var sleepSourceSubtitle: String {
        if preferredSleepSourceName.isEmpty {
            return "Automatic"
        }
        return "\(preferredSleepSourceName) preferred"
    }

    private var analyticsSubtitle: String {
        AppAnalytics.shared.statusSummary + ". No raw Health values, route data, file contents, or names."
    }

    private var healthDataSubtitle: String {
        let workoutCount = healthManager.healthDataStore.count
        let dailyCount = healthManager.dailyHealthStore.count

        guard healthManager.authorizationStatus == .authorized else {
            return "Connect Health to sync and manage data"
        }

        guard workoutCount > 0 || dailyCount > 0 else {
            return "Sync history and manage cached data"
        }

        if let earliest = healthManager.dailyHealthStore.keys.min() {
            return "\(SharedFormatters.count(dailyCount, "day")) and \(SharedFormatters.count(workoutCount, "workout")) since \(SettingsDateFormatters.mediumDate.string(from: earliest))"
        }

        return "\(SharedFormatters.count(dailyCount, "day")) and \(SharedFormatters.count(workoutCount, "workout")) saved"
    }

    private var healthPermissionsSubtitle: String {
        switch healthManager.authorizationStatus {
        case .unavailable:
            return "Health unavailable on this device"
        case .authorized:
            return "Access by data type"
        case .denied:
            return "Check missing or changed Health access"
        case .notDetermined:
            return "See every requested Health data type"
        }
    }

    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }
}

/// A titled group of settings rows.
private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(title: title)
            VStack(spacing: 0) {
                content()
            }
        }
    }
}

private struct SettingsPickerRow<Control: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let subtitle: String
    var showsRule = true
    @ViewBuilder let control: () -> Control

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.md))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Theme.Colors.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: Theme.Layout.minimumTapTarget)
        }
        .ledgerRow(showsRule: showsRule)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var showsRule = true

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.Colors.success)
        .ledgerRow(showsRule: showsRule)
    }
}

private struct SettingsLinkRow: View {
    let title: String
    let subtitle: String
    var value: String?
    var showsRule = true

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.sm)

            if let value {
                Text(value)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Image(systemName: "chevron.right")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .ledgerRow(showsRule: showsRule)
        .accessibilityElement(children: .combine)
    }
}

enum SettingsDateFormatters {
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
