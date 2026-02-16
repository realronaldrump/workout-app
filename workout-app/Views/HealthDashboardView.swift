import SwiftUI
import Charts

// swiftlint:disable file_length

struct HealthDashboardView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var dataManager: WorkoutDataManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedRange: HealthTimeRange = .fourWeeks
    @State private var selectedCategory: HealthCategory = .all
    @State private var selectedDetailKind: HealthMetricKind?
    @State private var selectedWorkout: Workout?
    @State private var showingWorkoutsInRange = false
    @State private var showingCustomRange = false
    @State private var customRange: DateInterval = {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        return DateInterval(start: start, end: end)
    }()

    private var allHealthData: [WorkoutHealthData] {
        healthManager.healthDataStore.values.sorted { $0.workoutDate > $1.workoutDate }
    }

    private var allWorkouts: [Workout] {
        dataManager.workouts
    }

    private var workoutStore: [UUID: Workout] {
        Dictionary(uniqueKeysWithValues: allWorkouts.map { ($0.id, $0) })
    }

    private var earliestDate: Date? {
        let workoutDates = allWorkouts.map { $0.date }
        let healthDates = allHealthData.map { $0.workoutDate }
        return (workoutDates + healthDates).min()
    }

    private var currentRange: DateInterval {
        selectedRange.interval(reference: Date(), earliest: earliestDate, custom: customRange)
    }

    private var previousRange: DateInterval? {
        guard selectedRange != .all else { return nil }
        let duration = currentRange.duration
        let end = currentRange.start
        let start = end.addingTimeInterval(-duration)
        return DateInterval(start: start, end: end)
    }

    private var currentHealthData: [WorkoutHealthData] {
        allHealthData.filter { currentRange.contains($0.workoutDate) }
    }

    private var previousHealthData: [WorkoutHealthData] {
        guard let previousRange else { return [] }
        return allHealthData.filter { previousRange.contains($0.workoutDate) }
    }

    private var currentWorkouts: [Workout] {
        allWorkouts.filter { currentRange.contains($0.date) }
    }

    private var previousWorkouts: [Workout] {
        guard let previousRange else { return [] }
        return allWorkouts.filter { previousRange.contains($0.date) }
    }

    private var rangeLabel: String {
        formatRange(currentRange)
    }

    private var headerSubtitle: String {
        let workoutCount = currentWorkouts.count
        let healthCount = currentHealthData.count
        return "\(rangeLabel) • \(workoutCount) workouts • \(healthCount) health entries"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                        headerSection

                        timeRangeSection

                        categorySection

                        if healthManager.healthDataStore.isEmpty {
                            emptyState
                        } else if currentHealthData.isEmpty {
                            rangeEmptyState
                        } else {
                            highlightsSection

                            quickStatsSection

                            trendsSection

                            if selectedCategory == .all || selectedCategory == .sessions {
                                recentSessionsSection
                            }
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xxl)
                    .padding(.horizontal, Theme.Spacing.lg)
                }
            }
            .navigationTitle("Health Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    AppPillButton(title: "Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(item: $selectedDetailKind) { kind in
                if let detail = detailFor(kind) {
                    HealthMetricDetailScreen(detail: detail, rangeLabel: rangeLabel)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text(kind.title)
                            .font(Theme.Typography.title2)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("Not enough data in this range yet.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationDestination(item: $selectedWorkout) { workout in
                WorkoutDetailView(workout: workout)
            }
            .navigationDestination(isPresented: $showingWorkoutsInRange) {
                WorkoutsInRangeView(workouts: currentWorkouts, rangeLabel: rangeLabel)
            }
            .sheet(isPresented: $showingCustomRange) {
                CustomRangeSheet(range: $customRange) {
                    selectedRange = .custom
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Health Insights")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.5)

            Text(headerSubtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var timeRangeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Time Range")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(HealthTimeRange.allCases) { range in
                        Button {
                            if range == .custom {
                                showingCustomRange = true
                            } else {
                                selectedRange = range
                            }
                        } label: {
                            Text(range.title)
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(selectedRange == range ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.lg)
                                .padding(.vertical, Theme.Spacing.sm)
                                .frame(minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                        .fill(selectedRange == range ? Theme.Colors.elevated : Theme.Colors.surface)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Focus")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(HealthCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: category.icon)
                                    .font(.caption)
                                Text(category.title)
                                    .font(Theme.Typography.subheadline)
                            }
                            .foregroundStyle(selectedCategory == category ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                    .fill(selectedCategory == category ? Theme.Colors.elevated : Theme.Colors.surface)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var highlightsSection: some View {
        let cards = highlightCards.filter { selectedCategory == .all || $0.category == selectedCategory }
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if !cards.isEmpty {
                Text("Highlights")
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.md) {
                        ForEach(cards) { card in
                            MetricTileButton(
                                action: {
                                    handleHighlightTap(card)
                                },
                                content: {
                                    HighlightCard(model: card)
                                }
                            )
                            .frame(width: 240)
                        }
                    }
                }
            }
        }
    }

    private var quickStatsSection: some View {
        let cards = summaryCards.filter { selectedCategory == .all || $0.category == selectedCategory }
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Quick Stats")
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if selectedRange != .all {
                    Text("vs previous")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.Spacing.md)], spacing: Theme.Spacing.md) {
                ForEach(cards) { card in
                    MetricTileButton(
                        chevronPlacement: .bottomTrailing,
                        action: {
                            handleQuickStatTap(card)
                        },
                        content: {
                            MetricSummaryCard(model: card)
                        }
                    )
                }
            }
        }
    }

    private var trendsSection: some View {
        let allKinds: [HealthMetricKind] = [.heartRate, .sleep, .activity, .cardio, .body]
        let filteredKinds = allKinds.filter { selectedCategory == .all || $0.category == selectedCategory }
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Trends")
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(filteredKinds, id: \.id) { kind in
                    trendCard(kind: kind)
                }
            }
        }
    }

    @ViewBuilder
    private func trendCard(kind: HealthMetricKind) -> some View {
        let detail = detailFor(kind)
        if let detail, let summary = trendSummary(for: detail) {
            TrendCard(
                title: detail.kind.title,
                value: summary.primary,
                summary: summary.secondary,
                points: summary.points,
                color: detail.kind.tint
            ) {
                selectedDetailKind = kind
            }
        } else {
            EmptyMetricCard(
                title: kind.title,
                message: "Not enough data in this range yet."
            )
        }
    }

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Recent Workout Health")
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)

            if currentHealthData.isEmpty {
                EmptyMetricCard(
                    title: "No workout health in this range",
                    message: "Try a longer range or sync new workouts."
                )
            } else {
                ForEach(Array(currentHealthData.prefix(5)), id: \.workoutId) { data in
                    if let workout = workoutStore[data.workoutId] {
                        MetricTileButton(
                            action: {
                                selectedWorkout = workout
                            },
                            content: {
                                WorkoutHealthCard(
                                    healthData: data,
                                    workout: workout
                                )
                            }
                        )
                    } else {
                        WorkoutHealthCard(
                            healthData: data,
                            workout: nil
                        )
                    }
                }
            }
        }
    }

    private func handleHighlightTap(_ card: HighlightCardModel) {
        switch card.category {
        case .sleep:
            selectedDetailKind = .sleep
        case .activity:
            selectedDetailKind = .activity
        case .heart:
            selectedDetailKind = .heartRate
        case .cardio:
            selectedDetailKind = .cardio
        case .body:
            selectedDetailKind = .body
        case .sessions:
            showingWorkoutsInRange = true
        case .all:
            break
        }
    }

    private func handleQuickStatTap(_ card: MetricSummaryModel) {
        switch card.category {
        case .sessions:
            showingWorkoutsInRange = true
        case .heart:
            selectedDetailKind = .heartRate
        case .sleep:
            selectedDetailKind = .sleep
        case .activity:
            selectedDetailKind = .activity
        case .cardio:
            selectedDetailKind = .cardio
        case .body:
            selectedDetailKind = .body
        case .all:
            break
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 52))
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.top, Theme.Spacing.xl)

            Text("No health data yet")
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Connect Apple Health to see sleep, cardio, activity, heart rate, and body trends.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    private var rangeEmptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("No data in this range")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Try a longer range or adjust the custom dates.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    // MARK: - Models

    private var highlightCards: [HighlightCardModel] {
        let avgWorkoutHR = average(currentHealthData.compactMap { $0.avgHeartRate })
        let avgSleep = average(currentHealthData.compactMap { $0.sleepSummary?.totalHours })
        let avgEnergy = average(currentHealthData.compactMap { $0.dailyActiveEnergy })

        return [
            HighlightCardModel(
                title: "Avg Workout HR",
                value: avgWorkoutHR.map { "\(Int($0)) bpm" } ?? "--",
                subtitle: "Average workout heart rate in this range",
                icon: "heart.fill",
                tint: Theme.Colors.error,
                category: .heart
            ),
            HighlightCardModel(
                title: "Avg Sleep",
                value: avgSleep.map { String(format: "%.1fh", $0) } ?? "--",
                subtitle: "Average sleep duration in this range",
                icon: "moon.zzz.fill",
                tint: Theme.Colors.accentSecondary,
                category: .sleep
            ),
            HighlightCardModel(
                title: "Daily Energy",
                value: avgEnergy.map { "\(Int($0)) cal" } ?? "--",
                subtitle: "Average active energy in this range",
                icon: "flame.fill",
                tint: Theme.Colors.warning,
                category: .activity
            )
        ]
    }

    private var summaryCards: [MetricSummaryModel] {
        let workoutCount = currentWorkouts.count
        let previousWorkoutCount = previousRange == nil ? nil : Double(previousWorkouts.count)

        let avgHR = average(currentHealthData.compactMap { $0.avgHeartRate })
        let prevAvgHR = average(previousHealthData.compactMap { $0.avgHeartRate })

        let calories = currentHealthData.compactMap { $0.activeCalories }.reduce(0, +)
        let prevCalories = previousRange == nil ? nil : previousHealthData.compactMap { $0.activeCalories }.reduce(0, +)

        let peakHR = currentHealthData.compactMap { $0.maxHeartRate }.max()
        let prevPeakHR = previousHealthData.compactMap { $0.maxHeartRate }.max()

        return [
            MetricSummaryModel(
                title: "Workouts",
                value: "\(workoutCount)",
                subtitle: "Sessions in range",
                icon: "figure.run",
                tint: Theme.Colors.success,
                delta: deltaText(current: Double(workoutCount), previous: previousWorkoutCount),
                category: .sessions
            ),
            MetricSummaryModel(
                title: "Avg Workout HR",
                value: avgHR.map { "\(Int($0)) bpm" } ?? "--",
                subtitle: "Average heart rate during workouts",
                icon: "heart.fill",
                tint: Theme.Colors.error,
                delta: deltaText(current: avgHR, previous: prevAvgHR, lowerIsBetter: true),
                category: .heart
            ),
            MetricSummaryModel(
                title: "Calories Burned",
                value: calories > 0 ? "\(formatNumber(calories)) cal" : "--",
                subtitle: "Active calories from workouts",
                icon: "flame.fill",
                tint: Theme.Colors.warning,
                delta: deltaText(current: calories, previous: prevCalories),
                category: .activity
            ),
            MetricSummaryModel(
                title: "Peak HR",
                value: peakHR.map { "\(Int($0)) bpm" } ?? "--",
                subtitle: "Highest workout heart rate",
                icon: "bolt.heart.fill",
                tint: Theme.Colors.accentSecondary,
                delta: deltaText(current: peakHR, previous: prevPeakHR, lowerIsBetter: true),
                category: .heart
            )
        ]
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func detailFor(_ kind: HealthMetricKind) -> HealthMetricDetail? {
        switch kind {
        case .heartRate:
            let avgPoints = makePoints(currentHealthData, value: { $0.avgHeartRate }, label: "Avg HR")
            let maxPoints = makePoints(currentHealthData, value: { $0.maxHeartRate }, label: "Max HR")
            let previousAvgPoints = makePoints(previousHealthData, value: { $0.avgHeartRate }, label: "Avg HR")
            let previousMaxPoints = makePoints(previousHealthData, value: { $0.maxHeartRate }, label: "Max HR")

            guard !avgPoints.isEmpty || !maxPoints.isEmpty else { return nil }

            return HealthMetricDetail(
                kind: kind,
                summary: "Avg and peak heart rate across workouts.",
                explanation: "Each point is taken from the workout's synced heart rate summary (average and max).",
                series: [
                    HealthMetricSeries(label: "Avg HR", unit: "bpm", color: .red, points: avgPoints),
                    HealthMetricSeries(label: "Max HR", unit: "bpm", color: .pink.opacity(0.7), points: maxPoints)
                ],
                comparisonSeries: [
                    HealthMetricSeries(label: "Avg HR", unit: "bpm", color: .red, points: previousAvgPoints),
                    HealthMetricSeries(label: "Max HR", unit: "bpm", color: .pink.opacity(0.7), points: previousMaxPoints)
                ]
            )
        case .sleep:
            let sleepPoints = makePoints(currentHealthData, value: { $0.sleepSummary?.totalHours }, label: "Sleep")
            let previousSleepPoints = makePoints(previousHealthData, value: { $0.sleepSummary?.totalHours }, label: "Sleep")
            guard !sleepPoints.isEmpty else { return nil }

            return HealthMetricDetail(
                kind: kind,
                summary: "Total sleep hours leading into workouts.",
                explanation: "Sleep points reflect total sleep time captured in Apple Health leading into workout days.",
                series: [
                    HealthMetricSeries(label: "Sleep", unit: "h", color: Theme.Colors.accentSecondary, points: sleepPoints)
                ],
                comparisonSeries: [
                    HealthMetricSeries(
                        label: "Sleep",
                        unit: "h",
                        color: Theme.Colors.accentSecondary,
                        points: previousSleepPoints
                    )
                ]
            )
        case .activity:
            let energyPoints = makePoints(currentHealthData, value: { $0.dailyActiveEnergy }, label: "Active Energy")
            let ratioPoints = makePoints(currentHealthData, value: { data in
                guard let energy = data.dailyActiveEnergy else { return nil }
                guard let workout = currentWorkouts.first(where: { $0.id == data.workoutId }) else { return nil }
                return workout.totalVolume / max(energy, 1)
            }, label: "Load Ratio")
            let previousEnergyPoints = makePoints(previousHealthData, value: { $0.dailyActiveEnergy }, label: "Active Energy")
            let previousRatioPoints = makePoints(previousHealthData, value: { data in
                guard let energy = data.dailyActiveEnergy else { return nil }
                guard let workout = previousWorkouts.first(where: { $0.id == data.workoutId }) else { return nil }
                return workout.totalVolume / max(energy, 1)
            }, label: "Load Ratio")

            guard !energyPoints.isEmpty || !ratioPoints.isEmpty else { return nil }

            return HealthMetricDetail(
                kind: kind,
                summary: "Daily energy vs training output.",
                explanation: "Load Ratio is workout volume divided by daily active energy to normalize output across days.",
                series: [
                    HealthMetricSeries(label: "Active Energy", unit: "cal", color: .orange, points: energyPoints),
                    HealthMetricSeries(label: "Load Ratio", unit: "ratio", color: Theme.Colors.accent, points: ratioPoints)
                ],
                comparisonSeries: [
                    HealthMetricSeries(label: "Active Energy", unit: "cal", color: .orange, points: previousEnergyPoints),
                    HealthMetricSeries(label: "Load Ratio", unit: "ratio", color: Theme.Colors.accent, points: previousRatioPoints)
                ]
            )
        case .cardio:
            let vo2Points = makePoints(currentHealthData, value: { $0.vo2Max }, label: "VO2 Max")
            let recoveryPoints = makePoints(currentHealthData, value: { $0.heartRateRecovery }, label: "HR Recovery")
            let walkingPoints = makePoints(currentHealthData, value: { $0.walkingHeartRateAverage }, label: "Walking HR")
            let previousVO2Points = makePoints(previousHealthData, value: { $0.vo2Max }, label: "VO2 Max")
            let previousRecoveryPoints = makePoints(previousHealthData, value: { $0.heartRateRecovery }, label: "HR Recovery")
            let previousWalkingPoints = makePoints(previousHealthData, value: { $0.walkingHeartRateAverage }, label: "Walking HR")

            guard !vo2Points.isEmpty || !recoveryPoints.isEmpty || !walkingPoints.isEmpty else { return nil }

            return HealthMetricDetail(
                kind: kind,
                summary: "Cardio-related metrics from Apple Health near workout days.",
                explanation: "VO2 Max, heart rate recovery, and walking heart rate are commonly used to track aerobic trends.",
                series: [
                    HealthMetricSeries(label: "VO2 Max", unit: "ml/kg/min", color: Theme.Colors.success, points: vo2Points),
                    HealthMetricSeries(label: "HR Recovery", unit: "bpm", color: Theme.Colors.accentSecondary, points: recoveryPoints),
                    HealthMetricSeries(label: "Walking HR", unit: "bpm", color: Theme.Colors.warning, points: walkingPoints)
                ],
                comparisonSeries: [
                    HealthMetricSeries(
                        label: "VO2 Max",
                        unit: "ml/kg/min",
                        color: Theme.Colors.success,
                        points: previousVO2Points
                    ),
                    HealthMetricSeries(
                        label: "HR Recovery",
                        unit: "bpm",
                        color: Theme.Colors.accentSecondary,
                        points: previousRecoveryPoints
                    ),
                    HealthMetricSeries(
                        label: "Walking HR",
                        unit: "bpm",
                        color: Theme.Colors.warning,
                        points: previousWalkingPoints
                    )
                ]
            )
        case .body:
            let weightPoints = makePoints(currentHealthData, value: { data in
                guard let mass = data.bodyMass else { return nil }
                return mass * 2.20462
            }, label: "Weight")
            let bodyFatPoints = makePoints(currentHealthData, value: { data in
                guard let percent = data.bodyFatPercentage else { return nil }
                return percent * 100
            }, label: "Body Fat")
            let previousWeightPoints = makePoints(previousHealthData, value: { data in
                guard let mass = data.bodyMass else { return nil }
                return mass * 2.20462
            }, label: "Weight")
            let previousBodyFatPoints = makePoints(previousHealthData, value: { data in
                guard let percent = data.bodyFatPercentage else { return nil }
                return percent * 100
            }, label: "Body Fat")

            guard !weightPoints.isEmpty || !bodyFatPoints.isEmpty else { return nil }

            return HealthMetricDetail(
                kind: kind,
                summary: "Body composition trends near workout days.",
                explanation: "Weight and body fat points come from Apple Health samples near workout days and can vary with measurement timing.",
                series: [
                    HealthMetricSeries(label: "Weight", unit: "lb", color: Theme.Colors.accent, points: weightPoints),
                    HealthMetricSeries(label: "Body Fat", unit: "%", color: Theme.Colors.warning, points: bodyFatPoints)
                ],
                comparisonSeries: [
                    HealthMetricSeries(label: "Weight", unit: "lb", color: Theme.Colors.accent, points: previousWeightPoints),
                    HealthMetricSeries(label: "Body Fat", unit: "%", color: Theme.Colors.warning, points: previousBodyFatPoints)
                ]
            )
        }
    }

    private struct TrendSummarySnapshot {
        let primary: String
        let secondary: String
        let points: [HealthTrendPoint]
    }

    private func trendSummary(for detail: HealthMetricDetail) -> TrendSummarySnapshot? {
        guard let primarySeries = detail.series.first(where: { !$0.points.isEmpty }) else { return nil }
        let latest = primarySeries.points.max(by: { $0.date < $1.date })
        let average = average(primarySeries.points.map { $0.value })
        let primaryValue = latest.map { formatValue($0.value, unit: primarySeries.unit) } ?? "--"
        let secondaryValue = average.map { "Avg \(formatValue($0, unit: primarySeries.unit))" } ?? "No average"
        return TrendSummarySnapshot(primary: primaryValue, secondary: secondaryValue, points: primarySeries.points)
    }

    // MARK: - Helpers

    private func makePoints(_ data: [WorkoutHealthData], value: (WorkoutHealthData) -> Double?, label: String) -> [HealthTrendPoint] {
        data.compactMap { item in
            guard let value = value(item) else { return nil }
            return HealthTrendPoint(date: item.workoutDate, value: value, label: label)
        }
        .sorted { $0.date < $1.date }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func formatNumber(_ num: Double) -> String {
        if num > 10000 {
            return String(format: "%.1fk", num / 1000)
        }
        return "\(Int(num))"
    }

    private func deltaText(current: Double?, previous: Double?, lowerIsBetter: Bool = false) -> MetricDelta? {
        guard let current, let previous else { return nil }
        let diff = current - previous
        if abs(diff) < 0.01 { return nil }
        let isPositive = diff > 0
        let isGood = lowerIsBetter ? !isPositive : isPositive
        return MetricDelta(
            text: String(format: "%+.0f", diff),
            isPositive: isPositive,
            isGood: isGood
        )
    }

    private func formatRange(_ interval: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let start = formatter.string(from: interval.start)
        let end = formatter.string(from: interval.end)
        return "\(start) – \(end)"
    }

    private func formatValue(_ value: Double, unit: String) -> String {
        switch unit {
        case "bpm":
            return "\(Int(value)) bpm"
        case "cal":
            return "\(Int(value)) cal"
        case "h":
            return String(format: "%.1fh", value)
        case "ratio":
            return String(format: "%.2f", value)
        case "ml/kg/min":
            return String(format: "%.1f ml/kg/min", value)
        case "lb":
            return String(format: "%.1f lb", value)
        case "%":
            return String(format: "%.1f%%", value)
        default:
            return String(format: "%.1f", value)
        }
    }
}

// MARK: - Supporting Models

enum HealthCategory: String, CaseIterable, Identifiable {
    case all
    case heart
    case sleep
    case activity
    case cardio
    case body
    case sessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .heart: return "Heart"
        case .sleep: return "Sleep"
        case .activity: return "Activity"
        case .cardio: return "Cardio"
        case .body: return "Body"
        case .sessions: return "Sessions"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .heart: return "heart.fill"
        case .sleep: return "moon.zzz.fill"
        case .activity: return "flame.fill"
        case .cardio: return "figure.run"
        case .body: return "figure.arms.open"
        case .sessions: return "clock.arrow.2.circlepath"
        }
    }
}

