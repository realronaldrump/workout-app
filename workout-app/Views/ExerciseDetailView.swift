import SwiftUI
import Charts

struct ExerciseDetailView: View {
    let exerciseName: String
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject var annotationsManager: WorkoutAnnotationsManager
    @ObservedObject var gymProfilesManager: GymProfilesManager
    @StateObject private var insightsEngine: InsightsEngine
    @State private var selectedChart = ChartType.weight
    @State private var selectedGymScope: GymScope = .all
    @State private var showingLocationPicker = false

    enum ChartType: String, CaseIterable {
        case weight = "Max Weight"
        case volume = "Volume"
        case oneRepMax = "1RM"
        case reps = "Reps"
    }

    enum GymScope: Hashable {
        case all
        case unassigned
        case gym(UUID)
    }

    init(
        exerciseName: String,
        dataManager: WorkoutDataManager,
        annotationsManager: WorkoutAnnotationsManager,
        gymProfilesManager: GymProfilesManager
    ) {
        self.exerciseName = exerciseName
        self.dataManager = dataManager
        self.annotationsManager = annotationsManager
        self.gymProfilesManager = gymProfilesManager
        _insightsEngine = StateObject(
            wrappedValue: InsightsEngine(
                dataManager: dataManager,
                annotationsProvider: { annotationsManager.annotations },
                gymNameProvider: { gymProfilesManager.gymNameSnapshot() }
            )
        )
    }

    private var scopedHistory: [(date: Date, sets: [WorkoutSet])] {
        var history: [(date: Date, sets: [WorkoutSet])] = []
        for workout in dataManager.workouts {
            guard let exercise = workout.exercises.first(where: { $0.name == exerciseName }) else { continue }
            let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
            let matches: Bool
            switch selectedGymScope {
            case .all:
                matches = true
            case .unassigned:
                matches = gymId == nil
            case .gym(let targetId):
                matches = gymId == targetId
            }
            if matches {
                history.append((date: workout.date, sets: exercise.sets))
            }
        }
        return history.sorted { $0.date < $1.date }
    }

    private var exerciseInsights: [Insight] {
        insightsEngine.insights.filter { $0.exerciseName == exerciseName }
    }

    private var locationLabel: String {
        switch selectedGymScope {
        case .all:
            return "All gyms"
        case .unassigned:
            return "Unassigned"
        case .gym(let id):
            return gymProfilesManager.gymName(for: id) ?? "Deleted gym"
        }
    }

    private var isDeletedScope: Bool {
        if case .gym(let id) = selectedGymScope {
            return gymProfilesManager.gymName(for: id) == nil
        }
        return false
    }

    private var locationBadgeStyle: GymBadgeStyle {
        switch selectedGymScope {
        case .all:
            return .assigned
        case .unassigned:
            return .unassigned
        case .gym(let id):
            return gymProfilesManager.gymName(for: id) == nil ? .deleted : .assigned
        }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    ExerciseStatsCards(exerciseName: exerciseName, history: scopedHistory)

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Progress Chart")
                                .font(Theme.Typography.title2)
                                .foregroundColor(Theme.Colors.textPrimary)

                            Spacer()

                            locationMenu

                            Picker("Chart Type", selection: $selectedChart) {
                                ForEach(ChartType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if isDeletedScope {
                            Text("Deleted gym. Select a valid location.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.warning)
                        }

                        ExerciseProgressChart(history: scopedHistory, chartType: selectedChart)
                            .frame(height: 250)
                            .padding(Theme.Spacing.lg)
                            .softCard(elevation: 2)
                    }

                    ExerciseRangeBreakdown(history: scopedHistory)

                    if !exerciseInsights.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Text("Insights")
                                .font(Theme.Typography.title3)
                                .foregroundColor(Theme.Colors.textPrimary)

                            VStack(spacing: Theme.Spacing.md) {
                                ForEach(exerciseInsights) { insight in
                                    InsightCardView(insight: insight)
                                }
                            }
                        }
                    }

                    PersonalRecordsView(history: scopedHistory)

                    RecentSetsView(history: scopedHistory)
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            Task {
                await insightsEngine.generateInsights()
            }
        }
        .onChange(of: selectedChart) { _, _ in
            Haptics.selection()
        }
    }

    private var locationMenu: some View {
        Button {
            showingLocationPicker = true
        } label: {
            HStack(spacing: 6) {
                GymBadge(text: locationLabel, style: locationBadgeStyle)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingLocationPicker) {
            GymSelectionSheet(
                title: "Location Scope",
                gyms: gymProfilesManager.sortedGyms,
                selected: currentScopeSelection,
                showAllGyms: true,
                showUnassigned: true,
                lastUsedGymId: nil,
                showLastUsed: false,
                showAddNew: false,
                onSelect: handleScopeSelection,
                onAddNew: nil
            )
        }
    }

    private var currentScopeSelection: GymSelection {
        switch selectedGymScope {
        case .all:
            return .allGyms
        case .unassigned:
            return .unassigned
        case .gym(let id):
            return .gym(id)
        }
    }

    private func handleScopeSelection(_ selection: GymSelection) {
        switch selection {
        case .allGyms:
            selectedGymScope = .all
        case .unassigned:
            selectedGymScope = .unassigned
        case .gym(let id):
            selectedGymScope = .gym(id)
        }
    }
}

