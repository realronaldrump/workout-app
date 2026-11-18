import SwiftUI
import UIKit

/// A quick check-in with a separate Progress screen for the longer history.
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
    @AppStorage(BodyComparisonStartDate.key) private var savedStart = ""
    @AppStorage("bodyGoalWeightLb") private var goalWeight: Double = 0
    @AppStorage("bodyGoalStartWeightLb") private var goalStartWeight: Double = 0
    @AppStorage("bodyGoalStartDate") private var goalStartDate: Double = 0
    @AppStorage("bodyGoalReachedDate") private var goalReachedDate: Double = 0
    @AppStorage("favoriteExercises") private var favoriteExercisesData = "[]"

    @State private var showingProgress = false
    @State private var rangeOverride: BodyChartRange?
    @State private var weightSelection: BodyTrendDay?
    @State private var fatSelection: BodyTrendDay?
    @State private var showingGoal = false
    @State private var showingMethod = false
    @State private var showingLog = false
    @State private var weighInRequest: BodyWeighInRequest?
    @State private var detailDay: BodyTrendDay?
    @State private var selectedExercise: ExerciseSelection?
    @State private var liftRows: [BodyLiftRow] = []
    @State private var isRequestingAuthorization = false
    @State private var authorizationError: String?

    private var weight: BodySeries { store.weight }
    private var bodyFat: BodySeries { store.bodyFat }
    private var comparisonStart: Date? { BodyComparisonStartDate.decode(savedStart, calendar: weight.calendar) }
    private var range: BodyChartRange {
        if let rangeOverride { return rangeOverride }
        if comparisonStart != nil { return .sinceStart }
        let saved = BodyChartRange(rawValue: rangeRaw) ?? .threeMonths
        return saved == .sinceStart ? .threeMonths : saved
    }

    var body: some View {
        let now = Date()
        let rate = weight.displayTrend(asOf: now)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                overviewHeadline(now: now, rate: rate)
                if let latest = weight.readings.last {
                    latestWeighIn(latest, now: now)
                }
                overviewChart(now: now, rate: rate)

                Button {
                    selectRange(nil)
                    showingProgress = true
                } label: {
                    Text("Progress")
                        .font(Theme.Typography.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                }
                .buttonStyle(BrandSecondaryButtonStyle())
                .accessibilityIdentifier("body-open-progress")

                if let message = store.logErrorMessage ?? authorizationError {
                    Text(message)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                healthConnection
            }
            .padding(.horizontal, Theme.Layout.screenGutter)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xxl)
            .contentColumn()
        }
        .background(AdaptiveBackground())
        .refreshable { await store.reload(from: healthManager) }
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(isTabRoot ? .large : .inline)
        .accessibilityIdentifier("body-composition")
        .navigationDestination(isPresented: $showingProgress) { progressScreen }
        .toolbar {
            AppToolbarItem(placement: .topBarTrailing) {
                AppToolbarIconButton(systemImage: "plus", accessibilityLabel: "Log weight", variant: .subtle) {
                    weighInRequest = .new
                }
                .accessibilityIdentifier("body-log-weight")
            }
        }
        .sheet(item: $weighInRequest) { request in
            BodyWeighInEditor(request: request)
        }
        .task { refreshIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshIfNeeded(maxAge: 60) }
        }
        .onChange(of: healthManager.authorizationStatus) { _, status in
            if status == .authorized { store.refresh(from: healthManager) }
        }
        .onChange(of: healthManager.dailyDataRevision) { _, _ in store.refresh(from: healthManager) }
        .onChange(of: savedStart) { _, _ in selectRange(nil) }
        .onChange(of: store.snapshot.revision, initial: true) { _, _ in
            recordGoalReachedIfNeeded()
        }
    }

    private func overviewHeadline(now: Date, rate: BodyRate?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(overviewTitle(now: now, rate: rate))
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let rate, let last = weight.latest {
                Text(BodyFormat.trendPeriod(days: rate.windowDays, through: last.day, now: now, calendar: weight.calendar))
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if let error = store.errorMessage, weight.isEmpty {
                Text(error)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("body-latest-measurement")
    }

    private func overviewTitle(now: Date, rate: BodyRate?) -> String {
        if let rate {
            if rate.isSteady {
                return abs(rate.change) < 0.5 ? "Weight looks about the same" : "No clear weight change"
            }
            let rounded = (abs(rate.change) * 2).rounded() / 2
            let amount = rounded.formatted(.number.precision(.fractionLength(0...1)))
            return "\(rate.change < 0 ? "Down" : "Up") about \(amount) lb"
        }
        guard let latest = weight.latest else {
            return store.isLoading ? "Getting your weigh-ins…" : "Log your first weigh-in"
        }
        return weight.dayIndex(for: now) - latest.dayIndex > 7
            ? "Ready for a new weigh-in"
            : "More weigh-ins will show a trend"
    }

    private func latestWeighIn(_ reading: BodyRawSample, now: Date) -> some View {
        Button {
            weighInRequest = .edit(reading)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last weigh-in")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(BodyFormat.weight(reading.value))
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(BodyFormat.whenWeighed(reading.timestamp, now: now, calendar: weight.calendar))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Text("Edit")
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("body-edit-latest-weigh-in")
    }

    @ViewBuilder
    private func overviewChart(now: Date, rate: BodyRate?) -> some View {
        let calendar = weight.calendar
        let today = calendar.startOfDay(for: now)
        let last = weight.latest?.day ?? today
        let end = rate == nil ? today : last
        let numberOfDays = rate?.windowDays ?? 28
        if let first = calendar.date(byAdding: .day, value: 1 - numberOfDays, to: end) {
            let domain = first...end
            let days = weight.gridDays(in: domain).filter(\.hasReading)
            if days.count > 1 {
                BodyRecentChart(days: days, domain: domain, rate: rate, calendar: calendar)
                    .padding(Theme.Spacing.sm)
                    .softCard()
            }
        }
    }

    private var progressScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if weight.isEmpty {
                    Text("Your progress will appear after your first weigh-in.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    page
                }
            }
            .padding(.horizontal, Theme.Layout.screenGutter)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xxl)
            .contentColumn()
        }
        .background(AdaptiveBackground())
        .refreshable { await store.reload(from: healthManager) }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !weight.isEmpty {
                AppToolbarItem(placement: .topBarTrailing) {
                    AppToolbarButton(title: "Weigh-ins", systemImage: "list.bullet", variant: .subtle) {
                        showingLog = true
                    }
                    .accessibilityIdentifier("body-weigh-in-history")
                }
            }
        }
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
            BodyReadingsLog()
        }
        .sheet(item: $detailDay) { day in
            NavigationStack {
                BodyDayDetail(date: day.day)
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
        .task(id: LiftRefreshKey(revision: dataManager.datasetRevision, bodyRevision: store.snapshot.revision, favorites: favoriteExercisesData)) {
            await refreshLifts()
        }
    }

    @ViewBuilder
    private var page: some View {
        let now = Date()
        let rate = weight.displayTrend(asOf: now)
        let goalStatus = goalStatus(rate: weight.rate(asOf: now), now: now)
        let interval = chartInterval(for: weight, now: now)
        let showsReadings = range.showsReadings(in: interval, calendar: weight.calendar)

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

        chartBlock(interval: interval, now: now, showsReadings: showsReadings)

        BodyChangeSection(
            series: weight,
            range: interval,
            chartRange: range,
            savedStart: $savedStart
        )

        BodyGoalSection(
            status: goalStatus,
            reachedDate: goalReachedDate > 0 ? Date(timeIntervalSince1970: goalReachedDate) : nil,
            onEdit: { showingGoal = true }
        )

        if !bodyFat.isEmpty {
            BodyCompositionSection(
                weight: weight,
                bodyFat: bodyFat,
                domain: chartDomain(range == .all ? chartInterval(for: bodyFat, now: now) : interval, now: now),
                showsReadings: showsReadings,
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

    private func chartBlock(interval: DateInterval, now: Date, showsReadings: Bool) -> some View {
        let readings = weight.gridDays(in: interval).filter(\.hasReading)
        let start = comparisonStart
        let options = BodyChartRange.allCases.filter { $0 != .sinceStart || start != nil }.map { option in
            let label = option == .sinceStart
                ? start.map { "Since \(BodyFormat.shortDate($0, calendar: weight.calendar))" } ?? option.title
                : option.title
            return (label: label, value: option)
        }
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            AppSegmentedPicker(
                title: "Date range",
                selection: Binding(get: { range }, set: { selectRange($0) }),
                options: options
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if readings.isEmpty {
                    Text("No weigh-ins in this range")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    BodyChartReadout(series: weight, selection: weightSelection, summary: chartSummary(readings))
                    BodyTrendChart(
                        series: weight,
                        domain: chartDomain(interval, now: now),
                        showsReadings: showsReadings,
                        goal: goalWeight > 0 ? goalWeight : nil,
                        workoutDays: workoutDays(in: interval),
                        tint: BodyFormat.weightTint,
                        selection: $weightSelection
                    )
                    .accessibilityIdentifier("body-weight-chart")
                    legend(showsReadings: showsReadings)
                }
            }
            .padding(Theme.Spacing.md)
            .softCard()
        }
    }

    private func chartSummary(_ readings: [BodyTrendDay]) -> String {
        let count = SharedFormatters.count(readings.count, "weigh-in")
        guard readings.count > 1, let first = readings.first, let last = readings.last else { return count }
        let change = last.trend - first.trend
        return "\(count), trend \(BodyFormat.signedWeight(change))"
    }

    private func legend(showsReadings: Bool) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            if showsReadings {
                legendKey("Scale") {
                    Circle().fill(Theme.Colors.textSecondary.opacity(0.55)).frame(width: 6, height: 6)
                }
            }
            legendKey("Trend") {
                Capsule().fill(BodyFormat.weightTint).frame(width: 14, height: 3)
            }
            if weight.residualSigma != nil {
                legendKey("Usual range") {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(BodyFormat.weightTint.opacity(0.18)).frame(width: 14, height: 9)
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

    @ViewBuilder
    private var healthConnection: some View {
        if healthManager.authorizationStatus == .denied {
            AppPillButton(title: "Apple Health settings", systemImage: "gear", variant: .subtle) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
        } else if healthManager.authorizationStatus == .notDetermined {
            AppPillButton(
                title: isRequestingAuthorization ? "Waiting for Apple Health…" : "Connect Apple Health",
                systemImage: "heart",
                variant: .subtle,
                action: requestAuthorization
            )
            .disabled(isRequestingAuthorization)
        }
    }

    // MARK: Ranges

    private func selectRange(_ selection: BodyChartRange?) {
        rangeOverride = selection
        if let selection, selection != .sinceStart {
            rangeRaw = selection.rawValue
        }
        weightSelection = nil
        fatSelection = nil
    }

    private func chartInterval(for series: BodySeries, now: Date) -> DateInterval {
        range.interval(reference: now, earliest: series.grid.first?.day, comparisonStart: comparisonStart, calendar: series.calendar)
    }

    /// End at today's tick, leaving a full day for a chart that starts today.
    private func chartDomain(_ interval: DateInterval, now: Date) -> ClosedRange<Date> {
        let today = weight.calendar.startOfDay(for: now)
        return interval.start...(interval.start < today ? today : interval.end)
    }

    private func workoutDays(in interval: DateInterval) -> [Date] {
        let calendar = weight.calendar
        var days = Set<Date>()
        for workout in dataManager.workouts {
            let day = calendar.startOfDay(for: workout.date)
            if interval.start <= day && day < interval.end {
                days.insert(day)
            }
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
        let bodyRevision: UInt64
        let favorites: String
    }

    private func refreshLifts() async {
        guard !weight.isEmpty else { return }
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