enum HealthMetricKind: String, Identifiable, Hashable {
    case heartRate
    case sleep
    case activity
    case cardio
    case body

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heartRate: return "Heart Rate Trends"
        case .sleep: return "Sleep"
        case .activity: return "Activity vs Training"
        case .cardio: return "Cardio Progress"
        case .body: return "Body Composition"
        }
    }

    var tint: Color {
        switch self {
        case .heartRate: return .red
        case .sleep: return Theme.Colors.accentSecondary
        case .activity: return .orange
        case .cardio: return Theme.Colors.success
        case .body: return Theme.Colors.accent
        }
    }

    var category: HealthCategory {
        switch self {
        case .heartRate: return .heart
        case .sleep: return .sleep
        case .activity: return .activity
        case .cardio: return .cardio
        case .body: return .body
        }
    }
}

struct HealthMetricSeries: Identifiable {
    let id = UUID()
    let label: String
    let unit: String
    let color: Color
    let points: [HealthTrendPoint]
}

struct HealthMetricDetail: Identifiable {
    let id = UUID()
    let kind: HealthMetricKind
    let summary: String
    let explanation: String
    let series: [HealthMetricSeries]
    let comparisonSeries: [HealthMetricSeries]
}

struct HighlightCardModel: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color
    let category: HealthCategory
}