struct ExerciseStatsCards: View {
    let exerciseName: String
    let history: [(date: Date, sets: [WorkoutSet])]

    @State private var selectedStat: ExerciseStatKind?

    private var stats: (total: Int, maxWeight: Double, maxVolume: Double, avgReps: Double) {
        let allSets = history.flatMap { $0.sets }
        let maxWeight = allSets.map { $0.weight }.max() ?? 0
        let volumes = history.map { session in
            session.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        }
        let maxVolume = volumes.max() ?? 0
        let avgReps = allSets.isEmpty ? 0 : Double(allSets.reduce(0) { $0 + $1.reps }) / Double(allSets.count)

        return (allSets.count, maxWeight, maxVolume, avgReps)
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCard(
                title: "Total Sets",
                value: "\(stats.total)",
                icon: "number",
                color: .blue,
                onTap: { selectedStat = .totalSets }
            )

            StatCard(
                title: "Max Weight",
                value: "\(Int(stats.maxWeight)) lbs",
                icon: "scalemass.fill",
                color: .orange,
                onTap: { selectedStat = .maxWeight }
            )

            StatCard(
                title: "Max Volume",
                value: formatVolume(stats.maxVolume),
                icon: "chart.bar.fill",
                color: .green,
                onTap: { selectedStat = .maxVolume }
            )

            StatCard(
                title: "Avg Reps",
                value: String(format: "%.1f", stats.avgReps),
                icon: "repeat",
                color: .purple,
                onTap: { selectedStat = .avgReps }
            )
        }
        .navigationDestination(item: $selectedStat) { kind in
            ExerciseStatDetailView(kind: kind, exerciseName: exerciseName, history: history)
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk lbs", volume / 1000)
        }
        return "\(Int(volume)) lbs"
    }
}

struct ExerciseProgressChart: View {
    let history: [(date: Date, sets: [WorkoutSet])]
    let chartType: ExerciseDetailView.ChartType

    @State private var isAppearing = false
    @State private var selectedDataPoint: (date: Date, value: Double)?
    @State private var lastPRHapticDate: Date?
    @State private var selectionClearTask: Task<Void, Never>?

    private enum ChartSeries: String {
        case progress = "Progress"
        case trend = "Trend"
    }

    private var chartData: [(date: Date, value: Double)] {
        history.map { session in
            let value: Double
            switch chartType {
            case .weight:
                value = session.sets.map { $0.weight }.max() ?? 0
            case .volume:
                value = session.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
            case .oneRepMax:
                let bestSet = session.sets.max { set1, set2 in
                    calculateOneRepMax(weight: set1.weight, reps: set1.reps) <
                    calculateOneRepMax(weight: set2.weight, reps: set2.reps)
                }
                value = bestSet.map { calculateOneRepMax(weight: $0.weight, reps: $0.reps) } ?? 0
            case .reps:
                value = Double(session.sets.map { $0.reps }.max() ?? 0)
            }
            return (date: session.date, value: value)
        }
    }

    private var indexedChartData: [(id: Int, date: Date, value: Double)] {
        chartData.enumerated().map { index, point in
            (id: index, date: point.date, value: point.value)
        }
    }

