import SwiftUI
import UIKit

enum BodyChartRange: String, CaseIterable, Identifiable {
    case fourWeeks = "4W"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .fourWeeks: return 28
        case .threeMonths: return 91
        case .sixMonths: return 182
        case .year: return 365
        case .all: return nil
        }
    }

    /// Used in sentences such as "Average, 3 months".
    var name: String {
        switch self {
        case .fourWeeks: return "4 weeks"
        case .threeMonths: return "3 months"
        case .sixMonths: return "6 months"
        case .year: return "year"
        case .all: return "all time"
        }
    }

    /// Past six months the dots crowd out the line, so only the trend and band are drawn.
    var showsReadings: Bool { self != .year && self != .all }
}

/// Weight and body composition on one scroll: trend weight and pace up top, the chart, how much it
/// has changed, the goal, body fat, lifts against weight, and the weigh-in log.
struct BodyView: View {
    var isTabRoot = false

    @EnvironmentObject private var store: BodyStore
    @EnvironmentObject private var healthManager: HealthViewStore
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage("bodyRange") private var rangeRaw = BodyChartRange.threeMonths.rawValue
    @AppStorage("bodyGoalWeightLb") private var goalWeight: Double = 0
    @AppStorage("bodyGoalStartWeightLb") private var goalStartWeight: Double = 0
    @AppStorage("bodyGoalStartDate") private var goalStartDate: Double = 0
    @AppStorage("bodyGoalReachedDate") private var goalReachedDate: Double = 0
    @AppStorage("favoriteExercises") private var favoriteExercisesData = "[]"

    @State private var weightSelection: BodyTrendDay?
    @State private var fatSelection: BodyTrendDay?
    @State private var showingGoal = false
    @State private var showingMethod = false
    @State private var showingLog = false
    @State private var detailDay: BodyTrendDay?
    @State private var selectedExercise: ExerciseSelection?
    @State private var liftRows: [BodyLiftRow] = []
    @State private var isRequestingAuthorization = false
    @State private var authorizationError: String?