struct MetricDelta {
    let text: String
    let isPositive: Bool
    let isGood: Bool
}

struct MetricSummaryModel: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color
    let delta: MetricDelta?
    let category: HealthCategory
}

// MARK: - Components

private struct HighlightCard: View {
    let model: HighlightCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: model.icon)
                    .foregroundStyle(model.tint)
                Spacer()
            }

            Text(model.value)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(model.title)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text(model.subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(2)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}

private struct MetricSummaryCard: View {
    let model: MetricSummaryModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: model.icon)
                    .foregroundStyle(model.tint)
                Spacer()
                if let delta = model.delta {
                    HStack(spacing: 4) {
                        Image(systemName: delta.isPositive ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                        Text(delta.text)
                            .font(Theme.Typography.caption)
                    }
                    .foregroundStyle(delta.isGood ? Theme.Colors.success : Theme.Colors.error)
                }
            }

            Text(model.value)
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(model.title)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text(model.subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(2)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}

private struct TrendCard: View {
    let title: String
    let value: String
    let summary: String
    let points: [HealthTrendPoint]
    let color: Color
    let onTap: () -> Void

    private var sortedPoints: [HealthTrendPoint] {
        points.sorted { $0.date < $1.date }
    }

    private var startPoint: HealthTrendPoint? {
        sortedPoints.first
    }