    private var prDate: Date? {
        chartData.max(by: { $0.value < $1.value })?.date
    }

    private var chartColor: Color {
        switch chartType {
        case .weight: return Theme.Colors.chest
        case .volume: return Theme.Colors.quads
        case .oneRepMax: return Theme.Colors.gold
        case .reps: return Theme.Colors.back
        }
    }

    private var seriesColors: KeyValuePairs<String, Color> {
        [
            ChartSeries.progress.rawValue: chartColor,
            ChartSeries.trend.rawValue: Color.secondary.opacity(0.5)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Selected point info
            if let selected = selectedDataPoint {
                selectedPointHeader(selected: selected)
            }

            chartView
        }
        .onAppear {
            withAnimation(Theme.Animation.chartAppear) {
                isAppearing = true
            }
        }
        .onDisappear {
            selectionClearTask?.cancel()
        }
    }

    @ViewBuilder
    private func selectedPointHeader(selected: (date: Date, value: Double)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                Text(formatValue(selected.value))
                    .font(Theme.Typography.title3)
                    .foregroundColor(chartColor)
            }

            Spacer()

            if selected.date == prDate {
                PRMarkerView(date: selected.date)
            }
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }

    private var chartView: some View {
        Chart {
            variabilityBandMarks
            areaMarks
            lineMarks
            pointMarks
            trendLineMarks
            selectionRuleMark
        }
        .chartForegroundStyleScale(seriesColors)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                selectionClearTask?.cancel()
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                let x = value.location.x - frame.origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    // Find closest data point
                                    if let closest = chartData.min(by: {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    }) {
                                        selectedDataPoint = closest
                                        if let prDate, prDate == closest.date, lastPRHapticDate != prDate {
                                            Haptics.notify(.success)
                                            lastPRHapticDate = prDate
                                        }
                                    }
                                }
                            }
                            .onEnded { _ in
                                // Keep selection visible briefly (cancelled if the user starts dragging again).
                                selectionClearTask?.cancel()
                                selectionClearTask = Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    guard !Task.isCancelled else { return }
                                    withAnimation {
                                        selectedDataPoint = nil
                                    }
                                }
                            }
                    )
            }
        }
    }

    @ChartContentBuilder
    private var variabilityBandMarks: some ChartContent {
        if chartType == .oneRepMax {
            ForEach(variabilityBand, id: \.date) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Lower", point.lower),
                    yEnd: .value("Upper", point.upper)
                )
                .foregroundStyle(chartColor.opacity(0.12))
                .interpolationMethod(.catmullRom)
            }
        }
    }

    @ChartContentBuilder
    private var areaMarks: some ChartContent {
        ForEach(indexedChartData, id: \.id) { dataPoint in
            AreaMark(
                x: .value("Date", dataPoint.date),
                y: .value(chartType.rawValue, isAppearing ? dataPoint.value : 0)
            )
            .foregroundStyle(chartColor.opacity(0.15))
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(indexedChartData, id: \.id) { dataPoint in
            LineMark(
                x: .value("Date", dataPoint.date),
                y: .value(chartType.rawValue, isAppearing ? dataPoint.value : 0)
            )
            .foregroundStyle(by: .value("Series", ChartSeries.progress.rawValue))
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder
    private var pointMarks: some ChartContent {
        ForEach(indexedChartData, id: \.id) { dataPoint in
            PointMark(
                x: .value("Date", dataPoint.date),
                y: .value(chartType.rawValue, isAppearing ? dataPoint.value : 0)
            )
            .foregroundStyle(dataPoint.date == prDate ? Theme.Colors.gold : chartColor)
            .symbolSize(dataPoint.date == prDate ? 100 : 50)
            .annotation(position: .top) {
                if dataPoint.date == prDate {
                    Image(systemName: "trophy.fill")
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.gold)
                        .opacity(isAppearing ? 1 : 0)
                }
            }
        }
    }

    @ChartContentBuilder
    private var trendLineMarks: some ChartContent {
        if let trend = calculateTrendLine(), isAppearing {
            LineMark(
                x: .value("Date", trend.start.date),
                y: .value("Trend", trend.start.value)
            )
            .foregroundStyle(by: .value("Series", ChartSeries.trend.rawValue))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

            LineMark(
                x: .value("Date", trend.end.date),
                y: .value("Trend", trend.end.value)
            )
            .foregroundStyle(by: .value("Series", ChartSeries.trend.rawValue))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }

    @ChartContentBuilder
    private var selectionRuleMark: some ChartContent {
        if let selected = selectedDataPoint {
            RuleMark(x: .value("Selected", selected.date))
                .foregroundStyle(chartColor.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    private func formatValue(_ value: Double) -> String {
        switch chartType {
        case .weight, .oneRepMax:
            return "\(Int(value)) lbs"
        case .volume:
            if value >= 1000 {
                return String(format: "%.1fk lbs", value / 1000)
            }
            return "\(Int(value)) lbs"
        case .reps:
            return "\(Int(value)) reps"
        }
    }

    private func calculateOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }

    private func calculateTrendLine() -> (start: (date: Date, value: Double), end: (date: Date, value: Double))? {
        guard chartData.count >= 2 else { return nil }

        // Simple linear regression
        let n = Double(chartData.count)
        let sumX = chartData.enumerated().reduce(0.0) { $0 + Double($1.offset) }
        let sumY = chartData.reduce(0.0) { $0 + $1.value }
        let sumXY = chartData.enumerated().reduce(0.0) { $0 + (Double($1.offset) * $1.element.value) }
        let sumXX = chartData.enumerated().reduce(0.0) { $0 + (Double($1.offset) * Double($1.offset)) }

        let slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n

        let startValue = intercept
        let endValue = slope * (n - 1) + intercept

        let startDate = chartData[0].date
        let endDate = chartData[chartData.count - 1].date
        return (
            start: (date: startDate, value: startValue),
            end: (date: endDate, value: endValue)
        )
    }

    private var variabilityBand: [(date: Date, lower: Double, upper: Double)] {
        guard chartData.count >= 2 else { return [] }
        let values = chartData.map { $0.value }
        let window = 3
        return chartData.indices.map { index in
            let start = max(0, index - (window - 1))
            let slice = values[start...index]
            let mean = slice.reduce(0, +) / Double(slice.count)
            let variance = slice.reduce(0) { $0 + pow($1 - mean, 2) } / Double(slice.count)
            let std = sqrt(variance)
            return (date: chartData[index].date, lower: max(0, mean - std), upper: mean + std)
        }
    }
}

struct PersonalRecordsView: View {
    let history: [(date: Date, sets: [WorkoutSet])]

    private var records: [(title: String, value: String, date: Date)] {
        let allSets = history.flatMap { session in
            session.sets.map { (set: $0, date: session.date) }
        }

        var records: [(title: String, value: String, date: Date)] = []

        // Max weight
        if let maxWeightSet = allSets.max(by: { $0.set.weight < $1.set.weight }) {
            records.append(("Heaviest Weight", "\(Int(maxWeightSet.set.weight)) lbs × \(maxWeightSet.set.reps)", maxWeightSet.date))
        }

        // Max volume single set
        if let maxVolumeSet = allSets.max(by: {
            $0.set.weight * Double($0.set.reps) < $1.set.weight * Double($1.set.reps)
        }) {
            let volume = maxVolumeSet.set.weight * Double(maxVolumeSet.set.reps)
            records.append(("Max Volume (Single Set)", "\(Int(volume)) lbs", maxVolumeSet.date))
        }

        // Max reps
        if let maxRepsSet = allSets.max(by: { $0.set.reps < $1.set.reps }) {
            records.append(("Most Reps", "\(maxRepsSet.set.reps) @ \(Int(maxRepsSet.set.weight)) lbs", maxRepsSet.date))
        }

        // Best 1RM
        if let best1RM = allSets.max(by: {
            calculateOneRepMax(weight: $0.set.weight, reps: $0.set.reps) <
            calculateOneRepMax(weight: $1.set.weight, reps: $1.set.reps)
        }) {
            let orm = calculateOneRepMax(weight: best1RM.set.weight, reps: best1RM.set.reps)
            records.append(("Est. 1RM", "\(Int(orm)) lbs", best1RM.date))
        }

        return records
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Personal Records")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(records, id: \.title) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title)
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.textSecondary)
                            Text(record.value)
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }

                        Spacer()

                        Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
                }
            }
        }
    }

    private func calculateOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }
}