    private var range: BodyChartRange { BodyChartRange(rawValue: rangeRaw) ?? .threeMonths }
    private var weight: BodySeries { store.weight }
    private var bodyFat: BodySeries { store.bodyFat }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                content
            }
            .padding(.horizontal, Theme.Layout.screenGutter)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xxl)
            .contentColumn()
        }
        .background(AdaptiveBackground())
        .refreshable { await store.reload(from: healthManager) }
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(isTabRoot ? .large : .inline)
        .accessibilityIdentifier("body-composition")
        .sheet(isPresented: $showingGoal) {
            BodyGoalSheet(
                trend: weight.latest?.trend,
                currentGoal: goalWeight > 0 ? goalWeight : nil,
                onSave: saveGoal,
                onRemove: removeGoal
            )
        }
        .sheet(isPresented: $showingMethod) {
            BodyMethodSheet(ignoredReadingCount: weight.ignoredReadingCount + bodyFat.ignoredReadingCount)
        }
        .sheet(isPresented: $showingLog) {
            BodyReadingsLog(series: weight)
        }
        .sheet(item: $detailDay) { day in
            NavigationStack {
                BodyDayDetail(series: weight, day: day)
            }
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(item: $selectedExercise) { selection in
            ExerciseDetailView(
                exerciseName: selection.id,
                dataManager: dataManager,
                annotationsManager: annotationsManager,
                gymProfilesManager: gymProfilesManager
            )
        }
        .task { refreshIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshIfNeeded(maxAge: 60) }
        }
        .onChange(of: healthManager.authorizationStatus) { _, status in
            if status == .authorized { store.refresh(from: healthManager) }
        }
        .onChange(of: healthManager.dailyDataRevision) { _, _ in store.refresh(from: healthManager) }
        .onChange(of: store.snapshot.loadedAt) { _, _ in recordGoalReachedIfNeeded() }
        .task(id: LiftRefreshKey(revision: dataManager.datasetRevision, loadedAt: store.snapshot.loadedAt, favorites: favoriteExercisesData)) {
            await refreshLifts()
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if healthManager.authorizationStatus == .unavailable {
            messageBlock(
                title: "Apple Health isn't available here.",
                body: "Weight and body fat come from Apple Health, which this device doesn't have."
            )
        } else if healthManager.authorizationStatus != .authorized {
            accessBlock
        } else if !store.hasLoaded {
            if let error = store.errorMessage {
                errorBlock(error)
            } else {
                loadingBlock
            }
        } else if weight.isEmpty {
            emptyBlock
        } else {
            page
        }
    }

    @ViewBuilder
    private var page: some View {
        let now = Date()
        let rate = weight.rate(asOf: now)
        let goalStatus = goalStatus(rate: rate, now: now)

        if let error = store.errorMessage {
            Text("Couldn't refresh from Apple Health. Showing the last loaded readings. \(error)")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            BodyHero(
                series: weight,
                rate: rate,
                goalLine: goalStatus.map { BodyGoalText.heroLine(goal: goalWeight, status: $0) },
                now: now
            )
            compositionRow(now: now)
        }

        chartBlock(now: now)

        if weight.readingDayCount >= 8 {
            BodyChangeSection(
                series: weight,
                range: interval(for: range, now: now),
                rangeName: range.name,
                comparesPreviousPeriod: range != .all
            )
        }

        BodyGoalSection(
            status: goalStatus,
            reachedDate: goalReachedDate > 0 ? Date(timeIntervalSince1970: goalReachedDate) : nil,
            onEdit: { showingGoal = true }
        )

        if !bodyFat.isEmpty {
            BodyCompositionSection(
                weight: weight,
                bodyFat: bodyFat,
                domain: domain(for: range, series: bodyFat, now: now),
                showsReadings: range.showsReadings,
                selection: $fatSelection
            )
        }

        if !liftRows.isEmpty {
            BodyLiftsSection(
                rows: liftRows,
                summary: BodyLiftAnalyzer.summary(rows: liftRows, weightChange: weight.change(days: 90)),
                onOpen: { selectedExercise = ExerciseSelection(id: $0) }
            )
        }

        BodyWeighInsSection(
            series: weight,
            now: now,
            onSelectDay: { detailDay = $0 },
            onShowAll: { showingLog = true }
        )

        Button { showingMethod = true } label: {
            TextLinkLabel(title: "How this is calculated")
                .frame(minHeight: Theme.Layout.minimumTapTarget)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func compositionRow(now: Date) -> some View {
        if let composition = BodyComposition.latest(weight: weight, bodyFat: bodyFat),
           now.timeIntervalSince(composition.date) < 30 * 86_400 {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
                : AnyLayout(StatColumns())
            layout {
                DisplayStat(value: BodyFormat.number(composition.bodyFatPercent) + "%", label: "body fat", valueFont: Theme.Typography.number)
                DisplayStat(value: BodyFormat.number(composition.leanMass), unit: "lb", label: "lean mass", valueFont: Theme.Typography.number)
                DisplayStat(value: BodyFormat.number(composition.fatMass), unit: "lb", label: "fat mass", valueFont: Theme.Typography.number)
            }
        }
    }

    private func chartBlock(now: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            AppSegmentedPicker(
                title: "Range",
                selection: Binding(
                    get: { range },
                    set: { newValue in
                        weightSelection = nil
                        rangeRaw = newValue.rawValue
                    }
                ),
                options: BodyChartRange.allCases.map { (label: $0.rawValue, value: $0) }
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                BodyChartReadout(series: weight, selection: weightSelection, summary: chartSummary(now: now))
                BodyTrendChart(
                    series: weight,
                    domain: domain(for: range, series: weight, now: now),
                    showsReadings: range.showsReadings,
                    goal: goalWeight > 0 ? goalWeight : nil,
                    workoutDays: workoutDays(in: domain(for: range, series: weight, now: now)),
                    tint: BodyFormat.weightTint,
                    selection: $weightSelection
                )
                .accessibilityIdentifier("body-weight-chart")
                legend
            }
            .padding(Theme.Spacing.md)
            .softCard()
        }
    }

    private func chartSummary(now: Date) -> String {
        let days = weight.gridDays(in: interval(for: range, now: now))
        let count = days.reduce(0) { $0 + ($1.hasReading ? 1 : 0) }
        guard let first = days.first, let last = days.last else { return "No weigh-ins in this range" }
        let change = last.trend - first.trend
        return "\(SharedFormatters.count(count, "weigh-in")), trend \(BodyFormat.signedWeight(change))"
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.md) {
            if range.showsReadings {
                legendKey("Scale") {
                    Circle().fill(Theme.Colors.textSecondary.opacity(0.55)).frame(width: 6, height: 6)
                }
            }
            legendKey("Trend") {
                Capsule().fill(BodyFormat.weightTint).frame(width: 14, height: 3)
            }
            if weight.residualSigma != nil {
                legendKey("Usual range") {
                    RoundedRectangle(cornerRadius: 2).fill(BodyFormat.weightTint.opacity(0.18)).frame(width: 14, height: 9)
                }
            }
            legendKey("Workouts") {
                Rectangle().fill(Theme.Colors.ink.opacity(0.3)).frame(width: 2, height: 9)
            }
            if goalWeight > 0 {
                legendKey("Goal") {
                    Capsule().fill(Theme.Colors.plateGreen).frame(width: 12, height: 2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func legendKey<Mark: View>(_ title: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 4) {
            mark()
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: States

    private var accessBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(healthManager.authorizationStatus == .denied ? "Health access is off." : "See your weight trend.")
                .font(Theme.Typography.displayHeroCompact)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Connect Apple Health to chart your weight and body fat. This app only reads them.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let authorizationError {
                Text(authorizationError)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if healthManager.authorizationStatus == .denied {
                AppPrimaryButton(title: "Open Settings", systemImage: "gear") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            } else {
                AppPrimaryButton(
                    title: isRequestingAuthorization ? "Waiting for Apple Health…" : "Connect Apple Health",
                    isEnabled: !isRequestingAuthorization,
                    action: requestAuthorization
                )
            }
        }
    }

    private var emptyBlock: some View {
        messageBlock(
            title: "No weight in Apple Health yet.",
            body: "Weigh in on a connected scale, or add a reading in Health under Browse, Body Measurements, Weight. It shows up here after the next sync."
        )
    }

    private var loadingBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SkeletonRect(width: 120, height: 14)
            SkeletonRect(width: 220, height: 84, cornerRadius: Theme.CornerRadius.medium)
            SkeletonRect(width: 200, height: 18)
            SkeletonRect(height: 280, cornerRadius: Theme.CornerRadius.xlarge)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading weight")
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            messageBlock(title: "Couldn't load readings.", body: message)
            AppPrimaryButton(title: "Try again", systemImage: "arrow.clockwise") {
                store.refresh(from: healthManager)
            }
        }
    }

    private func messageBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.displayHeroCompact)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Ranges

    private func interval(for range: BodyChartRange, now: Date) -> DateInterval {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        guard let days = range.days,
              let start = calendar.date(byAdding: .day, value: -days, to: end) else {
            let first = weight.grid.first?.day ?? calendar.startOfDay(for: now)
            return DateInterval(start: min(first, end), end: end)
        }
        return DateInterval(start: start, end: end)
    }

    /// The chart's x span: the range, ending today so a stretch with no weigh-ins stays visible.
    private func domain(for range: BodyChartRange, series: BodySeries, now: Date) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: now)
        guard let days = range.days,
              let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) else {
            let first = series.grid.first?.day ?? end
            return min(first, end)...end
        }
        return start...end
    }

    private func workoutDays(in domain: ClosedRange<Date>) -> [Date] {
        let calendar = Calendar.current
        var days = Set<Date>()
        for workout in dataManager.workouts where domain.contains(calendar.startOfDay(for: workout.date)) {
            days.insert(calendar.startOfDay(for: workout.date))
        }
        return days.sorted()
    }

    // MARK: Goal

    private func goalStatus(rate: BodyRate?, now: Date) -> BodyGoalStatus? {
        guard goalWeight > 0, let latest = weight.latest else { return nil }
        let start = goalStartWeight > 0 ? goalStartWeight : latest.trend
        return BodyGoalStatus.make(goal: goalWeight, start: start, current: latest.trend, rate: rate, now: now)
    }

    private func saveGoal(_ goal: Double) {
        goalWeight = goal
        goalStartWeight = weight.latest?.trend ?? goal
        goalStartDate = Date().timeIntervalSince1970
        goalReachedDate = 0
        recordGoalReachedIfNeeded()
    }

    private func removeGoal() {
        goalWeight = 0
        goalStartWeight = 0
        goalStartDate = 0
        goalReachedDate = 0
    }

    private func recordGoalReachedIfNeeded() {
        guard goalReachedDate == 0, let status = goalStatus(rate: nil, now: Date()), status.isReached else { return }
        goalReachedDate = Date().timeIntervalSince1970
    }

    // MARK: Loading

    private func refreshIfNeeded(maxAge: TimeInterval = 300) {
        guard healthManager.authorizationStatus == .authorized else { return }
        if let loadedAt = store.snapshot.loadedAt, Date().timeIntervalSince(loadedAt) < maxAge { return }
        store.refresh(from: healthManager)
    }

    private func requestAuthorization() {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        authorizationError = nil
        Task {
            defer { isRequestingAuthorization = false }
            do {
                try await healthManager.requestAuthorization()
                healthManager.refreshAuthorizationStatus()
                store.refresh(from: healthManager)
            } catch {
                authorizationError = error.localizedDescription
            }
        }
    }

    private struct LiftRefreshKey: Equatable {
        let revision: UInt64
        let loadedAt: Date?
        let favorites: String
    }

    private func refreshLifts() async {
        guard store.hasLoaded else { return }
        let workouts = dataManager.workouts
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()
        let favorites = (try? JSONDecoder().decode([String].self, from: Data(favoriteExercisesData.utf8))) ?? []
        let metadata = ExerciseMetadataManager.shared
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -130, to: Date()) ?? .distantPast
        var excluded = Set<String>()
        for workout in workouts where workout.date >= recentCutoff {
            for exercise in workout.exercises {
                let name = resolver.aggregateName(for: exercise.name)
                if ExerciseLoad.isAssistedExercise(exercise.name)
                    || metadata.resolvedTags(for: exercise.name).contains(where: { $0.builtInGroup == .cardio }) {
                    excluded.insert(name)
                }
            }
        }
        let weightSeries = weight
        let rows = await Task.detached(priority: .utility) {
            BodyLiftAnalyzer.rows(
                workouts: workouts,
                resolver: resolver,
                excludedNames: excluded,
                favorites: favorites,
                weight: weightSeries,
                now: Date()
            )
        }.value
        guard !Task.isCancelled else { return }
        liftRows = rows
    }
}