    private var endPoint: HealthTrendPoint? {
        sortedPoints.last
    }

    private var minValue: Double? {
        points.map(\.value).min()
    }

    private var maxValue: Double? {
        points.map(\.value).max()
    }

    private var dateContext: String {
        guard let start = startPoint?.date, let end = endPoint?.date else { return "No dates" }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    private var valueContext: String {
        guard let minValue, let maxValue else { return "No values" }
        return "Low \(formatCompact(minValue))  High \(formatCompact(maxValue))"
    }

    private var accessibilityTrendSummary: String {
        guard let start = startPoint, let end = endPoint else { return "No trend data" }
        let startDateText = start.date.formatted(date: .abbreviated, time: .omitted)
        let endDateText = end.date.formatted(date: .abbreviated, time: .omitted)
        return "From \(formatCompact(start.value)) on \(startDateText) to \(formatCompact(end.value)) on \(endDateText). \(valueContext)"
    }

    var body: some View {
        MetricTileButton(chevronPlacement: .bottomTrailing, action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(summary)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Spacer()
                    Text(value)
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .frame(height: 70)
                .accessibilityLabel(Text("\(title) trend"))
                .accessibilityValue(Text(accessibilityTrendSummary))

                HStack {
                    Text(dateContext)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Spacer()
                    Text(valueContext)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
        }
    }

    private func formatCompact(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        if absValue >= 100 {
            return String(format: "%.0f", value)
        }
        if absValue >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }
}

private struct EmptyMetricCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

private struct CustomRangeSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var range: DateInterval
    let onApply: () -> Void

    @State private var startDate: Date
    @State private var endDate: Date

    init(range: Binding<DateInterval>, onApply: @escaping () -> Void) {
        _range = range
        self.onApply = onApply
        _startDate = State(initialValue: range.wrappedValue.start)
        _endDate = State(initialValue: range.wrappedValue.end)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    DatePicker(
                        "Start",
                        selection: $startDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)

                    DatePicker(
                        "End",
                        selection: $endDate,
                        in: startDate...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)

                    Button {
                        let calendar = Calendar.current
                        let start = calendar.startOfDay(for: startDate)
                        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
                        range = DateInterval(start: start, end: end)
                        onApply()
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

                    Spacer()
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

private struct HealthMetricDetailScreen: View {
    let detail: HealthMetricDetail
    let rangeLabel: String

    @State private var selectedSeriesLabel: String

    init(detail: HealthMetricDetail, rangeLabel: String) {
        self.detail = detail
        self.rangeLabel = rangeLabel
        _selectedSeriesLabel = State(initialValue: detail.series.first?.label ?? "")
    }

    private var activeSeries: HealthMetricSeries? {
        detail.series.first(where: { $0.label == selectedSeriesLabel }) ?? detail.series.first
    }

    private var comparisonSeries: HealthMetricSeries? {
        detail.comparisonSeries.first(where: { $0.label == selectedSeriesLabel })
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    headerSection

                    if detail.series.count > 1 {
                        Picker("Series", selection: $selectedSeriesLabel) {
                            ForEach(detail.series) { series in
                                Text(series.label).tag(series.label)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if let series = activeSeries {
                        chartSection(for: series)
                        statsSection(for: series)
                        dataPointsSection(for: series)
                    } else {
                        EmptyMetricCard(title: "No data", message: "No points for this metric yet.")
                    }

                    explanationSection
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle(detail.kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(rangeLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)

            Text(detail.summary)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func chartSection(for series: HealthMetricSeries) -> some View {
        let points = series.points

        return InteractiveTimeSeriesChart(
            points: points,
            color: series.color,
            areaFill: false,
            height: 220,
            valueText: { formatValue($0, unit: series.unit) },
            dateText: { $0.formatted(date: .abbreviated, time: .omitted) }
        )
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

	    private func statsSection(for series: HealthMetricSeries) -> some View {
	        let points = series.points
	        let values = points.map { $0.value }
	        let avg = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
	        let minValue = values.min()
	        let maxValue = values.max()
	        let minPoint = minValue.flatMap { min in
	            points
	                .filter { $0.value == min }
	                .max(by: { $0.date < $1.date })
	        }
	        let maxPoint = maxValue.flatMap { max in
	            points
	                .filter { $0.value == max }
	                .max(by: { $0.date < $1.date })
	        }
	        let change = comparisonDelta(currentSeries: series, comparisonSeries: comparisonSeries)
	        let includeDayForExtremes = series.unit == "lb"

	        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
	            Text("Summary")
	                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

	            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
	                MetricStatCard(title: "Average", value: avg.map { formatValue($0, unit: series.unit) } ?? "--")
	                MetricStatCard(
	                    title: "Min",
	                    value: minValue.map { formatValue($0, unit: series.unit) } ?? "--",
	                    subtitle: includeDayForExtremes ? minPoint.map { formatDay($0.date) } : nil
	                )
	                MetricStatCard(
	                    title: "Max",
	                    value: maxValue.map { formatValue($0, unit: series.unit) } ?? "--",
	                    subtitle: includeDayForExtremes ? maxPoint.map { formatDay($0.date) } : nil
	                )
	                MetricStatCard(title: "Change", value: change ?? "--")
	            }
	        }
	    }

    private func dataPointsSection(for series: HealthMetricSeries) -> some View {
        let points = series.points.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Data Points")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(points) { point in
                HStack {
                    Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(formatValue(point.value, unit: series.unit))
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .padding(Theme.Spacing.md)
                .softCard(elevation: 1)
            }
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("What this means")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(detail.explanation)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func formatValue(_ value: Double, unit: String) -> String {
        switch unit {
        case "bpm":
            return "\(Int(value)) bpm"
        case "cal":
            return "\(Int(value)) cal"
        case "h":
            return String(format: "%.1fh", value)
        case "ratio":
            return String(format: "%.2f", value)
        case "ml/kg/min":
            return String(format: "%.1f ml/kg/min", value)
        case "lb":
            return String(format: "%.1f lb", value)
        case "%":
            return String(format: "%.1f%%", value)
        default:
            return String(format: "%.1f", value)
        }
    }

    private func formatDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func comparisonDelta(currentSeries: HealthMetricSeries, comparisonSeries: HealthMetricSeries?) -> String? {
        guard let comparisonSeries else { return nil }
        let currentAvg = currentSeries.points.map { $0.value }
        let previousAvg = comparisonSeries.points.map { $0.value }
        guard !currentAvg.isEmpty, !previousAvg.isEmpty else { return nil }
        let currentValue = currentAvg.reduce(0, +) / Double(currentAvg.count)
        let previousValue = previousAvg.reduce(0, +) / Double(previousAvg.count)
        let diff = currentValue - previousValue
        if abs(diff) < 0.01 { return "No change" }
        let sign = diff >= 0 ? "+" : ""
        return "\(sign)\(formatValue(abs(diff), unit: currentSeries.unit))"
    }
	}

	private struct MetricStatCard: View {
	    let title: String
	    let value: String
	    let subtitle: String?

	    init(title: String, value: String, subtitle: String? = nil) {
	        self.title = title
	        self.value = value
	        self.subtitle = subtitle
	    }

	    var body: some View {
	        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
	            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
	                Text(title)
	                    .font(Theme.Typography.caption)
	                    .foregroundStyle(Theme.Colors.textTertiary)

	                Spacer(minLength: 0)

	                if let subtitle {
	                    Text(subtitle)
	                        .font(Theme.Typography.caption)
	                        .foregroundStyle(Theme.Colors.textSecondary)
	                        .lineLimit(1)
	                        .minimumScaleFactor(0.75)
	                }
	            }
	            Text(value)
	                .font(Theme.Typography.headline)
	                .foregroundStyle(Theme.Colors.textPrimary)
	        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

private struct WorkoutHealthCard: View {
    let healthData: WorkoutHealthData
    let workout: Workout?

    var body: some View {
        let date = healthData.workoutDate
        let dateText = "\(date.formatted(date: .abbreviated, time: .omitted)) • \(date.formatted(date: .omitted, time: .shortened))"

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let workout {
                        Text(workout.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(dateText)
                        .font(workout == nil ? Theme.Typography.headline : Theme.Typography.subheadline)
                        .foregroundStyle(workout == nil ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: Theme.Spacing.lg) {
                if let avgHR = healthData.avgHeartRate {
                    metricPill(icon: "heart.fill", value: "\(Int(avgHR))", unit: "bpm", color: .red)
                }

                if let cals = healthData.activeCalories {
                    metricPill(icon: "flame.fill", value: "\(Int(cals))", unit: "cal", color: .orange)
                }

                if let maxHR = healthData.maxHeartRate {
                    metricPill(icon: "bolt.heart", value: "\(Int(maxHR))", unit: "max", color: .pink)
                }

                Spacer()
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func metricPill(icon: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(Theme.Typography.subheadline)
                .bold()
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(unit)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}