struct RecentSetsView: View {
    let history: [(date: Date, sets: [WorkoutSet])]
    @State private var visibleCount: Int = 5

    private var sortedSessions: [(date: Date, sets: [WorkoutSet])] {
        history.sorted { $0.date > $1.date }
    }

    private var recentSessions: [(date: Date, sets: [WorkoutSet])] {
        Array(sortedSessions.prefix(visibleCount))
    }

    private var canShowMore: Bool {
        sortedSessions.count > visibleCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Recent Sessions")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(recentSessions, id: \.date) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.textSecondary)

                        ForEach(Array(session.sets.enumerated()), id: \.offset) { index, set in
                            HStack {
                                Text("Set \(index + 1)")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textTertiary)
                                    .frame(width: 50, alignment: .leading)

                                Text("\(Int(set.weight)) lbs × \(set.reps)")
                                    .font(Theme.Typography.body)
                                    .monospacedDigit()

                                Spacer()

                                Text("\(Int(set.weight * Double(set.reps))) lbs")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
                }

                if canShowMore {
                    Button {
                        withAnimation(.easeInOut) {
                            visibleCount = min(visibleCount + 5, sortedSessions.count)
                        }
                    } label: {
                        Text("Show more")
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                    }
                    .softCard(elevation: 1)
                }
            }
        }
    }
}

struct ExerciseRangeBreakdown: View {
    let history: [(date: Date, sets: [WorkoutSet])]

    private var allSets: [WorkoutSet] {
        history.flatMap { $0.sets }
    }

    private var repBuckets: [RepRangeBucket] {
        let buckets: [(label: String, range: ClosedRange<Int>, tint: Color)] = [
            ("1-3", 1...3, Theme.Colors.error),
            ("4-6", 4...6, Theme.Colors.warning),
            ("7-10", 7...10, Theme.Colors.accent),
            ("11-15", 11...15, Theme.Colors.accentSecondary),
            ("16-20", 16...20, Theme.Colors.success),
            ("21+", 21...100, Theme.Colors.textSecondary)
        ]
        let total = max(allSets.count, 1)
        return buckets.map { bucket in
            let count = allSets.filter { bucket.range.contains($0.reps) }.count
            return RepRangeBucket(
                label: bucket.label,
                range: bucket.range,
                count: count,
                percent: Double(count) / Double(total),
                tint: bucket.tint
            )
        }
    }

    private var intensityBuckets: [IntensityZoneBucket] {
        let best1RM = allSets.map { estimateOneRepMax(weight: $0.weight, reps: $0.reps) }.max() ?? 0
        let zones: [(label: String, range: ClosedRange<Double>, tint: Color)] = [
            ("<50%", 0.0...0.49, Theme.Colors.textSecondary),
            ("50-65%", 0.50...0.65, Theme.Colors.accentSecondary),
            ("65-75%", 0.66...0.75, Theme.Colors.accent),
            ("75-85%", 0.76...0.85, Theme.Colors.warning),
            ("85%+", 0.86...1.5, Theme.Colors.error)
        ]

        guard best1RM > 0 else { return [] }

        var counts = Array(repeating: 0, count: zones.count)
        for set in allSets {
            let intensity = set.weight / best1RM
            if let index = zones.firstIndex(where: { $0.range.contains(intensity) }) {
                counts[index] += 1
            }
        }

        let total = max(counts.reduce(0, +), 1)
        return zones.enumerated().map { index, zone in
            IntensityZoneBucket(
                label: zone.label,
                range: zone.range,
                count: counts[index],
                percent: Double(counts[index]) / Double(total),
                tint: zone.tint
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Rep Ranges & Intensity")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Chart(repBuckets) { bucket in
                BarMark(
                    x: .value("Share", bucket.percent),
                    y: .value("Range", bucket.label)
                )
                .foregroundStyle(bucket.tint)
            }
            .frame(height: 160)
            .chartXScale(domain: 0...1)
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)

            if !intensityBuckets.isEmpty {
                Chart(intensityBuckets) { bucket in
                    BarMark(
                        x: .value("Share", bucket.percent),
                        y: .value("Zone", bucket.label)
                    )
                    .foregroundStyle(bucket.tint)
                }
                .frame(height: 160)
                .chartXScale(domain: 0...1)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }

    private func estimateOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1 + 0.0333 * Double(reps))
    }
}
